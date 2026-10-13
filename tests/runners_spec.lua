local runners = require "code-runner.runners"
local registry = require "code-runner.runner_registry"

local function fresh()
  registry.reset()
end

local function real_inputs()
  local actions = require "code-runner.actions"
  local project = require "code-runner.project"
  local config = require "code-runner.config"
  return actions.get_actions(), {
    markers_for = function(key)
      return project.markers_for(key)
    end,
    icons = config.options.icons,
  }
end

T.section("runners: seed built-in sin tocar selección (RUN-002)")

T.it("rechaza catalog inválido", function()
  fresh()

  local summary, err = runners.seed(nil, {})

  T.falsy(summary)
  T.truthy(err)
  T.eq(0, registry.count())
end)

T.it("catalog vacío registra cero sin error", function()
  fresh()

  local summary, err = runners.seed({}, {})

  T.falsy(err)
  T.eq(0, #summary.registered)
  T.eq(0, registry.count())
end)

T.it("seed real puebla el registro con declaraciones", function()
  fresh()
  local catalog, opts = real_inputs()

  local summary, err = runners.seed(catalog, opts)

  T.falsy(err)
  T.truthy(#summary.registered > 10, "cobertura real: " .. #summary.registered)
  T.truthy(registry.has("go"), "go registrado")
  T.truthy(#registry.get("go").tasks > 0, "con tareas")

  local ordered = true
  for i = 2, #summary.registered do
    if summary.registered[i - 1] > summary.registered[i] then
      ordered = false
    end
  end
  T.truthy(ordered, "orden determinista por id")
  fresh()
end)

T.it("alias R omitido con motivo, sin duplicar", function()
  fresh()
  local catalog, opts = real_inputs()

  local summary = runners.seed(catalog, opts)

  T.truthy(summary.skipped_entries.R, "R reportado")
  T.truthy(summary.skipped_entries.R:find("alias", 1, true))
  T.falsy(registry.has("R"), "no duplica la declaración de r")
  fresh()
end)

T.it("acciones-función contabilizadas, no silenciadas", function()
  fresh()
  local catalog, opts = real_inputs()

  local summary = runners.seed(catalog, opts)

  T.truthy(summary.skipped_actions > 0, "omitidas: " .. summary.skipped_actions)
  fresh()
end)

T.it("seed idempotente: dos pasadas, un registro", function()
  fresh()
  local catalog, opts = real_inputs()

  runners.seed(catalog, opts)
  local n = registry.count()
  local summary = runners.seed(catalog, opts)

  T.eq(n, registry.count(), "sin duplicados")
  T.eq(n, #summary.registered)
  fresh()
end)

T.it("el catálogo legacy sigue mandando la selección (separación)", function()
  fresh()
  local catalog, opts = real_inputs()

  local before = table.concat(catalog.go.__order, "\n")
  runners.seed(catalog, opts)

  local actions = require("code-runner.actions").get_actions()
  T.eq(before, table.concat(actions.go.__order, "\n"), "labels de presentación intactos")
  T.truthy(registry.has("go"), "registro nuevo poblado en paralelo")

  local reg_ids = {}
  for _, t in ipairs(registry.get("go").tasks) do
    reg_ids[#reg_ids + 1] = t.id
  end
  T.truthy(#reg_ids > 0, "tasks con identidad estable al lado, no encima")
  fresh()
end)

T.section("runners/go: paridad con el catálogo (migración vertical, sin retirar)")

T.it("la declaración es un RunnerSpec válido", function()
  local runner = require "code-runner.runner"
  local decl = require("code-runner.runners.go").spec
  local spec, err = runner.new(decl)
  T.falsy(err)
  T.truthy(spec)
  T.eq("go", spec.id)
  T.eq(2, #spec.tasks)
end)

T.it("los ids coinciden con los derivados hoy de los labels", function()
  local task = require "code-runner.task"
  local config = require "code-runner.config"
  local decl = require("code-runner.runners.go").spec
  local icons = config.options.icons

  T.eq(task.id("go", icons.run .. " Run"), decl.tasks[1].id)
  T.eq(task.id("go", icons.build .. " Build"), decl.tasks[2].id)
  config.options = vim.deepcopy(config.defaults)
end)

T.it("paridad: lo declarado sustituye idéntico a lo legacy", function()
  local shell = require "code-runner.shell"
  local catalog = require("code-runner.actions").get_actions()
  local decl = require("code-runner.runners.go").spec
  local icons = require("code-runner.config").options.icons

  local vars = { ["$file"] = "/proj/main.go", ["$fileBase"] = "/proj/main" }
  local legacy_by_id = {}
  for _, label in ipairs(catalog.go.__order) do
    local cmd = catalog.go[label]
    if type(cmd) == "string" then
      legacy_by_id[require("code-runner.task").id("go", label)] =
        shell.substitute(cmd, vars, "go")
    end
  end

  for _, t in ipairs(decl.tasks) do
    T.truthy(legacy_by_id[t.id] ~= nil, "toda task declarada existe en legacy: " .. t.id)
    T.eq(legacy_by_id[t.id], shell.substitute(t.command, vars, "go"),
      "sustitución idéntica para " .. t.id)
  end
end)

T.it("paridad: resuelve con la misma identidad por el resolver", function()
  local runner = require "code-runner.runner"
  local resolve = require "code-runner.resolve"
  local decl = require("code-runner.runners.go").spec

  local spec = runner.new_or_error(decl)
  local res, err = resolve.resolve({
    runners = { spec },
    context = { filetype = "go", extension = "go", project = { marker = "go.mod" } },
  })

  T.falsy(err)
  T.eq(1, #res.candidates)
  T.eq("go", res.candidates[1].runner_id)
  T.eq(3, res.candidates[1].score)

  local ids = {}
  for _, t in ipairs(res.candidates[1].tasks) do
    ids[t.id] = true
  end
  T.truthy(ids["go.run"] and ids["go.build"])
end)

