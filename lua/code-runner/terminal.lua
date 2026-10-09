-- Ciclo de vida de la terminal del plugin: abrir/reutilizar la ventana, lanzar
-- el job (termopen), registrar estado central y limpiar al salir.
-- La UI (ventana/winbar/autoclose) vive en `terminal/ui.lua` y la
-- identificación de buffers en `terminal/buffer.lua`.
local config = require "code-runner.config"
local shell = require "code-runner.shell"
local buffer = require "code-runner.terminal.buffer"
local ui = require "code-runner.terminal.ui"
local tracking = require "code-runner.terminal.tracking"
local pty = require "code-runner.terminal.pty"

local M = {}
M.BUF_NAME = buffer.BUF_NAME

-- Execution en seguimiento (dueño: `terminal/tracking.lua`): la terminal
-- consume el Engine y lanza por el puerto `process` (adapter PTY). El path
-- legacy (state/quickfix/buffer) sigue como compat cuando no hay tracking.
--
-- Execution actualmente en seguimiento (copia) o nil.
function M.get_execution()
  return tracking.get()
end

-- Descriptores del último on_exit (introspección/tests). Con tracking, los
-- autocmds salen de `tracking.dispatch()`; sin tracking, vía legacy.
function M.last_events()
  return tracking.events()
end

-- Re-export de la UI y de los helpers de buffer para conservar la API pública
-- y lo que usan los tests (terminal._open_window, _label_parts, ...).
M._open_window = ui._open_window
M._apply_term_bg = ui._apply_term_bg
M._maybe_autoclose = ui._maybe_autoclose
M._label_parts = ui._label_parts
M._apply_window_label = ui._apply_window_label
M._has_marker = buffer.has_marker
M._is_orphan_by_name = buffer.is_orphan_by_name

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

-- Espeja una cancelación del Engine en el estado legacy sin duplicar eventos:
-- si el tracking canceló (fuente Engine), el estado espeja en silencio y los
-- autocmds salen de `tracking.dispatch()`; si no había tracking, legacy emite.
local function mirror_cancel()
  local done = tracking.cancel()

  if done then
    require("code-runner.state").set("cancelled", {}, { emit = false })
    tracking.dispatch()
    return true
  end

  return false
end

-- Cierra la ventana que muestra `buf` y libera el buffer del plugin.
-- Si el job seguía corriendo, el cierre por el usuario se registra como
-- cancelado (la terminal se borra y con ella muere el job).
function M._close_current(buf)
  if require("code-runner.state").get().status == "running" then
    if not mirror_cancel() then
      require("code-runner.state").set "cancelled"
    end
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

-- Mensaje final "[Process exited N]" con color: el core lo muestra como
-- virtual text sin color (namespace "nvim.terminal.exitmsg"). Este hook lo
-- reemplaza solo en terminales del plugin: azul si exit 0, rojo si error.
local EXITMSG_NS = vim.api.nvim_create_namespace "code-runner.exitmsg"
local CORE_EXITMSG_NS = "nvim.terminal.exitmsg"

-- Pinta el mensaje final de `buf` según `code`. Expuesto para tests.
function M._apply_exitmsg(buf, code, pos)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local ok_core, core_ns = pcall(vim.api.nvim_create_namespace, CORE_EXITMSG_NS)
  if ok_core then
    pcall(vim.api.nvim_buf_clear_namespace, buf, core_ns, 0, -1)
  end
  pcall(vim.api.nvim_buf_clear_namespace, buf, EXITMSG_NS, 0, -1)

  if type(code) ~= "number" then
    code = -1
  end

  local hl = code == 0 and "CodeRunnerExitOk" or "CodeRunnerExitErr"
  local virt = { virt_text = { { ("[Process exited %d]"):format(code), hl } }, virt_text_pos = "overlay" }
  local ok = pcall(vim.api.nvim_buf_set_extmark, buf, EXITMSG_NS, pos, 0, virt)

  if not ok then
    pcall(vim.api.nvim_buf_set_extmark, buf, EXITMSG_NS, vim.api.nvim_buf_line_count(buf) - 1, 0, virt)
  end
end

-- Instala el hook una sola vez (augroup con clear): solo actúa en buffers
-- del plugin, el resto de terminales siguen con el mensaje del core.
function M._hook_exitmsg()
  local group = vim.api.nvim_create_augroup("CodeRunnerExitMsg", { clear = true })

  vim.api.nvim_create_autocmd("TermClose", {
    group = group,
    callback = function(ev)
      if not buffer.has_marker(ev.buf) then
        return
      end

      local data = ev.data or {}
      M._apply_exitmsg(ev.buf, vim.v.event.status, data.pos)
    end,
  })
end

-- Estado final visible en la ventana y mensaje claro de cómo cerrarla
-- (tanto para compilación como para ejecución o ambas).
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

  local parts = ui._label_parts(vim.b[buf].code_runner_label)

  if ok then
    parts[#parts + 1] = { " · ✓ terminó OK · q cierra", "CodeRunnerTermOk" }
  else
    parts[#parts + 1] = { (" · ✗ error %d · q cierra"):format(code), "CodeRunnerTermErr" }
  end

  ui._apply_window_label(buf, parts)
end

-- Estado al salir del proceso: quickfix + closure según la configuración.
-- Slice 4: el Engine es la única fuente de Result e identidad. Si el on_exit
-- corresponde al job trackeado (`exec_id`), el Engine finaliza, el estado
-- legacy ESPEJA en silencio y los autocmds salen de `tracking.dispatch()`:
-- una sola emisión por transición. Sin `exec_id` o con tracking ausente
-- (llamadas legacy/tests, chain `&&`), path legacy intacto (state emite).
-- `exec_id` obsoleto no toca nada (barrera del slice 1b).
function M._on_exit(buf, code, cwd, run_id, exec_id)
  local state = require "code-runner.state"
  local s = state.get()
  local done = tracking.finish(code, exec_id)

  if done then
    if s.status == "running" and (run_id or s.run_id) == s.run_id then
      state.set(done.status, { code = done.result.code, cwd = cwd }, { emit = false })
    end
    tracking.dispatch()
  elseif s.status == "running" and (run_id or s.run_id) == s.run_id then
    state.set(code == 0 and "success" or "failed", { code = code, cwd = cwd })
  end

  -- Limpia temporales del job (p.ej. el directorio de clases que `javac -d`
  -- crea para el smart run de Java) en cuanto termina, sea éxito o error.
  local paths = vim.api.nvim_buf_is_valid(buf) and vim.b[buf] and vim.b[buf].code_runner_cleanup or nil

  if paths then
    for _, p in ipairs(paths) do
      pcall(vim.fn.delete, p, "rf")
    end

    if vim.api.nvim_buf_is_valid(buf) and vim.b[buf] then
      vim.b[buf].code_runner_cleanup = nil
    end
  end

  local qf_count = require("code-runner.quickfix").handle(buf, code, cwd)

  local cfg = config.options.terminal

  if cfg.autoclose and code == 0 then
    if ui._maybe_autoclose(buf, code) then
      return
    end
  end

  M._exit_hint(buf, code, qf_count)
end

-- Abre (o reutiliza) una terminal con el comando ya envuelto para el shell.
-- cwd (opcional): directorio en el que arranca el job (raíz del proyecto).
-- label (opcional): acción elegida (Run/Build) para el título de la ventana.
-- cleanup (opcional): lista de rutas a borrar al terminar el job.
-- Devuelve el exec_id del tracking (o nil si el comando no se modeló como
-- Execution): el llamador lo usa para identidad sin leer estado global.
function M.open(cmd, direction, cwd, label, cleanup)
  direction = direction or config.options.terminal.direction

  -- Maven/Gradle Wrapper (proyecto): `mvn`→`mvnw`, `gradle`→`gradlew` si el
  -- wrapper existe en el cwd. No cambia nada si no hay wrapper.
  if config.options.wrappers.enabled then
    cmd = shell.use_wrappers(cmd, cwd)
  end

  local command = shell.wrap_command(cmd)

  -- Key resuelta del archivo del usuario ANTES de cambiar la ventana actual
  -- (después, la ventana activa pasa a ser la terminal y %:e ya no vale).
  local entry_key = require("code-runner.context")._resolve_key()

  local term_win = buffer.get_last_terminal_window()
  local state = require "code-runner.state"
  local buf

  if term_win then
    vim.api.nvim_set_current_win(term_win)
    -- Reaplica el fondo (ventanas creadas antes del fix no lo tienen).
    ui._apply_term_bg(term_win)
    local candidate = vim.api.nvim_win_get_buf(term_win)

    if state.get().status == "running" then
      -- El job del plugin sigue en marcha: cancelarlo y reabrir desde cero
      -- (evitar reutilizar un buffer jobado igual equivale a stop implícito).
      if not mirror_cancel() then
        state.set "cancelled"
      end
      pcall(vim.api.nvim_buf_delete, candidate, { force = true })
    else
      -- Job terminado: reusamos el buffer (termopen reinicia ahí el nuevo
      -- comando). Sin esto, crear otro buffer con el mismo nombre lanza E95.
      buf = candidate
    end
  else
    ui._open_window(direction)
  end

  if not buf then
    -- Purga buffers del plugin que quedaron huérfanos (sin ventana): su job
    -- ya no corre o es nuestro y hay que reabrir. Dejarlos provoca E95 al
    -- crear otro buffer con el mismo nombre.
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= vim.api.nvim_get_current_buf() and (buffer.has_marker(b) or buffer.is_orphan_by_name(b)) then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end

    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, M.BUF_NAME)
    vim.b[buf][buffer.PLUGIN_MARK] = true
    vim.api.nvim_win_set_buf(0, buf)
  end

  label = label or ""
  vim.b[buf].code_runner_label = label
  vim.b[buf].code_runner_cleanup = cleanup or nil
  ui._apply_window_label(buf, ui._label_parts(label))

  -- Slice 8 (autoridad): el Engine transiciona PRIMERO; state espeja en
  -- silencio y Start se publica DESPUÉS desde el tracking (una emisión).
  -- `run_id` sigue siendo generación de sesión visible legacy (NO es
  -- Execution.id: ver `terminal/tracking.lua`); convive en paralelo para los
  -- guards legacy. Sin tracking (no modelable), rama legacy explícita que
  -- emite como antes — compat identificada, no confundida con la gobernada.
  -- Tracking Engine (dueño: `terminal/tracking.lua`).
  local exec_id = tracking.start(cmd, entry_key, label or "")
  local rid

  if exec_id ~= nil then
    state.set("running", {
      action = label ~= "" and label or nil,
      cwd = cwd,
      filetype = entry_key,
      buf = buf,
    }, { emit = false })
    rid = state.get().run_id
    tracking.dispatch()
  else
    -- Estado central antes de lanzar: registra el job nuevo y su run_id. Los
    -- on_exit de jobs anteriores (run_id viejo) no podrán pisar este estado.
    state.set("running", {
      action = label ~= "" and label or nil,
      cwd = cwd,
      filetype = entry_key,
      buf = buf,
    })
    rid = state.get().run_id
  end

  -- termopen exige un buffer sin modificar: al reusar el buffer de la
  -- terminal, el job anterior dejó `modified` en al revisar.
  pcall(vim.api.nvim_buf_set_option, buf, "modified", false)

  -- Slice 5: el lanzamiento productivo sale por el puerto (adapter PTY).
  -- `terminal.open` decide QUÉ (comando, buffer, cwd, callbacks); el CÓMO
  -- vive en `pty.launch`. Sin camino paralelo de lifecycle.
  local _, serr = pty.launch(command, {
    cwd = (cwd ~= nil and cwd ~= "") and cwd or nil,
    buf = buf,
    on_exit = function(code)
      M._on_exit(buf, code, cwd, rid, exec_id)
    end,
  })

  if serr ~= nil then
    local launched = tracking.fail_launch(exec_id)

    if launched then
      state.set("failed", { code = -1 }, { emit = false })
      tracking.dispatch()
    else
      state.set("failed", { code = -1 })
    end

    M.notify("No se pudo lanzar el comando: " .. tostring(cmd), vim.log.levels.ERROR)
    return nil
  end

  vim.cmd "startinsert"
  return exec_id
end

return M
