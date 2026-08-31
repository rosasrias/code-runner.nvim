-- Orquestador del catálogo de acciones por lenguaje.
--
-- El catálogo en sí vive en `actions/catalog.lua` (y sus helpers de Java/LaTeX
-- en `actions/java.lua` y `actions/latex.lua`) para mantener los módulos
-- pequeños. Aquí se ensambla: catálogo + overrides de usuario + alias R + orden.
local config = require "code-runner.config"
local terminal = require "code-runner.terminal"
local catalog = require "code-runner.actions.catalog"
local registry = require "code-runner.actions.registry"
local java = require "code-runner.actions.java"
local shell = require "code-runner.shell"
local profiles = require "code-runner.actions.profiles"

local M = {}

local open_runner = terminal.open
local notify = terminal.notify

function M.get_actions()
  local actions = catalog.build(open_runner, notify)

  -- Presets de perfiles (opt-in): variantes release/benchmark donde la
  -- herramienta las tiene de verdad. Se aplica al nivel del catálogo, así el
  -- usuario/registry pueden sobrescribirlos (misma prioridad que built-in).
  if config.options.profiles.enabled then
    local env = {
      RUN = config.options.icons.run,
      BUILD = config.options.icons.build,
      shell = shell,
    }
    for key in pairs(actions) do
      local extra = profiles.for_lang(env, key)
      if extra then
        actions[key] = vim.tbl_extend("force", actions[key] or {}, extra)
      end
    end
  end

  -- Extensiones del usuario (sobrescriben o añaden)
  for ext, user_actions in pairs(config.options.actions or {}) do
    if next(user_actions) == nil then
      actions[ext] = nil -- extensión explícitamente deshabilitada
    else
      actions[ext] = vim.tbl_extend("force", actions[ext] or {}, user_actions)
    end
  end

  -- Action registry (register_action): prioridad máxima sobre built-ins y
  -- config cruda. Aplica labels con icono según `kind`.
  actions = registry.apply(actions, config.options.icons)

  -- Alias para R (los scripts suelen usar extensión mayúscula)
  if actions.r then
    actions.R = vim.deepcopy(actions.r)
    actions.R.__order = nil
  end

  -- Orden alfabético estable en el selector
  for _, lang in pairs(actions) do
    local names = vim.tbl_keys(lang)
    table.sort(names)
    lang.__order = names
  end

  return actions
end

---------------------------------------------------------
-- Internals expuestos solo para tests
---------------------------------------------------------
M._internals = {
  java_has_main = java.has_main,
  java_package_of = java.package_of,
  java_source_root = java.source_root,
  find_pom_directory = java.find_pom_directory,
}

return M
