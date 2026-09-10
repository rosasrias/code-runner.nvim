-- Cancellation (EXEC-004): la cancelación debe apuntar a la Execution correcta.
--
-- Hoy el plugin cancela de forma global (`state.set "cancelled"` y cerrar el
-- buffer de terminal mata el job implícitamente). Este módulo (Core puro) es
-- el determinismo de cancelación por Execution:
--
--   - valida que la Execution sigue siendo la esperada (guard de identidad),
--   - opcionalmente detiene el proceso (terminate delegado al port EXEC-002),
--   - transiciona a `cancelled` vía el engine (emite lifecycle event).
--
-- Un on_exit tardío o una cancelación de un job reemplazado no pueden tocar
-- una Execution que ya no es la actual.
local engine = require "code-runner.engine"
local execution = require "code-runner.execution"

local M = {}

-- Cancela una Execution. Devuelve (exec_cancelled, nil) o (nil, error).
--
--   exec   Execution a cancelar (running|starting|created).
--   opts   {
--            expected:<id>   si se pasa, solo cancela cuando exec.id == expected
--                            (rechaza callbacks/cancelaciones viejas).
--            terminate:fn    opcional; fn(exec) -> boolean. Detiene el proceso
--                            antes de marcar cancelled (delegado al port).
--            now:número      timestamp inyectable.
--          }
function M.cancel(exec, opts)
  opts = opts or {}

  if not execution.valid(exec) then
    return nil, "cancel: Execution inválida"
  end

  if opts.expected ~= nil and not execution.matches(exec, opts.expected) then
    return nil, "cancel: Execution obsoleta (" .. tostring(exec.id) .. " != " .. tostring(opts.expected) .. ")"
  end

  if opts.terminate ~= nil then
    if type(opts.terminate) ~= "function" then
      return nil, "cancel: opts.terminate debe ser función o nil"
    end

    local ok, terr = opts.terminate(exec)

    if ok == false then
      return nil, "cancel: no se pudo terminar el proceso: " .. tostring(terr)
    end
  end

  if exec.status == "success" or exec.status == "failed" then
    return nil, "cancel: la Execution ya terminó (" .. exec.status .. ")"
  end

  return engine.cancel(exec, opts.now)
end

return M