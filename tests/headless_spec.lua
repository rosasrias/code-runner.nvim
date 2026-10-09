local process = require "code-runner.process"
local headless = require "code-runner.headless"
local shell = require "code-runner.shell"

T.section("headless: respeta el contrato del puerto (slice 6)")

T.it("pasa la validación del puerto (intercambiable a nivel contrato)", function()
  T.falsy(process.validate_adapter(headless), "misma forma que el puerto exige")
end)

T.it("spawn entrega el exit code real", function()
  local got = {}
  local handle, err = headless.spawn {
    cmd = shell.wrap_command("exit 5"),
    on_exit = function(code, signal)
      got.code = code
      got.signal = signal
    end,
  }

  T.truthy(handle, "spawn real: " .. tostring(err))

  vim.wait(10000, function()
    return got.code ~= nil
  end, 20)

  T.eq(5, got.code, "el código cruza el contrato")
  T.eq(nil, got.signal, "jobstart no entrega señal (documentado)")
end)

T.it("spawn rechaza opts inválidos sin efectos", function()
  T.falsy(headless.spawn(nil))
  T.falsy(headless.spawn { cmd = {} })
  T.falsy(headless.spawn { cmd = "no-tabla" })
end)

T.it("terminate detiene un job largo", function()
  local sleep_cmd = shell.IS_WIN and "Start-Sleep 30" or "sleep 30"
  local exited = {}
  local handle = headless.spawn {
    cmd = shell.wrap_command(sleep_cmd),
    on_exit = function(code)
      exited.code = code
    end,
  }
  T.truthy(handle)

  T.truthy(headless.terminate(handle))

  vim.wait(10000, function()
    return exited.code ~= nil
  end, 20)

  T.truthy(exited.code ~= nil, "el job detenido avisa su salida")
end)

T.it("send/terminate con handle inválido fallan", function()
  T.falsy(headless.send(nil, "x"))
  T.falsy(headless.terminate(nil))
  T.falsy(headless.terminate({}))
end)
