local project = require "code-runner.project"
local shell = require "code-runner.shell"
local config = require "code-runner.config"

local tmpdir = vim.fn.tempname() .. "/cr_proj_test"
vim.fn.mkdir(tmpdir, "p")

local trees = {} -- para limpiar al final

local function path(p)
  return p == nil and nil or vim.fs.normalize(p)
end

local function make_tree()
  local root = tmpdir .. "/tree_" .. (#trees + 1)
  vim.fn.mkdir(root, "p")
  table.insert(trees, root)
  return root
end

local function mkdir(dir)
  pcall(vim.fn.mkdir, dir, "p")
end

T.section("project: detección de la raíz")

T.it("go: go.mod en la raíz se detecta desde un subdirectorio", function()
  local root = make_tree()
  vim.fn.writefile({ "module demo" }, root .. "/go.mod")
  mkdir(root .. "/cmd")
  mkdir(root .. "/cmd/app")

  local r = project.find_from(root .. "/cmd/app", "go")
  T.eq(path(root), path(r), "raíz del proyecto")
end)

T.it("gana el marcador más cercano (monorepo)", function()
  local root = make_tree()
  vim.fn.writefile({ "module a" }, root .. "/go.mod")
  mkdir(root .. "/svc")
  vim.fn.writefile({ "module b" }, root .. "/svc/go.mod")
  mkdir(root .. "/svc/app")

  local r = project.find_from(root .. "/svc/app", "go")
  T.eq(path(root .. "/svc"), path(r))
end)

T.it(".git genérico detecta proyecto sin marcador de lenguaje", function()
  local root = make_tree()
  vim.fn.mkdir(root .. "/.git", "p")
  mkdir(root .. "/src")

  local r = project.find_from(root .. "/src", "nosuchlang")
  T.eq(path(root), path(r))
end)

T.it("sin marcadores devuelve nil", function()
  local root = make_tree()
  mkdir(root .. "/a")
  mkdir(root .. "/a/b")

  local r = project.find_from(root .. "/a/b", "go")
  T.falsy(r)
end)

T.it("marcador con glob (*.csproj) también vale", function()
  local root = make_tree()
  vim.fn.writefile({ "x" }, root .. "/App.csproj")
  mkdir(root .. "/src")

  local r = project.find_from(root .. "/src", "cs")
  T.eq(path(root), path(r))
end)

T.it("max_depth limita la subida", function()
  local root = make_tree()
  vim.fn.writefile({ "module" }, root .. "/go.mod")
  mkdir(root .. "/a")
  mkdir(root .. "/a/b")
  mkdir(root .. "/a/b/c")

  config.options.project.max_depth = 1

  local r = project.find_from(root .. "/a/b/c", "go")
  T.falsy(r)

  config.options.project = vim.deepcopy(config.defaults.project)
end)

T.it("marcadores extra del usuario se suman", function()
  local root = make_tree()
  vim.fn.writefile({ "workspace" }, root .. "/.nx")
  mkdir(root .. "/app")

  config.options.project.markers = { ".nx" }

  local r = project.find_from(root .. "/app", "go")
  T.eq(path(root), path(r))

  config.options.project = vim.deepcopy(config.defaults.project)
end)

T.it("project.enabled=false desactiva la detección", function()
  local root = make_tree()
  vim.fn.writefile({ "module" }, root .. "/go.mod")
  mkdir(root .. "/cmd")

  config.options.project.enabled = false

  local r = project.find_from(root .. "/cmd", "go")
  T.falsy(r)

  config.options.project = vim.deepcopy(config.defaults.project)
end)

T.section("project: resolve() y $project en el buffer")

T.it("resolve() vuelve al directorio del archivo sin marcadores", function()
  local root = make_tree()
  vim.fn.writefile({ "print(1)" }, root .. "/cosa.py")
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/cosa.py"))

  local r = project.resolve("py")
  T.eq(path(root), path(r))
end)

T.it("$project expande a la raíz del proyecto del buffer", function()
  local root = make_tree()
  vim.fn.writefile({ "{}" }, root .. "/package.json")
  mkdir(root .. "/src")
  vim.fn.writefile({ "export default 1" }, root .. "/src/App.js")
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/src/App.js"))

  local expanded = shell.substitute("echo $project", nil, "js")
  T.truthy(expanded:find(vim.fs.normalize(root), 1, true), "$project contiene la raíz")
end)

for _, t in ipairs(trees) do
  pcall(vim.fn.delete, t, "rf")
end