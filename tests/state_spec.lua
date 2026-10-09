local state = require "code-runner.state"
local terminal = require "code-runner.terminal"

local function open_file(name, lines)
  local dir = vim.fn.tempname() .. "/cr_state_test"
  vim.fn.mkdir(dir, "p")
  local f = dir .. "/" .. name
  vim.fn.writefile(lines, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
end

T.section("state: máquina de estados")

T.it("la lista de estados incluye running, success, failed y cancelled", function()
  for _, s in ipairs { "idle", "running", "success", "failed", "cancelled" } do
    T.truthy(vim.tbl_contains(state.STATUSES, s), s)
  end
end)

T.it("arranca en idle con campos vacíos", function()
  state.set("idle") -- estado global compartido con otros specs
  local s = state.get()
  T.eq("idle", s.status)
  T.eq(nil, s.action)
  T.eq(nil, s.cwd)
  T.eq(nil, s.code)
end)

T.it("set running guarda acción/cwd/filetype, limpia code y marca el inicio", function()
  state.set("running", { action = "Run test · TestAdd", cwd = "/tmp/proj", filetype = "go" })
  local s = state.get()
  T.eq("running", s.status)
  T.eq("Run test · TestAdd", s.action)
  T.eq("/tmp/proj", s.cwd)
  T.eq("go", s.filetype)
  T.eq(nil, s.code)
  T.truthy(s.started_at)
end)

T.it("success guarda el código de salida y conserva la acción del job", function()
  state.set("success", { code = 0 })
  local s = state.get()
  T.eq("success", s.status)
  T.eq(0, s.code)
  T.eq("go", s.filetype, "conserva el filetype del job que terminó")
  T.truthy(s.ended_at)
end)

T.it("failed guarda un código distinto de cero", function()
  state.set("failed", { code = 2 })
  T.eq("failed", state.get().status)
  T.eq(2, state.get().code)
end)

T.it("cancelled deja de verse como running", function()
  state.set("idle")
  state.set("cancelled")
  T.eq("cancelled", state.get().status)
end)

T.it("un status inválido es un no-op", function()
  state.set("idle")
  local before = state.get()
  T.falsy(state.set("exploded"))
  T.eq("idle", state.get().status)
end)

T.it("set con emit=false espeja sin autocmds (EXEC-009 slice 4)", function()
  local events = require "code-runner.events"
  local orig_emit = events.emit
  local calls = {}
  events.emit = function(status, s)
    table.insert(calls, status)
  end

  state.set("running", { action = "Run" }, { emit = false })
  state.set("success", { code = 0 }, { emit = false })

  events.emit = orig_emit
  T.eq(0, #calls, "silencio total")
  T.eq("success", state.get().status, "el estado sí se espeja")
  T.eq(0, state.get().code)
  state.set("idle")
end)

T.it("get devuelve una copia: mutarla no ensucia el interno", function()
  state.set("running", { action = "Build" })
  local s = state.get()
  s.action = "Hacked"
  T.eq("Build", state.get().action)
end)

T.section("state: API pública")

T.it("require('code-runner').state() refleja el estado central", function()
  local init = require "code-runner"
  T.eq("function", type(init.state))
  local s = init.state()
  T.truthy(s.status)
  T.eq(s.status, state.get().status)
end)

T.section("state: wiring con la terminal")

T.it("open() marca running con el filetype del buffer actual", function()
  state.set("idle")
  open_file("app.go", { "package main", "" })

  terminal.open("echo 'state wiring'", "horizontal")

  T.eq("running", state.get().status)
  T.eq("go", state.get().filetype)

  local buf = vim.api.nvim_get_current_buf()
  terminal._close_current(buf)
  T.eq("cancelled", state.get().status, "cerrar con q mientras corre = cancelled")
end)

T.it("regresión E95: re-ejecutar con el job anterior en marcha no choca", function()
  state.set("idle")

  terminal.open("echo 'primera'", "horizontal")
  local first = state.get().run_id

  terminal.open("echo 'segunda'", "horizontal")

  T.eq("running", state.get().status, "sigue corriendo tras re-ejecutar")
  T.truthy(state.get().run_id > first, "run_id crece con cada ejecución")

  terminal._close_current(vim.api.nvim_get_current_buf())
  T.eq("cancelled", state.get().status)
end)

T.it("regresión E95: terminado el job, re-ejecutar reutiliza el mismo buffer", function()
  state.set("idle")

  terminal.open("echo 'a'", "horizontal")
  local buf1 = vim.api.nvim_get_current_buf()

  -- deja que el primer job muera de verdad (necesita volver al event loop);
  -- echo sale 0 -> _on_exit registra success
  vim.wait(3000, function()
    return state.get().status == "success"
  end, 10)
  T.eq("success", state.get().status, "el primer job terminó y lo registró _on_exit")

  terminal.open("echo 'b'", "horizontal")
  local buf2 = vim.api.nvim_get_current_buf()

  T.eq(buf1, buf2, "termopen reinicia en el buffer de terminal existente")
  T.eq("running", state.get().status)

  terminal._close_current(buf2)
end)

T.it("_on_exit registra success cuando el job era el actual (run_id igual)", function()
  state.set("running", { cwd = "/tmp" })
  local rid = state.get().run_id
  local quickfix = require "code-runner.quickfix"
  local orig = quickfix.handle
  quickfix.handle = function() return 0 end

  local buf = vim.fn.bufadd ""
  terminal._on_exit(buf, 0, "/tmp", rid)

  T.eq("success", state.get().status)
  T.eq(0, state.get().code)

  quickfix.handle = orig
end)

T.it("_on_exit ignora un job viejo (run_id distinto) y no pisa el running actual", function()
  state.set("running", { cwd = "/tmp/a" })
  local old_rid = state.get().run_id
  state.set("running", { cwd = "/tmp/b" }) -- nuevo job reemplaza al anterior
  T.truthy(state.get().run_id > old_rid)

  local quickfix = require "code-runner.quickfix"
  local orig = quickfix.handle
  quickfix.handle = function() return 0 end

  local buf = vim.fn.bufadd ""
  terminal._on_exit(buf, 1, "/tmp/a", old_rid)

  T.eq("running", state.get().status, "el on_exit obsoleto no cambia el estado")

  quickfix.handle = orig
end)

T.it("_on_exit no pisa un estado ya cancelado por el usuario", function()
  state.set("cancelled")
  local rid = state.get().run_id
  local quickfix = require "code-runner.quickfix"
  local orig = quickfix.handle
  quickfix.handle = function() return 0 end

  local buf = vim.fn.bufadd ""
  terminal._on_exit(buf, 1, "/tmp", rid)

  T.eq("cancelled", state.get().status, "cancelled gana la carrera")

  quickfix.handle = orig
end)