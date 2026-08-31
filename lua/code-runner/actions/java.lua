-- Ejecución de Java sin Maven/Gradle (smart run) y auto-detección de Maven.
local terminal = require "code-runner.terminal"
local shell = require "code-runner.shell"

local notify = terminal.notify

local M = {}

function M.has_main(lines)
  for _, line in ipairs(lines) do
    if line:match "public%s+static%s+void%s+main" then
      return true
    end
  end
  return false
end

function M.package_of(lines)
  for _, line in ipairs(lines) do
    local pkg = line:match "^%s*package%s+([%w%.]+)%s*;"
    if pkg then
      return pkg
    end
  end
  return nil
end

-- Deduce la raíz de fuentes quitando los segmentos del package
-- Ej: <root>/com/example/demo + "com.example.demo" -> <root>
function M.source_root(dir, package)
  local parts = vim.split(package, ".", { plain = true })
  local segs = vim.split(dir:gsub("\\", "/"), "/", { plain = true })

  while #parts > 0 do
    local expected = table.remove(parts)
    local actual = table.remove(segs)

    if actual ~= expected then
      return nil
    end
  end

  local root = table.concat(segs, "/")

  if root == "" then
    return nil
  end

  return root
end

-- Smart run: compila con javac a un directorio temporal y ejecuta; limpia el
-- temp al terminar el job (ver code_runner_cleanup en terminal.open).
function M.plain_run()
  local file = vim.fn.expand "%:p"
  local lines = vim.fn.readfile(file)

  if not lines or #lines == 0 then
    notify("No se pudo leer el archivo", vim.log.levels.ERROR)
    return
  end

  if not M.has_main(lines) then
    notify("No se encontró método main", vim.log.levels.ERROR)
    return
  end

  local qfile = string.format('"%s"', file)
  local package = M.package_of(lines)

  -- Sin package: single-file source launcher (JDK 11+)
  if not package then
    terminal.open("java " .. qfile)
    return
  end

  local fqcn = package .. "." .. vim.fn.fnamemodify(file, ":t:r")
  local root = M.source_root(vim.fn.fnamemodify(file, ":h"), package)

  if not root then
    -- El árbol de directorios no coincide con el package: lanzar directo
    terminal.open("java " .. qfile)
    return
  end

  local out = vim.fn.tempname()
  local cmd = string.format(
    'javac -encoding UTF-8 -sourcepath "%s" -d "%s" %s && java -cp "%s" "%s"',
    root,
    out,
    qfile,
    out,
    fqcn
  )

  terminal.open(cmd, nil, nil, nil, { out })
end

function M.find_pom_directory(start_dir)
  local dir = start_dir

  while dir and #dir > 3 do
    if vim.fn.filereadable(dir .. "/pom.xml") == 1 then
      return dir
    end

    local parent = vim.fn.fnamemodify(dir, ":h")

    if parent == dir then
      break
    end

    dir = parent
  end

  return nil
end

-- Ejecuta la clase con package vía Maven (auto-run) si hay pom.xml.
function M.maven_run()
  local file = vim.fn.expand "%:p"
  local lines = vim.fn.readfile(file)

  if not lines or #lines == 0 then
    notify("No se pudo leer el archivo", vim.log.levels.ERROR)
    return
  end

  local package = M.package_of(lines)

  if not package then
    notify("No se encontró package", vim.log.levels.ERROR)
    return
  end

  local full_class = package .. "." .. vim.fn.fnamemodify(file, ":t:r")
  local pom_dir = M.find_pom_directory(vim.fn.fnamemodify(file, ":h"))

  if not pom_dir then
    notify("No se encontró pom.xml", vim.log.levels.ERROR)
    return
  end

  local cd_cmd = shell.IS_WIN and string.format('Set-Location "%s"', pom_dir) or string.format("cd '%s'", pom_dir)
  local mvn_cmd = string.format('mvn -q exec:java "-Dexec.mainClass=%s"', full_class)

  terminal.open(cd_cmd .. " && " .. mvn_cmd)
end

return M
