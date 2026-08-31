-- Action registry: registrar/sobrescribir/deshabilitar acciones por lenguaje
-- de forma programática (P1). Es la vía programática frente a
-- `config.options.actions` (tabla cruda); internamente se aplica igual que una
-- override al catálogo en `actions.lua`.
--
-- API:
--   register{ id, filetypes = {..}, kind = "run|build|test|misc", command = ".." | run = fn }
--     id            obligatorio, único (sobrescribir el mismo id reemplaza).
--     filetypes     lista de extensiones a las que aplica (obligatoria, no vacía).
--     kind          run|build|test|misc — determina el icono del label.
--     command|run   string (se sustituye) o función. Uno de los dos, obligatorio.
--     disable       true = elimina el lenguaje de filetypes del catálogo.
--   unregister(id) / list() / reset()
local M = {}

local entries = {} -- id -> spec
local order = {} -- ids en orden de registro

local VALID_KINDS = { run = true, build = true, test = true, misc = true }

function M.register(spec)
  assert(type(spec) == "table", "register_action: se espera una tabla")
  assert(type(spec.id) == "string" and spec.id ~= "", "register_action: falta 'id'")

  if not (spec.command or spec.run) and not spec.disable then
    error("register_action: falta 'command' o 'run' (o 'disable=true')")
  end

  if type(spec.filetypes) == "string" then
    spec.filetypes = { spec.filetypes }
  end

  assert(type(spec.filetypes) == "table" and #spec.filetypes > 0, "register_action: 'filetypes' no puede estar vacío")

  if spec.kind and not VALID_KINDS[spec.kind] then
    error("register_action: 'kind' inválido: " .. tostring(spec.kind))
  end

  spec.kind = spec.kind or "misc"

  if not order[spec.id] then
    table.insert(order, spec.id)
  end

  entries[spec.id] = spec
  return true
end

function M.unregister(id)
  entries[id] = nil

  for i, v in ipairs(order) do
    if v == id then
      table.remove(order, i)
      break
    end
  end
end

function M.list()
  local out = {}

  for _, id in ipairs(order) do
    out[id] = entries[id]
  end

  return out
end

function M.reset()
  entries = {}
  order = {}
end

-- Aplica el registry sobre el catálogo `actions` (mutándolo), devolviendo el
-- mismo. `env` = { RUN, BUILD } iconos.
function M.apply(actions, env)
  for _, id in ipairs(order) do
    local spec = entries[id]

    if spec.disable then
      for _, ext in ipairs(spec.filetypes) do
        actions[ext] = nil
      end
      goto continue
    end

    local prefix = env.run or ""
    if spec.kind == "build" then
      prefix = env.build or ""
    elseif spec.kind == "misc" then
      prefix = ""
    end
    -- kind "test" usa el mismo icono run (la acción contextual ya maneja tests).

    local name = spec.name or spec.id
    local label = (prefix == "" and name) or (prefix .. name)

    for _, ext in ipairs(spec.filetypes) do
      actions[ext] = actions[ext] or {}
      actions[ext][label] = spec.command or spec.run
    end

    ::continue::
  end

  return actions
end

return M
