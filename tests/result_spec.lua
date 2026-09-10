local result = require "code-runner.result"

T.section("result: fields (CONTRACTS §7)")

T.it("FIELDS expone exit code, signal, stdout, stderr, duration", function()
  for _, f in ipairs { "code", "signal", "stdout", "stderr", "duration" } do
    T.truthy(vim.tbl_contains(result.FIELDS, f), "campo " .. f)
  end
end)

T.it("new conserva todos los campos de una finalización completa", function()
  local r = result.new { code = 0, signal = nil, stdout = "out", stderr = "err", duration = 1.25 }
  T.eq(r.code, 0)
  T.eq(r.stdout, "out")
  T.eq(r.stderr, "err")
  T.eq(r.duration, 1.25)
end)

T.it("new devuelve Result canónico con solo los campos dados", function()
  local r = result.new { code = 2 }
  T.eq(r.code, 2)
  T.eq(r.stdout, nil)
  T.eq(r.duration, nil)
end)

T.it("new ignora campos fuera del contrato (no los copia)", function()
  local r = result.new { code = 0, extra = "ignored" }
  T.eq(r.extra, nil)
end)

T.it("new no comparte el spec original (independencia)", function()
  local input = { code = 0, stdout = "a", duration = 3 }
  local r = result.new(input)
  input.code = 99
  input.stdout = "changed"
  input.duration = 999
  T.eq(r.code, 0, "code copiado")
  T.eq(r.stdout, "a", "stdout copiado")
  T.eq(r.duration, 3, "duration copiado")
end)

T.it("new devuelve error con spec inválido", function()
  local r, err = result.new { code = "cero" }
  T.falsy(r, "sin result")
  T.truthy(err, "con error")
end)

T.section("result: validate / valid")

T.it("validate rechaza no-tabla", function()
  T.truthy(result.validate("nope"))
end)

T.it("validate rechaza code/signal no-numéricos", function()
  T.truthy(result.validate({ code = "0" }), "code string")
  T.truthy(result.validate({ signal = "9" }), "signal string")
end)

T.it("validate rechaza stdout/stderr/duration de tipo incorrecto", function()
  T.truthy(result.validate({ stdout = 42 }), "stdout no-string")
  T.truthy(result.validate({ stderr = {} }), "stderr no-string")
  T.truthy(result.validate({ duration = "rapido" }), "duration no-number")
end)

T.it("validate acepta Result vacío y completo", function()
  T.falsy(result.validate({}), "result vacío es válido")
  T.falsy(result.validate({ code = 0, signal = nil, stdout = "a", stderr = "b", duration = 1 }))
end)

T.section("result: status (éxito / fallo / indeterminado)")

T.it("code 0 -> success", function()
  T.eq(result.status(result.new { code = 0 }), "success")
end)

T.it("code distinto de cero -> failed", function()
  T.eq(result.status(result.new { code = 2 }), "failed")
end)

T.it("signal presente -> failed aunque code falte", function()
  T.eq(result.status(result.new { signal = 9 }), "failed")
end)

T.it("sin code ni signal -> puede existir entre code y señal", function()
  T.eq(result.status(result.new {}), nil, "indeterminado devuelve nil")
end)

T.it("result inválido -> status nil", function()
  T.eq(result.status(result.new { code = "x" }), nil)
end)

T.section("result: helpers booleanos y describe")

T.it("success/failed/indeterminate reflejan el estado", function()
  T.truthy(result.success({ code = 0 }), "exit 0 es éxito")
  T.truthy(result.failed({ code = 1 }), "exit 1 es fallo")
  T.truthy(result.failed({ signal = 15 }), "signal es fallo")
  T.truthy(result.indeterminate({}), "sin datos es indeterminado")
  T.falsy(result.success({ code = 2 }))
  T.falsy(result.failed({ code = 0 }))
end)

T.it("from_exit construye un Result desde el exit code", function()
  local r = result.from_exit(0)
  T.eq(r.code, 0)
  T.eq(r.stdout, nil)
  T.truthy(result.success(r), "resultado generado por from_exit clasificable")
end)

T.it("describe produce texto determinístico por estado", function()
  T.eq(result.describe({ code = 0 }), "salida exitosa (code 0)")
  T.eq(result.describe({ code = 3 }), "fallo (code 3)")
  T.eq(result.describe({ signal = 9 }), "fallo (signal 9)")
  T.eq(result.describe({}), "indeterminado")
end)

T.section("result: independencia de la UI de terminal")

T.it("el modelo no conoce buffers, ventanas ni quickfix", function()
  local r = result.new { code = 1 }
  T.falsy(r.buf, "sin buffer")
  T.falsy(r.winid, "sin ventana")
  T.truthy(result.status(r), "pero sí clasificable")
end)

T.it("acceptance: un error real (exit != 0) se representa y describe sin UI", function()
  local build_failure = { code = 2, stdout = "main.c:3:5: error: unknown type name 'x'", duration = 0.4 }
  local r = result.new(build_failure)
  T.truthy(result.failed(r))
  T.eq(result.status(r), "failed")
  T.contains(r.stdout, "error:", "stdout preservada")
  T.eq(result.describe(r), "fallo (code 2)")
end)