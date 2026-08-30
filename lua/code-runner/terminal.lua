local config = require "code-runner.config"
local shell = require "code-runner.shell"

local M = {}

function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "code-runner.nvim" })
end

local function get_main_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.bo[buf].filetype
    if ft ~= "NvimTree" and ft ~= "terminal" then
      return win
    end
  end
  return vim.api.nvim_get_current_win()
end

local function get_last_terminal_window()
  local terms = {}

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "terminal" then
      local pos = vim.api.nvim_win_get_position(win)
      table.insert(terms, { win = win, row = pos[1], col = pos[2] })
    end
  end

  if #terms == 0 then
    return nil
  end

  table.sort(terms, function(a, b)
    if a.col == b.col then
      return a.row < b.row
    end
    return a.col < b.col
  end)

  return terms[#terms].win
end

-- Abre (o reutiliza) una terminal con el comando ya envuelto para el shell.
-- cwd (opcional): directorio en el que arranca el job (raíz del proyecto).
function M.open(cmd, direction, cwd)
  direction = direction or config.options.terminal.direction
  local command = shell.wrap_command(cmd)

  local term_win = get_last_terminal_window()

  if term_win then
    vim.api.nvim_set_current_win(term_win)
  else
    vim.api.nvim_set_current_win(get_main_window())

    if direction == "horizontal" then
      vim.cmd "split"
      vim.cmd("resize " .. config.options.terminal.height)
    else
      vim.cmd "vsplit"
      vim.cmd("vertical resize " .. config.options.terminal.vertical_width)
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  local opts = {}

  if cwd and cwd ~= "" then
    opts.cwd = cwd
  end

  vim.fn.termopen(command, opts)
  vim.cmd "startinsert"
end

return M
