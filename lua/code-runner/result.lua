-- Result: el resultado normalizado de una ejecución (CONTRACTS §7).
--
-- Modela finalización de proceso con campos independientes de la UI:
--   { code, signal, stdout, stderr, duration }
--
-- code = 0 es éxito; code ~= 0 o signal presente es fallo; sin code/signal el
-- resultado está "indeterminado" (aún ejecutándose o sin datos).
--
-- Este módulo es Core puro: nada de vim, terminal ni quickfix. La producción
-- de un Result desde la finalización de un job vive en el Execution Engine
-- (EXEC-006); acá solo se valida, normaliza y consulta.
local M = {}

M.FIELDS = { "code", "signal", "stdout", "stderr", "duration" }

-- Valida un Result (tabla). Devuelve nil si es válido o un string de error.
function M.validate(result)
  if type(result) ~= "table" then
    return "Result debe ser una tabla"
  end

  if result.code ~= nil and type(result.code) ~= "number" then
    return "Result 'code' debe ser number o nil"
  end

  if result.signal ~= nil and type(result.signal) ~= "number" then
    return "Result 'signal' debe ser number o nil"
  end

  for _, f in ipairs { "stdout", "stderr" } do
    if result[f] ~= nil and type(result[f]) ~= "string" then
      return "Result '" .. f .. "' debe ser string o nil"
    end
  end

  if result.duration ~= nil and type(result.duration) ~= "number" then
    return "Result 'duration' debe ser number o nil"
  end

  return nil
end

-- True si el resultado es un Result válido.
function M.valid(result)
  return M.validate(result) == nil
end

-- Normaliza a un Result canónico. Solo copia los campos del contrato, ignora
-- extensiones. Devuelve (result, nil) o (nil, error).
function M.new(result)
  local err = M.validate(result)

  if err then
    return nil, err
  end

  local out = {}

  for _, f in ipairs(M.FIELDS) do
    if result[f] ~= nil then
      out[f] = result[f]
    end
  end

  return out
end

-- Crea un Result a partir del exit code de un proceso (forma on_exit de un
-- job termopen/jobstart). stdout/stderr/duration quedan nil: la vía de salida
-- (buffer de terminal, logs, ...) decide cómo capturarlos (EXEC-006).
function M.from_exit(code)
  return { code = code }
end

-- Estado derivado del resultado:
--   "success" si code == 0
--   "failed"  si code ~= 0 o hay signal
--    nil      si no hay ni code ni signal (indeterminado)
function M.status(result)
  if not M.valid(result) then
    return nil
  end

  if result.code == 0 then
    return "success"
  end

  if result.code ~= nil or result.signal ~= nil then
    return "failed"
  end

  return nil
end

-- True si terminó con éxito (code == 0). False si falló o está indeterminado.
function M.success(result)
  return M.status(result) == "success"
end

-- True si falló (code != 0 o signal). False si tuvo éxito o está indeterminado.
function M.failed(result)
  return M.status(result) == "failed"
end

-- True si aún no se puede clasificar (ni code ni signal).
function M.indeterminate(result)
  return M.valid(result) and M.status(result) == nil
end

-- Resumen de una línea para logs/notificaciones (lejos de la UI de la
-- terminal; solo texto útil y determinístico).
function M.describe(result)
  if not M.valid(result) then
    return "Result inválido"
  end

  local st = M.status(result)

  if st == "success" then
    return "salida exitosa (code 0)"
  end

  if st == "failed" then
    local why = result.signal and ("signal " .. result.signal) or ("code " .. tostring(result.code))
    return "fallo (" .. why .. ")"
  end

  return "indeterminado"
end

return M