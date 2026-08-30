local config = require "code-runner.config"

local M = {}

local last_choice = nil

M.setup = function(opts)
  config.setup(opts)
end

local function autosave()
  if not config.options.autosave then
    return
  end

  if vim.bo.buftype == "" and vim.bo.modified then
    pcall(vim.cmd, "silent write")
  end
end

local function execute_action(action)
  local shell = require "code-runner.shell"
  local terminal = require "code-runner.terminal"

  if type(action) == "function" then
    local ok, err = pcall(action)
    if not ok then
      terminal.notify(err, vim.log.levels.ERROR)
    end
  else
    terminal.open(shell.substitute(action))
  end
end

local function build_entry(actions, terminal)
  -- Busca acciones por extensión; si no hay, por filetype (ej: Makefile)
  local key = vim.fn.expand "%:e"

  if key == "" or not actions[key] then
    local ft = vim.bo.filetype
    if ft ~= "" and actions[ft] then
      key = ft
    end
  end

  local entry = actions[key]

  if not entry then
    terminal.notify("Tipo de archivo no soportado: ." .. (key == "" and "(sin extensión)" or key), vim.log.levels.WARN)
    return nil, nil
  end

  return entry, key
end

function M.build_run()
  autosave()

  if vim.bo.buftype ~= "" then
    return
  end

  local actions = require "code-runner.actions"
  local picker = require "code-runner.picker"
  local terminal = require "code-runner.terminal"

  local entry, key = build_entry(actions.get_actions(), terminal)

  if not entry then
    return
  end

  -- Título contextual: "⚡ CodeRunner · App.java"
  local ctx = vim.fn.expand "%:t"
  if ctx == "" then
    ctx = vim.fn.expand "%:e" ~= "" and ("." .. vim.fn.expand "%:e") or "sin archivo"
  end

  picker.select(entry.__order, {
    prompt = config.options.picker.title,
    title = config.options.picker.title .. " · " .. ctx,
  }, function(choice)
    if not choice then
      return
    end

    last_choice = { lang = key, choice = choice }
    execute_action(entry[choice])
  end)
end

-- Repite la última acción ejecutada sin abrir el selector
function M.run_last()
  autosave()

  local terminal = require "code-runner.terminal"

  if not last_choice then
    terminal.notify("No hay una ejecución anterior", vim.log.levels.WARN)
    return
  end

  local entry = require("code-runner.actions").get_actions()[last_choice.lang]
  local action = entry and entry[last_choice.choice]

  if not action then
    terminal.notify("La acción anterior ya no está disponible", vim.log.levels.WARN)
    return
  end

  execute_action(action)
end

-- Expuesto para tests
M._build_entry = build_entry

return M
