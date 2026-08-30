local cr = require "code-runner"
local history = require "code-runner.history"
local config = require "code-runner.config"

local tmpfile = os.tmpname()
history._data_file = tmpfile

local function fresh()
  pcall(os.remove, tmpfile)
  history.clear()
end

T.section("historial: registro y listado")

T.it("add registra una ejecución", function()
  fresh()
  config.options.history.enabled = true
  history.add("go test ./...", "C:/proj", "go")

  local items = history.list()
  T.eq(1, #items)
  T.eq("go test ./...", items[1].cmd)
  T.eq("C:/proj", items[1].cwd)
  T.eq("go", items[1].key)
  T.eq(1, items[1].count)
end)

T.it("repetir el mismo comando y cwd no duplica, suma count", function()
  fresh()
  history.add("go test ./...", "C:/proj", "go")
  history.add("go test ./...", "C:/proj", "go")
  history.add("go test ./...", "C:/proj", "go")

  local items = history.list()
  T.eq(1, #items, "una sola entrada")
  T.eq(3, items[1].count, "count acumulado")
end)

T.it("mismo comando con distinto cwd son entradas distintas", function()
  fresh()
  history.add("pytest", "C:/a", "py")
  history.add("pytest", "C:/b", "py")

  local items = history.list()
  T.eq(2, #items)
end)

T.it("el último ejecutado va primero", function()
  fresh()
  history.add("one", "C:/x", "go")
  history.add("two", "C:/x", "go")

  local items = history.list()
  T.eq("two", items[1].cmd)
  T.eq("one", items[2].cmd)
end)

T.it("max limita el tamaño guardando los más recientes", function()
  fresh()
  config.options.history.max = 2
  history.add("b1", "C:/p", "x")
  history.add("b2", "C:/p", "x")
  history.add("b3", "C:/p", "x")

  local items = history.list()
  T.eq(2, #items)
  T.eq("b3", items[1].cmd)
  T.eq("b2", items[2].cmd)

  config.options.history.max = config.defaults.history.max
end)

T.it("enabled=false no registra", function()
  fresh()
  config.options.history.enabled = false
  history.add("nope", "C:/x", "x")

  local found = false

  for _, it in ipairs(history.list()) do
    if it.cmd == "nope" then
      found = true
    end
  end

  T.falsy(found, "no debe estar en el historial")

  config.options.history.enabled = config.defaults.history.enabled
end)

T.it("clear vacía el historial", function()
  fresh()
  history.add("x", "C:/x", "x")
  history.clear()

  T.eq(0, #history.list())
end)

T.section("historial: persistencia")

T.it("cada archivo guarda su estado (se lee desde disco)", function()
  fresh()
  history.add("mvn test", "C:/m", "java")

  history._data_file = tmpfile .. "2"
  T.eq(0, #history.list(), "el archivo nuevo empieza vacío")

  history._data_file = tmpfile
  T.eq("mvn test", history.list()[1].cmd, "el original conserva sus datos")

  pcall(os.remove, tmpfile .. "2")
end)

T.it("un archivo corrupto devuelve historial vacío sin error", function()
  local f = io.open(tmpfile, "w")
  f:write "{ no es json"
  f:close()

  T.eq(0, #history.list())
end)

T.section("init: integración del historial")

T.it("build_run registra el comando sustituido", function()
  fresh()
  local dir = vim.fn.tempname() .. "/cr_hist"
  vim.fn.mkdir(dir, "p")
  local f = dir .. "/script.lua"
  vim.fn.writefile({ "print(1)" }, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))

  local picker = require "code-runner.picker"
  local terminal = require "code-runner.terminal"
  local orig_select, orig_open, orig_notify = picker.select, terminal.open, terminal.notify
  local opened = {}
  picker.select = function(_, _, cb)
    for _, label in ipairs(require("code-runner.actions").get_actions().lua.__order) do
      if label:find(config.options.icons.run, 1, true) and label:find("Run") then
        cb(label)
        return
      end
    end
  end
  terminal.open = function(cmd, _, cwd)
    table.insert(opened, { cmd = cmd, cwd = cwd })
  end
  terminal.notify = function() end

  cr.build_run()

  picker.select, terminal.open, terminal.notify = orig_select, orig_open, orig_notify
  config.options = vim.deepcopy(config.defaults)

  T.eq(1, #opened, "se ejecutó una acción")
  T.eq(1, #history.list(), "una entrada guardada")
  T.eq(opened[1].cmd, history.list()[1].cmd, "guarda el comando con variables sustituidas")
end)

T.it("run_history re-ejecuta la entrada elegida", function()
  fresh()
  history.add("pytest -q", "C:/p", "py")

  local picker = require "code-runner.picker"
  local terminal = require "code-runner.terminal"
  local orig_select, orig_open, orig_notify = picker.select, terminal.open, terminal.notify
  local shown, opened = nil, {}
  picker.select = function(items, _, cb)
    shown = items
    cb(items[1])
  end
  terminal.open = function(cmd, _, cwd)
    table.insert(opened, { cmd = cmd, cwd = cwd })
  end
  terminal.notify = function() end

  cr.run_history()

  picker.select, terminal.open, terminal.notify = orig_select, orig_open, orig_notify
  config.options = vim.deepcopy(config.defaults)

  T.eq(1, #shown)
  T.eq(1, #opened, "re-ejecutó")
  T.eq("pytest -q", opened[1].cmd)
  T.eq("C:/p", opened[1].cwd)
end)

T.it("run_history con historial vacío notifica WARN", function()
  fresh()

  local terminal = require "code-runner.terminal"
  local orig_notify = terminal.notify
  local notified = {}
  terminal.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  cr.run_history()

  terminal.notify = orig_notify

  T.eq(1, #notified)
  T.eq(vim.log.levels.WARN, notified[1].level)
end)

config.options = vim.deepcopy(config.defaults)