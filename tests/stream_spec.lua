local stream = require "code-runner.stream"

T.section("stream: normalización de chunks a líneas")

T.it("feed agrupa chunks en líneas completas en orden", function()
  local c = stream.new()
  c:feed("stdout", "line1\nline2\n")
  c:feed("stdout", "line3\n")

  local lines = c:lines()
  T.eq(#lines, 3)
  T.eq(lines[1].line, "line1")
  T.eq(lines[2].line, "line2")
  T.eq(lines[3].line, "line3")
end)

T.it("una línea partida entre chunks no se parte en la salida", function()
  local c = stream.new()
  c:feed("stdout", "hel")
  c:feed("stdout", "lo wo")
  c:feed("stdout", "rld\n")

  local lines = c:lines()
  T.eq(#lines, 1, "una sola línea completa")
  T.eq(lines[1].line, "hello world")
end)

T.it("interleaving de stdout/stderr conserva el orden real", function()
  local c = stream.new()
  c:feed("stdout", "out1\n")
  c:feed("stderr", "err1\n")
  c:feed("stdout", "out2\n")

  local lines = c:lines()
  T.eq(#lines, 3)
  T.eq(lines[1].channel, "stdout")
  T.eq(lines[1].line, "out1")
  T.eq(lines[2].channel, "stderr")
  T.eq(lines[2].line, "err1")
  T.eq(lines[3].channel, "stdout")
  T.eq(lines[3].line, "out2")
end)

T.it("líneas sin \n final quedan pendientes de su propio canal", function()
  local c = stream.new()
  c:feed("stdout", "a\nb") -- stdout deja partial "b"
  c:feed("stderr", "x") -- stderr deja partial "x"
  c:feed("stdout", "\n") -- cierra la partial de stdout

  local lines = c:lines()
  T.eq(#lines, 2)
  T.eq(lines[1].line, "a")
  T.eq(lines[2].line, "b", "la partial de stdout se cierra con su propio \n")

  local out = c:output()
  T.eq(out.stdout, "a\nb")
  T.eq(out.stderr, "x", "la partial de stderr queda pendiente de su canal, intacta")
end)

T.it("feed rechaza canal inválido y chunk no-string", function()
  local c = stream.new()
  local ok1, err1 = c:feed("bogus", "x")
  T.falsy(ok1)
  T.truthy(err1)

  local ok2, err2 = c:feed("stdout", 42)
  T.falsy(ok2)
  T.truthy(err2)

  T.eq(c:line_count(), 0)
end)

T.section("stream: output listo para Result")

T.it("output produce stdout/stderr concatenados sin \n final", function()
  local c = stream.new()
  c:feed("stdout", "a\nb\n")
  c:feed("stderr", "e1\ne2\n")

  local out = c:output()
  T.eq(out.stdout, "a\nb")
  T.eq(out.stderr, "e1\ne2")
end)

T.it("output deja nil en canales sin datos (CONTRACTS §7)", function()
  local c = stream.new()
  c:feed("stdout", "only stdout\n")

  local out = c:output()
  T.eq(out.stdout, "only stdout")
  T.eq(out.stderr, nil)
end)

T.it("chunk vacío o porción sin \n se preserva correctamente", function()
  local c = stream.new()
  c:feed("stdout", "texto sin salto")
  local out1 = c:output()
  T.eq(out1.stdout, "texto sin salto")

  c:feed("stdout", "\n")
  local out2 = c:output()
  T.eq(out2.stdout, "texto sin salto")
end)

T.section("stream: callbacks on_line / on_stdout / on_stderr")

T.it("on_line recibe cada línea completa en orden", function()
  local seen = {}
  local c = stream.new({ on_line = function(l) seen[#seen + 1] = l end })
  c:feed("stdout", "he")
  c:feed("stdout", "llo\n")
  c:feed("stderr", "e\n")

  T.eq(#seen, 2)
  T.eq(seen[1].line, "hello")
  T.eq(seen[1].channel, "stdout")
  T.eq(seen[2].channel, "stderr")
end)

T.it("on_stdout/on_stderr reciben los chunks crudos por canal", function()
  local so, se = {}, {}
  local c = stream.new({
    on_stdout = function(x) so[#so + 1] = x end,
    on_stderr = function(x) se[#se + 1] = x end,
  })
  c:feed("stdout", "a\nb\n")
  c:feed("stderr", "x\n")

  T.eq(#so, 1)
  T.eq(so[1], "a\nb\n")
  T.eq(#se, 1)
  T.eq(se[1], "x\n")
end)

T.section("stream: stats y reset")

T.it("stats cuenta chunks y bytes por canal", function()
  local c = stream.new()
  c:feed("stdout", "abcd\nef")
  c:feed("stderr", "xyz\n")

  local s = c:stats()
  T.eq(s.chunks.stdout, 1)
  T.eq(s.bytes.stdout, 7)
  T.eq(s.chunks.stderr, 1)
  T.eq(s.bytes.stderr, 4)
end)

T.it("reset limpia líneas, pending y stats", function()
  local c = stream.new()
  c:feed("stdout", "a\nb")
  T.eq(c:line_count(), 1)

  c:reset()
  T.eq(c:line_count(), 0)
  T.eq(c:output().stdout, nil, "pending parcial también limpiado")
  local s = c:stats()
  T.eq(s.chunks.stdout, 0)
end)

T.section("stream: Core puro (EXEC-003)")

T.it("el módulo no depende de vim ni del adapter de procesos", function()
  local c = stream.new()
  c:feed("stdout", "go test\n")
  c:feed("stderr", "")

  local out = c:output()
  T.eq(out.stdout, "go test")
  local lines = c:lines()
  T.eq(lines[1].channel, "stdout")
end)

T.it("acceptance: salida de una build de ejemplo se normaliza sin perder orden", function()
  local c = stream.new()
  c:feed("stdout", "main.go:3:5: unknown type name 'x'\n")
  c:feed("stderr", "go: build failed\n")

  local out = c:output()
  T.eq(out.stdout, "main.go:3:5: unknown type name 'x'")
  T.eq(out.stderr, "go: build failed")

  -- alimenta un Result real (EXEC-006) sin UI
  local result = require "code-runner.result"
  local r = result.new { code = 2, stdout = out.stdout, stderr = out.stderr }
  T.truthy(result.failed(r), "Result clasificable desde el stream")
end)