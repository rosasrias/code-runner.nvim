local restart = require "code-runner.restart"
local engine = require "code-runner.engine"

local function make_exec(status, now)
  local e = engine.create {
    task_id = "Run",
    context = { filetype = "go" },
    command = { executable = "go", args = { "run", "." } },
    now = now or 1000,
  }
  e = engine.start(e, 1001)
  e = engine.running(e, 1002)

  if status == "success" then
    e = engine.finish(e, { code = 0 }, 1005)
  elseif status == "failed" then
    e = engine.finish(e, { code = 2 }, 1005)
  elseif status == "cancelled" then
    e = engine.cancel(e, 1005)
  end

  return e
end

T.section("restart: crea una Execution nueva (EXEC-005)")

T.it("restart de una completada produce identidad nueva y estado created", function()
  local prev = make_exec "success"

  local fresh, ferr = restart.restart(prev, { now = 2000 })
  T.truthy(fresh, "fresh: " .. tostring(ferr))
  T.falsy(restart.same_identity(prev, fresh), "id distinto")
  T.eq(fresh.status, "created", "arranca de cero")
  T.eq(fresh.started_at, nil, "sin timestamp inicial")
  T.eq(fresh.finished_at, nil)
  T.eq(fresh.result, nil)
end)

T.it("restart hereda task_id, context y command de la anterior", function()
  local prev = make_exec "success"

  local fresh = restart.restart(prev, { now = 2000 })
  T.eq(fresh.task_id, "Run")
  T.eq(fresh.context.filetype, "go")
  T.eq(fresh.command.executable, "go")
  T.eq(fresh.command.args[1], "run")
end)

T.it("restart NO muta la Execution anterior (identidad intacta)", function()
  local prev = make_exec "success"
  local before = {
    id = prev.id,
    status = prev.status,
    started_at = prev.started_at,
    finished_at = prev.finished_at,
    result = prev.result and prev.result.code,
    task_id = prev.task_id,
  }

  restart.restart(prev, { now = 2000 })

  T.eq(prev.id, before.id, "id conservado")
  T.eq(prev.status, before.status, "status conservado (no fue cancelada/reescrita)")
  T.eq(prev.started_at, before.started_at, "started_at intacto")
  T.eq(prev.finished_at, before.finished_at, "finished_at intacto")
  T.eq(prev.result.code, before.result, "result intacto")
  T.eq(prev.task_id, before.task_id, "task intacta")
end)

T.it("restart con overrides (task_id/command) respeta los overrides", function()
  local prev = make_exec "success"

  local fresh = restart.restart(prev, {
    task_id = "test",
    command = "go test ./...",
    now = 2000,
  })
  T.eq(fresh.task_id, "test")
  T.eq(fresh.command.executable, "go")
  T.eq(fresh.command.args[1], "test")
end)

T.it("rechaza prev inválido", function()
  local f, err = restart.restart("nope")
  T.falsy(f)
  T.truthy(err)
end)

T.section("restart: sobre ejecuciones activas")

T.it("restart de una RUNNING funciona sin cancelarla ni mutarla", function()
  local running = make_exec "running"

  local fresh, ferr = restart.restart(running, { now = 2000 })
  T.truthy(fresh)
  T.falsy(restart.same_identity(running, fresh))
  T.eq(running.status, "running", "la running sigue running (el caller decide cancel)")
  T.eq(fresh.status, "created")

  -- el par fresh solo pasa por su propia vida
  fresh = engine.start(fresh, 2001)
  fresh = engine.running(fresh, 2002)
  fresh = engine.finish(fresh, { code = 0 }, 2005)
  T.eq(fresh.status, "success")
  T.eq(fresh.started_at, 2001)
end)

T.it("restart de una failed/cancelled también crea identidad nueva", function()
  for _, status in ipairs { "failed", "cancelled" } do
    local prev = make_exec(status)
    local fresh = restart.restart(prev, { now = 2000 })
    T.truthy(fresh, status)
    T.falsy(restart.same_identity(prev, fresh), "id distinto tras " .. status)
    T.eq(fresh.status, "created")
  end
end)

T.section("restart: Core puro (EXEC-005)")

T.it("acceptance: repetir un fallo sin reusar identidad de la vieja", function()
  local failed = make_exec "failed"

  local attempt2 = restart.restart(failed, { now = 2000 })
  attempt2 = engine.start(attempt2, 2001)
  attempt2 = engine.running(attempt2, 2002)
  attempt2 = engine.finish(attempt2, { code = 0 }, 2005)

  -- la vieja conserva su identidad y su fallo; la nueva es exitosa y distinta
  T.eq(failed.status, "failed")
  T.eq(failed.result.code, 2)
  T.falsy(restart.same_identity(failed, attempt2))
  T.eq(attempt2.status, "success")
end)

T.it("el módulo no depende de vim ni terminal (Core limpio)", function()
  local prev = make_exec "success"
  local fresh = restart.restart(prev, { now = 2000 })
  T.truthy(fresh, "restart funcional sin UI")
  T.truthy(fresh.command, "reusa command")
end)