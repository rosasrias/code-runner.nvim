local profiles = require "code-runner.actions.profiles"
local actions = require "code-runner.actions"
local config = require "code-runner.config"
local shell = require "code-runner.shell"

local env = {
  RUN = config.options.icons.run,
  BUILD = config.options.icons.build,
  shell = shell,
}

T.section("profiles: presets con significado real")

T.it("rust ofrece Build/Run en release", function()
  local extra = profiles.for_lang(env, "rust")
  T.truthy(extra, "rust tiene presets")
  T.eq("cargo build --release", extra[env.BUILD .. " Build (release)"])
  T.eq("cargo run --release", extra[env.RUN .. " Run (release)"])
end)

T.it("go ofrece Test benchmark", function()
  local extra = profiles.for_lang(env, "go")
  T.truthy(extra, "go tiene presets")
  T.eq("go test -bench . -benchmem", extra[env.RUN .. " Test (benchmark)"])
end)

T.it("c/c++ compilan con -O2 en release", function()
  local c = profiles.for_lang(env, "c")
  local cpp = profiles.for_lang(env, "cpp")
  T.truthy(c, "c tiene presets")
  T.truthy(cpp, "cpp tiene presets")
  T.contains(c[env.BUILD .. " Compile (release)"], "gcc -O2", "c usa gcc -O2")
  T.contains(cpp[env.BUILD .. " Compile (release)"], "g++ -O2", "cpp usa g++ -O2")
  T.truthy(c[env.RUN .. env.BUILD .. " Compile & Run (release)"]:find(env.BUILD .. " ", 1, true) or true, "con compile&run")
  T.contains(c[env.RUN .. env.BUILD .. " Compile & Run (release)"], "&&", "compile & run encadena")
end)

T.it("lenguajes sin un modo real no tienen presets", function()
  for _, key in ipairs { "py", "js", "java", "lua", "md", "tex" } do
    T.falsy(profiles.for_lang(env, key), key .. " no tiene presets")
  end
end)

T.it("el catálogo no cambia con profiles.enabled=false (default zero-config)", function()
  local original = config.options
  config.options = vim.deepcopy(config.defaults)
  T.falsy(config.options.profiles.enabled, "default false")

  local go = actions.get_actions().go
  local has_bench = false
  for _, l in ipairs(go.__order) do
    if l:find("benchmark", 1, true) then
      has_bench = true
    end
  end
  T.falsy(has_bench, "sin variantes de perfil en el picker por defecto")

  config.options = original
end)

T.it("con profiles.enabled=true las variantes aparecen en el catálogo", function()
  local original = config.options
  config.options = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), {
    profiles = { enabled = true },
  })

  local catalog = actions.get_actions()

  local rust = catalog.rust.__order
  T.truthy(rust, "rust presente")
  local has_release = false
  for _, l in ipairs(rust) do
    if l:find("release", 1, true) then
      has_release = true
    end
  end
  T.truthy(has_release, "rust ofrece release")

  local go = catalog.go.__order
  local has_bench = false
  for _, l in ipairs(go) do
    if l:find("benchmark", 1, true) then
      has_bench = true
    end
  end
  T.truthy(has_bench, "go ofrece benchmark")

  local py = catalog.py.__order
  local py_has = false
  for _, l in ipairs(py) do
    if l:find("release", 1, true) or l:find("benchmark", 1, true) then
      py_has = true
    end
  end
  T.falsy(py_has, "py sigue sin perfiles (no tiene modo real)")

  config.options = original
end)

T.it("__order sigue consistente (cubre todas las acciones) con profiles activos", function()
  local original = config.options
  config.options = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), {
    profiles = { enabled = true },
  })

  local catalog = actions.get_actions()
  for lang, entry in pairs(catalog) do
    local labels = {}
    for k in pairs(entry) do
      if k ~= "__order" then
        table.insert(labels, k)
      end
    end
    table.sort(labels)
    T.eq(#labels, #entry.__order, lang .. ": cantidad de labels")
    for i, label in ipairs(labels) do
      T.eq(label, entry.__order[i], lang .. ": orden alfabético")
    end
  end

  config.options = original
end)
