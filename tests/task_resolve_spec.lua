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
  T.eq(label, def.label)
  T.eq(entry[label], def.template)
  T.eq("go", def.key)
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

config.options = vim.deepcopy(config.defaults)
