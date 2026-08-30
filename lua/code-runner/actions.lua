local config = require "code-runner.config"
local shell = require "code-runner.shell"
local terminal = require "code-runner.terminal"

local M = {}

local notify = terminal.notify
local open_runner = terminal.open

---------------------------------------------------------
-- Java: helpers para ejecutar sin Maven/Gradle
---------------------------------------------------------
local function java_has_main(lines)
  for _, line in ipairs(lines) do
    if line:match "public%s+static%s+void%s+main" then
      return true
    end
  end
  return false
end

local function java_package_of(lines)
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
local function java_source_root(dir, package)
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

local function java_plain_run()
  local file = vim.fn.expand "%:p"
  local lines = vim.fn.readfile(file)

  if not lines or #lines == 0 then
    notify("No se pudo leer el archivo", vim.log.levels.ERROR)
    return
  end

  if not java_has_main(lines) then
    notify("No se encontró método main", vim.log.levels.ERROR)
    return
  end

  local qfile = string.format('"%s"', file)
  local package = java_package_of(lines)

  -- Sin package: single-file source launcher (JDK 11+)
  if not package then
    open_runner("java " .. qfile)
    return
  end

  local fqcn = package .. "." .. vim.fn.fnamemodify(file, ":t:r")
  local root = java_source_root(vim.fn.fnamemodify(file, ":h"), package)

  if not root then
    -- El árbol de directorios no coincide con el package: lanzar directo
    open_runner("java " .. qfile)
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

  open_runner(cmd)
end

---------------------------------------------------------
-- Maven
---------------------------------------------------------
local function find_pom_directory(start_dir)
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

local function maven_detected_run()
  local file = vim.fn.expand "%:p"
  local lines = vim.fn.readfile(file)

  if not lines or #lines == 0 then
    notify("No se pudo leer el archivo", vim.log.levels.ERROR)
    return
  end

  local package = java_package_of(lines)

  if not package then
    notify("No se encontró package", vim.log.levels.ERROR)
    return
  end

  local full_class = package .. "." .. vim.fn.fnamemodify(file, ":t:r")
  local pom_dir = find_pom_directory(vim.fn.fnamemodify(file, ":h"))

  if not pom_dir then
    notify("No se encontró pom.xml", vim.log.levels.ERROR)
    return
  end

  local cd_cmd = shell.IS_WIN and string.format('Set-Location "%s"', pom_dir) or string.format("cd '%s'", pom_dir)
  local mvn_cmd = string.format('mvn -q exec:java "-Dexec.mainClass=%s"', full_class)

  open_runner(cd_cmd .. " && " .. mvn_cmd)
end

---------------------------------------------------------
-- LaTeX: detectar archivo principal
---------------------------------------------------------
local function detect_main_tex()
  local current = vim.fn.expand "%:p"
  local lines = vim.fn.readfile(current, "", 15)

  for _, line in ipairs(lines) do
    local root = line:match "^%%%s*!TEX%s+root%s*=%s*(.+)"

    if root then
      local dir = vim.fn.fnamemodify(current, ":h")
      return vim.fn.fnamemodify(dir .. "/" .. root, ":p")
    end
  end

  return current
end

---------------------------------------------------------
-- Tabla de acciones
---------------------------------------------------------
function M.get_actions()
  local RUN = config.options.icons.run
  local BUILD = config.options.icons.build

  -- Plantilla para lenguajes compilados a binario nativo (C, C++, Swift, Fortran)
  local function native(compiler)
    local compile = compiler .. ' "%" -o "$fileBase' .. shell.EXE_SUFFIX .. '"'
    local run = "$binRun"

    return {
      [BUILD .. " Compile"] = compile,
      [RUN .. " Run"] = run,
      [RUN .. BUILD .. " Compile & Run"] = compile .. " && $binRun",
    }
  end

  local actions = {

    -----------------------------------------------------
    -- JAVA
    -----------------------------------------------------
    java = {
      [RUN .. " Maven auto-run"] = maven_detected_run,
      [BUILD .. " Maven build"] = "mvn -q clean package",
      [RUN .. " Spring Boot run"] = "mvn spring-boot:run",
      [BUILD .. " Spring Boot build"] = "mvn -q clean install",
      [RUN .. BUILD .. " Java smart run"] = java_plain_run,
    },

    -----------------------------------------------------
    -- C#
    -----------------------------------------------------
    cs = {
      [BUILD .. " Build"] = "dotnet build",
      [RUN .. " Run"] = "dotnet run",
    },

    -----------------------------------------------------
    -- C / C++
    -----------------------------------------------------
    c = native "gcc",

    cpp = native "g++",

    -----------------------------------------------------
    -- Python / JS / TS / PHP / Ruby / Shell
    -----------------------------------------------------
    py = {
      [RUN .. " Run"] = 'python "%"',
    },

    js = {
      [RUN .. " Run"] = 'node "%"',
    },

    ts = {
      [BUILD .. " Compile"] = 'tsc "%"',
      [RUN .. " Run"] = 'ts-node "%"',
      [RUN .. BUILD .. " Compile & Run"] = 'tsc "%" && node "$fileBase.js"',
    },

    php = {
      [RUN .. " Run"] = 'php "%"',
    },

    rb = {
      [RUN .. " Run"] = 'ruby "%"',
    },

    sh = {
      [RUN .. " Run"] = 'bash "%"',
    },

    zsh = {
      [RUN .. " Run"] = 'zsh "%"',
    },

    -----------------------------------------------------
    -- Lua / PowerShell / Batch
    -----------------------------------------------------
    lua = {
      [RUN .. " Run"] = 'lua "%"',
    },

    ps1 = {
      [RUN .. " Run"] = function()
        local exe = vim.fn.executable "pwsh" == 1 and "pwsh" or "powershell"
        open_runner(exe .. ' -NoLogo -NoProfile -File "%"')
      end,
    },

    bat = {
      [RUN .. " Run"] = function()
        if not shell.IS_WIN then
          notify(".bat solo se puede ejecutar en Windows", vim.log.levels.WARN)
          return
        end
        open_runner('cmd /c "%"')
      end,
    },

    -----------------------------------------------------
    -- R / Julia / Perl
    -----------------------------------------------------
    r = {
      [RUN .. " Run"] = 'Rscript "%"',
    },

    jl = {
      [RUN .. " Run"] = 'julia "%"',
    },

    pl = {
      [RUN .. " Run"] = 'perl "%"',
    },

    -----------------------------------------------------
    -- Dart / Elixir
    -----------------------------------------------------
    dart = {
      [RUN .. " Run"] = 'dart "%"',
    },

    ex = {
      [RUN .. " Run"] = 'elixir "%"',
    },

    exs = {
      [RUN .. " Run"] = 'elixir "%"',
    },

    -----------------------------------------------------
    -- Haskell / OCaml
    -----------------------------------------------------
    hs = {
      [RUN .. " Run"] = 'runghc "%"',
    },

    ml = {
      [RUN .. " Run"] = 'ocaml "%"',
    },

    -----------------------------------------------------
    -- Nim (compila y ejecuta en un paso)
    -----------------------------------------------------
    nim = {
      [RUN .. BUILD .. " Compile & Run"] = 'nim c -r "%"',
    },

    cr = {
      [RUN .. " Run"] = 'crystal "%"',
    },

    v = {
      [RUN .. " Run"] = 'v run "%"',
    },

    -----------------------------------------------------
    -- Scala / Clojure / Erlang / F#
    -----------------------------------------------------
    scala = {
      [RUN .. " Run"] = 'scala "%"',
    },

    clj = {
      [RUN .. " Run"] = 'clojure -M "%"',
    },

    erl = {
      [RUN .. " Run"] = 'escript "%"',
    },

    fsx = {
      [RUN .. " Run"] = 'dotnet fsi "%"',
    },

    -----------------------------------------------------
    -- Markdown (vista previa con glow)
    -----------------------------------------------------
    md = {
      [RUN .. " Preview"] = function()
        if vim.fn.executable "glow" == 0 then
          notify("glow no está instalado", vim.log.levels.ERROR)
          return
        end
        open_runner('glow "%"')
      end,
    },

    -----------------------------------------------------
    -- Makefile (se accede por filetype, sin extensión)
    -----------------------------------------------------
    make = {
      [BUILD .. " make"] = "make",
      [BUILD .. " make clean"] = "make clean",
    },

    -----------------------------------------------------
    -- Go
    -----------------------------------------------------
    go = {
      [RUN .. " Run"] = 'go run "%"',
      [BUILD .. " Build"] = 'go build -o "$fileBase' .. shell.EXE_SUFFIX .. '"',
    },

    -----------------------------------------------------
    -- Rust
    -----------------------------------------------------
    rust = {
      [BUILD .. " Build"] = "cargo build",
      [RUN .. " Run"] = "cargo run",
    },

    -----------------------------------------------------
    -- Kotlin
    -----------------------------------------------------
    kt = {
      [BUILD .. " Compile"] = 'kotlinc "%" -include-runtime -d "$fileBase.jar"',
      [RUN .. " Run"] = 'java -jar "$fileBase.jar"',
      [RUN .. BUILD .. " Compile & Run"] = 'kotlinc "%" -include-runtime -d "$fileBase.jar" && java -jar "$fileBase.jar"',
    },

    -----------------------------------------------------
    -- Swift
    -----------------------------------------------------
    swift = native "swiftc",

    -----------------------------------------------------
    -- Fortran
    -----------------------------------------------------
    f90 = native "gfortran",

    -----------------------------------------------------
    -- Zig (en Windows genera .exe sin -o)
    -----------------------------------------------------
    zig = (function()
      local build = shell.IS_WIN and 'zig build-exe "%"' or 'zig build-exe "%" -o "$fileBase"'
      local run = "$binRun"

      return {
        [BUILD .. " Build"] = build,
        [RUN .. " Run"] = run,
        [RUN .. BUILD .. " Build & Run"] = build .. " && $binRun",
      }
    end)(),

    -----------------------------------------------------
    -- HTML
    -----------------------------------------------------
    html = {
      [RUN .. " Live Server"] = function()
        if vim.fn.executable "live-server" == 0 then
          notify("live-server no está instalado", vim.log.levels.ERROR)
          return
        end
        open_runner('live-server "$dir"')
      end,
    },

    -----------------------------------------------------
    -- LaTeX
    -----------------------------------------------------
    tex = {
      [BUILD .. " Build PDF"] = function()
        local texfile = detect_main_tex()
        open_runner(string.format('latexmk -lualatex -interaction=nonstopmode -synctex=1 "%s"', texfile))
      end,

      [RUN .. BUILD .. " Continuous Build"] = function()
        local texfile = detect_main_tex()
        open_runner(string.format('latexmk -pvc -lualatex -interaction=nonstopmode -synctex=1 "%s"', texfile))
      end,

      [RUN .. " Open PDF"] = function()
        local texfile = detect_main_tex()
        local pdf = vim.fn.fnamemodify(texfile, ":r") .. ".pdf"

        if shell.IS_WIN then
          vim.fn.jobstart({ "cmd", "/c", "start", pdf }, { detach = true })
        else
          vim.fn.jobstart({ "xdg-open", pdf }, { detach = true })
        end
      end,

      [BUILD .. " Clean Aux Files"] = function()
        local texfile = detect_main_tex()
        open_runner(string.format('latexmk -c "%s"', texfile))
      end,
    },
  }

  -- Extensiones del usuario (sobrescriben o añaden)
  for ext, user_actions in pairs(config.options.actions or {}) do
    if next(user_actions) == nil then
      actions[ext] = nil -- extensión explícitamente deshabilitada
    else
      actions[ext] = vim.tbl_extend("force", actions[ext] or {}, user_actions)
    end
  end

  -- Alias para R (los scripts suelen usar extensión mayúscula)
  if actions.r then
    actions.R = vim.deepcopy(actions.r)
    actions.R.__order = nil
  end

  -- Orden alfabético estable en el selector
  for _, lang in pairs(actions) do
    local names = vim.tbl_keys(lang)
    table.sort(names)
    lang.__order = names
  end

  return actions
end

---------------------------------------------------------
-- Internals expuestos solo para tests
---------------------------------------------------------
M._internals = {
  java_has_main = java_has_main,
  java_package_of = java_package_of,
  java_source_root = java_source_root,
  find_pom_directory = find_pom_directory,
}

return M
