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

T.section("plugin: comandos de usuario")

T.it("registra :CodeRun, :CodeRunLast y :CodeRunHistory", function()
  dofile(PLUG_ROOT .. "/plugin/code-runner.lua")
  local cmds = vim.api.nvim_get_commands {}
  T.truthy(cmds.CodeRun, ":CodeRun registrado")
  T.truthy(cmds.CodeRunLast, ":CodeRunLast registrado")
  T.truthy(cmds.CodeRunHistory, ":CodeRunHistory registrado")
end)

T.it("el guard evita doble registro", function()
  local before = vim.api.nvim_get_commands {}
  dofile(PLUG_ROOT .. "/plugin/code-runner.lua") -- segunda carga: early return
  local after = vim.api.nvim_get_commands {}
  T.eq(before.CodeRun.definition, after.CodeRun.definition)
end)

config.options = vim.deepcopy(config.defaults)
