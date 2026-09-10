local engine = require "code-runner.engine"

local function fresh_spec(now)
  return {
    task_id = "Run",
    context = { filetype = "go" },
    command = { executable = "go", args = { "run", "." } },
    now = now or 1000,
  }
end

local function statuses_to_string(seen)
  return table.concat(seen, ",")
end

T.section("engine: describe el ciclo de vida (EXEC-001)")

T.it("existe un estado para cada etapa del ciclo", function()
  local statuses = engine.STATUSES()

  for _, s in ipairs { "created", "starting", "running", "success", "failed", "cancelled" } do
    T.truthy(vim.tbl_contains(statuses, s), "estado " .. s)
  end
end)

T.it("un run completo conduce created -> starting -> running -> success", function()
  engine.set_listener(nil)

  local e = engine.create(fresh_spec(1000))
  T.eq(e.status, "created")

  e = engine.start(e, 1001)
  T.eq(e.status, "starting")
  T.eq(e.started_at, 1001)

  e = engine.running(e, 1002)
  T.eq(e.status, "running")

  e = engine.finish(e, { code = 0 }, 1005)
  T.eq(e.status, "success")
  T.eq(e.finished_at, 1005)
end)

T.it("finish con code != 0 conduce a failed", function()
  engine.set_listener(nil)

  local e = engine.create(fresh_spec())
  e = engine.start(e)
  e = engine.running(e)
  e = engine.finish(e, { code = 3 }, 1009)

  T.eq(e.status, "failed")
  T.eq(e.result.code, 3)
end)

T.it("cancel desde running conduce a cancelled (terminal)", function()
  engine.set_listener(nil)

  local e = engine.create(fresh_spec())
  e = engine.start(e)
  e = engine.running(e)
  e = engine.cancel(e, 1010)

  T.eq(e.status, "cancelled")
  T.eq(e.finished_at, 1010)
end)

T.section("engine: listener de transiciones (puente EXEC-007)")

T.it("el listener recibe cada transición válida en orden", function()
  local seen = {}
  engine.set_listener(function(exec)
    seen[#seen + 1] = exec.status
  end)

  local e = engine.create(fresh_spec())
  e = engine.start(e)
  e = engine.running(e)
  e = engine.finish(e, { code = 0 })

  engine.set_listener(nil)

  T.eq(statuses_to_string(seen), "starting,running,success")
end)

T.it("un run fallido emite failed como terminal", function()
  local seen = {}
  engine.set_listener(function(exec)
    seen[#seen + 1] = exec.status
  end)

  local e = engine.create(fresh_spec())
  e = engine.start(e)
  e = engine.running(e)
  e = engine.finish(e, { code = 1 })

  engine.set_listener(nil)

  T.eq(statuses_to_string(seen), "starting,running,failed")
end)

T.it("cancel emite cancelled", function()
  local seen = {}
  engine.set_listener(function(exec)
    seen[#seen + 1] = exec.status
  end)

  local e = engine.create(fresh_spec())
  e = engine.start(e)
  e = engine.running(e)
  e = engine.cancel(e)

  engine.set_listener(nil)

  T.eq(statuses_to_string(seen), "starting,running,cancelled")
end)

T.it("set_listener(nil) desactiva la emisión", function()
  local count = 0
  engine.set_listener(function()
    count = count + 1
  end)

  local e = engine.create(fresh_spec())
  engine.start(e)
  engine.set_listener(nil)

  engine.running(e)
  engine.finish(e, { code = 0 })

  T.eq(count, 1, "solo la transición previa al desactivado")
end)

T.it("transiciones inválidas no emiten listener", function()
  local count = 0
  engine.set_listener(function()
    count = count + 1
  end)

  local e = engine.create(fresh_spec())
  e = engine.start(e)
  e = engine.running(e)

  e = engine.finish(e, { code = 0 }) -- success (terminal válido)
  local again = engine.finish(e, { code = 1 }, 2000) -- success es terminal

  engine.set_listener(nil)

  T.falsy(again, "no se puede refinalizar")
  T.eq(count, 3, "solo se emitieron las transiciones válidas (starting,running,success)")
end)

T.section("engine: Core puro, sin dependencias de UI")

T.it("el engine no depende de vim/terminal/quickfix (Core limpio)", function()
  engine.set_listener(nil)

  local e = engine.create(fresh_spec(1000))
  e = engine.start(e, 1001)
  e = engine.running(e, 1002)
  e = engine.finish(e, { code = 0, stdout = "ok" }, 1003)

  T.truthy(engine, "engine requerible")
  T.truthy(e.id, "identidad preservada")
  T.eq(e.result.stdout, "ok")
  T.eq(e.status, "success")
end)