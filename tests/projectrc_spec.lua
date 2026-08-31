local projectrc = require "code-runner.projectrc"
local registry = require "code-runner.actions.registry"
local config = require "code-runner.config"

local tmpdir = vim.fn.tempname() .. "/cr_projrc_test"
vim.fn.mkdir(tmpdir, "p")

local trees = {}

local function make_tree()
  local root = tmpdir .. "/tree_" .. (#trees + 1)
  vim.fn.mkdir(root, "p")
  vim.fn.mkdir(root .. "/src", "p")
  table.insert(trees, root)
  return root
end

local path = function(p)
  return vim.fs.normalize(p)
end

local function clean()
  registry.reset()
  projectrc.clear_cache()
end

T.section("projectrc: .code-runner.lua por proyecto")

T.it("un dotfile no existe no hace nada", function()
  clean()
  local root = make_tree()
  vim.fn.writefile({ "module demo" }, root .. "/go.mod")

  T.falsy(projectrc.load("go", root), "sin dotfile → false")
end)

T.it("carga .code-runner.lua y registra las tasks devueltas", function()
  clean()
  local root = make_tree()
  vim.fn.writefile({ "module demo" }, root .. "/go.mod")
  vim.fn.writefile({
    "return { tasks = {",
    "  dev = { filetypes = { 'zzz' }, kind = 'run', command = 'dev %' },",
    "} }",
  }, root .. "/.code-runner.lua")

  T.truthy(projectrc.load("go", root), "dotfile cargada")
  local entry = require("code-runner.actions").get_actions()["zzz"]
  local label = entry and entry.__order[1] or nil
  T.truthy(entry, "task registrada en el catálogo")

  local found = false
  if entry then
    for _, v in pairs(entry) do
      if v == "dev %" then
        found = true
      end
    end
  end
  T.truthy(found, "comando de la task presente")
end)

T.it("es cacheada por raíz (no recarga ni re-registra)", function()
  clean()
  local root = make_tree()
  vim.fn.writefile({ "module demo" }, root .. "/go.mod")
  local dot = root .. "/.code-runner.lua"
  vim.fn.writefile({ "return { tasks = { t = { filetypes = { 'zzz' }, kind = 'run', command = 'v1' } } }" }, dot)

  projectrc.load("go", root)
  -- Modificamos el dotfile y volvemos a cargar: no debería re-registrar.
  vim.fn.writefile({ "return { tasks = { t = { filetypes = { 'zzz' }, kind = 'run', command = 'v2' } } }" }, dot)
  projectrc.load("go", root)

  local entry = require("code-runner.actions").get_actions()["zzz"]
  local has_v2 = false
  for _, v in pairs(entry) do
    if v == "v2" then
      has_v2 = true
    end
  end
  T.falsy(has_v2, "no recarga el dotfile cacheado (sigue v1)")

  clean()
end)

T.it("un dotfile que lanza error se notifica sin propagar", function()
  clean()
  local root = make_tree()
  vim.fn.writefile({ "module demo" }, root .. "/go.mod")
  vim.fn.writefile({ "error('boom')" }, root .. "/.code-runner.lua")

  local terminal = require "code-runner.terminal"
  local orig = terminal.notify
  local notified = {}
  terminal.notify = function(msg, level)
    table.insert(notified, { msg = msg, level = level })
  end

  local ok = pcall(projectrc.load, "go", root)

  terminal.notify = orig

  T.truthy(ok, "no propaga el error")
  T.eq(1, #notified, "notifica un error")
  T.truthy(notified[1].msg:find(".code%-runner.lua"), "mensaje menciona el dotfile")

  clean()
end)

T.it("projectrc deshabilitado no carga nada", function()
  clean()
  local saved = config.options.projectrc.enabled
  config.options.projectrc.enabled = false

  local root = make_tree()
  vim.fn.writefile({ "module demo" }, root .. "/go.mod")
  vim.fn.writefile({ "return { tasks = {} }" }, root .. "/.code-runner.lua")

  T.falsy(projectrc.load("go", root), "deshabilitado → false")

  config.options.projectrc.enabled = saved
  clean()
end)

-- limpieza de árboles temporales
for _, t in ipairs(trees) do
  vim.fn.delete(t, "rf")
end
