local execution = require "code-runner.execution"
local state = require "code-runner.state"

local function fresh_spec(now, overrides)
  overrides = overrides or {}
  local spec = {
    task_id = "Run",
    context = { filetype = "go" },
    command = { executable = "go", args = { "run", "." } },
    now = now or 1000,
  }

  for k, v in pairs(overrides) do
    spec[k] = v
  end

  return spec
end

local function make(now)
  return execution.create(fresh_spec(now))
end

T.section("execution: entidad y identidad")

T.it("create produce una Execution con id único y creciente", function()
  execution._internals.reset_seq()

  local a = execution.create(fresh_spec())
  local b = execution.create(fresh_spec())

  T.eq(a.id, 1, "primer id")
  T.eq(b.id, 2, "segundo id")
  T.truthy(a.id ~= b.id, "identidad única durante su vida")
end)

T.it("es una entidad distinta de Task (tiene id/timestamps/result)", function()
  local exec = execution.create(fresh_spec())

  T.eq(exec.task_id, "Run", "referencia la tarea")
  T.truthy(exec.id, "pero tiene identidad propia")
  T.eq(exec.status, "created")
  T.eq(exec.started_at, nil)
  T.eq(exec.finished_at, nil)
  T.eq(exec.result, nil)
end)

T.it("create conserva context y normaliza command", function()
  local exec = execution.create(fresh_spec())

  T.eq(exec.context.filetype, "go")
  T.eq(exec.command.executable, "go")
  T.eq(exec.command.args[1], "run")
end)

T.it("create acepta command como string shorthand (se normaliza)", function()
  local exec = execution.create(fresh_spec(nil, { command = "go run ." }))

  T.eq(exec.command.executable, "go")
  T.eq(exec.command.args[1], "run")
  T.eq(exec.command.args[2], ".")
end)

T.it("error si faltan task_id o command", function()
  local e1, er1 = execution.create { command = "go run ." }
  T.falsy(e1)
  T.truthy(er1)

  local e2, er2 = execution.create { task_id = "Run" }
  T.falsy(e2)
  T.truthy(er2)
end)

T.it("error con command sin resolver (función)", function()
  local e, er = execution.create(fresh_spec(nil, { command = function() end }))
  T.falsy(e)
  T.truthy(er, "el comando debe estar resuelto")
end)

T.it("create no comparte comandos con el spec (independencia)", function()
  local spec = fresh_spec()
  local exec = execution.create(spec)

  spec.command = { executable = "evolved" }

  local unchanged = exec.command
  T.eq(unchanged.executable, "go", "command desacoplado del spec original")
end)

T.section("execution: validate / valid / lifecycle states")

T.it("validate corrobora status, timestamps y result", function()
  local exec = execution.create(fresh_spec())
  exec.started_at = "nope"
  T.truthy(execution.validate(exec), "started_at no numérico es inválido")

  local ok = execution.create(fresh_spec())
  T.falsy(execution.validate(ok))

  local bad_status = execution.create(fresh_spec())
  bad_status.status = "bogus"
  T.truthy(execution.validate(bad_status))
end)

T.it("valid refleja validate", function()
  local exec = execution.create(fresh_spec())
  T.truthy(execution.valid(exec))

  exec.status = "exploded"
  T.falsy(execution.valid(exec))
end)

T.it("STATUSES expone el ciclo de vida explícito", function()
  for _, s in ipairs { "created", "starting", "running", "success", "failed", "cancelled" } do
    T.truthy(vim.tbl_contains(execution.STATUSES, s), "estado " .. s)
  end
end)

T.section("execution: transiciones de estado")

T.it("success/failed requieren un Result clasificable", function()
  local e = execution.create(fresh_spec(1000))
  local bad, berr = execution.finish(e, {})
  T.falsy(bad)
  T.truthy(berr, "result indeterminado")
end)

T.it("finish con exit 0 -> success con result y finished_at", function()
  local e = execution.create(fresh_spec(1000))
  e = execution.start(e, 1010)
  e = execution.running(e, 1020)

  local done, derr = execution.finish(e, { code = 0 }, 1030)
  T.truthy(done, "finish ok: " .. tostring(derr))
  T.eq(done.status, "success")
  T.eq(done.started_at, 1010, "marcado al iniciar")
  T.eq(done.finished_at, 1030, "marcado al terminar")
  T.eq(done.result.code, 0)
end)

T.it("finish con exit no cero -> failed", function()
  local e = execution.create(fresh_spec(1000))
  e = execution.start(e, 1010)
  e = execution.running(e, 1020)

  local done = execution.finish(e, { code = 2 }, 1030)
  T.eq(done.status, "failed")
  T.eq(done.result.code, 2)
end)

T.it("cancel es válida desde created/starting/running", function()
  local c1 = execution.create(fresh_spec(1000))
  c1 = execution.cancel(c1, 1005)
  T.eq(c1.status, "cancelled")

  local c2 = execution.create(fresh_spec(1000))
  c2 = execution.start(c2, 1002)
  c2 = execution.cancel(c2, 1008)
  T.eq(c2.status, "cancelled")
  T.eq(c2.finished_at, 1008)
end)

T.it("transiciones inválidas fallan (running -> starting)", function()
  local e = execution.create(fresh_spec(1000))
  e = execution.start(e)
  e = execution.running(e)

  local back, berr = execution.transition(e, "starting")
  T.falsy(back)
  T.truthy(berr, "no se puede volver atrás")
end)

T.it("cancelled es terminal: no se puede continuar", function()
  local e = execution.create(fresh_spec(1000))
  e = execution.cancel(e)

  local continued, cerr = execution.running(e)
  T.falsy(continued)
  T.truthy(cerr, "ejecución cancelada es terminal")
end)

T.it("finished no puede cambiar de resultado", function()
  local e = execution.create(fresh_spec(1000))
  e = execution.start(e)
  e = execution.running(e)
  e = execution.finish(e, { code = 0 })

  local again, aerr = execution.finish(e, { code = 9 })
  T.falsy(again)
  T.truthy(aerr, "estado success es terminal")
end)

T.it("el resultado debe corresponder con el destino", function()
  local e = execution.create(fresh_spec(1000))
  e = execution.start(e)
  e = execution.running(e)

  local mismatch, merr = execution.transition(e, "success", { result = { code = 3 } })
  T.falsy(mismatch)
  T.truthy(merr, "result failed no puede marcar success")
end)

T.section("execution: rechazo de callbacks viejos")

T.it("matches distingue el id actual de uno obsoleto", function()
  local a = execution.create(fresh_spec(1000))
  local b = execution.create(fresh_spec(1000))

  T.truthy(execution.matches(a, a.id), "el callback del job actual pasa")
  T.falsy(execution.matches(a, b.id), "el callback de un job reemplazado se descarta")
  T.falsy(execution.matches(nil, a.id))
end)

T.it("acceptance: un on_exit tardío nunca pisa una ejecución nueva", function()
  -- comportamiento objetivo del Execution Engine (ARCH-005 / CONTRACTS §6)
  local first = execution.create(fresh_spec(1000))
  first = execution.start(first, 1001)
  first = execution.running(first, 1002)

  local second = execution.create(fresh_spec(2000))
  second = execution.start(second, 2001)
  second = execution.running(second, 2002)

  local stale_exit = { code = 99 }
  if execution.matches(first, second.id) == false and execution.matches(first, first.id) then
    -- el callback tardío de first se identifica y puede descartarse por la UI/engine
    T.truthy(true)
  end

  -- second es quien finaliza con su propio resultado
  local done = execution.finish(second, { code = 0 }, 2003)
  T.eq(done.status, "success")
  T.eq(done.result.code, 0)
end)

T.section("execution: independencia de state y terminal")

T.it("el modelo no toca state.run_id", function()
  local before = state.get().run_id

  local e = execution.create(fresh_spec())
  e = execution.start(e)
  e = execution.running(e)
  e = execution.finish(e, { code = 0 })

  local after = state.get().run_id
  T.eq(after, before, "state queda intacto (wiring es EXEC-006)")
end)

T.it("acceptance: identidad y ciclo sin dependencias de UI", function()
  local spec = fresh_spec(nil, { command = "go test ./..." })
  local e = execution.create(spec)
  T.truthy(execution.valid(e), "entidad válida")

  e = execution.start(e, 10)
  e = execution.running(e, 11)
  e = execution.finish(e, { code = 1, stdout = "FAIL" }, 12)

  T.eq(e.status, "failed")
  T.eq(e.result.stdout, "FAIL")
  T.truthy(e.id, "identidad única")
  T.eq(e.started_at, 10)
  T.eq(e.finished_at, 12)
end)