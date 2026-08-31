local registry = require "code-runner.actions.registry"
local actions = require "code-runner.actions"
local cr = require "code-runner"

local function find_label(entry)
  for k in pairs(entry) do
    if k ~= "__order" then
      return k
    end
  end
  return nil
end

registry.reset()

T.section("registry: register_action")

T.it("registra una acción por comando para un lenguaje", function()
  registry.reset()
  registry.register {
    id = "t1",
    filetypes = { "zzz" },
    kind = "run",
    command = "mytool %",
  }

  local entry = actions.get_actions()["zzz"]
  T.truthy(entry, "extensión registrada existe")
  local label = find_label(entry)
  T.truthy(label, "label con icono run")
  T.eq(entry[label], "mytool %")

  registry.reset()
end)

T.it("kind build usa el icono build en el label", function()
  registry.reset()
  registry.register {
    id = "t2",
    filetypes = { "aaa" },
    kind = "build",
    command = "make all",
  }

  local entry = actions.get_actions()["aaa"]
  local label = find_label(entry)
  local icons = require("code-runner.config").options.icons
  T.truthy(label:find(icons.build, 1, true), "label con icono build: " .. tostring(label))

  registry.reset()
end)

T.it("__order incluye la acción registrada", function()
  registry.reset()
  registry.register {
    id = "t3",
    name = "tool",
    filetypes = { "bbb" },
    kind = "misc",
    command = "tool",
  }

  local entry = actions.get_actions()["bbb"]
  local has = false
  for _, l in ipairs(entry.__order) do
    if l == "tool" then
      has = true
    end
  end
  T.truthy(has, "acción en __order")

  registry.reset()
end)

T.it("sobrescribir el mismo id reemplaza", function()
  registry.reset()
  registry.register { id = "t4", filetypes = { "ccc" }, kind = "run", command = "v1" }
  registry.register { id = "t4", filetypes = { "ccc" }, kind = "run", command = "v2" }

  local entry = actions.get_actions()["ccc"]
  local found = false
  for _, v in pairs(entry) do
    if v == "v2" then
      found = true
    end
  end
  local v1gone = true
  for _, v in pairs(entry) do
    if v == "v1" then
      v1gone = false
    end
  end
  T.truthy(found, "v2 presente")
  T.truthy(v1gone, "v1 reemplazado")

  registry.reset()
end)

T.it("unregister elimina la acción", function()
  registry.reset()
  registry.register { id = "t5", filetypes = { "ddd" }, kind = "run", command = "x" }
  registry.unregister "t5"

  local entry = actions.get_actions()["ddd"]
  T.falsy(entry, "extensión ya no tiene acciones")

  registry.reset()
end)

T.it("disable elimina el lenguaje del catálogo", function()
  registry.reset()
  registry.register {
    id = "t6",
    filetypes = { "py" },
    kind = "run",
    command = "python3 %",
  }
  registry.register { id = "t7", filetypes = { "py" }, disable = true }

  T.falsy(actions.get_actions()["py"], "py deshabilitado por registry")

  registry.reset()
end)

T.it("register_action público delega al registry", function()
  registry.reset()
  cr.register_action {
    id = "t8",
    filetypes = { "eee" },
    kind = "run",
    command = "echo hi",
  }

  T.truthy(cr.list_registered_actions()["t8"], "listada vía API")
  cr.unregister_action "t8"
  T.falsy(cr.list_registered_actions()["t8"], "desregistrada vía API")

  registry.reset()
end)

T.it("función run se guarda como callback", function()
  registry.reset()
  registry.register {
    id = "t9",
    filetypes = { "fff" },
    kind = "misc",
    run = function() end,
  }

  local entry = actions.get_actions()["fff"]
  local fn = nil
  for _, v in pairs(entry) do
    if type(v) == "function" then
      fn = v
    end
  end
  T.truthy(fn, "run guardado como función")

  registry.reset()
end)

T.it("errores de validación", function()
  registry.reset()
  local ok1 = pcall(registry.register, {}) -- sin id
  local ok3 = pcall(registry.register, { id = "x" }) -- sin filetypes/comando
  local ok4 = pcall(registry.register, { id = "y", filetypes = "py", command = "c", kind = "bogus" })
  T.falsy(ok1, "sin id falla")
  T.falsy(ok3, "sin comando falla")
  T.falsy(ok4, "kind inválido falla")

  registry.reset()
end)
