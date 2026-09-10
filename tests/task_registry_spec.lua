local task_registry = require "code-runner.task_registry"
local task = require "code-runner.task"

local function spec(id, name)
  return {
    id = id,
    name = name,
    kind = "run",
    command = "go run .",
    filetypes = { "go" },
  }
end

local function go_run()
  return task.new(spec("go.run", "Run"))
end

T.section("task_registry: registro por ID estable")

T.it("register normaliza un TaskSpec y lo guarda por su id", function()
  task_registry.reset()

  local t = task_registry.register(spec("go.run", "Run"))
  T.truthy(t, "devuelve el Task")
  T.eq(t.id, "go.run")

  local got = task_registry.get("go.run")
  T.truthy(got, "recuperable por id")
  T.eq(got.id, "go.run")
end)

T.it("register acepta un Task ya construido (valida identity)", function()
  task_registry.reset()

  local built = go_run()
  local t = task_registry.register(built)
  T.truthy(t)
  T.eq(task_registry.get("go.run").command, built.command)
end)

T.it("get devuelve nil para un id no registrado", function()
  task_registry.reset()

  task_registry.register(spec("go.run", "Run"))
  T.eq(task_registry.get("no.such"), nil)
end)

T.it("list expone todos los registrados (sin exponer el interno)", function()
  task_registry.reset()

  task_registry.register(spec("go.run", "Run"))
  task_registry.register(spec("go.test", "Test"))
  task_registry.register(spec("go.build", "Build"))

  local l = task_registry.list()
  T.eq(task_registry.count(), 3)
  T.truthy(l["go.run"], "contiene go.run")
  T.truthy(l["go.test"], "contiene go.test")
  T.truthy(l["go.build"], "contiene go.build")
  T.eq(l["go.build"].id, "go.build", "preserva el Task")
end)

T.it("has y count reflejan el contenido", function()
  task_registry.reset()

  T.falsy(task_registry.has("go.run"))
  T.eq(task_registry.count(), 0)

  task_registry.register(spec("go.run", "Run"))
  T.truthy(task_registry.has("go.run"))
  T.eq(task_registry.count(), 1)
end)

T.section("task_registry: unregister y reemplazo")

T.it("registrar el mismo id reemplaza sin duplicar el orden", function()
  task_registry.reset()

  task_registry.register(spec("go.run", "Run"))
  task_registry.register(spec("go.test", "Test"))
  task_registry.register(spec("go.run", "Run v2"))

  T.eq(task_registry.count(), 2, "no duplica")
  T.eq(task_registry.get("go.run").name, "Run v2", "reemplaza el contenido")
  T.eq(task_registry.count(), 2)
end)

T.it("unregister elimina por id y devuelve true/false", function()
  task_registry.reset()

  task_registry.register(spec("go.run", "Run"))
  T.truthy(task_registry.unregister("go.run"), "existía")
  T.falsy(task_registry.unregister("go.run"), "ya no existe")
  T.eq(task_registry.get("go.run"), nil)
end)

T.it("reset vacía por completo", function()
  task_registry.reset()

  task_registry.register(spec("go.run", "Run"))
  task_registry.register(spec("python.run", "Python Run"))
  task_registry.reset()

  T.eq(task_registry.count(), 0)
  T.eq(task_registry.get("go.run"), nil)
end)

T.section("task_registry: validación")

T.it("register rechaza specs inválidos (sin id/name)", function()
  task_registry.reset()

  local t1 = task_registry.register { name = "Run", kind = "run", command = "x" }
  T.falsy(t1, "sin id")

  local t2 = task_registry.register { id = "go.run", kind = "run", command = "x" }
  T.falsy(t2, "sin name")
end)

T.it("register rechaza no-tabla", function()
  task_registry.reset()

  local t = task_registry.register("go run .")
  T.falsy(t)
end)

T.it("register_or_error lanza en inválido y devuelve en válido", function()
  task_registry.reset()

  local threw = false
  local ok1 = pcall(function()
    task_registry.register_or_error { name = "Run", kind = "run", command = "x" }
  end)
  threw = not ok1

  T.truthy(threw)

  local ok = pcall(function()
    task_registry.register_or_error(spec("go.run", "Run"))
  end)
  T.truthy(ok)
end)

T.section("task_registry: identidad independiente de presentación")

T.it("la identidad es id estable, no el label/name", function()
  task_registry.reset()

  task_registry.register(spec("go.run", "Run"))
  task_registry.register(spec("go.test", "Run Test"))

  T.truthy(task_registry.get("go.run"))
  T.truthy(task_registry.get("go.test"))
  T.falsy(task_registry.get("Run"), "el label no es clave")
end)

T.it("acceptance: un Task se registra y recupera por ID estable", function()
  task_registry.reset()

  local t = task_registry.register(spec("rust.build", "Build"))
  T.eq(t.id, "rust.build")

  local got = task_registry.get("rust.build")
  T.eq(got.id, "rust.build")
  T.eq(got.kind, "run")
  T.truthy(got.command)
end)

T.it("acceptance: el registro no toca el Runner Registry (independencia)", function()
  -- ARCH-006 debe separar conceptos sin romper el runner legacy. Acá
  -- verificamos que task_registry es un módulo Core que no depende de él.
  task_registry.reset()

  task_registry.register(spec("go.run", "Run"))
  T.eq(task_registry.get("go.run").id, "go.run")

  -- el Runner Registry (actions/registry) sigue intacto por su cuenta:
  local actions_registry = require "code-runner.actions.registry"
  T.falsy(actions_registry.get, "api diferente: sin get propio, es runner-only")
  T.truthy(actions_registry.list, "sigue exponiendo su API runner")
end)