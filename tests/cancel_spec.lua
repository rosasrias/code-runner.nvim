local cancel = require "code-runner.cancel"
local engine = require "code-runner.engine"

local function running_exec(id_hint, now)
  local e = engine.create {
    task_id = "Run",
    context = { filetype = "go" },
    command = { executable = "go", args = { "run", "." } },
    now = 1000,
  }
  e = engine.start(e, 1001)
  e = engine.running(e, 1002)
  return e
end

T.section("cancel: apunta a la Execution correcta (EXEC-004)")

T.it("cancela una Execution running hacia cancelled (terminal)", function()
  local e = running_exec()
  local c, cerr = cancel.cancel(e, { now = 1005 })

  T.truthy(c, "cancelled: " .. tostring(cerr))
  T.eq(c.status, "cancelled")
  T.eq(c.finished_at, 1005)
  T.truthy(c.id, "identidad preservada")
end)

T.it("es un no-op (nil + error) si la Execution ya no es la esperada", function()
  local current = running_exec()
  local stale = running_exec()

  local c, cerr = cancel.cancel(stale, { expected = current.id, now = 1005 })
  T.falsy(c)
  T.truthy(cerr, "Execution obsoleta rechazada")
  T.eq(stale.status, "running", "la stale no se tocó")
end)

T.it("cancela la Execution correcta cuando el id coincide", function()
  local e = running_exec()
  local c, cerr = cancel.cancel(e, { expected = e.id, now = 1006 })

  T.truthy(c, "cancelado")
  T.eq(c.status, "cancelled")
end)

T.section("cancel: terminate delegado al port de procesos")

T.it("llama terminate antes de marcar cancelled", function()
  local e = running_exec()
  local terminated = false
  local called_with

  local c = cancel.cancel(e, {
    terminate = function(exec)
      called_with = exec
      terminated = true
      return true
    end,
    now = 1007,
  })

  T.truthy(terminated, "process.terminate invoked")
  T.eq(called_with.id, e.id, "recibe la Execution a cancelar")
  T.eq(c.status, "cancelled")
end)

T.it("errores de terminate NO marcan cancelled (proceso sigue vivo)", function()
  local e = running_exec()
  local c, cerr = cancel.cancel(e, {
    terminate = function() return false, "adapter rechazó terminate" end,
    now = 1008,
  })

  T.falsy(c)
  T.truthy(cerr, "fallo propagado")
  T.eq(e.status, "running", "sin transición si no se pudo terminar")
end)

T.it("acceptance: la cancelación pasa por el port (EXEC-002) sin UI", function()
  local process = require "code-runner.process"
  local e = running_exec()

  local terminated = false
  process.set_adapter(nil)

  -- el wiring real (EXEC-009) enhebrará process.terminate(handle):
  -- acá probamos que cancel acepta un terminate delegado.
  local c = cancel.cancel(e, {
    terminate = function()
      terminated = true
      return true
    end,
    now = 1009,
  })

  T.truthy(c)
  T.truthy(terminated)
  T.eq(c.status, "cancelled")
end)

T.section("cancel: solo estados activos")

T.it("rechaza cancelar una Execution ya terminada (success)", function()
  local e = running_exec()
  e = engine.finish(e, { code = 0 }, 1003)

  local c, cerr = cancel.cancel(e, { now = 1009 })
  T.falsy(c)
  T.truthy(cerr, "ya success")
end)

T.it("rechaza cancelar una Execution ya cancelada", function()
  local e = running_exec()
  e = engine.cancel(e, 1003)

  local c, cerr = cancel.cancel(e, { now = 1009 })
  T.falsy(c)
  T.truthy(cerr, "ya cancelled")
end)

T.it("rechaza Execution inválida", function()
  local c, cerr = cancel.cancel("nope", { now = 1 })
  T.falsy(c)
  T.truthy(cerr)
end)

T.section("cancel: emite el lifecycle event (EXEC-001/007)")

T.it("el listener ve la transición a cancelled", function()
  local seen = {}
  engine.set_listener(function(exec)
    seen[#seen + 1] = exec.status
  end)

  local e = running_exec()
  local c = cancel.cancel(e, { now = 1010 })

  engine.set_listener(nil)

  T.truthy(c)
  T.eq(seen[#seen], "cancelled", "el último event es cancelled")
end)