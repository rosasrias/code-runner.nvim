local resolve_mod = require "code-runner.task_resolve"
local task = require "code-runner.task"
local config = require "code-runner.config"

T.section("task_resolve: catálogo por identidad estable")

T.it("resuelve un label vigente a su plantilla actual", function()
  local entry = require("code-runner.actions").get_actions().go
  local label = entry.__order[1]
  local id = task.id("go", label)

  local def, err = resolve_mod.resolve(id, { lang = "go" })

  T.falsy(err)
  T.truthy(def)
  T.eq(id, def.task_id, "identidad estable")
  T.eq(entry[label], def.template, "plantilla vigente")
  T.eq("go", def.key)
  -- NOTA switch: por registry el label es el `name` estable (sin iconos de
  -- presentación), no el label legacy. El picker no cambia (usa __order).
end)

T.it("tras cambiar la plantilla, resuelve la nueva (no la guardada)", function()
  local registry = require "code-runner.actions.registry"
  registry.reset()
  require("code-runner").register_action {
    id = "op_evolve",
    filetypes = { "lua" },
    kind = "run",
    command = "mytool --opt A",
  }

  local entry = require("code-runner.actions").get_actions().lua
  local label
  for _, l in ipairs(entry.__order) do
    if l:find("op_evolve", 1, true) then
      label = l
    end
  end
  local id = task.id("lua", label)

  require("code-runner").register_action {
    id = "op_evolve",
    filetypes = { "lua" },
    kind = "run",
    command = "mytool --opt B",
  }

  local def = resolve_mod.resolve(id, { lang = "lua" })
  T.truthy(def and def.template:find("--opt B", 1, true), "plantilla vigente")
  registry.reset()
end)

T.it("task desconocida: motivo explícito, sin error duro", function()
  local def, reason = resolve_mod.resolve("go.noexiste", { lang = "go" })

  T.eq(nil, def)
  T.eq("task-desconocida", reason)
end)

T.it("key sin catálogo: motivo explícito", function()
  local def, reason = resolve_mod.resolve("zz.nope", { lang = "zz_nope" })

  T.eq(nil, def)
  T.eq("no-catalog-entry", reason)
end)

T.it("id vacío: motivo explícito", function()
  local def, reason = resolve_mod.resolve("", { lang = "go" })

  T.eq(nil, def)
  T.eq("task-desconocida", reason)
end)

T.section("task_resolve: test contextual reconstruido")

T.it("reconstruye el test desde $testName persistido y lo verifica", function()
  local context = require "code-runner.context"
  local label = context.test_action("go", { test = { name = "TestFoo" } })
  local id = task.id("go", label)

  local def, err = resolve_mod.resolve(id, { lang = "go", test_name = "TestFoo" })

  T.falsy(err)
  T.truthy(def)
  T.truthy(def.template:find("$testName", 1, true), "plantilla con placeholder")
end)

T.it("sin test_name no hay resolución silenciosa del test", function()
  local context = require "code-runner.context"
  local label = context.test_action("go", { test = { name = "TestFoo" } })
  local id = task.id("go", label)

  local def, reason = resolve_mod.resolve(id, { lang = "go" })

  T.eq(nil, def)
  T.eq("task-desconocida", reason)
end)

T.it("test_name que no coincide no resuelve", function()
  local context = require "code-runner.context"
  local label = context.test_action("go", { test = { name = "TestFoo" } })
  local id = task.id("go", label)

  local def, reason = resolve_mod.resolve(id, { lang = "go", test_name = "TestOtro" })

  T.eq(nil, def)
  T.eq("task-desconocida", reason)
end)

T.it("identidad independiente de iconos: resuelve con iconos cambiados", function()
  local saved = config.options.icons.run
  local entry = require("code-runner.actions").get_actions().go
  local label = entry.__order[1]
  local id = task.id("go", label)

  config.options.icons.run = "✿"
  local def = resolve_mod.resolve(id, { lang = "go" })

  config.options.icons.run = saved
  T.truthy(def, "el id no depende de la presentación")
end)

T.section("task_resolve: vía registry primero (switch de selección)")

T.it("custom con id propio sobrevive al refresh y resuelve", function()
  local registry = require "code-runner.runner_registry"
  registry.reset()
  registry.register {
    id = "zzcustom",
    filetypes = { "zzx" },
    tasks = { { id = "zzcustom.tool", name = "Tool", kind = "run", command = "CUSTOM tool ." } },
  }

  local def, err = resolve_mod.resolve("zzcustom.tool", { lang = "zzx" })

  T.falsy(err)
  T.truthy(def)
  T.eq("zzcustom.tool", def.task_id, "identidad del registry, no derivada")
  T.truthy(def.template:find("CUSTOM", 1, true), "plantilla del registry")
  registry.reset()
end)

T.it("en colisión de id manda el built-in (override va por actions.registry)", function()
  local registry = require "code-runner.runner_registry"
  registry.reset()
  registry.register {
    id = "go",
    filetypes = { "go" },
    tasks = { { id = "go.run", name = "Run", kind = "run", command = "CUSTOM go run ." } },
  }

  local def = resolve_mod.resolve("go.run", { lang = "go" })

  T.truthy(def)
  T.falsy(def.template:find("CUSTOM", 1, true),
    "el refresh re-siembre el built-in: el override custom va por config/actions.registry")
  registry.reset()
end)

T.it("sin registro usa el catálogo (compat explícita)", function()
  local registry = require "code-runner.runner_registry"
  registry.reset()

  local entry = require("code-runner.actions").get_actions().go
  local id = task.id("go", entry.__order[1])

  local def = resolve_mod.resolve(id, { lang = "go" })

  T.truthy(def, "fallback al catálogo cuando el registry no sabe")
  T.eq(id, def.task_id)
end)

T.it("la resolución no depende del orden del catálogo", function()
  local entry = require("code-runner.actions").get_actions().go
  local last_label = entry.__order[#entry.__order]
  local id = task.id("go", last_label)

  local def = resolve_mod.resolve(id, { lang = "go" })

  T.truthy(def, "encuentra el último igual que el primero")
  T.eq(id, def.task_id)
  T.eq(entry[last_label], def.template)
end)

T.it("el re-seed no ensombrece plantillas nuevas (frescura)", function()
  local registry = require "code-runner.runner_registry"
  local runners = require "code-runner.runners"
  registry.reset()

  runners.seed({ zzx = { ["Run"] = "OLD cmd", __order = { "Run" } } }, {})
  local first = resolve_mod.resolve("zzx.run", { lang = "zzx" })
  T.truthy(first and first.template:find("OLD", 1, true))

  runners.seed({ zzx = { ["Run"] = "NEW cmd", __order = { "Run" } } }, {})
  local second = resolve_mod.resolve("zzx.run", { lang = "zzx" })
  T.truthy(second and second.template:find("NEW", 1, true), "siempre el vigente")

  registry.reset()
end)

config.options = vim.deepcopy(config.defaults)
