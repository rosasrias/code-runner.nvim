-- Identificación y localización de los buffers/ventanas de terminal del plugin.
-- Separado para que terminal.lua y terminal/ui.lua compartan la lógica sin
-- acoplamiento circular.
local M = {}

M.BUF_NAME = "code-runner"

-- Marcador en b:variables que sobrevive al rename que hace termopen (el nombre
-- real pasa a ser term://cwd//pid:cmd, así que el nombre solo no es fiable).
M.PLUGIN_MARK = "code_runner_term"

function M.has_marker(b)
  return vim.b[b] ~= nil and vim.b[b][M.PLUGIN_MARK] == true
end

-- Huérfano por convención de nombre (basename EXACTO + sin archivo listado):
-- buffers que la terminal deja cuando se borra; jamás un archivo real del
-- usuario que se llame "code-runner" (esos están listados y tienen buftype "").
function M.is_orphan_by_name(b)
  if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t") ~= M.BUF_NAME then
    return false
  end

  -- buflisted puede venir como 1/0 o true/false según la build
  local listed = vim.bo[b].buflisted
  local is_listed = listed == 1 or listed == true

  return vim.bo[b].buftype == "terminal" or not is_listed
end

function M.get_main_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.bo[buf].filetype
    if ft ~= "NvimTree" and ft ~= "terminal" then
      return win
    end
  end
  return vim.api.nvim_get_current_win()
end

-- Reutiliza SOLO terminales del plugin (mismo buffer con nombre propio).
function M.get_last_terminal_window()
  local terms = {}

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if M.has_marker(buf) then
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

return M
