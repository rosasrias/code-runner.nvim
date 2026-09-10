local process = require "code-runner.process"

local function mock_adapter()
  local calls = {}
  local h = { id = 42 }

  return {
    _calls = calls,
    _handle = h,
    spawn = function(opts)
      calls[#calls + 1] = { "spawn", opts }
      return h
    end,
    send = function(handle, data)
      calls[#calls + 1] = { "send", handle, data }
      return true
    end,
    terminate = function(handle)
      calls[#calls + 1] = { "terminate", handle }
      return true
    end,
  }
end

local function bad_adapter()
  return {
    spawn = function() return nil, "no" end,
    send = function() return false end,
    terminate = function() return false end,
  }
end

T.section("process: validate_adapter / set_adapter")

T.it("validate_adapter acepta un adapter válido (shape completo)", function()
  T.falsy(process.validate_adapter(mock_adapter()))
end)

T.it("validate_adapter rechaza no-tabla y campos faltantes", function()
  T.truthy(process.validate_adapter(nil))
  T.truthy(process.validate_adapter("nope"))
  T.truthy(process.validate_adapter({}))
  T.truthy(process.validate_adapter({ spawn = function() end }))
  T.truthy(process.validate_adapter({ spawn = function() end, send = function() end }))
end)

T.it("set_adapter inyecta y es verificable con valid()", function()
  process.set_adapter(nil)
  T.falsy(process.valid(), "sin adapter no es válido")

  local m = mock_adapter()
  local err = process.set_adapter(m)
  T.falsy(err, "no error")
  T.truthy(process.valid(), "adapter válido")
  T.eq(process.get_adapter(), m, "get devuelve el mismo adapter")
end)

T.it("set_adapter rechaza adapter inválido con error", function()
  local err = process.set_adapter({ spawn = "nope" })
  T.truthy(err)
end)

T.section("process: spawn")

T.it("spawn llama al adapter con opts válidas y devuelve handle", function()
  local m = mock_adapter()
  process.set_adapter(m)

  local handle, herr = process.spawn {
    cmd = { "go", "run", "." },
    cwd = "/tmp",
    on_stdout = function() end,
    on_stderr = function() end,
    on_exit = function() end,
  }

  T.truthy(handle, "handle: " .. tostring(herr))
  T.eq(handle.id, 42)
  T.eq(m._calls[1][1], "spawn")
  T.eq(m._calls[1][2].cmd[1], "go")
  T.eq(m._calls[1][2].cwd, "/tmp")
end)

T.it("spawn acepta opts mínimas (solo cmd)", function()
  local m = mock_adapter()
  process.set_adapter(m)

  local handle = process.spawn { cmd = { "ls" } }
  T.truthy(handle)
end)

T.it("spawn falla sin adapter", function()
  process.set_adapter(nil)
  local h, err = process.spawn { cmd = { "ls" } }
  T.falsy(h)
  T.truthy(err)
end)

T.it("spawn falla con opts inválidos", function()
  local m = mock_adapter()
  process.set_adapter(m)

  local h1, e1 = process.spawn("nope")
  T.falsy(h1)
  T.truthy(e1)

  local h2, e2 = process.spawn { cmd = {} }
  T.falsy(h2)
  T.truthy(e2)

  local h3, e3 = process.spawn { cmd = { 123 } }
  T.falsy(h3)
  T.truthy(e3)

  local h4, e4 = process.spawn { cmd = { "ls" }, cwd = 42 }
  T.falsy(h4)
  T.truthy(e4)

  local h5, e5 = process.spawn { cmd = { "ls" }, on_stdout = "nope" }
  T.falsy(h5)
  T.truthy(e5)
end)

T.it("spawn falla si el adapter falla", function()
  local m = bad_adapter()
  process.set_adapter(m)

  local h, err = process.spawn { cmd = { "ls" } }
  T.falsy(h)
  T.truthy(err, "adapter fallo propagado")
end)

T.section("process: send / terminate")

T.it("send delega al adapter con handle y data", function()
  local m = mock_adapter()
  process.set_adapter(m)

  local ok = process.send(m._handle, "input\n")
  T.truthy(ok)
  T.eq(m._calls[1][1], "send")
  T.eq(m._calls[1][3], "input\n")
end)

T.it("terminate delega al adapter con handle", function()
  local m = mock_adapter()
  process.set_adapter(m)

  local ok = process.terminate(m._handle)
  T.truthy(ok)
  T.eq(m._calls[1][1], "terminate")
end)

T.it("send/terminate fallan sin adapter", function()
  process.set_adapter(nil)

  local ok1, err1 = process.send({}, "x")
  T.falsy(ok1)
  T.truthy(err1)

  local ok2, err2 = process.terminate({})
  T.falsy(ok2)
  T.truthy(err2)
end)

T.it("send/terminate fallan con handle nil", function()
  local m = mock_adapter()
  process.set_adapter(m)

  local ok1 = process.send(nil, "x")
  T.falsy(ok1)

  local ok2 = process.terminate(nil)
  T.falsy(ok2)
end)

T.section("process: Core puro (BOUNDARIES §19)")

T.it("el módulo no depende de vim.fn.jobstart ni vim.system", function()
  local m = mock_adapter()
  process.set_adapter(m)

  local handle, _ = process.spawn { cmd = { "echo", "test" } }
  T.truthy(handle, "port funcional sin neovim")
  T.truthy(process.valid(), "adapter seteado")
end)