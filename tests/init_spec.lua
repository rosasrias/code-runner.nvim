local cr = require "code-runner"
local config = require "code-runner.config"

T.section("init: resolución de acciones (build_entry)")

local tmpdir = vim.fn.tempname() .. "/cr_init_test"
vim.fn.mkdir(tmpdir, "p")

local function fake_terminal()
  local notified = {}
  return {
    notified = notified,
    notify = function(_, msg, level)
      table.insert(notified, { msg = msg, level = level })
    end,
    open = function() end,
  }
end

-- Rompe la carrera con jobs de terminal de specs previos que comparten el
-- mismo proceso headless: borra a la fuerza los buffers del plugin que hayan
-- quedado conectados, para que terminal.open arranque desde cero.
local function kill_plugin_terminals()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[b] and vim.b[b].code_runner_term then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

T.it("resuelve por extensión (.lua)", function()
  local f = tmpdir .. "/script.lua"
  vim.fn.writefile({ "print(1)" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))

  local entry, key = cr._build_entry(require("code-runner.actions").get_actions(), fake_terminal())
  T.eq("lua", key)
  T.truthy(entry and entry.__order)
end)

T.it("resuelve por filetype cuando no hay extensión (Makefile)", function()
  local f = tmpdir .. "/Makefile"
  vim.fn.writefile({ "all:", "\techo hi" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  vim.bo.filetype = "make" -- en uso real lo detecta Neovim

  local entry, key = cr._build_entry(require("code-runner.actions").get_actions(), fake_terminal())
  T.eq("make", key)
  T.truthy(entry)
end)

T.it("notifica con extensión no soportada", function()
  local f = tmpdir .. "/raro.xyz123"
  vim.fn.writefile({ "x" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  vim.bo.filetype = ""

  local ft = fake_terminal()
  local entry, key = cr._build_entry(require("code-runner.actions").get_actions(), ft)

  T.falsy(entry)
  T.eq(nil, key)
  T.eq(1, #ft.notified, "debió notificar")
end)

T.it("la extensión tiene prioridad sobre el filetype", function()
  local f = tmpdir .. "/nota.lua"
  vim.fn.writefile({ "-- x" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  vim.bo.filetype = "make" -- filetype incorrecto a propósito

  local _, key = cr._build_entry(require("code-runner.actions").get_actions(), fake_terminal())
  T.eq("lua", key)
end)

T.section("init: API pública")

T.it("expone la API pública: build_run, run_last, run_history y state", function()
  T.truthy(type(cr.build_run) == "function")
  T.truthy(type(cr.run_last) == "function")
  T.truthy(type(cr.run_history) == "function")
  T.truthy(type(cr.state) == "function")
  T.truthy(cr.state().status, "retorna el estado central (copiado)")
end)

T.it("API pública completa: run, context, stop, restart, register_action", function()
  T.truthy(type(cr.run) == "function", "run")
  T.eq(cr.run, cr.build_run, "run es alias de build_run")
  T.truthy(type(cr.stop) == "function", "stop")
  T.truthy(type(cr.restart) == "function", "restart")
  T.truthy(type(cr.context) == "function", "context")
  T.truthy(type(cr.register_action) == "function", "register_action")
  T.truthy(type(cr.unregister_action) == "function", "unregister_action")
  T.truthy(type(cr.list_registered_actions) == "function", "list_registered_actions")
end)

T.it("context() detecta el contexto del key dado", function()
  local cctx = cr.context("lua")
  T.truthy(type(cctx) == "table", "context retorna tabla")
  T.eq("lua", cctx.key, "key inferido/resuelto")
end)

T.it("_context_vars traduce cctx a variables de contexto", function()
  local vars = cr._context_vars {
    test = { name = "TestFoo" },
    entry = { name = "main", line = 12 },
  }
  T.eq("TestFoo", vars["$testName"], "$testName")
  T.eq("main", vars["$entry"], "$entry")
  T.eq("12", vars["$entryLine"], "$entryLine")
end)

T.it("_context_vars usa fqcn para $entry cuando existe", function()
  local vars = cr._context_vars {
    entry = { name = "main", fqcn = "com.demo.App", line = 9 },
  }
  T.eq("com.demo.App", vars["$entry"], "$entry usa fqcn")
end)

T.it("_context_vars con cctx vacío no inyecta nada", function()
  local vars = cr._context_vars { key = "lua" }
  T.falsy(vars["$testName"], "sin test")
  T.falsy(vars["$entry"], "sin entry")
end)

T.it("shell substituye $testName y $entry en el comando de una task", function()
  local shell = require "code-runner.shell"
  local cmd = shell.substitute("go test -run \"$testName\" --entry $entry", {
    ["$testName"] = "TestFoo",
    ["$entry"] = "main",
  })
  T.truthy(cmd:find("TestFoo", 1, true), "$testName resuelto")
  T.truthy(cmd:find("--entry main", 1, true), "$entry resuelto")
end)

T.it("una task de proyecto recibe $testName y $entry desde el contexto", function()
  local registry = require "code-runner.actions.registry"
  local terminal = require "code-runner.terminal"
  local picker = require "code-runner.picker"

  -- buffer go con un entry (main) y un test bajo el cursor
  local f = tmpdir .. "/ctx_task.go"
  vim.fn.writefile({
    "package demo",
    "",
    "func main() {",
    "  _ = 1",
    "}",
    "",
    "func TestGreet(t *testing.T) {",
    "  _ = 1",
    "}",
  }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  vim.api.nvim_win_set_cursor(0, { 7, 1 })

  -- task del proyecto (como haría .code-runner.lua vía el registry)
  registry.reset()
  cr.register_action {
    id = "task_dev",
    filetypes = { "go" },
    kind = "run",
    command = 'go test -run "$testName" --entry $entry',
  }

  -- capturamos el callback y el comando que llega a terminal.open
  local orig_select = picker.select
  local orig_open = terminal.open
  local chosen, opened
  picker.select = function(_, _, cb)
    chosen = cb
  end
  terminal.open = function(cmd, _, cwd, label)
    opened = { cmd = cmd, cwd = cwd, label = label }
  end

  local ok = pcall(cr.build_run)

  T.truthy(ok, "build_run no lanza")

  local entry = require("code-runner.actions").get_actions().go
  local label
  for _, l in ipairs(entry.__order) do
    if l:find("task_dev", 1, true) then
      label = l
    end
  end
  if chosen then
    chosen(label)
  end

  T.truthy(opened, "la task se ejecutó por terminal")
  T.truthy(opened and opened.cmd:find('"TestGreet"', 1, true), "$testName inyectado")
  T.truthy(opened and opened.cmd:find("--entry main", 1, true), "$entry inyectado (fqcn o name)")
  T.truthy(opened and opened.label and opened.label:find("task_dev", 1, true), "label de la task")

  terminal.open = orig_open
  picker.select = orig_select
  registry.reset()
end)

T.it("run_last reproduce una task de proyecto con sus variables de contexto", function()
  local registry = require "code-runner.actions.registry"
  local terminal = require "code-runner.terminal"
  local picker = require "code-runner.picker"

  local f = tmpdir .. "/ctx_task2.go"
  vim.fn.writefile({
    "package demo",
    "",
    "func main() {",
    "  _ = 1",
    "}",
    "",
    "func TestSum(t *testing.T) {",
    "  _ = 1",
    "}",
  }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  vim.api.nvim_win_set_cursor(0, { 7, 1 })

  registry.reset()
  cr.register_action {
    id = "task_test",
    filetypes = { "go" },
    kind = "test",
    command = 'go test -run "$testName" --entry $entry',
  }

  local orig_select = picker.select
  local orig_open = terminal.open
  local chosen, calls = nil, {}
  picker.select = function(_, _, cb)
    chosen = cb
  end
  terminal.open = function(cmd)
    table.insert(calls, cmd)
  end

  -- primera ejecución: elegimos la task
  local ok1 = pcall(cr.build_run)
  local entry = require("code-runner.actions").get_actions().go
  local label
  for _, l in ipairs(entry.__order) do
    if l:find("task_test", 1, true) then
      label = l
    end
  end
  if chosen then
    chosen(label)
  end

  T.truthy(ok1, "build_run ok")
  T.eq(1, #calls, "primera ejecución")
  T.truthy(calls[1] and calls[1]:find('"TestSum"', 1, true), "$testName en la primera")

  -- run_last reproduce la misma task con las mismas vars (sin reabrir picker)
  local ok2 = pcall(cr.run_last)
  T.truthy(ok2, "run_last ok")
  T.eq(2, #calls, "run_last re-ejecutó")
  T.truthy(calls[2] and calls[2]:find('"TestSum"', 1, true), "$testName reproducido en run_last")
  T.truthy(calls[2] and calls[2]:find("--entry main", 1, true), "$entry reproducido en run_last")

  terminal.open = orig_open
  picker.select = orig_select
  registry.reset()
end)

T.it("run_last sin ejecución previa notifica WARN", function()
  local terminal = require "code-runner.terminal"
  local original_notify = terminal.notify
  local notified = {}
  terminal.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  package.loaded["code-runner"] = nil
  local fresh = require "code-runner"
  fresh.run_last()

  terminal.notify = original_notify
  package.loaded["code-runner"] = nil

  T.eq(1, #notified, "una sola notificación")
  T.eq(vim.log.levels.WARN, notified[1].level)
end)

T.it("setup recarga la última ejecución persistida (sobrevive al reinicio)", function()
  -- usamos la etiqueta REAL de una acción de lua (con icono)
  local lua_entry = require("code-runner.actions").get_actions().lua
  local label = lua_entry.__order[#lua_entry.__order] -- la última de lua es "Run"

  -- persiste una 'última ejecución' como haría una sesión anterior
  local m = vim.fn.stdpath("data") .. "/code-runner"
  vim.fn.mkdir(m, "p")
  local file = m .. "/last.json"
  vim.fn.writefile({ vim.json.encode({ lang = "lua", choice = label }) }, file)

  -- simulamos reinicio: recargamos code-runner y llamamos setup (que debe
  -- poblar last_choice desde disco)
  require("code-runner.last")._data_file = file
  package.loaded["code-runner"] = nil
  local cr2 = require "code-runner"
  cr2.setup {}

  local terminal = require "code-runner.terminal"
  local original_notify = terminal.notify
  local calls = 0
  local msgs = {}
  terminal.notify = function(msg, level)
    calls = calls + 1
    msgs[#msgs + 1] = tostring(msg)
  end

  cr2.run_last()

  T.eq(0, calls, "run_last no avisa 'no hay ejecución': hay una cargada")

  terminal.notify = original_notify
  pcall(os.remove, file)
end)

T.section("init: identidad task_id en historial y last (EXEC-009 slice 2)")

T.it("build_run con tracking guarda task_id en historial y last", function()
  local terminal = require "code-runner.terminal"
  local tracking = require "code-runner.terminal.tracking"
  local picker = require "code-runner.picker"
  local history = require "code-runner.history"
  local last = require "code-runner.last"

  local f = tmpdir .. "/identity.lua"
  vim.fn.writefile({ "print(1)" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))

  -- historial y last aislados
  local saved_hist, saved_last = history._data_file, last._data_file
  local htmp, ltmp = os.tmpname(), os.tmpname()
  history._data_file, last._data_file = htmp, ltmp
  tracking.reset()

  -- open simulado con el contrato nuevo: devuelve exec_id y trackea
  local orig_select, orig_open = picker.select, terminal.open
  picker.select = function(items, _, cb)
    cb(items[1])
  end
  terminal.open = function(cmd, _, cwd, label)
    return tracking.start(cmd, "lua", label)
  end

  local ok = pcall(cr.build_run)
  T.truthy(ok, "build_run no lanza")

  local items = history.list()
  T.eq(1, #items)
  T.truthy(items[1].task_id, "el historial lleva task_id")
  T.truthy(items[1].task_id:find("^lua%.", 1) == 1, "derivado de la key")

  local persisted = last.get()
  T.truthy(persisted and persisted.task_id, "last lleva task_id")
  T.eq(items[1].task_id, persisted.task_id, "misma identidad en ambos")

  picker.select, terminal.open = orig_select, orig_open
  history._data_file, last._data_file = saved_hist, saved_last
  pcall(os.remove, htmp)
  pcall(os.remove, ltmp)
  tracking.reset()
  config.options = vim.deepcopy(config.defaults)
end)

T.it("build_run sin tracking registra legacy sin identidad", function()
  local terminal = require "code-runner.terminal"
  local picker = require "code-runner.picker"
  local history = require "code-runner.history"

  local f = tmpdir .. "/identity_legacy.lua"
  vim.fn.writefile({ "print(1)" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))

  local saved_hist = history._data_file
  local htmp = os.tmpname()
  history._data_file = htmp
  require("code-runner.terminal.tracking").reset()

  -- open stub legacy: devuelve nil (sin tracking, p.ej. chain &&)
  local orig_select, orig_open = picker.select, terminal.open
  picker.select = function(items, _, cb)
    cb(items[1])
  end
  terminal.open = function()
    return nil
  end

  local ok = pcall(cr.build_run)
  T.truthy(ok, "build_run no lanza")

  local items = history.list()
  T.eq(1, #items)
  T.eq(nil, items[1].task_id, "legacy sin identidad, como antes")

  picker.select, terminal.open = orig_select, orig_open
  history._data_file = saved_hist
  pcall(os.remove, htmp)
  config.options = vim.deepcopy(config.defaults)
end)

T.section("init: resolución operativa por task_id (EXEC-009 slice 3)")

-- build_run con tracking simulado + comando que evoluciona entre lanzamientos.
local function build_with_tracking(ext, custom_id, custom_cmd)
  local terminal = require "code-runner.terminal"
  local tracking = require "code-runner.terminal.tracking"
  local picker = require "code-runner.picker"

  local f = tmpdir .. "/slice3." .. ext
  vim.fn.writefile({ "print(1)" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))

  require("code-runner.actions.registry").reset()
  cr.register_action { id = custom_id, filetypes = { "lua" }, kind = "run", command = custom_cmd }

  local orig_select, orig_open = picker.select, terminal.open
  local opened = {}
  picker.select = function(items, _, cb)
    for _, l in ipairs(items) do
      if l:find(custom_id, 1, true) then
        cb(l)
        return
      end
    end
  end
  terminal.open = function(cmd, _, cwd, label)
    table.insert(opened, cmd)
    return tracking.start(cmd, "lua", label)
  end

  pcall(cr.build_run)

  picker.select, terminal.open = orig_select, orig_open
  return opened
end

T.it("run_last usa la plantilla vigente, no el comando guardado", function()
  local history = require "code-runner.history"
  local last = require "code-runner.last"
  local terminal = require "code-runner.terminal"
  local tracking = require "code-runner.terminal.tracking"

  local saved_hist, saved_last = history._data_file, last._data_file
  history._data_file, last._data_file = os.tmpname(), os.tmpname()
  tracking.reset()

  build_with_tracking("lua", "op_evolve_run", "mytool --opt A")

  -- la plantilla evoluciona (mismo id, nuevo comando)
  cr.register_action { id = "op_evolve_run", filetypes = { "lua" }, kind = "run", command = "mytool --opt B" }

  local opened = {}
  local orig_open = terminal.open
  terminal.open = function(cmd)
    table.insert(opened, cmd)
    return nil
  end

  local ok = pcall(cr.run_last)
  terminal.open = orig_open

  T.truthy(ok, "run_last no lanza")
  T.eq(1, #opened)
  T.truthy(opened[1]:find("--opt B", 1, true), "plantilla vigente, no replay ciego")

  history._data_file, last._data_file = saved_hist, saved_last
  tracking.reset()
  require("code-runner.actions.registry").reset()
  config.options = vim.deepcopy(config.defaults)
end)

T.it("run_last con tarea eliminada cae al replay legacy sin romper", function()
  local terminal = require "code-runner.terminal"
  local tracking = require "code-runner.terminal.tracking"

  tracking.reset()
  build_with_tracking("lua", "op_gone_run", "mytool --opt A")
  require("code-runner.actions.registry").reset() -- la tarea ya no existe

  local opened, notified = {}, {}
  local orig_open, orig_notify = terminal.open, terminal.notify
  terminal.open = function(cmd)
    table.insert(opened, cmd)
    return nil
  end
  terminal.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  local ok = pcall(cr.run_last)

  terminal.open, terminal.notify = orig_open, orig_notify
  T.truthy(ok, "nunca falla duro")
  -- legacy: reejecuta el comando guardado o avisa que la acción no existe
  T.truthy(#opened == 1 or #notified >= 1, "fallback explícito")

  tracking.reset()
  config.options = vim.deepcopy(config.defaults)
end)

T.it("run_history con status failed re-ejecuta igual (no es autoridad viva)", function()
  local terminal = require "code-runner.terminal"
  local picker = require "code-runner.picker"
  local history = require "code-runner.history"

  local saved_hist = history._data_file
  history._data_file = os.tmpname()
  history.clear()
  history.add("pytest -q", "C:/p", "py", { status = "failed" })

  local orig_select, orig_open = picker.select, terminal.open
  local opened = {}
  picker.select = function(items, _, cb)
    cb(items[1])
  end
  terminal.open = function(cmd)
    table.insert(opened, cmd)
    return nil
  end

  pcall(cr.run_history)

  picker.select, terminal.open = orig_select, orig_open
  T.eq(1, #opened, "el status registrado no bloquea")
  T.eq("pytest -q", opened[1])

  history._data_file = saved_hist
  config.options = vim.deepcopy(config.defaults)
end)

T.it("run_history con task_id desconocida reejecuta el comando guardado", function()
  local terminal = require "code-runner.terminal"
  local picker = require "code-runner.picker"
  local history = require "code-runner.history"

  local saved_hist = history._data_file
  history._data_file = os.tmpname()
  history.clear()
  history.add("pytest -q", "C:/p", "py", { task_id = "py.noexiste", vars = { ["$x"] = "1" } })

  local orig_select, orig_open = picker.select, terminal.open
  local opened = {}
  picker.select = function(items, _, cb)
    cb(items[1])
  end
  terminal.open = function(cmd)
    table.insert(opened, cmd)
    return nil
  end

  local ok = pcall(cr.run_history)

  picker.select, terminal.open = orig_select, orig_open
  T.truthy(ok, "nunca falla duro")
  T.eq(1, #opened)
  T.eq("pytest -q", opened[1], "fallback al comando guardado")

  history._data_file = saved_hist
  config.options = vim.deepcopy(config.defaults)
end)

T.it("re-lanzar desde historial crea ejecución nueva (no reutiliza id)", function()
  local terminal = require "code-runner.terminal"
  local tracking = require "code-runner.terminal.tracking"
  local picker = require "code-runner.picker"
  local history = require "code-runner.history"

  local saved_hist = history._data_file
  history._data_file = os.tmpname()
  history.clear()
  tracking.reset()

  local orig_select, orig_open = picker.select, terminal.open
  local seen_ids = {}
  picker.select = function(items, _, cb)
    cb(items[1])
  end
  terminal.open = function(cmd, _, cwd, label)
    local id = tracking.start(cmd, "py", label)
    table.insert(seen_ids, id)
    return id
  end

  history.add("pytest -q", "C:/p", "py")
  pcall(cr.run_history)
  pcall(cr.run_history)

  picker.select, terminal.open = orig_select, orig_open
  T.eq(2, #seen_ids)
  T.truthy(seen_ids[1] ~= seen_ids[2], "invariante 1: execution_id nunca se reutiliza")
  T.eq(seen_ids[2], history.list()[1].execution_id, "el historial apunta a la última")

  history._data_file = saved_hist
  tracking.reset()
  config.options = vim.deepcopy(config.defaults)
end)

T.section("init: stop()")

T.it("stop sin ejecución en marcha es un no-op (no rompe nada)", function()
  require("code-runner.state").set("idle")
  cr.stop()
  T.eq("idle", require("code-runner.state").get().status)
end)

T.it("stop cancela el job del plugin y libera su buffer", function()
  local terminal = require "code-runner.terminal"
  local state = require "code-runner.state"

  kill_plugin_terminals()
  state.set("idle")
  terminal.open("echo 'para detener'", "horizontal")

  T.eq("running", state.get().status)
  local buf = state.get().buf
  T.truthy(buf and vim.api.nvim_buf_is_valid(buf), "el estado guarda el buffer del job")

  cr.stop()

  T.eq("cancelled", state.get().status, "stop => cancelled")
  T.falsy(vim.api.nvim_buf_is_valid(buf), "el buffer del job fue liberado (el job murió con él)")
end)

T.it("stop no toca terminales externas (solo el buffer registrado)", function()
  local terminal = require "code-runner.terminal"
  local state = require "code-runner.state"
  local save_notify = terminal.notify
  terminal.notify = function() end

  -- terminal AJENA con su propio job vivo y de larga vida (multiplataforma)
  local foreign = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(foreign, "foreign_terminal")
  local foreign_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(foreign_win, foreign)
  local sleep_cmd = vim.fn.has "win32" == 1 and "ping -n 300 127.0.0.1" or "sleep 30"
  vim.fn.termopen(sleep_cmd, { on_exit = function() end })

  state.set("idle")
  terminal.open("echo 'del plugin'", "horizontal")

  cr.stop()

  T.truthy(vim.api.nvim_buf_is_valid(foreign), "la terminal ajena sigue viva")
  T.falsy(vim.b[foreign].code_runner_term, "la ajena no lleva el marcador del plugin")
  T.eq("terminal", vim.bo[foreign].buftype, "sigue siendo una terminal (su job intacto)")
  T.falsy(
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(foreign), ":t") == "code-runner",
    "su nombre es term://..., nunca code-runner"
  )

  -- limpieza: detener el job ajeno para no ensuciar los specs siguientes
  if vim.api.nvim_buf_is_valid(foreign) then
    pcall(vim.api.nvim_buf_delete, foreign, { force = true })
  end

  terminal.notify = save_notify
end)

T.section("init: restart()")

T.it("restart sin job en marcha y sin ejecución previa notifica WARN (de run_last)", function()
  local state = require "code-runner.state"
  state.set("idle")

  -- reinicia code-runner sin setup: last_choice queda nil (sin persistencia
  -- cargada en memoria), por lo que run_last avisa que no hay ejecución previa
  local last_m = require "code-runner.last"
  local saved_file = last_m._data_file
  last_m._data_file = os.tmpname()
  last_m.clear()

  package.loaded["code-runner"] = nil
  local cr_fresh = require "code-runner"

  local terminal = require "code-runner.terminal"
  local original_notify = terminal.notify
  local notified = {}
  terminal.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  cr_fresh.restart()

  T.truthy(#notified >= 1, "avisa que no hay ejecución previa")
  T.eq(vim.log.levels.WARN, notified[#notified].level)
  T.eq("idle", state.get().status, "no quedó en running")

  terminal.notify = original_notify
  last_m._data_file = saved_file
  package.loaded["code-runner"] = nil
  cr = require "code-runner"
end)

T.it("restart detiene el job en marcha de forma silenciosa", function()
  -- contrato principal de restart: el job en marcha se cancela ANTES de delegar
  -- en run_last (que es quien relanza). Se verifica la parte de stop silencioso
  -- aislada: _stop_silent cancela sin notificar.
  local terminal = require "code-runner.terminal"
  local state = require "code-runner.state"
  local original_notify = terminal.notify
  local notified = {}
  terminal.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  state.set("idle")
  kill_plugin_terminals()
  terminal.open("echo 'seed'", "horizontal")
  T.eq("running", state.get().status)
  local seed_buf = state.get().buf

  cr._stop_silent()

  T.eq("cancelled", state.get().status, "stop silencioso => cancelled")
  T.falsy(vim.api.nvim_buf_is_valid(seed_buf), "liberó el buffer del job")
  T.eq(0, #notified, "stop silencioso: ninguna notificación")

  terminal.notify = original_notify
end)

T.section("plugin: comandos de usuario")

T.it("registra :CodeRun, :CodeRunLast, :CodeRunHistory, :CodeRunStop y :CodeRunRestart", function()
  dofile(PLUG_ROOT .. "/plugin/code-runner.lua")
  local cmds = vim.api.nvim_get_commands {}
  T.truthy(cmds.CodeRun, ":CodeRun registrado")
  T.truthy(cmds.CodeRunLast, ":CodeRunLast registrado")
  T.truthy(cmds.CodeRunHistory, ":CodeRunHistory registrado")
  T.truthy(cmds.CodeRunStop, ":CodeRunStop registrado")
  T.truthy(cmds.CodeRunRestart, ":CodeRunRestart registrado")
end)

T.it("el guard evita doble registro", function()
  local before = vim.api.nvim_get_commands {}
  dofile(PLUG_ROOT .. "/plugin/code-runner.lua") -- segunda carga: early return
  local after = vim.api.nvim_get_commands {}
  T.eq(before.CodeRun.definition, after.CodeRun.definition)
end)

config.options = vim.deepcopy(config.defaults)
