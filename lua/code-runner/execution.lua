-- Execution: una tentativa de ejecutar un Task (CONTRACTS §5).
--
-- Todo lo que describimos del "número de ejecución" (run_id del plugin) vive
-- acá como entidad de primera clase con identidad propia:
--   { id, task_id, context, command, status, started_at, finished_at, result }
--
-- Task (qué se va a hacer) y Execution (un intento concreto, con tiempos y
-- resultados) son entidades distintas (CONTRACTS §5 / ARCH-005).
--
-- Este módulo es Core puro: nada de vim, terminal, state ni quickfix. Los
-- timestamps son inyectables (`now`) para tests determinísticos.
local command = require "code-runner.command"
local result = require "code-runner.result"

local M = {}

M.STATUSES = { "created", "starting", "running", "success", "failed", "cancelled" }

local STATUS_SET = {}
for _, s in ipairs(M.STATUSES) do
  STATUS_SET[s] = true
end

-- Transiciones explícitas (CONTRACTS §5 "Lifecycle states are explicit").
M.TRANSITIONS = {
  created = { starting = true, cancelled = true },
  starting = { running = true, failed = true, cancelled = true },
  running = { success = true, failed = true, cancelled = true },
  success = {},
  failed = {},
  cancelled = {},
}

local seq = 0

function M._internals_reset_seq()
  seq = 0
end

-- Devuelve el siguiente id de ejecución (único y creciente).
function M._next_id()
  seq = seq + 1
  return seq
end

local function clone(tbl)
  if type(tbl) == "table" then
    local out = {}

    for k, v in pairs(tbl) do
      out[k] = clone(v)
    end

    return out
  end

  return tbl
end

-- Crea una Execution nueva. `spec` acepta:
--   task_id   string (obligatorio)
--   context   tabla (CodeRunnerContext) o nil
--   command   CommandSpec | string shorthand (obligatorio; se normaliza)
--   status    opcional (default "created")
--   now       número de epoch (default os.time()) para timestamps inyectables
-- Devuelve (exec, nil) o (nil, error).
function M.create(spec)
  if type(spec) ~= "table" then
    return nil, "Execution requiere una tabla"
  end

  if type(spec.task_id) ~= "string" or spec.task_id == "" then
    return nil, "Execution requiere 'task_id' (string no vacío)"
  end

  if spec.context ~= nil and type(spec.context) ~= "table" then
    return nil, "Execution 'context' debe ser tabla o nil"
  end

  if spec.command == nil then
    return nil, "Execution requiere 'command'"
  end

  if type(spec.command) == "function" then
    return nil, "Execution 'command' debe estar resuelto (no es función)"
  end

  local cmd, cmd_err = command.normalize(spec.command)

  if not cmd then
    return nil, "Execution 'command' inválido: " .. tostring(cmd_err)
  end

  local status = spec.status or "created"

  if not STATUS_SET[status] then
    return nil, "Execution 'status' inválido: " .. tostring(status)
  end

  local now = spec.now or os.time()

  return {
    id = M._next_id(),
    task_id = spec.task_id,
    context = clone(spec.context),
    command = cmd,
    status = status,
    started_at = nil,
    finished_at = nil,
    result = nil,
  }, nil
end

-- Valida una entidad Execution existente. Devuelve nil o string de error.
function M.validate(exec)
  if type(exec) ~= "table" then
    return "Execution debe ser una tabla"
  end

  if type(exec.id) ~= "number" and type(exec.id) ~= "string" then
    return "Execution 'id' inválido"
  end

  if type(exec.task_id) ~= "string" or exec.task_id == "" then
    return "Execution 'task_id' inválido"
  end

  if type(exec.status) ~= "string" or not STATUS_SET[exec.status] then
    return "Execution 'status' inválido"
  end

  if exec.started_at ~= nil and type(exec.started_at) ~= "number" then
    return "Execution 'started_at' debe ser number o nil"
  end

  if exec.finished_at ~= nil and type(exec.finished_at) ~= "number" then
    return "Execution 'finished_at' debe ser number o nil"
  end

  if exec.result ~= nil and not result.valid(exec.result) then
    return "Execution 'result' inválido"
  end

  return nil
end

-- True si la entidad es una Execution válida.
function M.valid(exec)
  return M.validate(exec) == nil
end

-- True si la transición from -> to es válida.
function M.can(from, to)
  return (M.TRANSITIONS[from] or {})[to] == true
end

-- Transición de estado. Devuelve una nueva Execution (snapshot) con status y
-- timestamps actualizados (started_at en starting, finished_at en terminales).
-- Los terminales permitidos reciben opts.result (un Result válido). Devuelve
-- (exec, nil) o (nil, error).
function M.transition(exec, to, opts)
  opts = opts or {}

  if not M.valid(exec) then
    return nil, M.validate(exec)
  end

  if not STATUS_SET[to] then
    return nil, "status inválido: " .. tostring(to)
  end

  if not M.can(exec.status, to) then
    return nil, ("transición no permitida: %s -> %s"):format(exec.status, to)
  end

  local now = opts.now or os.time()
  local next_exec = clone(exec)
  next_exec.status = to

  if to == "starting" and next_exec.started_at == nil then
    next_exec.started_at = now
  end

  if to == "running" then
    next_exec.started_at = next_exec.started_at or now
  end

  if to == "success" or to == "failed" or to == "cancelled" then
    next_exec.finished_at = now
  end

  if next_exec.status == "success" or next_exec.status == "failed" then
    if opts.result == nil then
      return nil, "transition a " .. to .. " requiere opts.result"
    end

    local r, rerr = result.new(opts.result)

    if not r then
      return nil, "opts.result inválido: " .. tostring(rerr)
    end

    local rstatus = result.status(r)

    if rstatus ~= next_exec.status then
      return nil, ("Result classifica como '%s', no como '%s'"):format(tostring(rstatus), next_exec.status)
    end

    next_exec.result = r
  end

  return next_exec, nil
end

-- Conveniencias de ciclo de vida sobre transition.

-- created -> starting (marca started_at).
function M.start(exec, now)
  return M.transition(exec, "starting", { now = now })
end

-- starting -> running.
function M.running(exec, now)
  return M.transition(exec, "running", { now = now })
end

-- running -> success|failed según result, con finished_at y result adjunto.
function M.finish(exec, res, now)
  local st = result.status(res)

  if st ~= "success" and st ~= "failed" then
    return nil, "result indeterminado o inválido: " .. tostring(result.describe(res))
  end

  return M.transition(exec, st, { result = res, now = now })
end

-- running|starting|created -> cancelled.
function M.cancel(exec, now)
  return M.transition(exec, "cancelled", { now = now })
end

-- True si el id corresponde a esta Execution (rechazo de callbacks viejos).
-- El Execution Engine usará esto para descartar on_exit de jobs reemplazados.
function M.matches(exec, id)
  return exec ~= nil and exec.id == id
end

M._internals = {
  reset_seq = M._internals_reset_seq,
}

return M