-- Detección del directorio del proyecto para ejecutar desde la raíz.
-- Sube desde el directorio del archivo actual buscando marcadores por
-- lenguaje (go.mod, pom.xml, package.json, ...) y genéricos (.git, ...).
local config = require "code-runner.config"

local M = {}

local GENERIC_MARKERS = { ".git", ".hg", ".svn" }

local KEY_MARKERS = {
  go = { "go.mod" },
  java = { "pom.xml", "build.gradle", "settings.gradle", "build.gradle.kts" },
  rust = { "Cargo.toml" },
  py = { "pyproject.toml", "setup.py", "requirements.txt", "Pipfile" },
  js = { "package.json" },
  ts = { "package.json", "tsconfig.json" },
  php = { "composer.json" },
  rb = { "Gemfile", "Rakefile" },
  cs = { "*.csproj", "*.sln" },
  c = { "CMakeLists.txt", "meson.build", "Makefile" },
  cpp = { "CMakeLists.txt", "meson.build", "Makefile", "*.a" },
}

local function has_marker(dir, marker)
  if marker:find "[*?]" then
    return vim.fn.glob(dir .. "/" .. marker) ~= ""
  end

  local full = dir .. "/" .. marker

  return vim.fn.filereadable(full) == 1 or vim.fn.isdirectory(full) == 1
end

local function detect(dir, key, max_depth)
  local markers = {}

  for _, m in ipairs(KEY_MARKERS[key] or {}) do
    table.insert(markers, m)
  end

  for _, m in ipairs(config.options.project.markers) do
    if not vim.tbl_contains(markers, m) then
      table.insert(markers, m)
    end
  end

  for _, m in ipairs(GENERIC_MARKERS) do
    if not vim.tbl_contains(markers, m) then
      table.insert(markers, m)
    end
  end

  local depth = 0

  while dir do
    depth = depth + 1

    if depth > max_depth then
      return nil
    end

    for _, m in ipairs(markers) do
      if has_marker(dir, m) then
        return dir
      end
    end

    local parent = vim.fs.dirname(dir)

    if parent == dir then
      return nil
    end

    dir = parent
  end

  return nil
end

local function file_dir()
  return vim.fn.fnamemodify(vim.fn.expand "%:p", ":h")
end

-- Busca la raíz desde un directorio dado. nil si no encuentra marcadores
-- antes de quedarse sin padres o superar max_depth.
function M.find_from(dir, key)
  if not config.options.project.enabled then
    return nil
  end

  return detect(dir, key, config.options.project.max_depth)
end

-- Raíz del proyecto del buffer actual, o el directorio del archivo si no
-- hay marcadores (fallback: ejecutar siempre desde el dir del archivo).
function M.resolve(key)
  local dir = file_dir()
  return M.find_from(dir, key) or dir
end

M._detect = detect

return M