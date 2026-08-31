local health = require "code-runner.health"

T.section("health: derivación de herramientas del catálogo")

T.it("tool_of toma el primer token de un comando", function()
  T.eq("mvn", health._tool_of('mvn -q clean package'))
  T.eq("go", health._tool_of('go build -o "$fileBase.exe"'))
  T.eq("cargo", health._tool_of "cargo run")
  T.eq("python", health._tool_of 'python "%"')
  T.eq("dotnet", health._tool_of "dotnet run")
end)

T.it("tool_of ignora variables y funciones", function()
  T.falsy(health._tool_of "$binRun", "variable no es herramienta")
  T.falsy(health._tool_of(nil))
  T.falsy(health._tool_of "" , "vacío no es herramienta")
  T.falsy(health._tool_of "./mvnw -q clean", "ruta con separador no es del PATH")
end)

T.it("tool_of limpia comillas del primer token", function()
  T.eq("go", health._tool_of('"go" test'))
end)

T.it("tools_for dedupa y solo mira comandos string", function()
  local tools = health._tools_for({
    [1] = "mvn -q clean package",
    [2] = "mvn spring-boot:run",
    [3] = function() end,
    [4] = "$binRun",
  })
  T.eq(1, #vim.tbl_keys(tools))
  T.truthy(tools.mvn)
end)

T.it("used_keys une el buffer actual y el historial", function()
  -- mocks: buffer sin key (headless) e historial con "go" y "rust"
  local history = require "code-runner.history"
  local orig_add, orig_clear = history.add, history.clear
  history.clear()
  history.add("go test", vim.fn.getcwd(), "go")
  history.add("cargo run", vim.fn.getcwd(), "rust")

  local keys = health._used_keys()
  T.truthy(keys.go, "del historial: go")
  T.truthy(keys.rust, "del historial: rust")

  history.clear()
  history.add = orig_add
  history.clear = orig_clear
end)
