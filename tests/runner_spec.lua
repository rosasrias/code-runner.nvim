local runner = require "code-runner.runner"

T.section("runner: contrato declarativo (RUN-001)")

T.it("acepta un spec mínimo válido", function()
  T.truthy(runner.valid { id = "go" })
  T.falsy(runner.validate { id = "go" })
end)

T.it("new normaliza defaults sin compartir el original", function()
  local orig = {
    id = "py",
    filetypes = { "py" },
    project = { markers = { "pyproject.toml" } },
    tasks = {
      { id = "py.run", name = "Run", kind = "run", command = 'python "%"' },
    },
  }
  local spec = runner.new(orig)

  T.truthy(spec)
  T.eq("py", spec.id)
  T.eq({ "py" }, spec.filetypes)
  T.eq({ "pyproject.toml" }, spec.project.markers)
  T.eq("py.run", spec.tasks[1].id)

  orig.filetypes[1] = "MUTADO"
  orig.tasks[1].command = "MUTADO"
  T.eq("py", spec.filetypes[1])
  T.eq('python "%"', spec.tasks[1].command)
end)

T.it("rechaza IDs inválidos con error identificable", function()
  T.truthy(runner.validate { id = "" })
  T.truthy(runner.validate { id = "Go Run" })
  T.truthy(runner.validate { id = "Go" }, "mayúsculas: orden inequívoco")
  T.truthy(runner.validate {})
  T.truthy(runner.validate("go"))
  T.truthy(runner.valid { id = "9go" })
  T.truthy(runner.valid { id = "go.js" })
end)

T.it("rechaza filetypes/markers mal formados", function()
  T.truthy(runner.validate { id = "go", filetypes = "go" })
  T.truthy(runner.validate { id = "go", filetypes = { "" } })
  T.truthy(runner.validate { id = "go", project = { markers = { 42 } } })
  T.truthy(runner.validate { id = "go", project = "go.mod" })
end)

T.it("rechaza tareas mal formadas con motivo", function()
  local err = runner.validate {
    id = "go",
    tasks = { { id = "go.x", name = "X" } },
  }
  T.truthy(err and err:find("tasks%[1%]", 1), "apunta a la tarea")
end)

T.it("rechaza funciones: command, condition, enabled, run", function()
  local function is_fn_rejected(spec, where)
    local err = runner.validate(spec)
    T.truthy(err, where .. " debe rechazarse")
    T.truthy(err:find("funci", 1), "motivo identificable, no genérico")
  end

  local base = function()
    return { id = "go", tasks = { { id = "go.run", name = "Run", kind = "run", command = "go run ." } } }
  end

  local s = base()
  s.tasks[1].command = function() end
  is_fn_rejected(s, "command función")

  s = base()
  s.tasks[1].condition = function()
    return true
  end
  local cerr = runner.validate(s)
  T.truthy(cerr and cerr:find("condition", 1, true), "condition fuera del spec: " .. tostring(cerr))

  s = base()
  s.tasks[1].enabled = function()
    return true
  end
  is_fn_rejected(s, "enabled función")

  s = base()
  s.tasks[1].run = function() end
  is_fn_rejected(s, "run función")
end)

T.it("rechaza campos desconocidos (typos no pasan en silencio)", function()
  local err = runner.validate { id = "go", filetype = { "go" } }
  T.truthy(err and err:find("filetype", 1, true))
end)

T.it("enabled: ausente incluye, false excluye, otro tipo es error", function()
  local function task_with_enabled(v)
    local t = { id = "go.run", name = "Run", kind = "run", command = "go run ." }
    if v ~= "<ausente>" then
      t.enabled = v
    end
    return { id = "go", tasks = { t } }
  end

  T.truthy(runner.valid(task_with_enabled("<ausente>")), "ausente = incluido")

  local disabled = runner.new(task_with_enabled(false))
  T.eq(false, disabled.tasks[1].enabled, "false explícito se conserva")

  local err = runner.validate(task_with_enabled("false"))
  T.truthy(err and err:find("tasks%[1%]", 1), "string no se convierte: " .. tostring(err))

  local err2 = runner.validate(task_with_enabled(1))
  T.truthy(err2, "número tampoco")
end)

T.it("condition no pertenece al spec en ningún tipo", function()
  local err = runner.validate {
    id = "go",
    tasks = { { id = "go.run", name = "Run", kind = "run", command = "go run .", condition = "x" } },
  }
  T.truthy(err and err:find("condition", 1, true))

  T.truthy(runner.valid {
    id = "go",
    tasks = { { id = "go.run", name = "Run", kind = "run", command = "go run ." } },
  }, "sin condition, válido")
end)

T.section("runner: when como dato (batch explícito)")

local function task_with_when(when)
  return {
    id = "md",
    tasks = { { id = "md.preview", name = "Preview", kind = "run", command = 'glow "%"', when = when } },
  }
end

T.it("when válido pasa (os, tools, ambos, vacío parcial)", function()
  T.truthy(runner.valid(task_with_when(nil)))
  T.truthy(runner.valid(task_with_when { os = "win" }))
  T.truthy(runner.valid(task_with_when { os = "unix" }))
  T.truthy(runner.valid(task_with_when { tools = { "glow" } }))
  T.truthy(runner.valid(task_with_when { os = "unix", tools = { "glow", "less" } }))
end)

T.it("when malformado da error identificable", function()
  T.truthy(runner.validate(task_with_when("win")))
  T.truthy(runner.validate(task_with_when { os = "macos" }))
  T.truthy(runner.validate(task_with_when { os = "WIN" }))
  T.truthy(runner.validate(task_with_when { tools = "glow" }))
  T.truthy(runner.validate(task_with_when { tools = { "" } }))
  T.truthy(runner.validate(task_with_when { tools = { 42 } }))

  local err = runner.validate(task_with_when { os = "nope" })
  T.truthy(err and err:find("when", 1, true))

  local err2 = runner.validate(task_with_when { bogus = 1 })
  T.truthy(err2 and err2:find("bogus", 1, true), "typos no pasan: " .. tostring(err2))
end)

T.it("funciones dentro de when se rechazan", function()
  local spec = task_with_when(nil)
  spec.tasks[1].when = { tools = { "glow" }, check = function() end }

  local err = runner.validate(spec)
  T.truthy(err, "comportamiento, no dato")
end)

T.it("new conserva y desacopla when", function()
  local orig = task_with_when { os = "unix", tools = { "glow" } }
  local spec = runner.new_or_error(orig)

  T.eq("unix", spec.tasks[1].when.os)
  T.eq({ "glow" }, spec.tasks[1].when.tools)

  orig.tasks[1].when.tools[1] = "MUTADO"
  T.eq("glow", spec.tasks[1].when.tools[1])

  local plain = runner.new_or_error(task_with_when(nil))
  T.eq(nil, plain.tasks[1].when)
end)

T.it("new_or_error lanza en inválido y devuelve en válido", function()
  local ok = pcall(runner.new_or_error, { id = "" })
  T.falsy(ok)
  T.eq("go", runner.new_or_error({ id = "go" }).id)
end)

T.section("runner: conformidad del estado actual (caracterización, no migración)")

-- El catálogo legacy mezcla dato puro (strings) con comportamiento (closures
-- que ejecutan vía terminal.open). Este bloque CARACTERIZA ese estado para
-- RUN-002/004: no exige que los runners actuales cumplan el contrato nuevo.
local function inventory()
  local catalog = require("code-runner.actions").get_actions()
  local langs, fn_actions, pure_langs = 0, {}, {}

  for key, entry in pairs(catalog) do
    if type(entry) == "table" and entry.__order then
      langs = langs + 1
      local has_fn = false

      for _, label in ipairs(entry.__order) do
        if type(entry[label]) == "function" then
          has_fn = true
          table.insert(fn_actions, key .. " :: " .. label)
        end
      end

      if not has_fn then
        table.insert(pure_langs, key)
      end
    end
  end

  return langs, fn_actions, pure_langs
end

T.it("hay acciones-función acopladas a ejecución (documentado, no migrado)", function()
  local langs, fn_actions = inventory()

  T.truthy(langs > 0, "catálogo real recorrido")
  T.truthy(#fn_actions > 0, "existen closures ejecutoras: " .. table.concat(fn_actions, ", "):sub(1, 120))
end)

T.it("java y tex resuelven por función (acoplamiento B1 vigente)", function()
  local catalog = require("code-runner.actions").get_actions()

  local function has_fn(key)
    local entry = catalog[key]
    if type(entry) ~= "table" then
      return false
    end
    for _, label in ipairs(entry.__order or {}) do
      if type(entry[label]) == "function" then
        return true
      end
    end
    return false
  end

  T.truthy(has_fn("java"), "java ejecuta vía closures")
  T.truthy(has_fn("tex"), "tex ejecuta vía closures")
end)

T.it("existe un subconjunto ya declarativo (strings puros)", function()
  local _, _, pure_langs = inventory()

  T.truthy(#pure_langs > 0, "lenguajes solo-strings: " .. table.concat(pure_langs, ", "):sub(1, 120))
end)

T.it("un comando string real cabe en un RunnerSpec válido", function()
  local catalog = require("code-runner.actions").get_actions()
  local _, _, pure_langs = inventory()
  local key = pure_langs[1]
  local entry = catalog[key]

  local tasks = {}
  for _, label in ipairs(entry.__order) do
    table.insert(tasks, {
      id = "probe." .. label:gsub("%s+", "-"):gsub("[^%w%._-]", ""):lower(),
      name = label,
      kind = "run",
      command = entry[label],
    })
  end

  local spec, err = runner.new { id = "probe", filetypes = { key }, tasks = tasks }
  T.truthy(spec, "strings puros son RunnerSpec válido: " .. tostring(err))
end)

T.section("runner: puente from_catalog_entry (RUN-002, sin migrar)")

T.it("proyecta strings y reporta funciones omitidas", function()
  local entry = {
    ["> Run"] = "go run .",
    ["> Special"] = function() end,
    __order = { "> Run", "> Special" },
  }

  local spec, info = runner.from_catalog_entry("go", entry, { "go.mod" }, {})

  T.truthy(spec)
  T.eq("go", spec.id)
  T.eq({ "go" }, spec.filetypes)
  T.eq({ "go.mod" }, spec.project.markers)
  T.eq(1, #spec.tasks, "solo strings")
  T.eq(1, #info.skipped, "la función se reporta, no se migra en silencio")
  local norm, nerr = runner.new(spec)
  T.truthy(norm, "proyección normalizable: " .. tostring(nerr))
end)

T.it("entry sin __order (alias) da error explícito", function()
  local spec, err = runner.from_catalog_entry("R", { ["x"] = "y" }, nil, {})

  T.falsy(spec)
  T.truthy(err)
end)

T.it("key inválida da error explícito", function()
  local spec, err = runner.from_catalog_entry("", { __order = {} }, nil, {})

  T.falsy(spec)
  T.truthy(err)
end)
