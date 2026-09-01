local actions = require "code-runner.actions"
local config = require "code-runner.config"

T.section("actions: catálogo")

T.it("todos los lenguajes esperados están registrados", function()
  local catalog = actions.get_actions()
  local expected = {
    "java", "c", "cpp", "cs", "go", "rust", "kt", "zig", "swift", "f90",
    "py", "js", "ts", "php", "rb", "sh", "zsh", "lua", "ps1", "bat",
    "r", "R", "jl", "pl", "dart", "ex", "exs", "hs", "ml", "nim",
    "cr", "v", "scala", "clj", "erl", "fsx", "md", "make", "html", "tex",
    "deno", "bun", "d", "adb", "pas", "cu", "scm", "rkt", "lisp", "clojure",
    "groovy", "coffee", "fish", "raku", "tcl", "vbs", "kts", "odin", "gd", "vala",
  }
  for _, lang in ipairs(expected) do
    T.truthy(catalog[lang], "falta el lenguaje '" .. lang .. "'")
    T.truthy(catalog[lang].__order and #catalog[lang].__order > 0, lang .. " sin acciones")
  end
end)

T.it("__order está ordenado y cubre todas las acciones", function()
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
end)

T.it("las etiquetas incluyen los iconos de contexto", function()
  local icons = config.options.icons
  local catalog = actions.get_actions()
  T.truthy(catalog.go.__order[1]:find(icons.run, 1, true), "acción run con icono")
  T.truthy(catalog.c.__order[#catalog.c.__order]:find(icons.build, 1, true), "acción build con icono")
end)

T.it("los lenguajes recientes llevan la herramienta correcta en su plantilla", function()
  local catalog = actions.get_actions()
  local checks = {
    deno = "deno run",
    bun = "bun",
    d = "rdmd",
    adb = "gnatmake",
    pas = "fpc",
    cu = "nvcc",
    scm = "guile",
    rkt = "racket",
    lisp = "sbcl",
    clojure = "clojure",
    groovy = "groovy",
    coffee = "coffee",
    fish = "fish",
    raku = "raku",
    tcl = "tclsh",
    vbs = "cscript",
    kts = "kotlinc -script",
    odin = "odin run",
    gd = "godot",
    vala = "vala",
  }

  for lang, needle in pairs(checks) do
    local cmds = {}

    for _, label in ipairs(catalog[lang].__order) do
      local action = catalog[lang][label]
      if type(action) == "string" then
        table.insert(cmds, action)
      end
    end

    local found = false

    for _, c in ipairs(cmds) do
      if c:find(needle, 1, true) then
        found = true
      end
    end

    T.truthy(found, lang .. ": plantilla con '" .. needle .. "'")
  end
end)

T.it("el usuario puede añadir acciones sin perder las default", function()
  local original = config.options
  config.options = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), {
    actions = { go = { [" Vet"] = "go vet %" } },
  })

  local go = actions.get_actions().go
  T.truthy(go[" Vet"], "acción nueva del usuario")
  T.truthy(go[config.options.icons.run .. " Run"], "acción default preservada")

  config.options = original
end)

T.it("tabla vacía deshabilita un lenguaje", function()
  local original = config.options
  config.options = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), {
    actions = { rust = {} },
  })

  T.falsy(actions.get_actions().rust, "rust eliminado")

  config.options = original
end)

T.it("alias R replica a r", function()
  local catalog = actions.get_actions()
  T.eq(#catalog.r.__order, #catalog.R.__order)
end)

T.section("actions: internals de Java")

local internals = actions._internals

T.it("java_package_of detecta package", function()
  T.eq("com.example.demo", internals.java_package_of { "package com.example.demo;", "", "class App {}" })
  T.eq("com.x", internals.java_package_of { "   package   com.x ;" }, "tolera espacios")
end)

T.it("java_package_of devuelve nil sin package (default)", function()
  T.falsy(internals.java_package_of { "class App {}", "public static void main" })
end)

T.it("java_has_main detecta main", function()
  T.truthy(internals.java_has_main { "public static void main(String[] args)" })
  T.falsy(internals.java_has_main { "static int x = 1;" })
end)

T.it("java_source_root deduce la raíz (ruta unix)", function()
  T.eq(
    "/p/Demo/src/main/java",
    internals.java_source_root("/p/Demo/src/main/java/com/example/demo", "com.example.demo")
  )
end)

T.it("java_source_root deduce la raíz (ruta windows con backslashes)", function()
  T.eq(
    "C:/Users/x/Demo/src/main/java",
    internals.java_source_root("C:\\Users\\x\\Demo\\src\\main\\java\\com\\example\\demo", "com.example.demo")
  )
end)

T.it("java_source_root devuelve nil si el árbol no coincide", function()
  -- "demo" matchea el último segmento del package pero los demás no
  T.falsy(internals.java_source_root("/otra/ruta/demo", "com.example.demo"))
end)

T.it("java_source_root devuelve nil si consume toda la ruta", function()
  T.falsy(internals.java_source_root("/com/example/demo", "com.example.demo"))
end)

T.section("actions: C# msbuild / csc")

local compiled = require "code-runner.actions.languages.compiled"

local csdir = vim.fn.tempname()
vim.fn.mkdir(csdir, "p")

T.it("cs_project_file da prioridad a .sln sobre .csproj", function()
  vim.fn.writefile({ "" }, csdir .. "/App.sln")
  vim.fn.writefile({ "" }, csdir .. "/App.csproj")
  T.eq(vim.fs.normalize(csdir .. "/App.sln"), vim.fs.normalize(compiled.cs_project_file(csdir)))
end)

T.it("cs_project_file encuentra .csproj si no hay .sln", function()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  vim.fn.writefile({ "" }, d .. "/Proj.csproj")
  T.eq(vim.fs.normalize(d .. "/Proj.csproj"), vim.fs.normalize(compiled.cs_project_file(d)))
end)

T.it("cs_project_file devuelve nil sin proyecto", function()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  T.falsy(compiled.cs_project_file(d))
end)

T.it("cs_build_cmd con .sln usa msbuild si está disponible", function()
  local spec = compiled.cs_build_cmd(csdir, { msbuild = true, dotnet = true, csc = true })
  T.truthy(spec)
  T.contains(spec.cmd, "msbuild")
  T.contains(spec.cmd, "App.sln")
  T.eq(csdir, spec.cwd)
end)

T.it("cs_build_cmd con proyecto y sin msbuild usa dotnet build", function()
  local spec = compiled.cs_build_cmd(csdir, { msbuild = false, dotnet = true })
  T.truthy(spec)
  T.contains(spec.cmd, "dotnet build")
  T.contains(spec.cmd, "App.sln")
end)

T.it("cs_build_cmd con proyecto y sin herramientas devuelve nil", function()
  T.falsy(compiled.cs_build_cmd(csdir, { msbuild = false, dotnet = false }))
end)

T.it("cs_build_cmd en .cs suelto usa csc si está disponible", function()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  vim.fn.writefile({ "class P {}" }, d .. "/Main.cs")
  vim.cmd("edit " .. vim.fn.fnameescape(d .. "/Main.cs"))

  local spec = compiled.cs_build_cmd(d, { csc = true, dotnet = true })
  T.truthy(spec)
  T.contains(spec.cmd, "csc")
end)

T.it("cs_build_cmd en .cs suelto sin csc pero con dotnet usa single-file", function()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  local spec = compiled.cs_build_cmd(d, { csc = false, dotnet = true })
  T.truthy(spec)
  T.truthy(spec.cmd:match "^dotnet", "usa dotnet single-file")
  T.falsy(spec.cmd:find("csc", 1, true), "no usa csc")
end)
