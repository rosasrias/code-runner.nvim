local config = require "code-runner.config"
local shell = require "code-runner.shell"

local M = {}
M.BUF_NAME = "code-runner"

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

-- Reutiliza SOLO terminales del plugin (mismo buffer con nombre propio)
local function get_last_terminal_window()
  local terms = {}

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "terminal" and vim.api.nvim_buf_get_name(buf):find(M.BUF_NAME, 1, true) then
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

-- Crea la ventana para la terminal según la dirección configurada.
-- Expuesto como M._open_window para tests.
function M._open_window(direction)
  local main = get_main_window()
  vim.api.nvim_set_current_win(main)

  if direction == "float" then
    local cfg = config.options.terminal.float
    local cols = vim.o.columns
    local lines = vim.o.lines

    vim.api.nvim_open_win(vim.api.nvim_get_current_buf(), true, {
      relative = "editor",
      width = math.floor(cols * cfg.width),
      height = math.floor(lines * cfg.height),
      col = math.floor(cols * (1 - cfg.width) / 2),
      row = math.floor(lines * (1 - cfg.height) / 2),
      style = "minimal",
      border = "rounded",
    })
    return
  end

  if direction == "horizontal" then
    vim.cmd "split"
    vim.cmd("resize " .. config.options.terminal.height)
  else
    vim.cmd "vsplit"
    vim.cmd("vertical resize " .. config.options.terminal.vertical_width)
  end
end

-- Cierra la terminal si terminó con éxito (autoclose). Nunca deja la
-- sesión sin ventanas.
function M._maybe_autoclose(buf, code)
  local cfg = config.options.terminal

  if not cfg.autoclose or code ~= 0 then
    return false
  end

  if #vim.api.nvim_list_wins() <= 1 then
    return false
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  return true
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
    M._open_window(direction)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, M.BUF_NAME)
  vim.api.nvim_win_set_buf(0, buf)
  local opts = {}

  if cwd and cwd ~= "" then
    opts.cwd = cwd
  end

  opts.on_exit = function(_, code)
    require("code-runner.quickfix").handle(buf, code, cwd)
    M._maybe_autoclose(buf, code)
  end

  vim.fn.termopen(command, opts)
  vim.cmd "startinsert"
end

return M