local task = require "code-runner.task"
local actions = require "code-runner.actions"
local config = require "code-runner.config"

local ICONS = config.options.icons

T.section("task: kinds (CONTRACTS §3)")

T.it("KINDS cubre los kinds del contrato", function()
  for _, kind in ipairs { "run", "build", "test", "debug", "lint", "format", "misc" } do
    T.truthy(task.KINDS[kind], "kind " .. kind .. " soportado")
  end
end)

T.section("task: id (identity estable, ADR-002)")

T.it("go.Run -> go.run (canónico)", function()
  T.eq(task.id("go", "Run"), "go.run")
end)

T.it("python Test · TestFoo -> python.test-testfoo (slug determinístico)", function()
  T.eq(task.id("python", "Test · TestFoo"), "python.test-testfoo")
end)

T.it("runner y stem vacíos devuelven solo la parte no vacía", function()
  T.eq(task.id("", "anything"), "anything")
  T.eq(task.id("go", ""), "go")
  T.eq(task.id("", ""), "")
end)

T.it("es determinístico (misma entrada, mismo id)", function()
  local a = task.id("rust", "Build & Run")
  local b = task.id("rust", "Build & Run")
  T.eq(a, b)
end)

T.it("el id nunca conserva espacios ni mayúsculas", function()
  local id = task.id("Java", "Maven Auto-Run")
  T.falsy(id:find("%s"), "sin espacios")
  T.eq(id, id:lower(), "minúsculas")
end)

T.section("task: validate / new")

T.it("validate rechaza spec no-tabla", function()
  T.truthy(task.validate("nope"))
end)

T.it("validate rechaza sin id/name", function()
  T.truthy(task.validate { name = "x", kind = "run", command = "c" }, "sin id")
  T.truthy(task.validate { id = "x", kind = "run", command = "c" }, "sin name")
end)

T.it("validate rechaza kind inválido", function()
  T.truthy(task.validate { id = "x", name = "x", kind = "bogus", command = "c" })
end)

T.it("validate rechaza command que no es string ni función", function()
  T.truthy(task.validate { id = "x", name = "x", kind = "run", command = 42 })
end)

T.it("validate acepta spec mínimo válido", function()
  T.falsy(task.validate { id = "go.run", name = "Run", kind = "run", command = "go run %" })
end)

T.it("new normaliza defaults (filetypes vacío, enabled true)", function()
  local t = task.new { id = "go.run", name = "Run", kind = "run", command = "go run %" }
  T.truthy(t, "task creado")
  T.eq(t.filetypes[1], nil)
  T.eq(t.enabled, true)
  T.eq(t.condition, nil)
end)

T.it("new conserva los campos opcionales dados", function()
  local cond = function() return true end
  local t = task.new {
    id = "java.test",
    name = "Test",
    kind = "test",
    command = "mvn test",
    filetypes = { "java" },
    cwd = "src",
    condition = cond,
    enabled = false,
    description = "Corre los tests",
  }
  T.eq(t.filetypes[1], "java")
  T.eq(t.cwd, "src")
  T.eq(t.condition, cond)
  T.eq(t.enabled, false)
  T.eq(t.description, "Corre los tests")
end)

T.it("new falla (nil+error) con spec inválido", function()
  local t, err = task.new { id = "x", name = "x", kind = "nope", command = "c" }
  T.falsy(t, "sin task")
  T.truthy(err, "con error")
end)

T.it("new no comparte el spec original (independencia)", function()
  local spec = { id = "go.run", name = "Run", kind = "run", command = "go run", filetypes = { "go" } }
  local t = task.new(spec)
  spec.command = "changed"
  spec.filetypes[1] = "zzz"
  T.eq(t.command, "go run", "command copiado")
  T.eq(t.filetypes[1], "go", "filetypes copiado")
end)

T.it("new_or_error lanza en inválido y devuelve en válido", function()
  local ok = pcall(task.new_or_error, { id = "x", name = "x", kind = "run", command = {} })
  local t = task.new_or_error { id = "x", name = "x", kind = "run", command = "c" }
  T.falsy(ok, "lanza con command inválido")
  T.truthy(t, "devuelve task válido")
end)

T.section("task: from_catalog (proyección del catálogo legacy)")

T.it("label run -> kind run, name sin icono, filetypes {lang}", function()
  local t = task.from_catalog("go", ICONS.run .. " Run", 'go run "%"', ICONS)
  T.eq(t.id, "go.run")
  T.eq(t.name, "Run")
  T.eq(t.kind, "run")
  T.eq(t.filetypes[1], "go")
  T.eq(t.command, 'go run "%"')
end)

T.it("label build -> kind build", function()
  local t = task.from_catalog("rust", ICONS.build .. " Build", "cargo build", ICONS)
  T.eq(t.id, "rust.build")
  T.eq(t.kind, "build")
end)

T.it("label con 'Test' -> kind test", function()
  local t = task.from_catalog("go", ICONS.run .. " Test · TestAdd", "go test -run TestAdd", ICONS)
  T.eq(t.kind, "test")
  T.contains(t.id, "test", "id derivado del nombre de test")
end)

T.it("comando función se preserva sin ejecutar", function()
  local fn = function() return true end
  local t = task.from_catalog("cs", ICONS.build .. " Build", fn, ICONS)
  T.truthy(task.valid(t), "spec válido")
  T.eq(t.command, fn)
end)

T.it("es determinística", function()
  local a = task.from_catalog("py", ICONS.run .. " Run", "python %", ICONS)
  local b = task.from_catalog("py", ICONS.run .. " Run", "python %", ICONS)
  T.eq(a.id, b.id)
  T.eq(a.name, b.name)
  T.eq(a.kind, b.kind)
end)

T.it("require de task.new: las proyecciones del catálogo son TaskSpec válidos", function()
  local t = task.from_catalog("md", ICONS.run .. " Preview", function() end, ICONS)
  local parsed, err = task.new(t)
  T.truthy(parsed, "parseable: " .. tostring(err))
  T.eq(parsed.kind, "run")
  T.eq(parsed.description, nil)
end)

T.section("task: todo el catálogo actual es representable (acceptance criteria)")

T.it("cada (lang, label) del catálogo produce un Task válido con id único y sin iconos", function()
  local catalog = actions.get_actions()
  local seen = {}

  for lang, entry in pairs(catalog) do
    seen[lang] = seen[lang] or {}

    for label, command in pairs(entry) do
      if label ~= "__order" then
        local t = task.from_catalog(lang, label, command, ICONS)
        local parsed, err = task.new(t)

        T.truthy(parsed, lang .. " · " .. label .. ": " .. tostring(err))
        T.eq(parsed.id, t.id, lang .. " id estable")

        T.falsy(t.id:find(ICONS.run, 1, true) or t.id:find(ICONS.build, 1, true), "id sin iconos: " .. t.id)
        T.falsy(t.name:find(ICONS.run, 1, true) or t.name:find(ICONS.build, 1, true), "name sin iconos: " .. t.name)
        T.falsy(seen[lang][t.id], "id duplicado en " .. lang .. ": " .. t.id)
        seen[lang][t.id] = true
      end
    end
  end

  T.truthy(next(catalog), "catálogo no vacío")
end)

T.it("la identidad no depende de la presentación (otra config de iconos)", function()
  local a = task.from_catalog("go", ICONS.run .. " Run", "go run %", ICONS)
  local b = task.from_catalog("go", "➤  Run", "go run %", { run = "➤ ", build = "PF-", registered = "R-" })
  T.eq(a.id, b.id, "mismo id con iconos distintos")
  T.eq(a.name, b.name, "mismo name con iconos distintos")
  T.eq(a.kind, b.kind, "mismo kind con iconos distintos")
end)