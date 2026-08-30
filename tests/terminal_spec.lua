local terminal = require "code-runner.terminal"
local config = require "code-runner.config"

local function clean_windows()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).float and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  local wins = vim.api.nvim_list_wins()
  local first = vim.api.nvim_get_current_win()

  for _, win in ipairs(wins) do
    if not vim.api.nvim_win_get_config(win).float then
      first = win
      break
    end
  end

  vim.api.nvim_set_current_win(first)

  while #vim.api.nvim_list_wins() > 1 do
    local closed = false

    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if win ~= first and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
        closed = true
        break
      end
    end

    if not closed then
      break
    end
  end
end

T.section("terminal: defaults y public API")

T.it("los defaults mantienen la terminal abierta con título propio", function()
  T.eq(false, config.options.terminal.autoclose)
  T.truthy(config.options.terminal.title)
  T.truthy(config.options.terminal.float.width)
  T.truthy(config.options.terminal.float.height)
end)

T.it("el buffer del plugin tiene nombre propio (para reutilizarlo)", function()
  T.eq("code-runner", terminal.BUF_NAME)
end)

T.section("terminal: creación de ventanas")

T.it("horizontal crea un split normal (no flotante)", function()
  vim.cmd "only"
  local before = #vim.api.nvim_list_wins()

  terminal._open_window("horizontal")

  T.eq(before + 1, #vim.api.nvim_list_wins())
  T.falsy(vim.api.nvim_win_get_config(0).float)

  clean_windows()
end)

T.it("float crea una ventana flotante sobre el editor", function()
  vim.cmd "only"

  terminal._open_window("float")

  local cfg = vim.api.nvim_win_get_config(0)
  T.eq("editor", cfg.relative)

  clean_windows()
end)

T.section("terminal: autoclose al terminar con éxito")

local function with_term_window()
  clean_windows()
  -- purga buffers heredados de otros tests con el mismo nombre
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):find(terminal.BUF_NAME, 1, true) then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end

  local term_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(term_buf, terminal.BUF_NAME)
  vim.cmd "split"
  vim.api.nvim_win_set_buf(0, term_buf)
  return term_buf
end

T.it("exit code 0 cierra la ventana de la terminal", function()
  config.options.terminal.autoclose = true
  local term_buf = with_term_window()
  local before = #vim.api.nvim_list_wins()

  T.truthy(terminal._maybe_autoclose(term_buf, 0))

  T.eq(before - 1, #vim.api.nvim_list_wins(), "una ventana menos")
  clean_windows()
end)

T.it("exit code != 0 mantiene la terminal abierta", function()
  config.options.terminal.autoclose = true
  local term_buf = with_term_window()
  local before = #vim.api.nvim_list_wins()

  T.falsy(terminal._maybe_autoclose(term_buf, 1))

  T.eq(before, #vim.api.nvim_list_wins())
  clean_windows()
end)

T.it("no cierra si es la única ventana", function()
  config.options.terminal.autoclose = true
  clean_windows()
  local term_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, term_buf)

  T.falsy(terminal._maybe_autoclose(term_buf, 0), "protege la última ventana")
  clean_windows()
end)

T.it("autoclose=false nunca cierra", function()
  config.options.terminal.autoclose = false
  local term_buf = with_term_window()

  T.falsy(terminal._maybe_autoclose(term_buf, 0))

  clean_windows()
  config.options.terminal = vim.deepcopy(config.defaults.terminal)
end)

T.section("terminal: título visible (winbar/float)")

T.it("la ventana float recibe el título en su borde", function()
  vim.cmd "only"
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = 20,
    height = 10,
    row = 1,
    col = 1,
    style = "minimal",
    border = "rounded",
  })

  terminal._apply_window_label(buf, "⚡ CodeRunner · Terminal · Build")

  local title = vim.api.nvim_win_get_config(win).title
  T.truthy(vim.inspect(title):find("CodeRunner · Terminal · Build", 1, true), "el título del float está presente")

  clean_windows()
end)

T.it("los splits muestran la terminal en su winbar", function()
  clean_windows()
  vim.cmd "only"
  local buf = vim.api.nvim_create_buf(false, true)
  vim.cmd "split"
  vim.api.nvim_win_set_buf(0, buf)

  terminal._apply_window_label(buf, "⚡ CodeRunner · Terminal · Run")

  local wb = vim.wo[0].winbar or ""
  T.truthy(wb:find("Terminal", 1, true), "winbar contiene el título")

  clean_windows()
end)

T.section("terminal: al terminar se mantiene abierta con ayuda")

T.it("sin autoclose queda abierta, avisa y ofrece q para cerrar", function()
  config.options.terminal.autoclose = false
  local term_buf = with_term_window()
  local before = #vim.api.nvim_list_wins()

  terminal._exit_hint(term_buf, 0)

  T.eq(before, #vim.api.nvim_list_wins(), "la ventana sigue abierta")

  local has_q = false
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(term_buf, "n")) do
    if m.lhs == "q" then
      has_q = true
      break
    end
  end

  T.truthy(has_q, "existe el mapa q para cerrar la terminal")

  terminal._close_current(term_buf)
  T.falsy(vim.api.nvim_buf_is_valid(term_buf), "se libera el buffer del plugin")

  clean_windows()
end)

T.it("con error también queda abierta y marca el título", function()
  config.options.terminal.autoclose = false
  local term_buf = with_term_window()

  terminal._exit_hint(term_buf, 2)

  local wb = vim.wo[0].winbar or ""
  T.truthy(wb:find("error", 1, true), "el winbar avisa del fallo")

  clean_windows()
end)

pcall(clean_windows)