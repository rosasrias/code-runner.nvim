-- TaskSpec: el concepto de dominio primario (ADR-001, ARCH-002).
--
-- Task es una definición ejecutable. Task identity es `id` (estable y
-- determinístico, independiente de presentación — ADR-002). Los campos de
-- presentación (`name`, `description`) viven al lado pero nunca son identidad.
--
-- Este módulo es Core puro: no depende de vim, picker, terminal ni ejecución.
-- Solo estructuras de datos + validación.
local M = {}

-- Kinds soportados (CONTRACTS.md §3). La lista crece por ADR, no ad-hoc.
M.KINDS = {
  run = true,
  build = true,
  test = true,
  debug = true,
  lint = true,
  format = true,
  misc = true,
}

-- Slug determinístico para construcción de IDs. Elimina espacios, símbolos y
-- normaliza a minúsculas. Es el único punto que "crea" identidad por derivación.
local function slug(s)
  s = tostring(s or "")
  s = s:gsub("%s+", "-")
  s = s:gsub("[^%w%._-]", "")
  s = s:gsub("-+", "-")
  s = s:gsub("^[%._-]+", ""):gsub("[%._-]+$", "")
  return s:lower()
end

-- Construye un ID canónico "runner.slug". Determinístico para el mismo input.
--   task.id("go", "Run")           -> "go.run"
--   task.id("go", "Test · TestA")  -> "go.test-testa"
--   task.id("", "anything")        -> "anything"
function M.id(runner, stem)
  local r = slug(runner or "")
  local n = slug(stem or "")

  if r == "" then
    return n
  end

  if n == "" then
    return r
  end

  return r .. "." .. n
end

-- Devuelve el error de validación de un TaskSpec, o nil si es válido.
local KEYS = {
  "id",
  "name",
  "kind",
  "command",
  "filetypes",
  "cwd",
  "condition",
  "enabled",
  "description",
}

function M.validate(spec)
  if type(spec) ~= "table" then
    return "TaskSpec debe ser una tabla"
  end

  if type(spec.id) ~= "string" or spec.id == "" then
    return "TaskSpec requiere 'id' (string no vacío)"
  end

  if type(spec.name) ~= "string" or spec.name == "" then
    return "TaskSpec requiere 'name' (string no vacío)"
  end

  if type(spec.kind) ~= "string" or not M.KINDS[spec.kind] then
    return "TaskSpec 'kind' inválido: " .. tostring(spec.kind)
  end

  if not (type(spec.command) == "string" or type(spec.command) == "function") then
    return "TaskSpec requiere 'command' (string o función)"
  end

  if spec.filetypes ~= nil and type(spec.filetypes) ~= "table" then
    return "TaskSpec 'filetypes' debe ser tabla o nil"
  end

  if spec.enabled ~= nil and type(spec.enabled) ~= "boolean" and type(spec.enabled) ~= "function" then
    return "TaskSpec 'enabled' debe ser boolean, función o nil"
  end

  return nil
end

-- Devuelve true si el spec es válido.
function M.valid(spec)
  return M.validate(spec) == nil
end

-- Normaliza un spec a un Task canónico. Devuelve nil + error si es inválido.
function M.new(spec)
  local err = M.validate(spec)

  if err then
    return nil, err
  end

  local filetypes = {}

  for i = 1, #(spec.filetypes or {}) do
    filetypes[i] = spec.filetypes[i]
  end

  local task = {
    id = spec.id,
    name = spec.name,
    kind = spec.kind,
    command = spec.command,
    filetypes = filetypes,
    cwd = spec.cwd,
    condition = spec.condition,
    enabled = spec.enabled,
    description = spec.description,
  }

  -- defaults
  if task.enabled == nil then
    task.enabled = true
  end

  return task
end

-- Como M.new pero lanza error si el spec es inválido (para registros que
-- quieren fallar temprano). Expuesto para consumidores que prefieren assert.
function M.new_or_error(spec)
  local task, err = M.new(spec)

  if not task then
    error("TaskSpec inválido: " .. tostring(err), 2)
  end

  return task
end

-- Proyección del catálogo legacy (label → command) a TaskSpec.
--
-- El catálogo actual identifica acciones por label con iconos de presentación
-- (ej. " Run"). Esta función convierte esa proyección en un TaskSpec con ID
-- estable derivado del texto, sin iconos. Es una adaptación de migración (no el
-- destino final de identidad): sirve para demostrar que el comportamiento
-- actual ES representable por TaskSpec.
--
--   icons: { run = <string>, build = <string> } para despegar los prefijos.
--   lang:  clave del catálogo (go, py, rust, ...).
function M.from_catalog(lang, label, command, icons)
  icons = icons or {}

  local run = icons.run or ""
  local build = icons.build or ""

  local kind = "misc"

  -- El kind se infiere del primer icono del label. Un label puede combinar
  -- ambos iconos (RUN..BUILD.." Compile & Run"): manda el primero.
  if build ~= "" and label:sub(1, #build) == build then
    kind = "build"
  elseif run ~= "" and label:sub(1, #run) == run then
    kind = "run"
  end

  -- Despegar TODOS los iconos iniciales (puede haber RUN+BUILD juntos).
  local text = label
  local stripped

  repeat
    stripped = false

    if run ~= "" and text:sub(1, #run) == run then
      text = text:sub(#run + 1)
      stripped = true
    end

    if build ~= "" and text:sub(1, #build) == build then
      text = text:sub(#build + 1)
      stripped = true
    end
  until not stripped

  text = (text or ""):gsub("^%s+", "")

  if text:lower():find("test", 1, true) then
    kind = "test"
  end

  return {
    id = M.id(lang, text),
    name = text,
    kind = kind,
    filetypes = { lang },
    command = command,
  }
end

M._internals = {
  slug = slug,
}

return M