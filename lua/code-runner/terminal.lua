local config = require "code-runner.config"
local shell = require "code-runner.shell"

local M = {}
M.BUF_NAME = "code-runner"

-- identificador de buffers del PLUGIN: marcador en b:variables que pusimos al
-- crear el buffer y que sobrevive al rename que hace termopen (el nombre real
-- pasa a ser term://cwd//pid:cmd, así que el nombre solo no es fiable).
local PLUGIN_MARK = "code_runner_term"

local function has_marker(b)
  return vim.b[b] ~= nil and vim.b[b][PLUGIN_MARK] == true
end

-- Huérfano por convención de nombre (basename EXACTO + sin archivo listado):
-- buffers que la terminal deja cuando se borra; jamás un archivo real del
-- usuario que se llame "code-runner" (esos están listados y tienen buftype "").
local function is_orphan_by_name(b)
  if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t") ~= M.BUF_NAME then
    return false
  end

  -- buflisted puede venir como 1/0 o true/false según la build
  local listed = vim.bo[b].buflisted
  local is_listed = listed == 1 or listed == true

  return vim.bo[b].buftype == "terminal" or not is_listed
end

function M.notify(msg, level, title)
  level = level or vim.log.levels.INFO

  -- Si hay un proveedor de notificaciones propio (nvim-notify u otro),
  -- respetarlo: él ya sabe colorear por nivel.
  local info = debug.getinfo(vim.notify, "S")
  local src = info and (info.short_src or "") or ""
  local default_provider = src:find("_core[/\\]editor%.lua", 1) ~= nil
    or src:find("_defaults%.lua", 1) ~= nil

  if not default_provider then
    vim.notify(msg, level, { title = title or "code-runner.nvim" })
    return
  end

  -- El notify del core solo colorea WARN/ERROR (INFO sale blanco).
  -- Coloreamos nosotros con grupos estándar que existen en cualquier tema.
  local hl = "Question" -- verde: éxito/aviso
  if level == vim.log.levels.ERROR then
    hl = "ErrorMsg"
  elseif level == vim.log.levels.WARN then
    hl = "WarningMsg"
  end

  vim.api.nvim_echo({ { msg, hl } }, true, {})
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
    if has_marker(buf) then
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
-- Expuesto como M._label_parts para tests.
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
-- { texto } | { texto, hl }. Expuesto como M._apply_window_label.
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

-- Cierra la ventana que muestra `buf` y libera el buffer del plugin.
-- Si el job seguía corriendo, el cierre por el usuario se registra como
-- cancelado (la terminal se borra y con ella muere el job).
-- Expuesto como M._close_current para tests.
function M._close_current(buf)
  if require("code-runner.state").get().status == "running" then
    require("code-runner.state").set "cancelled"
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

-- Estado final visible en la ventana y mensaje claro de cómo cerrarla
-- (tanto para compilación como para ejecución o ambas).
-- Expuesto como M._exit_hint para tests.
function M._exit_hint(buf, code, qf_count)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local ok = code == 0
  local t = config.options.terminal

  if not ok then
    local msg

    if qf_count and qf_count > 0 then
      msg = (
        "El comando terminó con error (código %d). %d problema(s) en la lista quickfix (:cn / :cl)."
      ):format(code, qf_count)
    else
      msg = (
        "El comando terminó con error (código %d). No se detectaron errores parseables en la salida; revisá la terminal."
      ):format(code)
    end

    M.notify(msg, vim.log.levels.ERROR)
  else
    M.notify(
      "El comando terminó correctamente (código 0). Revisa la salida y cierra esta terminal con q.",
      vim.log.levels.INFO
    )
  end

  vim.keymap.set("n", "q", function()
    M._close_current(buf)
  end, { buffer = buf, nowait = true, desc = "Cerrar terminal de code-runner" })

  local parts = M._label_parts(vim.b[buf].code_runner_label)

  if ok then
    parts[#parts + 1] = { " · ✓ terminó OK · q cierra", "CodeRunnerTermOk" }
  else
    parts[#parts + 1] = { (" · ✗ error %d · q cierra"):format(code), "CodeRunnerTermErr" }
  end

  M._apply_window_label(buf, parts)
end

-- Estado al salir del proceso: quickfix + closure según la configuración.
-- Solo registra success/failed si el job sigue siendo el actual (run_id):
-- un on_exit asíncrono de un job reemplazado, o un cierre por el usuario
-- (cancelado), no pueden pisar el estado del job que corre ahora.
function M._on_exit(buf, code, cwd, run_id)
  local state = require "code-runner.state"
  local s = state.get()

  if s.status == "running" and (run_id or s.run_id) == s.run_id then
    state.set(code == 0 and "success" or "failed", { code = code, cwd = cwd })
  end

  -- Limpia temporales del job (p.ej. el directorio de clases que `javac -d`
  -- crea para el smart run de Java) en cuanto termina, sea éxito o error.
  local paths = vim.b[buf] and vim.b[buf].code_runner_cleanup

  if paths then
    for _, p in ipairs(paths) do
      pcall(vim.fn.delete, p, "rf")
    end

    if vim.b[buf] then
      vim.b[buf].code_runner_cleanup = nil
    end
  end

  local qf_count = require("code-runner.quickfix").handle(buf, code, cwd)

  local cfg = config.options.terminal

  if cfg.autoclose and code == 0 then
    if M._maybe_autoclose(buf, code) then
      return
    end
  end

  M._exit_hint(buf, code, qf_count)
end

-- Abre (o reutiliza) una terminal con el comando ya envuelto para el shell.
-- cwd (opcional): directorio en el que arranca el job (raíz del proyecto).
-- label (opcional): acción elegida (Run/Build) para el título de la ventana.
function M.open(cmd, direction, cwd, label, cleanup)
  direction = direction or config.options.terminal.direction
  local command = shell.wrap_command(cmd)

  -- Key resuelta del archivo del usuario ANTES de cambiar la ventana actual
  -- (después, la ventana activa pasa a ser la terminal y %:e ya no vale).
  local entry_key = require("code-runner.context")._resolve_key()

  local term_win = get_last_terminal_window()
  local state = require "code-runner.state"
  local buf

  if term_win then
    vim.api.nvim_set_current_win(term_win)
    local candidate = vim.api.nvim_win_get_buf(term_win)

    if state.get().status == "running" then
      -- El job del plugin sigue en marcha: cancelarlo y reabrir desde cero
      -- (evitar reutilizar un buffer jobado igual equivale a stop implícito).
      state.set "cancelled"
      pcall(vim.api.nvim_buf_delete, candidate, { force = true })
    else
      -- Job terminado: reusamos el buffer (termopen reinicia ahí el nuevo
      -- comando). Sin esto, crear otro buffer con el mismo nombre lanza E95.
      buf = candidate
    end
  else
    M._open_window(direction)
  end

  if not buf then
    -- Purga buffers del plugin que quedaron huérfanos (sin ventana): su job
    -- ya no corre o es nuestro y hay que reabrir. Dejarlos provoca E95 al
    -- crear otro buffer con el mismo nombre.
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= vim.api.nvim_get_current_buf() and (has_marker(b) or is_orphan_by_name(b)) then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end

    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, M.BUF_NAME)
    vim.b[buf][PLUGIN_MARK] = true
    vim.api.nvim_win_set_buf(0, buf)
  end

  label = label or ""
  vim.b[buf].code_runner_label = label
  vim.b[buf].code_runner_cleanup = cleanup or nil
  M._apply_window_label(buf, M._label_parts(label))

  local opts = {}

  if cwd and cwd ~= "" then
    opts.cwd = cwd
  end

  -- Estado central antes de lanzar: registra el job nuevo y su run_id. Los
  -- on_exit de jobs anteriores (run_id viejo) no podrán pisar este estado.
  state.set("running", {
    action = label ~= "" and label or nil,
    cwd = cwd,
    filetype = entry_key,
    buf = buf,
  })
  local rid = state.get().run_id

  opts.on_exit = function(_, code)
    M._on_exit(buf, code, cwd, rid)
  end

  -- termopen exige un buffer sin modificar: al reusar el buffer de la
  -- terminal, el job anterior dejó `modified` en al revisar.
  pcall(vim.api.nvim_buf_set_option, buf, "modified", false)

  if vim.fn.termopen(command, opts) == -1 then
    state.set("failed", { code = -1 })
    M.notify("No se pudo lanzar el comando: " .. command, vim.log.levels.ERROR)
    return
  end

  vim.cmd "startinsert"
end

return M