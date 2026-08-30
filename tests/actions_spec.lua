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
