local cr = require "code-runner"
local config = require "code-runner.config"

T.section("init: resolución de acciones (build_entry)")

local tmpdir = vim.fn.tempname() .. "/cr_init_test"
vim.fn.mkdir(tmpdir, "p")

local function fake_terminal()
  local notified = {}
  return {
    notified = notified,
    notify = function(_, msg, level)
      table.insert(notified, { msg = msg, level = level })
    end,
    open = function() end,
  }
end

-- Rompe la carrera con jobs de terminal de specs previos que comparten el
-- mismo proceso headless: borra a la fuerza los buffers del plugin que hayan
-- quedado conectados, para que terminal.open arranque desde cero.
local function kill_plugin_terminals()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[b] and vim.b[b].code_runner_term then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

T.it("resuelve por extensión (.lua)", function()
  local f = tmpdir .. "/script.lua"
  vim.fn.writefile({ "print(1)" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))

  local entry, key = cr._build_entry(require("code-runner.actions").get_actions(), fake_terminal())
  T.eq("lua", key)
  T.truthy(entry and entry.__order)
end)

T.it("resuelve por filetype cuando no hay extensión (Makefile)", function()
  local f = tmpdir .. "/Makefile"
  vim.fn.writefile({ "all:", "\techo hi" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  vim.bo.filetype = "make" -- en uso real lo detecta Neovim

  local entry, key = cr._build_entry(require("code-runner.actions").get_actions(), fake_terminal())
  T.eq("make", key)
  T.truthy(entry)
end)

T.it("notifica con extensión no soportada", function()
  local f = tmpdir .. "/raro.xyz123"
  vim.fn.writefile({ "x" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  vim.bo.filetype = ""

  local ft = fake_terminal()
  local entry, key = cr._build_entry(require("code-runner.actions").get_actions(), ft)

  T.falsy(entry)
  T.eq(nil, key)
  T.eq(1, #ft.notified, "debió notificar")
end)

T.it("la extensión tiene prioridad sobre el filetype", function()
  local f = tmpdir .. "/nota.lua"
  vim.fn.writefile({ "-- x" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  vim.bo.filetype = "make" -- filetype incorrecto a propósito

  local _, key = cr._build_entry(require("code-runner.actions").get_actions(), fake_terminal())
  T.eq("lua", key)
end)

T.section("init: API pública")

T.it("expone la API pública: build_run, run_last, run_history y state", function()
  T.truthy(type(cr.build_run) == "function")
  T.truthy(type(cr.run_last) == "function")
  T.truthy(type(cr.run_history) == "function")
  T.truthy(type(cr.state) == "function")
  T.truthy(cr.state().status, "retorna el estado central (copiado)")
end)

T.it("API pública completa: run, context, stop, restart, register_action", function()
  T.truthy(type(cr.run) == "function", "run")
  T.eq(cr.run, cr.build_run, "run es alias de build_run")
  T.truthy(type(cr.stop) == "function", "stop")
  T.truthy(type(cr.restart) == "function", "restart")
  T.truthy(type(cr.context) == "function", "context")
  T.truthy(type(cr.register_action) == "function", "register_action")
  T.truthy(type(cr.unregister_action) == "function", "unregister_action")
  T.truthy(type(cr.list_registered_actions) == "function", "list_registered_actions")
end)

T.it("context() detecta el contexto del key dado", function()
  local cctx = cr.context("lua")
  T.truthy(type(cctx) == "table", "context retorna tabla")
  T.eq("lua", cctx.key, "key inferido/resuelto")
end)

T.it("run_last sin ejecución previa notifica WARN", function()
  local terminal = require "code-runner.terminal"
  local original_notify = terminal.notify
  local notified = {}
  terminal.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  package.loaded["code-runner"] = nil
  local fresh = require "code-runner"
  fresh.run_last()

  terminal.notify = original_notify
  package.loaded["code-runner"] = nil

  T.eq(1, #notified, "una sola notificación")
  T.eq(vim.log.levels.WARN, notified[1].level)
end)

T.it("setup recarga la última ejecución persistida (sobrevive al reinicio)", function()
  -- usamos la etiqueta REAL de una acción de lua (con icono)
  local lua_entry = require("code-runner.actions").get_actions().lua
  local label = lua_entry.__order[#lua_entry.__order] -- la última de lua es "Run"

  -- persiste una 'última ejecución' como haría una sesión anterior
  local m = vim.fn.stdpath("data") .. "/code-runner"
  vim.fn.mkdir(m, "p")
  local file = m .. "/last.json"
  vim.fn.writefile({ vim.json.encode({ lang = "lua", choice = label }) }, file)

  -- simulamos reinicio: recargamos code-runner y llamamos setup (que debe
  -- poblar last_choice desde disco)
  require("code-runner.last")._data_file = file
  package.loaded["code-runner"] = nil
  local cr2 = require "code-runner"
  cr2.setup {}

  local terminal = require "code-runner.terminal"
  local original_notify = terminal.notify
  local calls = 0
  local msgs = {}
  terminal.notify = function(msg, level)
    calls = calls + 1
    msgs[#msgs + 1] = tostring(msg)
  end

  cr2.run_last()

  T.eq(0, calls, "run_last no avisa 'no hay ejecución': hay una cargada")

  terminal.notify = original_notify
  pcall(os.remove, file)
end)

T.section("init: stop()")

T.it("stop sin ejecución en marcha es un no-op (no rompe nada)", function()
  require("code-runner.state").set("idle")
  cr.stop()
  T.eq("idle", require("code-runner.state").get().status)
end)

T.it("stop cancela el job del plugin y libera su buffer", function()
  local terminal = require "code-runner.terminal"
  local state = require "code-runner.state"

  kill_plugin_terminals()
  state.set("idle")
  terminal.open("echo 'para detener'", "horizontal")

  T.eq("running", state.get().status)
  local buf = state.get().buf
  T.truthy(buf and vim.api.nvim_buf_is_valid(buf), "el estado guarda el buffer del job")

  cr.stop()

  T.eq("cancelled", state.get().status, "stop => cancelled")
  T.falsy(vim.api.nvim_buf_is_valid(buf), "el buffer del job fue liberado (el job murió con él)")
end)

T.it("stop no toca terminales externas (solo el buffer registrado)", function()
  local terminal = require "code-runner.terminal"
  local state = require "code-runner.state"
  local save_notify = terminal.notify
  terminal.notify = function() end

  -- terminal AJENA con su propio job vivo y de larga vida (multiplataforma)
  local foreign = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(foreign, "foreign_terminal")
  local foreign_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(foreign_win, foreign)
  local sleep_cmd = vim.fn.has "win32" == 1 and "ping -n 300 127.0.0.1" or "sleep 30"
  vim.fn.termopen(sleep_cmd, { on_exit = function() end })

  state.set("idle")
  terminal.open("echo 'del plugin'", "horizontal")

  cr.stop()

  T.truthy(vim.api.nvim_buf_is_valid(foreign), "la terminal ajena sigue viva")
  T.falsy(vim.b[foreign].code_runner_term, "la ajena no lleva el marcador del plugin")
  T.eq("terminal", vim.bo[foreign].buftype, "sigue siendo una terminal (su job intacto)")
  T.falsy(
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(foreign), ":t") == "code-runner",
    "su nombre es term://..., nunca code-runner"
  )

  -- limpieza: detener el job ajeno para no ensuciar los specs siguientes
  if vim.api.nvim_buf_is_valid(foreign) then
    pcall(vim.api.nvim_buf_delete, foreign, { force = true })
  end

  terminal.notify = save_notify
end)

T.section("init: restart()")

T.it("restart sin job en marcha y sin ejecución previa notifica WARN (de run_last)", function()
  local state = require "code-runner.state"
  state.set("idle")

  -- reinicia code-runner sin setup: last_choice queda nil (sin persistencia
  -- cargada en memoria), por lo que run_last avisa que no hay ejecución previa
  local last_m = require "code-runner.last"
  local saved_file = last_m._data_file
  last_m._data_file = os.tmpname()
  last_m.clear()

  package.loaded["code-runner"] = nil
  local cr_fresh = require "code-runner"

  local terminal = require "code-runner.terminal"
  local original_notify = terminal.notify
  local notified = {}
  terminal.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  cr_fresh.restart()

  T.truthy(#notified >= 1, "avisa que no hay ejecución previa")
  T.eq(vim.log.levels.WARN, notified[#notified].level)
  T.eq("idle", state.get().status, "no quedó en running")

  terminal.notify = original_notify
  last_m._data_file = saved_file
  package.loaded["code-runner"] = nil
  cr = require "code-runner"
end)

T.it("restart detiene el job en marcha de forma silenciosa", function()
  -- contrato principal de restart: el job en marcha se cancela ANTES de delegar
  -- en run_last (que es quien relanza). Se verifica la parte de stop silencioso
  -- aislada: _stop_silent cancela sin notificar.
  local terminal = require "code-runner.terminal"
  local state = require "code-runner.state"
  local original_notify = terminal.notify
  local notified = {}
  terminal.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  state.set("idle")
  kill_plugin_terminals()
  terminal.open("echo 'seed'", "horizontal")
  T.eq("running", state.get().status)
  local seed_buf = state.get().buf

  cr._stop_silent()

  T.eq("cancelled", state.get().status, "stop silencioso => cancelled")
  T.falsy(vim.api.nvim_buf_is_valid(seed_buf), "liberó el buffer del job")
  T.eq(0, #notified, "stop silencioso: ninguna notificación")

  terminal.notify = original_notify
end)

T.section("plugin: comandos de usuario")

T.it("registra :CodeRun, :CodeRunLast, :CodeRunHistory, :CodeRunStop y :CodeRunRestart", function()
  dofile(PLUG_ROOT .. "/plugin/code-runner.lua")
  local cmds = vim.api.nvim_get_commands {}
  T.truthy(cmds.CodeRun, ":CodeRun registrado")
  T.truthy(cmds.CodeRunLast, ":CodeRunLast registrado")
  T.truthy(cmds.CodeRunHistory, ":CodeRunHistory registrado")
  T.truthy(cmds.CodeRunStop, ":CodeRunStop registrado")
  T.truthy(cmds.CodeRunRestart, ":CodeRunRestart registrado")
end)

T.it("el guard evita doble registro", function()
  local before = vim.api.nvim_get_commands {}
  dofile(PLUG_ROOT .. "/plugin/code-runner.lua") -- segunda carga: early return
  local after = vim.api.nvim_get_commands {}
  T.eq(before.CodeRun.definition, after.CodeRun.definition)
end)

config.options = vim.deepcopy(config.defaults)
