local tracking = require "code-runner.terminal.tracking"

local function fresh()
  tracking.reset()
end

T.section("tracking: identidad tarea vs invocación (punto 1)")

T.it("cada start crea una Execution nueva con id fresco", function()
  fresh()

  local a = tracking.start("go run .", "go", "Run")
  local exec_a = tracking.get()
  local b = tracking.start("go run .", "go", "Run")
  local exec_b = tracking.get()

  T.truthy(a)
  T.truthy(b)
  T.truthy(a ~= b, "dos lanzamientos, dos ids")
  T.eq(a, exec_a.id)
  T.eq(b, exec_b.id)
  T.eq(exec_a.task_id, exec_b.task_id, "misma tarea")
end)

T.it("el reemplazo cancela la anterior: ninguna queda running huérfana", function()
  fresh()

  local a = tracking.start("go run .", "go", "Run")
  local b = tracking.start("go test ./...", "go", "Test")
  local current = tracking.get()

  T.eq(b, current.id)
  T.eq("running", current.status)
  -- la anterior ya no es la actual: su on_exit tardío no la toca
  T.falsy(tracking.finish(0, a))
  T.eq(b, tracking.get().id)
  T.eq("running", tracking.get().status)
end)

T.it("task_id estable: key+label mandan, sin iconos de presentación", function()
  fresh()

  tracking.start("go run .", "go", "▶ Run")
  local exec = tracking.get()

  T.eq("go.run", exec.task_id)
  T.falsy(exec.task_id:find("▶", 1, true))
end)

T.section("tracking: el guard es barrera real (punto 2)")

T.it("A, B, on_exit tardío de A: B intacta", function()
  fresh()

  local a = tracking.start("echo a", "go", "Run")
  local b = tracking.start("echo b", "go", "Run")
  local before = tracking.get()

  local res = tracking.finish(1, a)

  T.falsy(res, "el tardío de A se rechaza")
  local after = tracking.get()
  T.eq(b, after.id, "sigue siendo B")
  T.eq("running", after.status, "B no se toca")
  T.eq(before.id, after.id)
end)

T.it("el callback válido de B sí finaliza B", function()
  fresh()

  tracking.start("echo a", "go", "Run")
  local b = tracking.start("echo b", "go", "Run")

  local done = tracking.finish(0, b)

  T.truthy(done)
  T.eq("success", done.status)
  T.eq("success", tracking.get().status)
end)

T.it("doble finish: el segundo es no-op", function()
  fresh()

  local id = tracking.start("echo a", "go", "Run")
  tracking.finish(0, id)

  T.falsy(tracking.finish(1, id), "terminal ya no finaliza")
  T.eq("success", tracking.get().status)
end)

T.it("finish sin start es no-op", function()
  fresh()

  T.falsy(tracking.finish(0, 999))
  T.eq(nil, tracking.get())
end)

T.section("tracking: fallback explícito con && (punto 3)")

T.it("chain && no trackea pero deja motivo observable", function()
  fresh()

  local id = tracking.start("javac X.java && java X", "java", "Build")

  T.eq(nil, id, "sin Execution: legacy manda")
  T.eq(nil, tracking.get(), "nada a medio inicializar")
  local skip = tracking.skip_reason()
  T.truthy(skip, "fallback explícito")
  T.eq("command-no-normaliza", skip.reason)
  T.falsy(skip.cmd == nil, "conserva el comando para diagnóstico")
end)

T.it("un start válido limpia el skip anterior", function()
  fresh()

  tracking.start("a && b", "go", "Run")
  T.truthy(tracking.skip_reason())

  tracking.start("go run .", "go", "Run")
  T.eq(nil, tracking.skip_reason())
  T.eq("running", tracking.get().status)
end)

T.section("tracking: cancelación y cierre (punto 4)")

T.it("cancel → on_exit: el exit tardío no reabre ni finaliza", function()
  fresh()

  local id = tracking.start("sleep 30", "go", "Run")
  local cancelled = tracking.cancel()

  T.eq("cancelled", cancelled.status)
  T.falsy(tracking.finish(0, id), "exit tras cancelar se ignora")
  T.eq("cancelled", tracking.get().status)
end)

T.it("cancel sin running es no-op", function()
  fresh()

  T.eq(nil, tracking.cancel())
  local id = tracking.start("echo x", "go", "Run")
  tracking.finish(0, id)
  T.eq(nil, tracking.cancel(), "tras success ya no cancela")
end)

T.it("fail_launch marca failed solo con el expected vigente", function()
  fresh()

  local a = tracking.start("echo a", "go", "Run")
  local b = tracking.start("echo b", "go", "Run")

  T.falsy(tracking.fail_launch(a), "stale no marca")
  T.eq("running", tracking.get().status)

  local done = tracking.fail_launch(b)
  T.eq("failed", done.status)
  T.eq(-1, done.result.code)
end)

T.it("eventos: finish expone Success+Exit, cancel Cancelled+Exit", function()
  fresh()

  local id = tracking.start("echo ok", "go", "Run")
  tracking.finish(0, id)

  local names = {}
  for _, e in ipairs(tracking.events()) do
    names[#names + 1] = e.name
  end
  T.eq({ "CodeRunnerSuccess", "CodeRunnerExit" }, names)

  tracking.start("sleep 30", "go", "Run")
  tracking.cancel()

  names = {}
  for _, e in ipairs(tracking.events()) do
    names[#names + 1] = e.name
  end
  T.eq({ "CodeRunnerCancelled", "CodeRunnerExit" }, names)
end)

T.section("tracking: dispatch único al bus de Neovim (slice 4)")

local function listen_count(pattern, store)
  vim.api.nvim_create_autocmd("User", {
    pattern = pattern,
    callback = function()
      store[#store + 1] = pattern
    end,
  })
end

T.it("dispatch dispara Success+Exit exactamente una vez", function()
  fresh()
  local seen = {}
  listen_count("CodeRunnerSuccess", seen)
  listen_count("CodeRunnerExit", seen)

  local id = tracking.start("echo ok", "go", "Run")
  tracking.finish(0, id)
  local n = tracking.dispatch()

  T.eq(2, n)
  T.eq(2, #seen, "una sola emisión por transición, sin duplicar")
end)

T.it("dispatch sin eventos dispara cero", function()
  fresh()
  tracking.reset()

  T.eq(0, tracking.dispatch())
end)

T.it("events.enabled=false no dispara", function()
  fresh()
  local config = require "code-runner.config"
  local saved = config.options.events.enabled
  config.options.events.enabled = false

  local seen = {}
  listen_count("CodeRunnerSuccess", seen)

  local id = tracking.start("echo ok", "go", "Run")
  tracking.finish(0, id)

  T.eq(0, tracking.dispatch())
  T.eq(0, #seen)

  config.options.events.enabled = saved
end)
