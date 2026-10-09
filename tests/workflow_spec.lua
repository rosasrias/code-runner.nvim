local workflow = require "code-runner.workflow"
local shell = require "code-runner.shell"

-- Blindaje: los tests con comandos reales usan la plataforma real, no el
-- valor que otros tests hayan dejado en shell.IS_WIN.
local PLATFORM_WIN = vim.fn.has "win32" == 1

local function clean()
  workflow.reset()
  require("code-runner.projectrc").clear_cache()
end

-- Core síncrono `execute` con run_step inyectado (sin procesos reales).

T.section("workflow: execute (núcleo secuencial)")

T.it("corre todos los pasos en orden (sin stop_on_fail)", function()
  clean()
  local called = {}
  local spec = { name = "t", steps = { "a", "b", "c" }, stop_on_fail = false }

  local res = workflow.execute(spec, function(cmd)
    table.insert(called, cmd)
    return cmd == "b" and 1 or 0
  end)

  T.eq(3, #called, "los 3 pasos se ejecutan")
  T.eq("a", called[1])
  T.eq("b", called[2])
  T.eq("c", called[3])
  T.falsy(res.ok, "resultado global false por el paso fallido")
  T.eq(3, #res.results, "hay resultado por cada paso")
  T.eq(0, res.results[1].code)
  T.eq(1, res.results[2].code)
  T.eq(0, res.results[3].code)
end)

T.it("con stop_on_fail se detiene en el primer error", function()
  clean()
  local called = {}
  local spec = { name = "t", steps = { "ok", "bad", "never" }, stop_on_fail = true }

  local res = workflow.execute(spec, function(cmd)
    table.insert(called, cmd)
    return cmd == "bad" and 2 or 0
  end)

  T.eq(2, #called, "no corre el paso posterior al error")
  T.eq("ok", called[1])
  T.eq("bad", called[2])
  T.falsy(res.ok)
  T.eq(2, #res.results, "solo hay resultados de los pasos corridos")
end)

T.it("stop_on_fail por defecto es true", function()
  clean()
  -- El default lo normaliza `register`; se ejecuta sobre el spec registrado.
  workflow.register({ name = "t", steps = { "bad", "never" } })
  local called = {}

  workflow.execute(workflow.list().t, function(cmd)
    table.insert(called, cmd)
    return cmd == "bad" and 1 or 0
  end)

  T.eq(1, #called, "default detiene en el primer error")
end)

T.it("todo OK devuelve ok=true y para por todos los pasos", function()
  clean()
  local called = 0
  local spec = { name = "t", steps = { "a", "b" } }

  local res = workflow.execute(spec, function()
    called = called + 1
    return 0
  end)

  T.truthy(res.ok)
  T.eq(2, called)
end)

T.it("sustituye $file en los pasos", function()
  clean()
  local dir = vim.fn.tempname() .. "/cr_wf_sub"
  vim.fn.mkdir(dir, "p")
  local f = dir .. "/x.py"
  vim.fn.writefile({ "print(1)" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))

  local seen = nil
  local spec = { name = "t", steps = { "python %" } }

  workflow.execute(spec, function(cmd)
    seen = cmd
    return 0
  end)

  T.eq("python " .. f, seen, "$file se sustituye por la ruta del buffer (sin comillas)")
end)

T.section("workflow: register / list / reset")

T.it("registra una task y la lista", function()
  clean()
  workflow.register({ name = "ci", steps = { "go build ./...", "go test ./..." } })

  local list = workflow.list()
  T.truthy(list.ci, "task registrada")
  T.eq(2, #list.ci.steps)
  T.truthy(list.ci.stop_on_fail, "stop_on_fail default true")
end)

T.it("re-registrar el mismo nombre reemplaza", function()
  clean()
  workflow.register({ name = "x", steps = { "v1" } })
  workflow.register({ name = "x", steps = { "v2" } })
  T.eq(1, #workflow.list().x.steps)
  T.eq("v2", workflow.list().x.steps[1])
end)

T.it("steps vacío lanza error (no se registra mal)", function()
  clean()
  local ok = pcall(workflow.register, { name = "mal", steps = {} })
  T.falsy(ok, "steps vacío rechazado")
  T.falsy(workflow.list().mal, "no queda registrada")
end)

T.it("reset limpia las tasks", function()
  clean()
  workflow.register({ name = "t", steps = { "a" } })
  workflow.reset()
  T.falsy(workflow.list().t, "sin tasks tras reset")
end)

T.section("workflow: parallel register")

T.it("parallel=true normaliza a #steps", function()
  clean()
  workflow.register({ name = "t", steps = { "a", "b", "c" }, parallel = true })
  T.eq(3, workflow.list().t.parallel, "true → número de pasos")
end)

T.it("parallel=N acota la concurrencia y conserva el número", function()
  clean()
  workflow.register({ name = "t", steps = { "a", "b", "c" }, parallel = 2 })
  T.eq(2, workflow.list().t.parallel, "se conserva el límite")
end)

T.it("parallel ausente/false queda falsy (secuencial)", function()
  clean()
  workflow.register({ name = "t", steps = { "a", "b" } })
  T.falsy(workflow.list().t.parallel, "default secuencial")
end)

T.section("workflow: parallel execute (núcleo síncrono)")

T.it("ejecuta todos los pasos sin stop_on_fail", function()
  clean()
  local called = {}
  local n = 100 -- ejercicio de la ruta con vim.wait
  local function run_step(cmd)
    table.insert(called, cmd)
    vim.wait(1)
    return 0
  end
  local spec = workflow.list().t or { name = "t", steps = {} }

  -- registro con parallel=true
  workflow.register({ name = "t", steps = { "a", "b", "c" }, parallel = true })
  local res = workflow.execute(workflow.list().t, run_step)

  T.eq(3, #called, "se ejecutan los 3 pasos")
  T.truthy(res.ok, "todo ok")
  T.eq(3, #res.results, "hay resultado por cada paso")
end)

T.it("con un fallo y stop_on_fail reporta ok=false", function()
  clean()
  workflow.register({ name = "t", steps = { "ok", "bad", "never" }, parallel = true })

  local res = workflow.execute(workflow.list().t, function(cmd)
    vim.wait(1)
    return cmd == "bad" and 2 or 0
  end)

  T.falsy(res.ok, "fallo detectado")
  T.eq(3, #res.results, "en paralelo corren todos los pasos lanzados")
end)

T.section("workflow: parallel.run con jobstart real")

if vim.fn.executable "python" == 1 or PLATFORM_WIN then
  T.it("on_done llega con todos los resultados correctos", function()
    clean()
    local base = PLATFORM_WIN and "cmd /c exit" or "sh -c 'exit'"
    -- usamos comandos con exit code determinista
    local ok_cmd = PLATFORM_WIN and "cmd /c exit 0" or "true"
    local bad_cmd = PLATFORM_WIN and "cmd /c exit 3" or "false"
    local steps = { ok_cmd, ok_cmd, bad_cmd, ok_cmd }
    workflow.register({ name = "par", steps = steps, parallel = true })

    local done_once = false
    local final = nil

    workflow.run("par", function(result)
      final = result
      done_once = true
    end)

    -- espera a que el callback corra
    local deadline = vim.loop.hrtime() + 5e9
    while not done_once and vim.loop.hrtime() < deadline do
      vim.wait(20)
    end

    T.truthy(done_once, "on_done se llama")
    if final then
      T.eq(4, #final.results, "4 pasos corridos")
      T.eq(0, final.results[1].code)
      T.truthy(final.results[3].code ~= 0, "el tercer paso falló")
      T.falsy(final.ok, "task fallada por el paso malo")
    end
  end)

  T.it("parallel acotado (N) lanza máximo N a la vez", function()
    clean()
    local ok_cmd = PLATFORM_WIN and "cmd /c exit 0" or "true"
    local steps = {}
    for _ = 1, 6 do
      steps[#steps + 1] = ok_cmd
    end
    workflow.register({ name = "bounded", steps = steps, parallel = 2 })

    local done_once = false
    local active = 0
    local max_active = 0
    local final = nil

    local orig_run_step = workflow.run_step
    workflow.run_step = function(cmd, cwd, on_exit)
      active = active + 1

      if active > max_active then
        max_active = active
      end

      return orig_run_step(cmd, cwd, function(code)
        active = active - 1
        on_exit(code)
      end)
    end

    workflow.run("bounded", function(result)
      final = result
      done_once = true
    end)

    local deadline = vim.loop.hrtime() + 5e9
    while not done_once and vim.loop.hrtime() < deadline do
      vim.wait(20)
    end

    workflow.run_step = orig_run_step

    T.truthy(done_once, "on_done se llama")
    T.eq(2, max_active, "nunca más de 2 concurrentes")
    T.truthy(final and final.ok, "todos los pasos OK")
  end)
else
  T.skip("parallel jobstart", "necesita una shell real (python/cmd) para el E2E")
end

T.section("workflow: dispatch desde .code-runner.lua")

if vim.fn.executable "python" == 1 or PLATFORM_WIN then
  T.it("un paso exitoso reporta exit 0", function()
    clean()
    local cmd = PLATFORM_WIN and "cmd /c exit 0" or "true"
    shell.IS_WIN = PLATFORM_WIN
    local job = workflow.run_step(cmd, nil, function() end)
    vim.fn.jobwait({ job })

    local code = nil
    local called = 0
    job = workflow.run_step(cmd, nil, function(c)
      code = c
      called = called + 1
    end)
    vim.fn.jobwait({ job })

    T.eq(1, called, "on_exit se llamó")
    T.eq(0, code, "exit code 0")
  end)

  T.it("un paso que falla reporta exit != 0", function()
    clean()
    local cmd = PLATFORM_WIN and "cmd /c exit 7" or "false"
    shell.IS_WIN = PLATFORM_WIN
    local code = nil
    local job = workflow.run_step(cmd, nil, function(c)
      code = c
    end)
    vim.fn.jobwait({ job })

    T.truthy(code ~= nil and code ~= 0, "exit code distinto de cero")
  end)
else
  T.skip("pasos headless", "necesita una shell real (python/cmd) para el E2E")
end

T.section("workflow: dispatch desde .code-runner.lua")

T.it("una task con steps se registra en el engine (no en el picker)", function()
  clean()
  local root = vim.fn.tempname() .. "/cr_wf_dot"
  vim.fn.mkdir(root, "p")
  vim.fn.writefile({ "module demo" }, root .. "/go.mod")
  vim.fn.writefile({
    "return { tasks = {",
    "  ci = { steps = { 'go build ./...', 'go test ./...' } },",
    "  picker = { filetypes = { 'zzz' }, kind = 'run', command = 'pick %' },",
    "} }",
  }, root .. "/.code-runner.lua")

  T.truthy(require("code-runner.projectrc").load("go", root))

  local wf = workflow.list()
  T.truthy(wf.ci, "task con steps en el motor")
  T.eq(2, #wf.ci.steps)
  T.eq(root, wf.ci.cwd, "cwd = raíz del proyecto")
  T.falsy(wf.picker, "la tarea command NO va al motor")

  local entry = require("code-runner.actions").get_actions()["zzz"]
  T.truthy(entry, "la tarea command sí va al picker")
  T.falsy(entry.ci, "la task con steps no aparece en el picker")

  clean()
end)

T.section("workflow: ciclo de vida por el Engine (slice 6)")

if vim.fn.executable "python" == 1 or PLATFORM_WIN then
  T.it("run() conduce cada paso por running→success del Engine", function()
    clean()
    local engine = require "code-runner.engine"
    local ok_cmd = PLATFORM_WIN and "cmd /c exit 0" or "true"
    workflow.register({ name = "eng", steps = { ok_cmd, ok_cmd }, stop_on_fail = true })

    local seen = {}
    engine.set_listener(function(exec)
      table.insert(seen, exec.status .. ":" .. exec.task_id)
    end)

    local final = nil
    workflow.run("eng", function(result)
      final = result
    end)

    local deadline = vim.loop.hrtime() + 10e9
    while final == nil and vim.loop.hrtime() < deadline do
      vim.wait(20)
    end
    engine.set_listener(nil)

    T.truthy(final and final.ok, "el workflow completa")
    T.truthy(vim.tbl_contains(seen, "running:eng.step-1"), "paso 1 por el Engine")
    T.truthy(vim.tbl_contains(seen, "success:eng.step-1"), "paso 1 finalizado")
    T.truthy(vim.tbl_contains(seen, "running:eng.step-2"), "paso 2 por el Engine")
    T.truthy(vim.tbl_contains(seen, "success:eng.step-2"), "sin segundo orquestador")
    clean()
  end)

  T.it("dos corridas no comparten identidad de ejecución", function()
    clean()
    local engine = require "code-runner.engine"
    local ok_cmd = PLATFORM_WIN and "cmd /c exit 0" or "true"
    workflow.register({ name = "twice", steps = { ok_cmd }, stop_on_fail = true })

    local ids = {}
    engine.set_listener(function(exec)
      if exec.status == "running" then
        table.insert(ids, exec.id)
      end
    end)

    local n = 0
    local function once()
      workflow.run("twice", function()
        n = n + 1
      end)
    end
    once()

    local deadline = vim.loop.hrtime() + 10e9
    while n < 1 and vim.loop.hrtime() < deadline do
      vim.wait(20)
    end
    once()
    deadline = vim.loop.hrtime() + 10e9
    while n < 2 and vim.loop.hrtime() < deadline do
      vim.wait(20)
    end
    engine.set_listener(nil)

    T.eq(2, n, "ambas corridas completan")
    T.eq(2, #ids, "una Execution running por corrida")
    T.truthy(ids[1] ~= ids[2], "invocaciones distintas, ids distintos")
    clean()
  end)

  T.it("fallo de spawn avisa on_exit(-1) en vez de colgar", function()
    clean()
    local code, count = nil, 0
    local job = workflow.run_step("echo x", "/cwd/inexistente/cr_test", function(c)
      code = c
      count = count + 1
    end)

    T.eq(nil, job, "sin job válido")
    T.eq(1, count, "on_exit llega igual")
    T.eq(-1, code, "código de fallo de lanzamiento")
    clean()
  end)

  T.it("paso con && corre como una Execution del proceso spawneado", function()
    clean()
    local engine = require "code-runner.engine"
    local chain = PLATFORM_WIN and "cmd /c exit 0 && cmd /c exit 0" or "true && true"
    workflow.register({ name = "chain", steps = { chain }, stop_on_fail = true })

    local seen = {}
    engine.set_listener(function(exec)
      table.insert(seen, exec.status .. ":" .. exec.task_id)
    end)

    local final = nil
    workflow.run("chain", function(result)
      final = result
    end)

    local deadline = vim.loop.hrtime() + 10e9
    while final == nil and vim.loop.hrtime() < deadline do
      vim.wait(20)
    end
    engine.set_listener(nil)

    T.truthy(final and final.ok, "el chain completa")
    T.truthy(vim.tbl_contains(seen, "running:chain.step-1"), "trackeado, no legacy")
    T.truthy(vim.tbl_contains(seen, "success:chain.step-1"), "un proceso, un Result")
    clean()
  end)
else
  T.skip("workflow Engine", "necesita una shell real (python/cmd)")
end

T.section("workflow: execute* honra el Engine (slice 9, contrato)")

T.it("execute() transiciona cada paso: sin segundo ciclo de vida", function()
  clean()
  local engine = require "code-runner.engine"
  local seen = {}
  engine.set_listener(function(exec)
    table.insert(seen, exec.status .. ":" .. exec.task_id)
  end)

  local res = workflow.execute(
    { name = "sync", steps = { "a", "b" }, stop_on_fail = false },
    function()
      return 0
    end
  )
  engine.set_listener(nil)

  T.truthy(res.ok, "retorno intacto")
  T.eq(2, #res.results)
  T.truthy(vim.tbl_contains(seen, "running:sync.step-1"))
  T.truthy(vim.tbl_contains(seen, "success:sync.step-1"))
  T.truthy(vim.tbl_contains(seen, "running:sync.step-2"))
  T.truthy(vim.tbl_contains(seen, "success:sync.step-2"))
  clean()
end)

T.it("execute() clasifica el fallo en el Engine sin cambiar el retorno", function()
  clean()
  local engine = require "code-runner.engine"
  local seen = {}
  engine.set_listener(function(exec)
    table.insert(seen, exec.status .. ":" .. exec.task_id)
  end)

  local res = workflow.execute(
    { name = "syncfail", steps = { "bad" }, stop_on_fail = true },
    function()
      return 2
    end
  )
  engine.set_listener(nil)

  T.falsy(res.ok, "retorno intacto")
  T.truthy(vim.tbl_contains(seen, "failed:syncfail.step-1"))
  clean()
end)

T.it("execute_parallel() transiciona cada paso en el Engine", function()
  clean()
  local engine = require "code-runner.engine"
  workflow.register({ name = "pareng", steps = { "a", "b" }, parallel = true })

  local seen = {}
  engine.set_listener(function(exec)
    table.insert(seen, exec.status .. ":" .. exec.task_id)
  end)

  local res = workflow.execute(workflow.list().pareng, function()
    vim.wait(1)
    return 0
  end)
  engine.set_listener(nil)

  T.truthy(res.ok, "retorno intacto")
  T.truthy(vim.tbl_contains(seen, "success:pareng.step-1"))
  T.truthy(vim.tbl_contains(seen, "success:pareng.step-2"))
  clean()
end)

clean()
