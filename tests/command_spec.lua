local command = require "code-runner.command"

T.section("command: parse (shorthand -> CommandSpec)")

T.it("go run $file -> executable go + args (CONTRACTS §8)", function()
  local spec = command.parse("go run $file")
  T.eq(spec.executable, "go")
  T.eq(#spec.args, 2)
  T.eq(spec.args[1], "run")
  T.eq(spec.args[2], "$file")
end)

T.it("go test $file -> executable go + args [test, $file]", function()
  local spec = command.parse("go test $file")
  T.eq(spec.executable, "go")
  T.eq(spec.args[1], "test")
end)

T.it("quotes agrupan un token con espacios (ruta $file)", function()
  local spec = command.parse('gcc "%" -o "$fileBase"')
  T.eq(spec.executable, "gcc")
  T.eq(spec.args[1], "%")
  T.eq(spec.args[2], "-o")
  T.eq(spec.args[3], "$fileBase")
end)

T.it("comillas no se conservan en el token", function()
  local spec = command.parse('mvn -q clean "-Dvalue=hello world"')
  T.eq(spec.args[3], "-Dvalue=hello world")
end)

T.it("vars de contexto se preservan como tokens (CONTRACTS §9)", function()
  local spec = command.parse('go test "-run=$testName" $dir $project')
  T.eq(spec.args[1], "test")
  T.eq(spec.args[2], "-run=$testName")
  T.eq(spec.args[3], "$dir")
  T.eq(spec.args[4], "$project")
end)

T.it("cadena vacía -> error", function()
  local spec, err = command.parse("")
  T.falsy(spec)
  T.truthy(err)
end)

T.it("no-string -> error", function()
  local spec, err = command.parse(42)
  T.falsy(spec)
  T.truthy(err)
end)

T.section("command: split_chain (multi-comando &&)")

T.it("separa sentencias por &&", function()
  local parts = command.split_chain("gcc % -o x && ./x")
  T.eq(#parts, 2)
  T.eq(parts[1], "gcc % -o x")
  T.eq(parts[2], "./x")
end)

T.it("&& dentro de comillas no separa", function()
  local parts = command.split_chain('echo "a && b"')
  T.eq(#parts, 1)
  T.eq(parts[1], 'echo "a && b"')
end)

T.it("parse rechaza una cadena multi-comando", function()
  local spec, err = command.parse("fpc % && ./x")
  T.falsy(spec)
  T.truthy(err)
end)

T.it("split_chain + parse representan cada sentencia", function()
  local parts = command.split_chain('tsc "%" && node "$fileBase.js"')
  local orden = {}

  for _, part in ipairs(parts) do
    local spec = command.parse(part)
    orden[#orden + 1] = spec.executable .. ":" .. spec.args[1]
  end

  T.eq(orden[1], "tsc:%")
  T.eq(orden[2], "node:$fileBase.js")
end)

T.section("command: build (round-trip)")

T.it("build reconstruye la cadena de un spec simple", function()
  T.eq(command.build({ executable = "go", args = { "run", "$file" } }), "go run $file")
end)

T.it("build comilla solo tokens con espacios", function()
  T.eq(command.build({ executable = "go", args = { "run", "file with spaces.bin" } }), 'go run "file with spaces.bin"')
end)

T.it("build sin args no deja espacio final", function()
  T.eq(command.build({ executable = "ls" }), "ls")
end)

T.it("round-trip: parse -> build -> parse conserva tokens", function()
  local original = 'gcc "%" -o "$fileBase.exe" -lm'
  local spec = command.parse(original)
  local rebuilt = command.build(spec)
  local spec2 = command.parse(rebuilt)

  T.eq(spec2.executable, spec.executable)
  T.eq(spec2.args[1], spec.args[1])
  T.eq(spec2.args[2], spec.args[2])
  T.eq(spec2.args[3], spec.args[3])
  T.eq(spec2.args[4], spec.args[4])
end)

T.it("round-trip con espacios dentro de comillas", function()
  local original = 'kotlinc "%" -include-runtime -d "$fileBase.jar"'
  local spec = command.parse(original)
  local spec2 = command.parse(command.build(spec))

  T.eq(spec2.executable, spec.executable)
  T.eq(table.concat(spec2.args, "|"), table.concat(spec.args, "|"))
end)

T.section("command: validate / valid / normalize")

T.it("validate rechaza no-tabla", function()
  T.truthy(command.validate("nope"))
end)

T.it("validate rechaza sin executable", function()
  T.truthy(command.validate({ args = { "x" } }))
end)

T.it("validate rechaza args no-tabla", function()
  T.truthy(command.validate({ executable = "x", args = "file" }))
end)

T.it("validate rechaza args con no-strings", function()
  T.truthy(command.validate({ executable = "x", args = { 1 } }))
end)

T.it("validate rechaza cwd y env de tipo incorrecto", function()
  T.truthy(command.validate({ executable = "x", cwd = 42 }), "cwd no-string")
  T.truthy(command.validate({ executable = "x", env = "FOO=1" }), "env no-tabla")
end)

T.it("validate acepta spec mínimo y completo", function()
  T.falsy(command.validate({ executable = "x" }))
  T.falsy(command.validate({ executable = "x", args = { "a" }, cwd = "p", env = { FOO = "1" } }))
end)

T.it("normalize desde string devuelve CommandSpec canónico", function()
  local spec = command.normalize("go run $file")
  T.eq(spec.executable, "go")
  T.eq(spec.args[1], "run")
  T.eq(spec.cwd, nil)
  T.eq(spec.env, nil)
end)

T.it("normalize no comparte el spec/string original (independencia)", function()
  local input = { executable = "go", args = { "run", "a" }, env = { X = "1" } }
  local spec = command.normalize(input)

  input.args[1] = "CHANGED"
  input.env.X = "CHANGED"
  input.executable = "CHANGED"

  T.eq(spec.executable, "go", "executable copiado")
  T.eq(spec.args[1], "run", "args copiado")
  T.eq(spec.env.X, "1", "env copiado")
end)

T.it("normalize rechaza entrada inválida (multi-comando / tipo raro)", function()
  local a, ae = command.normalize("a && b")
  local b, be = command.normalize(42)
  T.falsy(a)
  T.truthy(ae)
  T.falsy(b)
  T.truthy(be)
end)

T.section("command: acceptance — todo el catálogo es representable")

T.it("cada comando string del catálogo se normaliza (o chain por &&)", function()
  local actions = require "code-runner.actions"
  local catalog = actions.get_actions()
  local count = 0

  for lang, entry in pairs(catalog) do
    for label, cmd in pairs(entry) do
      if label ~= "__order" and type(cmd) == "string" then
        count = count + 1
        local parts = command.split_chain(cmd)

        for _, part in ipairs(parts) do
          local spec, err = command.normalize(part)
          T.truthy(spec, lang .. " · " .. label .. ": " .. tostring(err))
        end
      end
    end
  end

  T.truthy(count > 0, "varios comandos string en el catálogo: " .. count)
end)