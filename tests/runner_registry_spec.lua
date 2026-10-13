local registry = require "code-runner.runner_registry"

local function fresh()
  registry.reset()
end

local function go_spec()
  return {
    id = "go",
    filetypes = { "go" },
    project = { markers = { "go.mod" } },
    tasks = {
      { id = "go.run", name = "Run", kind = "run", command = "go run ." },
    },
  }
end

T.section("runner_registry: registro por ID estable")

T.it("register normaliza y guarda por id", function()
  fresh()

  local spec, err = registry.register(go_spec())

  T.falsy(err)
  T.truthy(spec)
  T.eq("go", registry.get("go").id)
  T.eq(1, registry.count())
  T.truthy(registry.has("go"))
  T.falsy(registry.has("py"))
end)

T.it("register rechaza specs inválidos con motivo", function()
  fresh()

  local spec, err = registry.register { id = "Go" }

  T.falsy(spec)
  T.truthy(err)
  T.eq(0, registry.count(), "nada a medio registrar")
end)

T.it("re-registrar reemplaza sin duplicar posición", function()
  fresh()
  registry.register(go_spec())
  registry.register {
    id = "go",
    tasks = { { id = "go.test", name = "Test", kind = "test", command = "go test ./..." } },
  }

  T.eq(1, registry.count())
  T.eq("go.test", registry.get("go").tasks[1].id, "contenido reemplazado")
end)

T.it("unregister/list/reset", function()
  fresh()
  registry.register(go_spec())
  registry.register { id = "py" }

  T.truthy(registry.unregister("go"))
  T.falsy(registry.unregister("go"), "segunda vez false")
  T.eq(1, registry.count())

  local list = registry.list()
  T.truthy(list.py, "lista expone por id")
  T.eq(nil, list.go)

  registry.reset()
  T.eq(0, registry.count())
  T.eq(nil, registry.get("py"))
end)

T.it("register_or_error lanza en inválido", function()
  fresh()

  local ok = pcall(registry.register_or_error, { id = "" })
  T.falsy(ok)
  T.eq("go", registry.register_or_error(go_spec()).id)
  fresh()
end)

T.it("lo registrado no comparte referencias con el spec", function()
  fresh()
  local orig = go_spec()
  registry.register(orig)
  orig.tasks[1].command = "MUTADO"

  T.eq("go run .", registry.get("go").tasks[1].command)
  fresh()
end)
