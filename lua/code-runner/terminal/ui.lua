-- UI de la terminal: abrir la ventana (split/float), título/winbar coloreado y
-- autoclose. Separado de terminal.lua (ciclo de vida del job) para mantener
-- módulos pequeños.
local config = require "code-runner.config"
local buffer = require "code-runner.terminal.buffer"

local M = {}

-- Fondo de la terminal igual al de NvimTree (darker_black).
-- Sin esto la terminal usa el Normal del editor (black), visiblemente
-- más claro que el sidebar. Opt-out: terminal.winhighlight = "".
function M._apply_term_bg(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local hl = config.options.terminal.winhighlight
  if hl == nil then
    return
  end
  if hl ~= "" then
    -- Solo el fondo del titulo: resuelve su bg efectivo y lo aplica en un
    -- grupo propio sin fg, asi el texto de la terminal no se toca. Se
    -- resuelve en cada apertura: sigue al tema (incluye recargas) y no
    -- depende de base46. Sin bg en el titulo, el grupo queda vacio y la
    -- terminal usa su fondo normal.
    local ok, title_hl = pcall(vim.api.nvim_get_hl, 0, { name = "CodeRunnerTermTitle", link = true })
    if ok and title_hl and title_hl.bg then
      vim.api.nvim_set_hl(0, "CodeRunnerTermBg", { bg = title_hl.bg })
    else
      vim.api.nvim_set_hl(0, "CodeRunnerTermBg", {})
    end
  end
  -- "" limpia el heredado del split (los splits heredan winhighlight).
  vim.wo[win].winhighlight = hl
end

-- Crea la ventana para la terminal según la dirección configurada.
function M._open_window(direction)
  local main = buffer.get_main_window()
  vim.api.nvim_set_current_win(main)

  if direction == "float" then
    local cfg = config.options.terminal.float
    local cols = vim.o.columns
    local lines = vim.o.lines

    local win = vim.api.nvim_open_win(vim.api.nvim_get_current_buf(), true, {
      relative = "editor",
      width = math.floor(cols * cfg.width),
      height = math.floor(lines * cfg.height),
      col = math.floor(cols * (1 - cfg.width) / 2),
      row = math.floor(lines * (1 - cfg.height) / 2),
      style = "minimal",
      border = "rounded",
    })
    M._apply_term_bg(win)
    return
  end

  if direction == "horizontal" then
    vim.cmd "split"
    vim.cmd("resize " .. config.options.terminal.height)
  else
    vim.cmd "vsplit"
    vim.cmd("vertical resize " .. config.options.terminal.vertical_width)
  end
  M._apply_term_bg(vim.api.nvim_get_current_win())
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

-- Color de la acción según su icono (repite la lógica del picker con los
-- grupos propios del plugin, personalizables en base46)
local function label_hl(label)
  local icons = config.options.icons

  if icons.run ~= "" and label:find(icons.run, 1, true) then
    return "CodeRunnerActionRun"
  end

  if icons.build ~= "" and label:find(icons.build, 1, true) then
    return "CodeRunnerActionBuild"
  end

  return "CodeRunnerActionMisc"
end

-- Segmentos [texto, hl] del título: base + la acción elegida coloreada.
function M._label_parts(label)
  local parts = { { config.options.terminal.title, "CodeRunnerTermTitle" } }

  if label and label ~= "" then
    parts[#parts + 1] = " · "
    parts[#parts + 1] = { label, label_hl(label) }
  end

  return parts
end

-- Pone el texto de la ventana de la terminal: title del float o winbar en
-- los splits. Acepta un string (plano) o una lista de segmentos:
-- { texto } | { texto, hl }.
function M._apply_window_label(buf, parts)
  local segments = type(parts) == "table" and parts or { { parts, nil } }

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      if vim.api.nvim_win_get_config(win).relative ~= "" then
        local float_title = {}

        for _, s in ipairs(segments) do
          if type(s) == "string" then
            float_title[#float_title + 1] = { s }
          elseif s[2] and s[2] ~= "" then
            float_title[#float_title + 1] = { s[1], s[2] }
          else
            float_title[#float_title + 1] = { s[1] }
          end
        end

        vim.api.nvim_win_set_config(win, { title = float_title })
      else
        local winbar_parts = {}

        for _, s in ipairs(segments) do
          if type(s) == "string" then
            winbar_parts[#winbar_parts + 1] = s
          elseif s[2] and s[2] ~= "" then
            winbar_parts[#winbar_parts + 1] = ("%%#%s#%s%%*"):format(s[2], s[1])
          else
            winbar_parts[#winbar_parts + 1] = s[1]
          end
        end

        vim.wo[win].winbar = " " .. table.concat(winbar_parts)
      end
    end
  end
end

return M
