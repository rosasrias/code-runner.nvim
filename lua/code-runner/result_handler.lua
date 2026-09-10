-- Result Handling (EXEC-006): convertir la terminación del proceso en Result.
--
-- El puente del lado proceso: un on_exit (termopen/jobstart) entrega
-- (code[, signal]). Este módulo (Core puro) construye un Result (CONTRACTS §7)
-- y lo adjunta a la Execution vía `engine.finish`, con dos garantías:
--
--   1. Identity guard (`expected`): un on_exit tardío de un job reemplazado
--      NUNCA escribe un Result sobre una Execution que ya no es la actual.
--   2. Solo estados activos (starting/running) pueden finalizar; terminales
--      se rechazan (el Result queda "indeterminado" si faltan code y signal).
--
-- stdout/stderr/duration son opcionales: el stream (EXEC-003) los alimenta
-- cuando haya captura real; un termopen no los entrega.
local engine = require "code-runner.engine"
local execution = require "code-runner.execution"
local result = require "code-runner.result"

local M = {}

-- Construye un Result canónico desde la terminación. (code, signal) vienen del
-- on_exit; stdout/stderr/duration son capturas opcionales. Devuelve (result,nil)
-- o (nil, error).
function M.from_on_exit(info)
  return result.new {
    code = info.code,
    signal = info.signal,
    stdout = info.stdout,
    stderr = info.stderr,
    duration = info.duration,
  }
end

-- Completa una Execution con el Result de su terminación. Devuelve
-- (exec_finish, nil) o (nil, error).
--
--   exec   Execution activa (starting|running) a finalizar.
--   opts   {
--            code, signal      del on_exit (code obligatorio salvo signal).
--            stdout, stderr    opcional (captura del stream).
--            duration          opcional (seg.).
--            expected:<id>     identity guard: rechaza on_exit obsoleto.
--            now               timestamp inyectable.
--          }
function M.complete(exec, opts)
  opts = opts or {}

  if opts.expected ~= nil and not execution.matches(exec, opts.expected) then
    return nil, ("result: on_exit obsoleto (%d es la actual, no %d)"):format(exec.id, opts.expected)
  end

  if exec.status ~= "starting" and exec.status ~= "running" then
    return nil, "result: la Execution ya está en estado terminal (" .. exec.status .. ")"
  end

  local r, rerr = M.from_on_exit(opts)

  if not r then
    return nil, "result: " .. tostring(rerr)
  end

  return engine.finish(exec, r, opts.now)
end

return M