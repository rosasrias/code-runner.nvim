-- RunnerSpec: la descripción declarativa de un runner (RUN-001, ADR-016).
--
-- Un Runner DECLARA capacidades y tareas; no detecta, no resuelve, no ejecuta:
--
--   declara   RunnerSpec (este módulo: datos + validación pura)
--   resuelve  Task Resolver (fase RUN-002: candidatos desde un contexto)
--   detecta   adaptadores (filesystem, ejecutables) — nunca el spec
--   ejecuta   Execution Engine (el runner nunca spawnea)
--
-- Forma:
--   {
--     id = "go",                        -- estable (runner del task.id)
--     filetypes = { "go" },             -- hints de ruteo (datos, no detección)
--     project = { markers = { "go.mod" } }, -- NOMBRES de marcadores, sin FS
--     tasks = { TaskSpec, ... },        -- TaskSpec válidos SIN funciones
--   }
--
-- Sin funciones en ningún campo (`command`, `condition`, `enabled`, `cwd`
-- como función se rechazan): un spec con comportamiento no es declarativo.
-- La resolución condicional vive en el resolver (RUN-002), no en el spec.
-- Tampoco duplica TaskSpec: las tareas SON TaskSpec (task.lua), el runner
-- las compone.
--
-- Semántica de `enabled` (campo del propio TaskSpec, sin campos nuevos):
-- ausente = incluido (default `true` de `task.new`); `false` = exclusión
-- explícita; otro tipo = error de validación (nunca conversión silenciosa).
-- Ids en minúsculas para un orden total inequívoco.
--
-- Condiciones de disponibilidad (batch explícito, ADR-018): una tarea puede
-- llevar `when = { os = "win"|"unix", tools = { "glow" } }` (todo opcional).
-- Es DATO declarativo: el resolver la evalúa contra disponibilidad
-- inyectada (`resolve` opts); el spec nunca sondea nada. Conjunción simple:
-- todo lo declarado debe cumplirse; sin datos para evaluarlo, la tarea se
-- excluye (explícito, nunca permisividad silenciosa).
--
-- Core puro: solo depende de `task.lua`. Sin vim, FS, procesos ni UI.
local task = require "code-runner.task"

local M = {}

-- Identidad estable: minúsculas, sin espacios (forma canónica del slug de
-- task.id). Los ids con mayúsculas se rechazan para que el desempate por id
-- del resolver sea inequívoco (sin equivalencias implícitas).
local function valid_id(id)
  return type(id) == "string" and id:match("^[a-z0-9][a-z0-9._-]*$") ~= nil
end

local function string_list(value, what)
  if value == nil then
    return true
  end

  if type(value) ~= "table" then
    return false, what .. " debe ser tabla o nil"
  end

  for i, v in ipairs(value) do
    if type(v) ~= "string" or v == "" then
      return false, what .. "[" .. i .. "] debe ser string no vacío"
    end
  end

  return true
end

-- Rechaza cualquier valor función (comportamiento, no declaración).
local function no_functions(value, path)
  if type(value) == "function" then
    return "RunnerSpec es declarativo: " .. path .. " no puede ser función"
  end

  if type(value) == "table" then
    for k, v in pairs(value) do
      local err = no_functions(v, path .. "." .. tostring(k))

      if err then
        return err
      end
    end
  end

  return nil
end

local KNOWN_KEYS = {
  id = true,
  filetypes = true,
  project = true,
  tasks = true,
  description = true,
}

local KNOWN_WHEN_KEYS = {
  os = true,
  tools = true,
}

local VALID_OS = {
  win = true,
  unix = true,
}

-- Valida `when` (condiciones de disponibilidad como dato). nil = sin
-- condiciones. Devuelve nil o string de error.
local function validate_when(when, path)
  if when == nil then
    return nil
  end

  if type(when) ~= "table" then
    return path .. " debe ser tabla o nil"
  end

  for k in pairs(when) do
    if not KNOWN_WHEN_KEYS[k] then
      return path .. ": campo desconocido '" .. tostring(k) .. "'"
    end
  end

  if when.os ~= nil and not VALID_OS[when.os] then
    return path .. '.os debe ser "win", "unix" o nil'
  end

  if when.tools ~= nil then
    if type(when.tools) ~= "table" then
      return path .. ".tools debe ser tabla o nil"
    end

    for i, tool in ipairs(when.tools) do
      if type(tool) ~= "string" or tool == "" then
        return path .. ".tools[" .. i .. "] debe ser string no vacío"
      end
    end
  end

  return nil
end

local function copy_when(when)
  if when == nil then
    return nil
  end

  local out = { os = when.os }

  if when.tools ~= nil then
    out.tools = {}

    for i, tool in ipairs(when.tools) do
      out.tools[i] = tool
    end
  end

  return out
end

-- Devuelve el error de validación o nil si es válido.
function M.validate(spec)
  if type(spec) ~= "table" then
    return "RunnerSpec debe ser una tabla"
  end

  for k in pairs(spec) do
    if not KNOWN_KEYS[k] then
      return "RunnerSpec: campo desconocido '" .. tostring(k) .. "'"
    end
  end

  if not valid_id(spec.id) then
    return "RunnerSpec requiere 'id' estable en minúsculas (ej. 'go', sin espacios ni mayúsculas)"
  end

  local ok, err = string_list(spec.filetypes, "RunnerSpec 'filetypes'")

  if not ok then
    return err
  end

  if spec.project ~= nil then
    if type(spec.project) ~= "table" then
      return "RunnerSpec 'project' debe ser tabla o nil"
    end

    local pok, perr = string_list(spec.project.markers, "RunnerSpec 'project.markers'")

    if not pok then
      return perr
    end
  end

  if spec.description ~= nil and type(spec.description) ~= "string" then
    return "RunnerSpec 'description' debe ser string o nil"
  end

  if spec.tasks ~= nil then
    if type(spec.tasks) ~= "table" then
      return "RunnerSpec 'tasks' debe ser tabla o nil"
    end

    for i, t in ipairs(spec.tasks) do
      local terr = task.validate(t)

      if terr then
        return "RunnerSpec tasks[" .. i .. "] inválido: " .. terr
      end

      -- `enabled` es el ÚNICO toggle declarativo y viene del propio TaskSpec
      -- (booleano; ausente = true por `task.new`). `task.validate` ya rechaza
      -- otros tipos (sin conversión silenciosa); acá se documenta la fuente
      -- para no inventar campos: nada sale de configuración externa.
      -- `condition`, en cambio, no pertenece al spec en ningún tipo: la
      -- disponibilidad condicional se expresa con filetypes/markers y las
      -- condiciones de runtime vivirán en el resolver (fase explícita).
      if t.condition ~= nil then
        return "RunnerSpec tasks[" .. i .. "].condition no pertenece al spec declarativo (usar filetypes/markers)"
      end

      local werr = validate_when(t.when, "tasks[" .. i .. "].when")

      if werr then
        return "RunnerSpec " .. werr
      end

      local ferr = no_functions(t, "tasks[" .. i .. "]")

      if ferr then
        return ferr
      end
    end
  end

  return nil
end

-- True si el spec es un RunnerSpec válido.
function M.valid(spec)
  return M.validate(spec) == nil
end

local function copy_list(value)
  if value == nil then
    return {}
  end

  local out = {}

  for i, v in ipairs(value) do
    out[i] = v
  end

  return out
end

-- Normaliza un RunnerSpec canónico y desacoplado (copia). Devuelve
-- (spec, nil) o (nil, error). Las tasks se normalizan con `task.new`.
function M.new(spec)
  local err = M.validate(spec)

  if err then
    return nil, err
  end

  local tasks = {}

  for i, t in ipairs(spec.tasks or {}) do
    local nt, nerr = task.new(t)

    if not nt then
      return nil, "RunnerSpec tasks[" .. i .. "] inválido: " .. tostring(nerr)
    end

    -- `task.new` no conoce `when` (contrato P1 intacto): se re-adjunta aquí
    -- ya validado, desacoplado.
    nt.when = copy_when(t.when)
    tasks[i] = nt
  end

  local project

  if spec.project ~= nil then
    project = { markers = copy_list(spec.project.markers) }
  end

  return {
    id = spec.id,
    filetypes = copy_list(spec.filetypes),
    project = project,
    tasks = tasks,
    description = spec.description,
  }, nil
end

-- Como `new`, pero lanza en inválido.
function M.new_or_error(spec)
  local r, err = M.new(spec)

  if not r then
    error("RunnerSpec inválido: " .. tostring(err), 2)
  end

  return r
end

-- Proyección del catálogo legacy a RunnerSpec (precedente: task.from_catalog,
-- ARCH-002). `entry` es `{ [label] = command|string|function, __order }`,
-- `key` la extensión/filetype, `markers` la lista declarativa de marcadores
-- (ver `project.markers_for`), `icons` para despegar presentación.
--
-- Solo las acciones string son declarativas: las function se OMITEN y se
-- reportan en `skipped` (no se migran en silencio). Devuelve
-- (spec_plano, { skipped = {label,...} }) o (nil, error) si la key no da un
-- id válido. El spec resultante se normaliza con `M.new` por el llamador.
-- Puro, sin comportamiento: sirve para caracterizar el catálogo real contra
-- el resolver sin cambiar la selección productiva.
function M.from_catalog_entry(key, entry, markers, icons)
  if type(key) ~= "string" or key == "" then
    return nil, "from_catalog_entry: key debe ser string no vacío"
  end

  -- Aliases de presentación ("R" = copia de "r"): no son identidades nuevas.
  -- Se omiten con motivo explícito en vez de duplicar la declaración.
  if key ~= key:lower() then
    return nil, "from_catalog_entry: alias '" .. key .. "': usar la key minúscula"
  end

  if type(entry) ~= "table" or type(entry.__order) ~= "table" then
    return nil, "from_catalog_entry: entry sin __order (alias o vacía)"
  end

  local tasks = {}
  local skipped = {}

  for _, label in ipairs(entry.__order) do
    local command = entry[label]

    if type(command) == "string" then
      tasks[#tasks + 1] = task.from_catalog(key, label, command, icons)
    elseif label ~= "__order" then
      skipped[#skipped + 1] = label
    end
  end

  local spec = {
    id = key,
    filetypes = { key },
    tasks = tasks,
  }

  if markers ~= nil then
    spec.project = { markers = markers }
  end

  return spec, { skipped = skipped }
end

return M
