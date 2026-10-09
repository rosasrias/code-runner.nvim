-- Execution Engine (EXEC-001, seed): driver del ciclo de vida de la Ejecución.
--
-- El modelo (execution.lua) define los estados y transiciones; este módulo es
-- la capa que los *conduce* y que anuncia cada transición a un listener
-- inyectable. Así EXEC-007 (Execution Events) podrá enganchar las autocmds
-- `CodeRunner*` sin que el modelo ni el engine dependan de vim.
--
-- El Process Adapter real (spawn/stream/terminate) es EXEC-002; acá el engine
-- solo orquesta created → starting → running → success|failed|cancelled.
--
-- Core puro: no depende de vim, terminal, picker, quickfix ni language runners
-- (BOUNDARIES §7 Execution).
local execution = require "code-runner.execution"

local M = {}

local listener = nil

-- El listener recibe cada Execution tras una transición válida:
--   listener(exec)  -- exec es la snapshots ya transicionada
-- Pasa nil para desactivar. Solo acepta function o nil (programmer error
-- si no); un listener que lanza no rompe la transición (se aísla con pcall,
-- EXEC-007: el engine sigue siendo el dueño estable del lifecycle).
function M.set_listener(fn)
  assert(fn == nil or type(fn) == "function", "engine.set_listener: se espera function o nil")
  listener = fn
end

local function emit(exec)
  if listener and exec then
    pcall(listener, exec)
  end
end

-- created -> starting (marca started_at y emite).
function M.start(exec, now)
  local s, err = execution.start(exec, now)
  emit(s)
  return s, err
end

-- starting -> running (emite).
function M.running(exec, now)
  local r, err = execution.running(exec, now)
  emit(r)
  return r, err
end

-- running -> success|failed con Result (emite el estado terminal).
function M.finish(exec, res, now)
  local done, err = execution.finish(exec, res, now)
  emit(done)
  return done, err
end

-- running|starting|created -> cancelled (emite).
function M.cancel(exec, now)
  local c, err = execution.cancel(exec, now)
  emit(c)
  return c, err
end

-- Alias de creación de Execution (para el flujo real del engine).
function M.create(spec)
  return execution.create(spec)
end

function M.STATUSES()
  return execution.STATUSES
end

return M