-- Restart (EXEC-005): re-ejecutar SIEMPRE como una Execution nueva.
--
-- La regla es no mutar la identidad de una Execution ya terminada o en
-- marcha: el restart crea una Execution fresca (id nuevo, timestamps/result
-- nil, status created) reusando task_id/context/command de la anterior.
--
-- Core puro: no depende de vim ni de terminal. El caller (EXEC-009 / init)
-- decide si cancela primero la heartbeat activa (cancel.lua); acá solo se
-- garantiza el modelo de identidad.
local execution = require "code-runner.execution"

local M = {}

-- Crea una Execution NUEVA para repetir `prev`. Devuelve (fresh, nil) o
-- (nil, error).
--
--   prev   Execution a repetir (completed o running).
--   spec   overrides opcionales: { task_id, context, command, now }.
--          Los campos ausentes se heredan de prev. prev NUNCA se muta.
function M.restart(prev, spec)
  if not execution.valid(prev) then
    return nil, "restart: prev no es una Execution válida"
  end

  spec = spec or {}

  local fresh, err = execution.create {
    task_id = spec.task_id or prev.task_id,
    context = spec.context or prev.context,
    command = spec.command or prev.command,
    now = spec.now or os.time(),
  }

  if not fresh then
    return nil, "restart: " .. tostring(err)
  end

  return fresh, nil
end

-- True si a y b comparten identidad (garantía de "no mutar la identidad").
function M.same_identity(a, b)
  return a ~= nil and b ~= nil and a.id == b.id
end

return M