local process = require "code-runner.process"
local pty = require "code-runner.terminal.pty"
local shell = require "code-runner.shell"

local function scratch_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "modified", false)
  return buf
end

T.section("pty: instalación en el puerto (slice 5)")

T.it("install deja el puerto válido", function()
  process.set_adapter(nil)
  T.falsy(process.valid())

  local err = pty.install()

  T.falsy(err)
  T.truthy(process.valid(), "PTY como adapter por defecto")
end)

T.it("launch respeta un adapter inyectado (mock)", function()
  local seen = {}
  process.set_adapter {
    spawn = function(opts)
      seen.cmd = opts.cmd
      return { fake = true }, nil
    end,
    send = function()
      return true
    end,
    terminate = function()
      return true
    end,
  }

  local handle, err = pty.launch({ "echo", "x" }, { buf = 1, on_exit = function() end })

  T.falsy(err)
  T.truthy(handle.fake, "el mock decide el mecanismo")
  T.eq({ "echo", "x" }, seen.cmd)

  pty.install()
end)

T.it("launch instala el PTY si el puerto está vacío", function()
  process.set_adapter(nil)

  local handle, err = pty.launch({ "echo", "x" }, { buf = -999 })

  T.falsy(handle, "buf inválido: sin efectos")
  T.truthy(err)
  T.truthy(process.valid(), "pero el PTY quedó instalado")
end)

T.section("pty: spawn real con PTY (no solo invocación)")

T.it("traduce el exit code del proceso", function()
  pty.install()

  local got = {}
  local handle, err = process.spawn {
    cmd = shell.wrap_command("exit 42"),
    buf = scratch_buf(),
    on_exit = function(code, signal)
      got.code = code
      got.signal = signal
    end,
  }

  T.truthy(handle, "spawn real: " .. tostring(err))

  vim.wait(10000, function()
    return got.code ~= nil
  end, 20)

  T.eq(42, got.code, "el código cruza el puerto")
  T.eq(nil, got.signal, "termopen no entrega señal (documentado)")
end)

T.it("buf inválido no spawnea (nil + error, sin efectos)", function()
  pty.install()

  local handle, err = process.spawn { cmd = { "echo", "x" }, buf = -999 }

  T.falsy(handle)
  T.truthy(err)
end)

T.it("terminate detiene un job largo y llega su on_exit", function()
  pty.install()

  local sleep_cmd = shell.IS_WIN and "Start-Sleep 30" or "sleep 30"
  local exited = {}
  local handle = process.spawn {
    cmd = shell.wrap_command(sleep_cmd),
    buf = scratch_buf(),
    on_exit = function(code)
      exited.code = code
    end,
  }
  T.truthy(handle)

  local ok = process.terminate(handle)
  T.truthy(ok, "terminate aceptado")

  vim.wait(10000, function()
    return exited.code ~= nil
  end, 20)

  T.truthy(exited.code ~= nil, "el job detenido avisa su salida")
end)

T.it("send negocia stdin (false con handle inválido)", function()
  pty.install()

  local ok, err = process.send(nil, "x")
  T.falsy(ok)
  T.truthy(err)

  local sleep_cmd = shell.IS_WIN and "Start-Sleep 30" or "sleep 30"
  local handle = process.spawn { cmd = shell.wrap_command(sleep_cmd), buf = scratch_buf() }
  T.truthy(handle)

  local sent = process.send(handle, "hola\n")
  T.eq("boolean", type(sent), "contrato booleano best-effort")

  process.terminate(handle)
end)

T.it("dos jobs no cruzan sus callbacks", function()
  pty.install()

  local sleep_cmd = shell.IS_WIN and "Start-Sleep 30" or "sleep 30"
  local a_fired, b_code = false, nil

  local ha = process.spawn {
    cmd = shell.wrap_command(sleep_cmd),
    buf = scratch_buf(),
    on_exit = function()
      a_fired = true
    end,
  }
  local hb = process.spawn {
    cmd = shell.wrap_command("exit 7"),
    buf = scratch_buf(),
    on_exit = function(code)
      b_code = code
    end,
  }
  T.truthy(ha and hb)

  process.terminate(ha)

  vim.wait(10000, function()
    return a_fired and b_code ~= nil
  end, 20)

  T.truthy(a_fired, "A avisó lo suyo")
  T.eq(7, b_code, "B conserva su propio código")
end)
