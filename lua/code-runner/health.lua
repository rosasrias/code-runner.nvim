-- :checkhealth code-runner
-- Informa el estado de integración del plugin y la disponibilidad de las
-- herramientas reales que usan las acciones del catálogo **resuelto** (ya con
-- overrides del usuario/registry/profiles).
--
-- Para "distinguir lo que el usuario no usa", las herramientas solo se
-- revisan para los lenguajes que el usuario ha ejecutado (historial) o tiene
-- abiertos (buffer actual): un toolchain que no está instalado no es un error
-- si el usuario nunca lo usó.
local config = require "code-runner.config"
local history = require "code-runner.history"
local context = require "code-runner.context"

local M = {}

-- Extrae el binario del primer token de un comando. Ignora variables del
-- plugin ($binRun, $fileBase...) y rutas con separador (no son herramientas
-- del PATH).
function M._tool_of(cmd)
  if type(cmd) ~= "string" then
    return nil
  end

  local first = cmd:match "^%s*([^%s]+)"

  if not first then
    return nil
  end

  if first:sub(1, 1) == "$" then
    return nil
  end

  first = first:gsub("^[\"']", ""):gsub("[\"']$", "")

  if first:find "[/\\]" then
    return nil
  end

  return first
end

-- Herramientas que usa un conjunto de acciones (solo las de tipo string; las
-- funciones p.ej. java smart run no se pueden derivar por aquí).
function M._tools_for(actions)
  local tools = {}

  if type(actions) ~= "table" then
    return tools
  end

  for _, action in pairs(actions) do
    local t = M._tool_of(action)
    if t then
      tools[t] = true
    end
  end

  return tools
end

-- Lenguajes "usados": key del buffer actual + keys del historial. Devuelve la
-- unión, sin nils.
function M._used_keys()
  local keys = {}

  local ok, cur = pcall(context._resolve_key)
  if ok and cur and cur ~= "" then
    keys[cur] = true
  end

  local ok2, items = pcall(history.list)
  if ok2 and type(items) == "table" then
    for _, it in ipairs(items) do
      if it.key and it.key ~= "" then
        keys[it.key] = true
      end
    end
  end

  return keys
end

local RECOMMENDED = {
  -- "markdown" es "md" en el catálogo
  md = { glow = "preview de Markdown" },
}

-- Disponibilidad de cada herramienta para un lenguaje dado (derivadas de las
-- acciones). Devuelve lista de { name, present }.
function M._lang_tools(lang, actions)
  local missing, present = {}, {}

  for tool in pairs(M._tools_for(actions)) do
    local found = vim.fn.executable(tool) == 1
    if found then
      present[#present + 1] = tool
    else
      missing[#missing + 1] = tool
    end
  end

  for rec, why in pairs(RECOMMENDED[lang] or {}) do
    if vim.fn.executable(rec) == 1 then
      present[#present + 1] = rec .. " (recomendada: " .. why .. ")"
    end
  end

  table.sort(missing)
  table.sort(present)
  return missing, present
end

local function core(health)
  health.info("Nvim %s", vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch)

  if type(config.options) ~= "table" or not config.options.quickfix then
    health.error("Config no inicializada: llamá a require('code-runner').setup()")
    return false
  end

  health.ok "Config cargada (zero-config por defecto)"
  health.info("Canal de errores: quickfix.style = %s", config.options.quickfix.style or "?")

  return true
end

local function tools(health)
  local ok, actions_mod = pcall(require, "code-runner.actions")

  if not ok then
    health.error("No se pudo cargar el catálogo de acciones:", actions_mod)
    return
  end

  local ok2, actions = pcall(actions_mod.get_actions)

  if not ok2 then
    health.error("No se pudo construir el catálogo:", actions)
    return
  end

  local used = M._used_keys()
  local any_used = false

  for lang in pairs(used) do
    -- el catálogo clavea por extensión; "undefined"/vacío no cuentan
    local lang_actions = actions[lang]
    if lang_actions and next(lang_actions) then
      any_used = true
      local missing, present = M._lang_tools(lang, lang_actions)

      if #missing == 0 then
        health.ok("%s: herramientas listas (%s)", lang, table.concat(present, ", "))
      else
        health.warn(
          "%s: faltan %s (presentes: %s)",
          lang,
          table.concat(missing, ", "),
          #present > 0 and table.concat(present, ", ") or "ninguna"
        )
      end
    end
  end

  if not any_used then
    health.info(
      "Sin ejecuciones previas ni buffer con idioma conocido: probá :CodeRun en un archivo y volvé a correr :checkhealth."
    )
  end
end

function M.check()
  local ok, health = pcall(require, "vim.health")

  if not ok then
    ok, health = pcall(require, "health")
  end

  if not ok then
    vim.notify(":checkhealth requiere el módulo salud de Neovim", vim.log.levels.WARN)
    return
  end

  health.start "code-runner"
  local ready = core(health)
  if ready then
    tools(health)
  end
end

return M
