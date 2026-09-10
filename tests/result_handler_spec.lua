local result_handler = require "code-runner.result_handler"
local result = require "code-runner.result"
local engine = require "code-runner.engine"

local function running_exec()
  local e = engine.create { task_id = "Run", command = "go run .", now = 1000 }
  e = engine.start(e, 1001)
  e = engine.running(e, 1002)
  return e
end

T.section("result_handler: on_exit -> Result (EXEC-006)")

T.it("completa con code 0 -> success y Result adjunto", function()
  local exec = running_exec()

  local done, rerr = result_handler.complete(exec, { code = 0, now = 1005 })
  T.truthy(done, tostring(rerr))
  T.eq(done.status, "success")
  T.eq(done.result.code, 0)
  T.eq(done.result.signal, nil)
  T.eq(done.finished_at, 1005)
end)

T.it("completa con code != 0 -> failed", function()
  local exec = running_exec()

  local done = result_handler.complete(exec, { code = 2, now = 1005 })
  T.eq(done.status, "failed")
  T.eq(done.result.code, 2)
end)

T.it("completa con signal -> failed aunque code falte", function()
  local exec = running_exec()

  local done, rerr = result_handler.complete(exec, { signal = 9, now = 1005 })
  T.truthy(done, tostring(rerr))
  T.eq(done.status, "failed")
  T.eq(done.result.signal, 9)
end)

T.it("adjunta stdout/stderr/duration del stream", function()
  local exec = running_exec()

  local done = result_handler.complete(exec, {
    code = 0,
    stdout = "hola\nmundo\n",
    stderr = "",
    duration = 0.4,
    now = 1005,
  })
  T.eq(done.result.stdout, "hola\nmundo\n")
  T.eq(done.result.stderr, "")
  T.eq(done.result.duration, 0.4)
end)

T.it("result es canónico (solo campos del contrato)", function()
  local r, nerr = result_handler.from_on_exit { code = 3, foo = "extra" }
  T.truthy(r, tostring(nerr))
  T.falsy(r.foo)
  T.truthy(result.valid(r))
end)

T.it("rechaza sin code ni signal (indeterminado)", function()
  local f, err = result_handler.complete(running_exec(), { now = 1005 })
  T.falsy(f, "no finaliza sin clasificar")
  T.truthy(err)
  T.contains(err, "indeterminado")
end)

T.section("result_handler: identity guard")

T.it("acceptance: un on_exit tardío (expected) no toca una Execution 'running' más nueva", function()
  local exec = running_exec()

  -- el job viejo #old muere tarde; el exec actual es exec.id
  local stale_id = exec.id - 1
  local f, err = result_handler.complete(exec, { code = 1, expected = stale_id, now = 1005 })
  T.falsy(f, "rechaza el on_exit obsoleto")
  T.truthy(err)
  T.contains(err, "obsoleto")
  T.eq(exec.status, "running", "la Execution actual no fue pisada")
  T.eq(exec.result, nil)
end)

T.it("con expected correcto completa normal", function()
  local exec = running_exec()

  local done = result_handler.complete(exec, { code = 0, expected = exec.id, now = 1005 })
  T.eq(done.status, "success")
  T.eq(done.result.code, 0)
end)

T.section("result_handler: estados del proceso")

T.it("rechaza completar una Execution ya terminal", function()
  local exec = running_exec()
  exec = engine.finish(exec, { code = 0 }, 1005)

  local f, err = result_handler.complete(exec, { code = 1, now = 1010 })
  T.falsy(f)
  T.truthy(err)
  T.contains(err, "terminal")
  T.eq(exec.result.code, 0, "resultado original intacto")
end)

T.it("rechaza completar una Execution que aún no arrancó (created)", function()
  local fresh = engine.create { task_id = "Run", command = "go run .", now = 1000 }

  local f, err = result_handler.complete(fresh, { code = 0, now = 1005 })
  T.falsy(f)
  T.truthy(err)
end)

T.it("on_exit de code 0 tras signal guarda el Result y queda success", function()
  local exec = running_exec()

  local done = result_handler.complete(exec, { code = 0, signal = 0, now = 1005 })
  T.eq(done.status, "success", "signal 0 es señal limpia")
end)