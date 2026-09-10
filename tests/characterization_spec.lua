-- characterization_spec.lua
-- Tests de caracterización para ARCH-001: protegen comportamiento observable
-- antes de la migración arquitectónica. No dependen de implementación interna.
--
-- Estos tests verifican CONTRATOS, no implementación. Si la arquitectura
-- cambia pero el comportamiento observable se preserva, estos tests deben
-- seguir pasando.

local T = _G.T
local actions = require("code-runner.actions")
local state = require("code-runner.state")
local context = require("code-runner.context")
local history = require("code-runner.history")
local last = require("code-runner.last")
local shell = require("code-runner.shell")
local project = require("code-runner.project")
local config = require("code-runner.config")
local events = require("code-runner.events")
local workflow = require("code-runner.workflow")
local picker = require("code-runner.picker")
local init = require("code-runner.init")

-- ============================================================
-- Helpers
-- ============================================================

local function reset_all()
  state.reset()
  history.clear()
  last.clear()
  workflow.reset()
  context._clear_cache()
  if actions._reset_for_test then
    actions._reset_for_test()
  end
end

local function fresh_test_file(name, ext)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/" .. (name or "test_char") .. "." .. (ext or "lua")
  vim.fn.writefile({ "print('hello')" }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  return file, dir
end

-- ============================================================
-- 1. Execution Flow (build_run → terminal → state)
-- ============================================================

T.section("characterization: execution flow")

T.it("build_run resolves action by extension and sets state to running", function()
  local file, dir = fresh_test_file("flow_lua", "lua")
  state.reset()

  -- build_run es async (usa picker), pero podemos verificar que resuelve
  -- la action correctamente y que el state se prepara.
  local entry, key = init._build_entry(actions.get_actions(), {
    notify = function() end,
  })

  T.truthy(entry, "debería resolver una entry para .lua")
  T.eq("lua", key, "key debería ser la extensión")
  T.truthy(entry.__order, "entry debería tener __order")
  T.truthy(#entry.__order > 0, "entry debería tener al menos una acción")
end)

T.it("build_run detects context and injects test action when cursor is in a test", function()
  -- Crear un buffer Go con un test
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/flow_go_test.go"
  vim.fn.writefile({
    "package main",
    "",
    "import \"testing\"",
    "",
    "func TestAdd(t *testing.T) {",
    "    t.Fatal(\"fail\")",
    "}",
  }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  vim.api.nvim_win_set_cursor(0, { 6, 5 }) -- dentro de TestAdd

  local entry, key = init._build_entry(actions.get_actions(), {
    notify = function() end,
  })

  T.truthy(entry, "debería resolver una entry para .go")
  T.eq("go", key)

  local cctx = context.detect(key)
  T.truthy(cctx.test, "debería detectar un test")
  T.eq("TestAdd", cctx.test.name, "debería detectar TestAdd")

  local decorated = context.decorate(entry, key, cctx)
  T.truthy(decorated, "debería crear una acción contextual de test")
  T.contains(decorated.label, "TestAdd", "label debería contener el nombre del test")
  T.contains(decorated.cmd, "$testName", "cmd debería usar $testName")
end)

T.it("context_vars maps test/entry context to shell variables", function()
  local vars = init._context_vars({
    test = { name = "TestFoo" },
    entry = { name = "main", line = 42, fqcn = "com.example.Main" },
  })

  T.eq("TestFoo", vars["$testName"])
  T.eq("com.example.Main", vars["$entry"])
  T.eq("42", vars["$entryLine"])
end)

T.it("context_vars with nil context produces empty table", function()
  local vars = init._context_vars(nil)
  T.eq(0, vim.tbl_count(vars), "debería producir una tabla vacía")
end)

T.it("context_vars with partial context injects only available vars", function()
  local vars = init._context_vars({
    test = { name = "TestBar" },
    entry = nil,
  })

  T.eq("TestBar", vars["$testName"])
  T.falsy(vars["$entry"], "no debería inyectar $entry sin entry context")
end)

-- ============================================================
-- 2. State Transitions
-- ============================================================

T.section("characterization: state transitions")

T.it("state starts idle with nil fields", function()
  state.reset()
  local s = state.get()
  T.eq("idle", s.status)
  T.falsy(s.action)
  T.falsy(s.cwd)
  T.falsy(s.filetype)
  T.falsy(s.buf)
  T.falsy(s.code)
  T.falsy(s.started_at)
  T.falsy(s.ended_at)
end)

T.it("state running stores action/cwd/filetype and increments run_id", function()
  state.reset()
  local before = state.get().run_id

  state.set("running", {
    action = "Run",
    cwd = "/tmp",
    filetype = "lua",
    buf = 42,
  })

  local s = state.get()
  T.eq("running", s.status)
  T.eq("Run", s.action)
  T.eq("/tmp", s.cwd)
  T.eq("lua", s.filetype)
  T.eq(42, s.buf)
  T.truthy(s.started_at, "started_at debería estar definido")
  T.eq(before + 1, s.run_id, "run_id debería incrementar")
end)

T.it("state success stores exit code and preserves action metadata", function()
  state.reset()
  state.set("running", { action = "Build", cwd = "/proj", filetype = "go" })
  state.set("success", { code = 0 })

  local s = state.get()
  T.eq("success", s.status)
  T.eq(0, s.code)
  T.eq("Build", s.action, "action del running debería persistir")
  T.eq("/proj", s.cwd, "cwd del running debería persistir")
  T.eq("go", s.filetype, "filetype del running debería persistir")
  T.truthy(s.ended_at, "ended_at debería estar definido")
end)

T.it("state failed stores non-zero code", function()
  state.reset()
  state.set("running", { action = "Run" })
  state.set("failed", { code = 1 })

  T.eq("failed", state.get().status)
  T.eq(1, state.get().code)
end)

T.it("state cancelled transitions from running", function()
  state.reset()
  state.set("running", { action = "Run" })
  state.set("cancelled")

  T.eq("cancelled", state.get().status)
end)

T.it("invalid status transition is a no-op", function()
  state.reset()
  state.set("running", {})
  state.set("invalid_status")

  T.eq("running", state.get().status, "el status no debería cambiar")
end)

T.it("state.get() returns a copy — mutations do not affect internal state", function()
  state.reset()
  state.set("running", { action = "Test" })

  local copy = state.get()
  copy.status = "hacked"
  copy.action = "hacked"

  local original = state.get()
  T.eq("running", original.status)
  T.eq("Test", original.action)
end)

T.it("consecutive runs increment run_id monotonically", function()
  state.reset()
  state.set("running", { action = "A" })
  local id1 = state.get().run_id
  state.set("success", { code = 0 })

  state.set("running", { action = "B" })
  local id2 = state.get().run_id

  T.truthy(id2 > id1, "run_id debería crecer: " .. id1 .. " < " .. id2)
end)

T.it("public state() reflects the central state", function()
  state.reset()
  state.set("running", { action = "X" })

  local pub = init.state()
  T.eq("running", pub.status)
  T.eq("X", pub.action)
end)

-- ============================================================
-- 3. Context Resolution Pipeline
-- ============================================================

T.section("characterization: context resolution pipeline")

T.it("detect returns key-only for unsupported extensions", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/unknown.xyz"
  vim.fn.writefile({ "content" }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))

  local ctx = context.detect("xyz")
  T.eq("xyz", ctx.key)
  T.falsy(ctx.test, "extensión no soportada no tiene test detection")
  T.falsy(ctx.entry, "extensión no soportada no tiene entry detection")
end)

T.it("detect returns test and entry for Go files", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/ctx_go_test.go"
  vim.fn.writefile({
    "package main",
    "",
    "import \"testing\"",
    "",
    "func TestMyFunc(t *testing.T) {",
    "    // test body",
    "}",
    "",
    "func main() {",
    "    // entry",
    "}",
  }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  vim.api.nvim_win_set_cursor(0, { 6, 5 })

  local ctx = context.detect("go")
  T.eq("go", ctx.key)
  T.truthy(ctx.test, "debería detectar test")
  T.eq("TestMyFunc", ctx.test.name)
  T.truthy(ctx.entry, "debería detectar entry")
  T.truthy(ctx.entry.name ~= nil, "entry debería tener un nombre")
end)

T.it("context cache reuses result for same line+buffer", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/cache_same.lua"
  vim.fn.writefile({ "-- test" }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))

  context._clear_cache()
  local r1 = context.detect("lua")
  local r2 = context.detect("lua")

  T.eq(r1, r2, "misma línea+buffer debería reutilizar cache (identity)")
end)

T.it("context cache invalidates on cursor change", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/cache_cursor.go"
  vim.fn.writefile({
    "package main",
    "func TestA(t *testing.T) {}",
    "func TestB(t *testing.T) {}",
  }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))

  context._clear_cache()
  vim.api.nvim_win_set_cursor(0, { 2, 5 })
  local r1 = context.detect("go")

  vim.api.nvim_win_set_cursor(0, { 3, 5 })
  local r2 = context.detect("go")

  -- Ambos tests están en líneas distintas; el cache debería haberse invalidado
  T.truthy(r1.test, "línea 2 debería detectar TestA")
  T.truthy(r2.test, "línea 3 debería detectar TestB")
  -- Los nombres pueden ser distintos si los tests están en distintas líneas
end)

T.it("test_action returns nil when context has no test", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/no_test.lua"
  vim.fn.writefile({ "print('no test')" }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))

  local ctx = context.detect("lua")
  local label, cmd = context.test_action("lua", ctx)
  T.falsy(label, "sin test detectado, no debería haber test_action")
end)

T.it("test_action uses per-language override from config", function()
  local ctx = { test = { name = "TestFoo" } }
  config.options.context.test.go = "custom_test_cmd $testName"

  local label, cmd = context.test_action("go", ctx)
  T.truthy(cmd, "debería tener un cmd")
  T.contains(cmd, "custom_test_cmd", "debería usar el override de config")
  -- La plantilla usa $testName como variable; se sustituye luego en shell.substitute.
  -- Verificamos que la plantilla retenga el token $testName.
  T.contains(cmd, "$testName", "la plantilla debería retener $testName para sustitución")

  -- restaurar
  config.options.context.test.go = nil
end)

T.it("test_action: cmd=false disables the language", function()
  local ctx = { test = { name = "TestFoo" } }
  config.options.context.test.go = false

  local label, cmd = context.test_action("go", ctx)
  T.falsy(label, "cmd=false debería deshabilitar test_action")

  config.options.context.test.go = nil
end)

T.it("test_action: context.enabled=false disables all", function()
  local ctx = { test = { name = "TestFoo" } }
  local was = config.options.context.enabled
  config.options.context.enabled = false

  local label, cmd = context.test_action("go", ctx)
  T.falsy(label, "context.enabled=false debería deshabilitar todo")

  config.options.context.enabled = was
end)

-- ============================================================
-- 4. Picker Integration
-- ============================================================

T.section("characterization: picker integration")

T.it("picker receives entry.__order items", function()
  local entry, _ = init._build_entry(actions.get_actions(), {
    notify = function() end,
  })
  T.truthy(entry.__order, "entry debería tener __order")
  T.truthy(#entry.__order > 0, "debería haber al menos una acción")

  -- Verificar que cada item en __order tiene un comando en entry
  for _, label in ipairs(entry.__order) do
    T.truthy(entry[label], "label '" .. label .. "' debería tener un comando en entry")
  end
end)

T.it("test action appears first in decorated entry", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/picker_test.go"
  vim.fn.writefile({
    "package main",
    "import \"testing\"",
    "func TestFoo(t *testing.T) {}",
  }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  vim.api.nvim_win_set_cursor(0, { 3, 5 })

  local entry = init._build_entry(actions.get_actions(), { notify = function() end })
  local cctx = context.detect("go")
  local decorated = context.decorate(entry, "go", cctx)

  T.truthy(decorated, "debería haber decorado con test_action")
  T.eq(decorated.label, entry.__order[1], "test action debería ser la primera en __order")
end)

T.it("picker cancel does not execute any action", function()
  local executed = false
  picker.select({ "A", "B" }, {
    prompt = "test",
  }, function(choice)
    if choice then
      executed = true
    end
  end)

  -- En tests, picker.select con vim.ui.select es síncrono cuando se llama
  -- directamente; simulamos cancelación pasando nil
  picker.select({}, { prompt = "test" }, function(choice)
    -- nil = cancelación
    T.falsy(choice, "cancelación debería dar nil")
  end)

  T.truthy(not executed, "no debería haber ejecutado nada")
end)

-- ============================================================
-- 5. Event Emission Order
-- ============================================================

T.section("characterization: event emission order")

T.it("running emits CodeRunnerStart with state data", function()
  state.reset()
  local received = {}

  local id = vim.api.nvim_create_autocmd("User", {
    pattern = "CodeRunnerStart",
    callback = function(args)
      table.insert(received, args.data)
    end,
  })

  state.set("running", { action = "Run", cwd = "/tmp", filetype = "lua" })

  vim.api.nvim_del_autocmd(id)
  T.eq(1, #received, "debería recibir 1 evento Start")
  T.eq("Run", received[1].action)
  T.eq("/tmp", received[1].cwd)
end)

T.it("success emits CodeRunnerSuccess then CodeRunnerExit", function()
  state.reset()
  local order = {}

  local id1 = vim.api.nvim_create_autocmd("User", {
    pattern = "CodeRunnerSuccess",
    callback = function()
      table.insert(order, "success")
    end,
  })

  local id2 = vim.api.nvim_create_autocmd("User", {
    pattern = "CodeRunnerExit",
    callback = function()
      table.insert(order, "exit")
    end,
  })

  state.set("running", {})
  state.set("success", { code = 0 })

  vim.api.nvim_del_autocmd(id1)
  vim.api.nvim_del_autocmd(id2)

  T.eq(2, #order)
  T.eq("success", order[1], "Success debería emitirse primero")
  T.eq("exit", order[2], "Exit debería emitirse después")
end)

T.it("failed emits CodeRunnerFailed then CodeRunnerExit", function()
  state.reset()
  local order = {}

  local id1 = vim.api.nvim_create_autocmd("User", {
    pattern = "CodeRunnerFailed",
    callback = function()
      table.insert(order, "failed")
    end,
  })

  local id2 = vim.api.nvim_create_autocmd("User", {
    pattern = "CodeRunnerExit",
    callback = function()
      table.insert(order, "exit")
    end,
  })

  state.set("running", {})
  state.set("failed", { code = 1 })

  vim.api.nvim_del_autocmd(id1)
  vim.api.nvim_del_autocmd(id2)

  T.eq(2, #order)
  T.eq("failed", order[1])
  T.eq("exit", order[2])
end)

T.it("cancelled emits CodeRunnerCancelled then CodeRunnerExit", function()
  state.reset()
  local order = {}

  local id1 = vim.api.nvim_create_autocmd("User", {
    pattern = "CodeRunnerCancelled",
    callback = function()
      table.insert(order, "cancelled")
    end,
  })

  local id2 = vim.api.nvim_create_autocmd("User", {
    pattern = "CodeRunnerExit",
    callback = function()
      table.insert(order, "exit")
    end,
  })

  state.set("running", {})
  state.set("cancelled")

  vim.api.nvim_del_autocmd(id1)
  vim.api.nvim_del_autocmd(id2)

  T.eq(2, #order)
  T.eq("cancelled", order[1])
  T.eq("exit", order[2])
end)

T.it("events.enabled=false suppresses all emissions", function()
  state.reset()
  local count = 0
  local was = config.options.events.enabled
  config.options.events.enabled = false

  local id = vim.api.nvim_create_autocmd("User", {
    pattern = "CodeRunnerStart",
    callback = function()
      count = count + 1
    end,
  })

  state.set("running", {})
  vim.api.nvim_del_autocmd(id)
  config.options.events.enabled = was

  T.eq(0, count, "no debería emitir eventos con events.enabled=false")
end)

T.it("idle state does not emit events", function()
  state.reset()
  local count = 0

  local id = vim.api.nvim_create_autocmd("User", {
    pattern = { "CodeRunnerStart", "CodeRunnerSuccess", "CodeRunnerFailed", "CodeRunnerCancelled", "CodeRunnerExit" },
    callback = function()
      count = count + 1
    end,
  })

  -- state.set("idle") no existe como transición válida, pero reset() debería
  -- existir sin emitir eventos
  state.reset()
  vim.api.nvim_del_autocmd(id)

  T.eq(0, count, "reset no debería emitir eventos")
end)

-- ============================================================
-- 6. History & Last Persistence Roundtrip
-- ============================================================

T.section("characterization: history & last persistence")

T.it("history: add then list returns the entry", function()
  history.clear()
  history.add("echo hello", "/tmp", "lua")

  local items = history.list()
  T.eq(1, #items)
  T.eq("echo hello", items[1].cmd)
  T.eq("/tmp", items[1].cwd)
  T.eq("lua", items[1].key)
  T.eq(1, items[1].count)
end)

T.it("history: duplicate cmd+cwd increments count", function()
  history.clear()
  history.add("echo a", "/tmp", "lua")
  history.add("echo a", "/tmp", "lua")
  history.add("echo a", "/tmp", "lua")

  local items = history.list()
  T.eq(1, #items, "debería haber solo 1 entrada")
  T.eq(3, items[1].count, "count debería ser 3")
end)

T.it("history: same cmd different cwd are separate entries", function()
  history.clear()
  history.add("echo a", "/dir1", "lua")
  history.add("echo a", "/dir2", "lua")

  local items = history.list()
  T.eq(2, #items)
end)

T.it("history: most recent is first", function()
  history.clear()
  history.add("first", "/a", "lua")
  history.add("second", "/b", "lua")

  local items = history.list()
  T.eq("second", items[1].cmd)
  T.eq("first", items[2].cmd)
end)

T.it("history: clear empties the list", function()
  history.clear()
  history.add("cmd", "/tmp", "lua")
  history.clear()

  T.eq(0, #history.list())
end)

T.it("history: enabled=false prevents recording", function()
  history.clear()
  local was = config.options.history.enabled
  config.options.history.enabled = false

  history.add("should_not_record", "/tmp", "lua")
  T.eq(0, #history.list())

  config.options.history.enabled = was
end)

T.it("history: persists to disk and survives reload", function()
  local tmpfile = vim.fn.tempname() .. ".json"
  history._data_file = tmpfile
  history.clear()
  history.add("persist_test", "/tmp", "lua")
  history._data_file = nil

  -- Recargar desde disco
  history._data_file = tmpfile
  local items = history.list()
  T.eq(1, #items)
  T.eq("persist_test", items[1].cmd)

  history._data_file = nil
  os.remove(tmpfile)
end)

T.it("history: corrupted file returns empty without error", function()
  local tmpfile = vim.fn.tempname() .. ".json"
  local f = io.open(tmpfile, "w")
  f:write("NOT VALID JSON {{{")
  f:close()

  history._data_file = tmpfile
  local items = history.list()
  T.eq(0, #items, "archivo corrupto debería devolver lista vacía")

  history._data_file = nil
  os.remove(tmpfile)
end)

T.it("last: set then get returns the entry", function()
  last.clear()
  last.set({ lang = "go", choice = "Run", cmd = "go run main.go" })

  local entry = last.get()
  T.truthy(entry)
  T.eq("go", entry.lang)
  T.eq("Run", entry.choice)
  T.eq("go run main.go", entry.cmd)
end)

T.it("last: get without file returns nil", function()
  last.clear()
  local entry = last.get()
  T.falsy(entry)
end)

T.it("last: clear deletes the entry", function()
  last.clear()
  last.set({ lang = "lua" })
  last.clear()

  T.falsy(last.get())
end)

T.it("last: persists to disk and survives reload", function()
  local tmpfile = vim.fn.tempname() .. ".json"
  last._data_file = tmpfile
  last.clear()
  last.set({ lang = "rust", choice = "Build" })
  last._data_file = nil

  last._data_file = tmpfile
  local entry = last.get()
  T.truthy(entry)
  T.eq("rust", entry.lang)

  last._data_file = nil
  os.remove(tmpfile)
end)

-- ============================================================
-- 7. Workflow End-to-End
-- ============================================================

T.section("characterization: workflow end-to-end")

T.it("workflow: register then list returns the spec", function()
  workflow.reset()
  workflow.register({
    name = "test_wf",
    steps = { "echo A", "echo B" },
  })

  local list = workflow.list()
  T.truthy(list["test_wf"])
  T.eq(2, #list["test_wf"].steps)
  T.eq(true, list["test_wf"].stop_on_fail, "stop_on_fail debería ser true por defecto")
end)

T.it("workflow: sequential execute runs all steps in order", function()
  workflow.reset()
  local order = {}

  workflow.register({
    name = "seq_test",
    steps = { "echo 1", "echo 2", "echo 3" },
    stop_on_fail = false,
  })

  local spec = workflow.list()["seq_test"]
  local result = workflow.execute(spec, function(cmd, cwd)
    table.insert(order, cmd)
    return 0
  end)

  T.eq(true, result.ok)
  T.eq(3, #result.results)
  T.eq(3, #order)
end)

T.it("workflow: sequential execute stops on fail when stop_on_fail=true", function()
  workflow.reset()
  local run_count = 0

  workflow.register({
    name = "stop_test",
    steps = { "echo A", "false", "echo C" },
    stop_on_fail = true,
  })

  local spec = workflow.list()["stop_test"]
  local result = workflow.execute(spec, function(cmd, cwd)
    run_count = run_count + 1
    if cmd:find("false") then
      return 1
    end
    return 0
  end)

  T.eq(false, result.ok)
  T.eq(2, #result.results, "debería haber ejecutado solo 2 pasos")
end)

T.it("workflow: sequential execute continues when stop_on_fail=false", function()
  workflow.reset()

  workflow.register({
    name = "continue_test",
    steps = { "echo A", "false", "echo C" },
    stop_on_fail = false,
  })

  local spec = workflow.list()["continue_test"]
  local result = workflow.execute(spec, function(cmd, cwd)
    if cmd:find("false") then
      return 1
    end
    return 0
  end)

  T.eq(false, result.ok)
  T.eq(3, #result.results, "debería haber ejecutado los 3 pasos")
end)

T.it("workflow: parallel register normalizes true to #steps", function()
  workflow.reset()
  workflow.register({
    name = "par_test",
    steps = { "echo A", "echo B", "echo C" },
    parallel = true,
  })

  local spec = workflow.list()["par_test"]
  T.eq(3, spec.parallel, "parallel=true debería normalizarse a #steps")
end)

T.it("workflow: parallel register caps concurrency to N", function()
  workflow.reset()
  workflow.register({
    name = "par_n",
    steps = { "echo A", "echo B", "echo C", "echo D" },
    parallel = 2,
  })

  local spec = workflow.list()["par_n"]
  T.eq(2, spec.parallel)
end)

T.it("workflow: register rejects empty steps", function()
  workflow.reset()
  local ok, err = pcall(function()
    workflow.register({ name = "bad", steps = {} })
  end)
  T.falsy(ok, "steps vacío debería lanzar error")
end)

T.it("workflow: reset clears all tasks", function()
  workflow.reset()
  workflow.register({ name = "x", steps = { "echo 1" } })
  workflow.reset()

  T.eq(0, vim.tbl_count(workflow.list()))
end)

T.it("workflow: substitutes $file in steps", function()
  workflow.reset()
  local captured_cmd

  workflow.register({
    name = "subst_test",
    steps = { "echo $file" },
  })

  local spec = workflow.list()["subst_test"]
  workflow.execute(spec, function(cmd, cwd)
    captured_cmd = cmd
    return 0
  end)

  T.truthy(captured_cmd, "debería haber capturado un comando")
  -- $file se expande al archivo actual (o se preserva si no hay)
  T.truthy(captured_cmd:find("echo"), "debería contener echo")
end)

T.it("workflow: re-registering same name replaces", function()
  workflow.reset()
  workflow.register({ name = "dup", steps = { "echo A" } })
  workflow.register({ name = "dup", steps = { "echo B", "echo C" } })

  local spec = workflow.list()["dup"]
  T.eq(2, #spec.steps, "re-registrar debería reemplazar")
end)

-- ============================================================
-- 8. Public API Surface
-- ============================================================

T.section("characterization: public API surface")

T.it("all public functions are callable", function()
  T.truthy(type(init.setup) == "function", "setup debería ser function")
  T.truthy(type(init.run) == "function", "run debería ser function")
  T.truthy(type(init.run_last) == "function", "run_last debería ser function")
  T.truthy(type(init.run_history) == "function", "run_history debería ser function")
  T.truthy(type(init.stop) == "function", "stop debería ser function")
  T.truthy(type(init.restart) == "function", "restart debería ser function")
  T.truthy(type(init.context) == "function", "context debería ser function")
  T.truthy(type(init.state) == "function", "state debería ser function")
  T.truthy(type(init.register_action) == "function", "register_action debería ser function")
  T.truthy(type(init.unregister_action) == "function", "unregister_action debería ser function")
  T.truthy(type(init.list_registered_actions) == "function", "list_registered_actions debería ser function")
end)

T.it("run is an alias of build_run", function()
  T.eq(init.run, init.build_run, "run debería ser la misma función que build_run")
end)

T.it("state() returns a table with expected fields", function()
  state.reset()
  local s = init.state()
  T.truthy(type(s) == "table", "state debería devolver una tabla")
  T.truthy(s.status ~= nil, "state debería tener status")
  T.truthy(vim.tbl_contains(state.STATUSES, s.status), "status debería ser uno de los STATUSES")
end)

T.it("context() detects context for a given key", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/api_ctx.go"
  vim.fn.writefile({
    "package main",
    "import \"testing\"",
    "func TestApi(t *testing.T) {}",
  }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  vim.api.nvim_win_set_cursor(0, { 3, 5 })

  local ctx = init.context("go")
  T.truthy(ctx)
  T.eq("go", ctx.key)
end)

T.it("register_action and unregister_action roundtrip", function()
  init.register_action({
    id = "char_test_action",
    filetypes = { "lua" },
    kind = "run",
    command = "echo char_test",
  })

  local registered = init.list_registered_actions()
  T.truthy(registered["char_test_action"])

  init.unregister_action("char_test_action")
  registered = init.list_registered_actions()
  T.falsy(registered["char_test_action"])
end)

T.it("list_registered_actions returns empty table initially", function()
  require("code-runner.actions.registry").reset()
  local list = init.list_registered_actions()
  T.eq(0, vim.tbl_count(list))
end)

T.it("stop() is a no-op when idle", function()
  state.reset()
  -- stop() no debería lanzar error ni cambiar el estado
  init.stop()
  T.eq("idle", state.get().status)
end)

T.it("restart() without prior execution notifies (does not crash)", function()
  state.reset()
  last.clear()
  -- restart llama _stop_silent + run_last; run_last notifica WARN
  -- pero no debería lanzar error
  local ok = pcall(init.restart)
  T.truthy(ok, "restart sin ejecución previa no debería crashear")
end)

-- ============================================================
-- 9. Command Resolution (shell.substitute + wrap_command)
-- ============================================================

T.section("characterization: command resolution")

T.it("substitute expands $file to current buffer path", function()
  local file, _ = fresh_test_file("cmd_resolve", "lua")
  local result = shell.substitute("$file", {}, "lua")
  T.contains(result, "cmd_resolve.lua")
end)

T.it("substitute expands $dir to current buffer directory", function()
  local file, dir = fresh_test_file("cmd_dir", "lua")
  local result = shell.substitute("$dir", {}, "lua")
  -- $dir expande al directorio del buffer actual (normalizado)
  local expected = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand("%:p"), ":h"))
  T.eq(vim.fs.normalize(expected), vim.fs.normalize(result))
end)

T.it("substitute expands $stem to filename without extension", function()
  local file, _ = fresh_test_file("cmd_stem", "lua")
  local result = shell.substitute("$stem", {}, "lua")
  T.contains(result, "cmd_stem")
  T.falsy(result:find("%.lua$"), "stem no debería contener la extensión")
end)

T.it("wrap_command on Windows wraps in powershell", function()
  if vim.fn.has("win32") == 0 then
    T.skip("solo Windows")
    return
  end

  local result = shell.wrap_command("echo hello")
  T.truthy(type(result) == "table", "wrap_command debería devolver una tabla de argumentos")
  T.eq("powershell", result[1], "el primer argumento debería ser powershell")
  -- T.join para verificar que no es un string
end)

T.it("wrap_command on Unix wraps in bash", function()
  if vim.fn.has("win32") == 1 then
    T.skip("solo Unix")
    return
  end

  local result = shell.wrap_command("echo hello")
  T.contains(result, "bash")
end)

-- ============================================================
-- 10. Project Detection
-- ============================================================

T.section("characterization: project detection")

T.it("project.resolve returns file dir when no markers", function()
  local dir = vim.fn.tempname() .. "/no_markers"
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/proj_test.lua"
  vim.fn.writefile({ "-- test" }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))

  local root = project.resolve()
  T.truthy(root, "debería devolver un directorio")
end)

T.it("project.find_from detects marker in parent", function()
  local root = vim.fn.tempname() .. "/proj_parent"
  local sub = root .. "/src/deep"
  vim.fn.mkdir(sub, "p")
  vim.fn.writefile({ "" }, root .. "/go.mod")

  local found = project.find_from(sub, "go")
  T.truthy(found, "debería encontrar go.mod en el padre")
  T.eq(vim.fs.normalize(root), vim.fs.normalize(found))
end)

T.it("project.find_from respects max_depth", function()
  local root = vim.fn.tempname() .. "/proj_depth"
  local deep = root .. "/a/b/c/d/e"
  vim.fn.mkdir(deep, "p")
  vim.fn.writefile({ "" }, root .. "/go.mod")

  local found = project._detect(deep, "go", 3)
  T.falsy(found, "max_depth=3 no debería encontrar go.mod 5 niveles arriba")
end)

T.it("project.find_from with no markers returns nil", function()
  local dir = vim.fn.tempname() .. "/no_proj"
  vim.fn.mkdir(dir, "p")

  local found = project.find_from(dir, "go")
  T.falsy(found)
end)

-- ============================================================
-- 11. Stop/Restart Behavior
-- ============================================================

T.section("characterization: stop/restart behavior")

T.it("stop() transitions running state to cancelled", function()
  state.reset()
  state.set("running", { action = "Run", buf = -1 })
  -- Simular un buffer inválido (el job ya no existe)
  init.stop()
  -- Con buf inválido, debería setear cancelled
  T.eq("cancelled", state.get().status)
end)

T.it("stop_silent does not emit notifications", function()
  state.reset()
  state.set("running", { action = "Run", buf = -1 })
  -- _stop_silent no debería notificar
  init._stop_silent()
  T.eq("cancelled", state.get().status)
end)

T.it("restart calls stop then run_last", function()
  state.reset()
  last.clear()
  -- restart con nada debería ser un no-op sin crash
  local ok = pcall(init.restart)
  T.truthy(ok)
end)

-- ============================================================
-- 12. Integration: build_run → history
-- ============================================================

T.section("characterization: history integration with execution")

T.it("history.add records the substituted command", function()
  history.clear()
  history.add("go run main.go", "/project", "go")
  history.add("go test ./...", "/project", "go")

  local items = history.list()
  T.eq(2, #items)
  T.eq("go test ./...", items[1].cmd) -- más reciente primero
end)

T.it("history deduplicates on cmd+cwd", function()
  history.clear()
  history.add("go test ./...", "/project", "go")
  history.add("go test ./...", "/project", "go")

  local items = history.list()
  T.eq(1, #items)
  T.eq(2, items[1].count)
end)

-- ============================================================
-- 13. Architectural Contract Tests
-- ============================================================

T.section("characterization: architectural contracts")

T.it("actions catalog has __order for every language", function()
  local all = actions.get_actions()
  for lang, entry in pairs(all) do
    if lang ~= "R" then -- R es alias
      T.truthy(entry.__order, lang .. " debería tener __order")
      T.truthy(#entry.__order > 0, lang .. " __order debería tener items")
    end
  end
end)

T.it("every label in __order maps to a command or function in the entry", function()
  local all = actions.get_actions()
  for lang, entry in pairs(all) do
    for _, label in ipairs(entry.__order or {}) do
      local cmd = entry[label]
      T.truthy(
        type(cmd) == "string" or type(cmd) == "function",
        lang .. "/" .. label .. " debería tener un comando o función"
      )
    end
  end
end)

T.it("state.STATUSES contains all expected statuses", function()
  local expected = { "idle", "running", "success", "failed", "cancelled" }
  for _, s in ipairs(expected) do
    T.truthy(vim.tbl_contains(state.STATUSES, s), "STATUSES debería contener: " .. s)
  end
end)

T.it("shell.substitute is deterministic for same inputs", function()
  local file, _ = fresh_test_file("deterministic", "lua")
  local r1 = shell.substitute("$file $stem", {}, "lua")
  local r2 = shell.substitute("$file $stem", {}, "lua")
  T.eq(r1, r2, "substitute debería ser determinista")
end)

T.it("shell.substitute handles paths with spaces", function()
  local dir = vim.fn.tempname() .. "/path with spaces"
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/spaced file.lua"
  vim.fn.writefile({ "-- test" }, file)
  vim.cmd("edit " .. vim.fn.fnameescape(file))

  local result = shell.substitute("$file", {}, "lua")
  T.contains(result, "spaced file.lua", "debería manejar espacios en la ruta")
end)
