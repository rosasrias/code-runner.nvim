local resolve = require "code-runner.resolve"

local function go_runner(over)
  local base = {
    id = "go",
    filetypes = { "go" },
    project = { markers = { "go.mod" } },
    tasks = {
      { id = "go.run", name = "Run", kind = "run", command = "go run ." },
      { id = "go.test", name = "Test", kind = "test", command = "go test ./..." },
    },
  }

  if over then
    for k, v in pairs(over) do
      base[k] = v
    end
  end

  return base
end

local function py_runner()
  return {
    id = "py",
    filetypes = { "py" },
    tasks = {
      { id = "py.run", name = "Run", kind = "run", command = 'python "%"' },
    },
  }
end

T.section("resolve: entrada, salida y sin-coincidencias")

T.it("sin runners devuelve candidatos vacío (no nil ni error)", function()
  local res, err = resolve.resolve { runners = {}, context = { filetype = "go" } }

  T.falsy(err)
  T.truthy(res)
  T.eq(0, #res.candidates)
end)

T.it("sin señales no hay match (nada de catch-all implícitos)", function()
  local res = resolve.resolve {
    runners = { { id = "vacio" } },
    context = { filetype = "go", project = { marker = "go.mod" } },
  }

  T.eq(0, #res.candidates, "runner sin filetypes ni markers nunca es candidato")
end)

T.it("entradas malformadas dan error identificable", function()
  T.falsy(resolve.resolve(nil))
  T.falsy(resolve.resolve { runners = "x", context = {} })
  T.falsy(resolve.resolve { runners = {}, context = "x" })

  local res, err = resolve.resolve { runners = { { id = "ok" }, { id = "" } }, context = {} }
  T.falsy(res)
  T.truthy(err and err:find("runners%[2%]", 1), "apunta al runner: " .. tostring(err))
end)

T.it("contexto mínimo (tabla vacía) no rompe", function()
  local res, err = resolve.resolve { runners = { go_runner() }, context = {} }

  T.falsy(err)
  T.eq(0, #res.candidates)
end)

T.section("resolve: señales y puntaje")

T.it("filetype matchea (2 puntos)", function()
  local res = resolve.resolve { runners = { go_runner() }, context = { filetype = "go" } }

  T.eq(1, #res.candidates)
  T.eq("go", res.candidates[1].runner_id)
  T.eq(2, res.candidates[1].score)
  T.eq(2, #res.candidates[1].tasks)
end)

T.it("extension matchea cuando no hay filetype", function()
  local res = resolve.resolve { runners = { go_runner() }, context = { extension = "go" } }

  T.eq(1, #res.candidates)
end)

T.it("marker matchea (1 punto) sin filetype", function()
  local res = resolve.resolve {
    runners = { go_runner { filetypes = {} } },
    context = { project = { marker = "go.mod" } },
  }

  T.eq(1, #res.candidates)
  T.eq(1, res.candidates[1].score)
end)

T.it("marker ajeno no matchea", function()
  local res = resolve.resolve {
    runners = { go_runner { filetypes = {} } },
    context = { project = { marker = "package.json" } },
  }

  T.eq(0, #res.candidates)
end)

T.it("una categoría suma una sola vez (filetype+extensión = 2, no 4)", function()
  local res = resolve.resolve {
    runners = { go_runner() },
    context = { filetype = "go", extension = "go" },
  }

  T.eq(1, #res.candidates)
  T.eq(2, res.candidates[1].score, "misma señal, sin multiplicar")
end)

T.it('extensión con punto inicial equivale (".go" = "go")', function()
  local res = resolve.resolve {
    runners = { go_runner() },
    context = { extension = ".go" },
  }

  T.eq(1, #res.candidates)
end)

T.it("markers comparan exacto (el punto de .git no se toca)", function()
  local res = resolve.resolve {
    runners = { { id = "git", project = { markers = { ".git" } } } },
    context = { project = { marker = ".git" } },
  }

  T.eq(1, #res.candidates)
  T.eq(1, res.candidates[1].score)
end)

T.it("mayúsculas no equivalen en señales (contrato minúsculas)", function()
  local res = resolve.resolve {
    runners = { go_runner() },
    context = { filetype = "Go" },
  }

  T.eq(0, #res.candidates, "exactitud documentada, sin magia")
end)

T.it("múltiples candidatos ordenan por score y desempata por id", function()
  local res = resolve.resolve {
    runners = {
      go_runner { id = "zeta", filetypes = { "go" } },
      go_runner { id = "alfa", filetypes = { "go" } },
      py_runner(),
    },
    context = { filetype = "go", project = { marker = "go.mod" } },
  }

  -- go+marker = 3 para zeta/alfa (desempate alfabético), py fuera
  T.eq(2, #res.candidates)
  T.eq("alfa", res.candidates[1].runner_id)
  T.eq(3, res.candidates[1].score)
  T.eq("zeta", res.candidates[2].runner_id)
end)

T.it("determinista: misma entrada, misma salida", function()
  local input = {
    runners = { go_runner(), py_runner() },
    context = { filetype = "py", project = { marker = "go.mod" } },
  }

  local a = resolve.resolve(input)
  local b = resolve.resolve(input)

  T.eq(#a.candidates, #b.candidates)
  for i, c in ipairs(a.candidates) do
    T.eq(c.runner_id, b.candidates[i].runner_id)
    T.eq(c.score, b.candidates[i].score)
    T.eq(#c.tasks, #b.candidates[i].tasks)
  end
end)

T.section("resolve: tareas visibles")

T.it("enabled=false excluye la tarea", function()
  local r = go_runner()
  r.tasks[2].enabled = false

  local res = resolve.resolve { runners = { r }, context = { filetype = "go" } }

  T.eq(1, #res.candidates[1].tasks)
  T.eq("go.run", res.candidates[1].tasks[1].id)
end)

T.it("enabled ausente incluye (default documentado)", function()
  local r = go_runner()
  r.tasks[1].enabled = nil

  local res = resolve.resolve { runners = { r }, context = { filetype = "go" } }

  T.eq(2, #res.candidates[1].tasks, "ausente = incluido")
end)

T.section("resolve: condiciones when con disponibilidad inyectada")

local function when_runner()
  return {
    id = "md",
    filetypes = { "md" },
    tasks = {
      { id = "md.preview", name = "Preview", kind = "run", command = 'glow "%"', when = { tools = { "glow" } } },
      { id = "md.raw", name = "Raw", kind = "run", command = 'cat "%"' },
      { id = "md.winonly", name = "Win", kind = "run", command = 'type "%"', when = { os = "win" } },
    },
  }
end

local function md_ids(res)
  local ids = {}
  for _, t in ipairs(res.candidates[1].tasks) do
    ids[#ids + 1] = t.id
  end
  return ids
end

T.it("tools satisfechas incluyen, faltantes excluyen", function()
  local ctx = { filetype = "md" }

  local with_tool = resolve.resolve {
    runners = { when_runner() },
    context = ctx,
    availability = { tools = { glow = true } },
  }
  T.truthy(vim.tbl_contains(md_ids(with_tool), "md.preview"))

  local without_tool = resolve.resolve {
    runners = { when_runner() },
    context = ctx,
    availability = { tools = {} },
  }
  T.falsy(vim.tbl_contains(md_ids(without_tool), "md.preview"))
  T.truthy(vim.tbl_contains(md_ids(without_tool), "md.raw"), "sin when siempre visible")
end)

T.it("sin datos de disponibilidad no hay permisividad silenciosa", function()
  local res = resolve.resolve { runners = { when_runner() }, context = { filetype = "md" } }

  T.eq({ "md.raw" }, md_ids(res), "solo la tarea sin when")
end)

T.it("os coincide incluye, distinto excluye", function()
  local win = resolve.resolve {
    runners = { when_runner() },
    context = { filetype = "md" },
    availability = { os = "win", tools = {} },
  }
  T.truthy(vim.tbl_contains(md_ids(win), "md.winonly"))

  local unix = resolve.resolve {
    runners = { when_runner() },
    context = { filetype = "md" },
    availability = { os = "unix", tools = {} },
  }
  T.falsy(vim.tbl_contains(md_ids(unix), "md.winonly"))
end)

T.it("conjunción: os ok + tool faltante excluye", function()
  local r = when_runner()
  r.tasks[1].when = { os = "win", tools = { "glow" } }

  local res = resolve.resolve {
    runners = { r },
    context = { filetype = "md" },
    availability = { os = "win", tools = {} },
  }

  T.falsy(vim.tbl_contains(md_ids(res), "md.preview"))
end)

T.it("variantes con fallback declarativo (ps1: pwsh|powershell)", function()
  local r = {
    id = "ps1",
    filetypes = { "ps1" },
    tasks = {
      { id = "ps1.run-pwsh", name = "Run pwsh", kind = "run", command = "pwsh ...", when = { tools = { "pwsh" } } },
      { id = "ps1.run-ps", name = "Run ps", kind = "run", command = "powershell ...", when = { tools = { "powershell" } } },
    },
  }
  local ctx = { filetype = "ps1" }

  local both = resolve.resolve { runners = { r }, context = ctx, availability = { tools = { pwsh = true, powershell = true } } }
  T.eq(2, #both.candidates[1].tasks, "ambas explícitas, el picker decide")

  local only_ps = resolve.resolve { runners = { r }, context = ctx, availability = { tools = { powershell = true } } }
  T.eq({ "ps1.run-ps" }, md_ids(only_ps))
end)

T.it("filetypes de tarea filtra por contexto", function()
  local r = go_runner()
  r.tasks[1].filetypes = { "go" }
  r.tasks[2].filetypes = { "rust" }

  local res = resolve.resolve { runners = { r }, context = { filetype = "go" } }

  T.eq(1, #res.candidates[1].tasks)
  T.eq("go.run", res.candidates[1].tasks[1].id)
end)

T.it("mismo task id en dos runners se conserva con su runner", function()
  local a = go_runner { id = "a" }
  local b = go_runner { id = "b" }

  local res = resolve.resolve { runners = { a, b }, context = { filetype = "go" } }

  T.eq(2, #res.candidates)
  T.eq("a", res.candidates[1].runner_id)
  T.eq("b", res.candidates[2].runner_id)
  T.eq("go.run", res.candidates[1].tasks[1].id)
  T.eq("go.run", res.candidates[2].tasks[1].id)
end)

T.section("resolve: caracterización con el catálogo real (sin migrar selección)")

-- Proyecta TODO el catálogo legacy a RunnerSpecs (puros) y resuelve con
-- contextos realistas. Caracteriza la salida esperada del resolver con
-- datos reales; la selección productiva (picker por labels) NO cambia.
local function project_catalog()
  local runner_mod = require "code-runner.runner"
  local catalog = require("code-runner.actions").get_actions()
  local project = require "code-runner.project"
  local config = require "code-runner.config"

  local runners, skipped_total, failed, aliases = {}, 0, {}, {}

  for key, entry in pairs(catalog) do
    local spec, info = runner_mod.from_catalog_entry(key, entry, project.markers_for(key), config.options.icons)

    if spec then
      local norm, nerr = runner_mod.new(spec)

      if norm then
        runners[#runners + 1] = norm
        skipped_total = skipped_total + #(info.skipped or {})
      else
        failed[#failed + 1] = key .. ": " .. tostring(nerr)
      end
    elseif type(info) == "string" and info:find("alias", 1, true) then
      aliases[#aliases + 1] = key
    else
      failed[#failed + 1] = key .. ": " .. tostring(info)
    end
  end

  table.sort(runners, function(a, b)
    return a.id < b.id
  end)

  return runners, skipped_total, failed, aliases
end

T.it("el catálogo real proyecta a RunnerSpecs válidos", function()
  local runners, skipped_total, failed, aliases = project_catalog()

  T.truthy(#runners > 10, "cobertura real, no fixture: " .. #runners .. " runners")
  T.eq(0, #failed, "ninguna proyección rompe: " .. table.concat(failed, "; "):sub(1, 200))
  T.truthy(skipped_total > 0, "funciones omitidas y reportadas: " .. skipped_total)
  T.eq({ "R" }, aliases, "único alias conocido, sin duplicar declaración")
end)

T.it("contexto go+go.mod resuelve el runner go con sus tareas", function()
  local runners = project_catalog()

  local res, err = resolve.resolve {
    runners = runners,
    context = { filetype = "go", extension = "go", project = { marker = "go.mod" } },
  }

  T.falsy(err)
  T.truthy(#res.candidates > 0)

  local go
  for _, c in ipairs(res.candidates) do
    if c.runner_id == "go" then
      go = c
    end
  end

  T.truthy(go, "go es candidato")
  T.eq(3, go.score, "filetype + marker")
  T.truthy(#go.tasks > 0, "con tareas")
  T.eq("go", res.candidates[1].runner_id, "primero por puntaje")
end)

T.it("contexto desconocido no inventa candidatos", function()
  local runners = project_catalog()

  local res = resolve.resolve {
    runners = runners,
    context = { filetype = "zz_nope", extension = "zz_nope" },
  }

  T.eq(0, #res.candidates)
end)

T.it("determinista sobre el catálogo completo", function()
  local runners = project_catalog()
  local context = { filetype = "py", extension = "py", project = { marker = "pyproject.toml" } }

  local a = resolve.resolve { runners = runners, context = context }
  local b = resolve.resolve { runners = runners, context = context }

  T.eq(#a.candidates, #b.candidates)
  for i, c in ipairs(a.candidates) do
    T.eq(c.runner_id, b.candidates[i].runner_id)
    T.eq(c.score, b.candidates[i].score)
  end
end)
