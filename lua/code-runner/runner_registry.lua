-- Runner Registry: guarda RunnerSpecs por su ID estable (CONTRACTS §17).
--
-- Espeja el patrón de `task_registry.lua`: clave `id`, reemplazo sin
-- duplicar posición, API register/unregister/get/list/has/count/reset.
-- Simplificación deliberada respecto a task_registry: como `id` es
-- obligatorio en RunnerSpec, `register` siempre normaliza con `runner.new`
-- (idempotente); no hay doble vía spec-vs-construido.
--
-- Vacío hasta poblarse: `runners.seed` (built-ins, pre-decorate) y registros
-- runtime lo llenan; `task_resolve` lo consulta primero (registry-first con
-- re-seed). El picker legacy sigue leyendo el catálogo hasta su migración.
--
-- Core puro: solo depende de `runner.lua`.
local runner = require "code-runner.runner"

local M = {}

local entries = {} -- runner_id -> RunnerSpec normalizado
local order = {} -- ids en orden de registro

-- Registra un RunnerSpec (se normaliza con runner.new). Devuelve
-- (spec, nil) o (nil, error). Re-registrar reemplaza sin duplicar posición.
function M.register(spec)
  if type(spec) ~= "table" then
    return nil, "Runner Registry: se espera una tabla (RunnerSpec)"
  end

  local r, err = runner.new(spec)

  if not r then
    return nil, "Runner Registry: " .. tostring(err)
  end

  if not entries[r.id] then
    table.insert(order, r.id)
  end

  entries[r.id] = r
  return r, nil
end

-- Como `register`, pero lanza en inválido.
function M.register_or_error(spec)
  local r, err = M.register(spec)

  if not r then
    error("Runner Registry: " .. tostring(err), 2)
  end

  return r
end

-- Desregistra por ID estable. Devuelve true si existía, false si no.
function M.unregister(runner_id)
  if not entries[runner_id] then
    return false
  end

  entries[runner_id] = nil

  for i, id in ipairs(order) do
    if id == runner_id then
      table.remove(order, i)
      break
    end
  end

  return true
end

-- Devuelve el RunnerSpec por ID estable (nil si no está).
function M.get(runner_id)
  return entries[runner_id]
end

-- Lista en orden de registro (mapa id -> spec). No expone el interno.
function M.list()
  local out = {}

  for _, id in ipairs(order) do
    out[id] = entries[id]
  end

  return out
end

-- Cuenta de runners registrados.
function M.count()
  return #order
end

-- True si existe un runner con ese id.
function M.has(runner_id)
  return entries[runner_id] ~= nil
end

-- Vacía el registro.
function M.reset()
  entries = {}
  order = {}
  return true
end

return M
