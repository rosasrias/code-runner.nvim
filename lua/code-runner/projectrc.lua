-- Carga de `.code-runner.lua` por proyecto (P1).
--
-- Busca el archivo en la raíz del proyecto del buffer actual (mismo root que
-- usa `project.resolve` para ejecutar) y lo evalúa una sola vez por raíz
-- (cacheado). El archivo puede:
--   1) llamar directamente a la API:  require("code-runner").register_action{...}
--   2) devolver una tabla con `tasks`:  return { tasks = { dev = { ... } } }
--      donde cada task es un spec completo de register_action (id/name/
--      filetypes/kind/command|run). Se registran vía el registry.
-- Se carga de forma segura (pcall); los errores se notifican, no se propagan.
local config = require "code-runner.config"
local terminal = require "code-runner.terminal"

local M = {}

local DOTFILE = ".code-runner.lua"
local loaded_roots = {}

-- Registra las tasks devueltas por el dotfile (`return { tasks = {...} }`).
-- Dos formas:
--   - con `steps` (lista de comandos) → task de workflow (engine secuencial,
--     se invoca por nombre con :CodeRunTask); no aparece en el picker.
--   - con `command`/`run` → acción del picker (registry), el flujo P1 original.
local function register_tasks(tasks, root, key)
  local registry = require "code-runner.actions.registry"

  for name, task in pairs(tasks) do
    if task.steps ~= nil then
      require("code-runner.workflow").register({
        name = task.name or name,
        steps = task.steps,
        stop_on_fail = task.stop_on_fail,
        parallel = task.parallel,
        cwd = task.cwd or root,
        key = task.key or key,
      })
    else
      local spec = vim.tbl_deep_extend("force", task, {
        id = task.id or name,
        name = task.name or name,
      })
      registry.register(spec)
    end
  end
end

-- Carga el dotfile para el proyecto del `key` dado. Devuelve true si existía
-- y se cargó (o error notificado), false si no hay dotfile. Idempotente por raíz.
function M.load(key, dir)
  if not config.options.projectrc.enabled then
    return false
  end

  local project = require "code-runner.project"

  local root

  if dir then
    -- Permite probar/llamar con una raíz explícita (#test y usuarios).
    root = project.find_from(dir, key) or dir
  else
    root = project.resolve(key)
  end

  if not root or loaded_roots[root] ~= nil then
    return loaded_roots[root] == true and true or false
  end

  local file = root .. "/" .. DOTFILE

  if vim.fn.filereadable(file) ~= 1 then
    loaded_roots[root] = false
    return false
  end

  loaded_roots[root] = true

  local ok, result = pcall(dofile, file)

  if not ok then
    terminal.notify(".code-runner.lua: " .. tostring(result), vim.log.levels.ERROR)
    return true
  end

  if type(result) == "table" and result.tasks then
    local reg_ok, reg_err = pcall(register_tasks, result.tasks, root, key)

    if not reg_ok then
      terminal.notify(".code-runner.lua: tasks inválidas: " .. tostring(reg_err), vim.log.levels.ERROR)
    end
  end

  return true
end

-- Limpia el cache (tests / cambios del archivo en runtime).
function M.clear_cache()
  loaded_roots = {}
end

return M
