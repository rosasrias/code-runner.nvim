-- Task Registry: guarda Tasks ejecutables por su ID estable (CONTRACTS §16,
-- ARCH-006).
--
-- Task identity es `task.id` (ADR-002): los registries NO son label-keyed,
-- a diferencia del Runner Registry legacy (`actions/registry.lua`, que sigue
-- guardando por label). Esto preserva identidad independiente de presentación.
--
-- Core puro: no depende de vim, picker, terminal ni ejecución. Los runners
-- (qué lenguaje/host puede ejecutar) viven aparte en el Runner Registry; acá
-- solo viven Tasks ya resueltas/registradas.
local task = require "code-runner.task"

local M = {}

local entries = {} -- task_id -> Task
local order = {} -- task_ids en orden de registro

-- Registra un Task. Acepta un TaskSpec (se normaliza con task.new) o un Task ya
-- construido. Devuelve (Task, nil) o (nil, error). Registrar el mismo id
-- reemplaza (sin duplicar en el orden) y conserva su posición.
--
-- Si se pasa un Task ya construido (tabla con .id), se validan identidad y
-- coherencia: el campo `id` no debe existir (los registries derivan identidad
-- del par (runner, stem)); si existe debe coincidir con task.id.
function M.register(spec_or_task)
  if type(spec_or_task) ~= "table" then
    return nil, "Task Registry: se espera una tabla (TaskSpec o Task)"
  end

  -- Detectar si es un Task ya normalizado (tiene .id de una creación).
  local t

  if spec_or_task.id ~= nil then
    t = spec_or_task

    local terr = task.validate(t)

    if terr then
      return nil, "Task Registry: " .. terr
    end
  else
    local nerr

    t, nerr = task.new(spec_or_task)

    if not t then
      return nil, "Task Registry: " .. tostring(nerr)
    end
  end

  local tid = t.id

  if not entries[tid] then
    table.insert(order, tid)
  end

  entries[tid] = t
  return t, nil
end

-- Registra un Task lanzando error si es inválido (para registros que quieren
-- fallar temprano). Devuelve el Task registrado.
function M.register_or_error(spec_or_task)
  local t, err = M.register(spec_or_task)

  if not t then
    error("Task Registry: " .. tostring(err), 2)
  end

  return t
end

-- Desregistra por ID estable. Devuelve true si existía, false si no.
function M.unregister(task_id)
  if not entries[task_id] then
    return false
  end

  entries[task_id] = nil

  for i, id in ipairs(order) do
    if id == task_id then
      table.remove(order, i)
      break
    end
  end

  return true
end

-- Devuelve el Task por ID estable (nil si no está).
function M.get(task_id)
  return entries[task_id]
end

-- Lista de Tasks en orden de registro (mapa id -> Task). No expone el interno.
function M.list()
  local out = {}

  for _, id in ipairs(order) do
    out[id] = entries[id]
  end

  return out
end

-- Cuenta de Tasks registrados.
function M.count()
  return #order
end

-- True si existe un Task con ese id.
function M.has(task_id)
  return entries[task_id] ~= nil
end

-- Vacía el registro.
function M.reset()
  entries = {}
  order = {}
  return true
end

return M