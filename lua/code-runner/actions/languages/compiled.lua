-- Acciones de lenguajes compilados (binario nativo o build+run).
-- `build(env)` recibe { RUN, BUILD, shell } y devuelve el sub-catálogo.
local M = {}
local shell = require "code-runner.shell"

-- Archivo de proyecto C# (.sln o .csproj) en `dir`, o nil si no hay.
-- El orden .sln > primer .csproj sigue lo que msbuild/dotnet esperan.
function M.cs_project_file(dir)
  local sln = vim.fn.glob(dir .. "/" .. "*.sln")

  if sln ~= "" then
    return vim.fn.fnamemodify(sln, ":p")
  end

  local csproj = vim.fn.glob(dir .. "/" .. "*.csproj")

  if csproj ~= "" then
    return vim.fn.fnamemodify(csproj, ":p")
  end

  return nil
end

-- Comando de build C# según la plataforma y qué herramienta hay:
--   - con proyecto (.sln/.csproj): msbuild si existe, sino dotnet build
--   - .cs suelto: csc si existe (compilador de .NET en Windows), sino
--     `dotnet <file.cs>` (single-file ejecución, sin compilar a exe).
-- `tools` es un override para tests: `{ msbuild=bool, dotnet=bool, csc=bool }`.
-- Devuelve `{ cmd, cwd }` o nil si no hay ninguna herramienta.
function M.cs_build_cmd(dir, tools)
  tools = tools or {}
  local has_msbuild
  if tools.msbuild ~= nil then has_msbuild = tools.msbuild else has_msbuild = vim.fn.executable "msbuild" == 1 end
  local has_dotnet
  if tools.dotnet ~= nil then has_dotnet = tools.dotnet else has_dotnet = vim.fn.executable "dotnet" == 1 end
  local has_csc
  if tools.csc ~= nil then has_csc = tools.csc else has_csc = vim.fn.executable "csc" == 1 end

  local proj = M.cs_project_file(dir)

  -- Con proyecto: msbuild > dotnet build
  if proj then
    if has_msbuild then
      return { cmd = 'msbuild "' .. proj .. '"', cwd = dir }
    end

    if has_dotnet then
      return { cmd = 'dotnet build "' .. proj .. '"', cwd = dir }
    end

    return nil
  end

  -- .cs suelto (sin proyecto): csc > dotnet single-file
  if not has_csc and not has_dotnet then
    return nil
  end

  local file = vim.fn.expand "%:p"
  -- La acción es una función: no pasa por shell.substitute, así que el nombre
  -- base del exe se resuelve acá (no se puede dejar $fileBase literal).
  local exe = shell.quoted_run(vim.fn.fnamemodify(file, ":r") .. shell.EXE_SUFFIX)
  local cmd = has_csc and ('csc "/out:%s" "%s"'):format(exe, file) or 'dotnet "' .. file .. '"'

  return { cmd = cmd, cwd = dir }
end

-- Acción del catálogo: resuelve la raíz del proyecto C# y lanza el build.
local function cs_build()
  local project = require "code-runner.project"
  local terminal = require "code-runner.terminal"
  local notify = terminal.notify

  local dir = project.resolve("cs") or vim.fn.fnamemodify(vim.fn.expand "%:p", ":h")
  local spec = M.cs_build_cmd(dir)

  if not spec then
    notify("No se encontró msbuild ni dotnet/csc para compilar C#", vim.log.levels.ERROR)
    return
  end

  terminal.open(spec.cmd, nil, spec.cwd)
end

function M.build(env)
  local RUN, BUILD, shell = env.RUN, env.BUILD, env.shell

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

  return {
    -- C#
    cs = {
      [BUILD .. " Build"] = "dotnet build",
      [RUN .. " Run"] = "dotnet run",
      [BUILD .. " Build (msbuild)"] = cs_build,
    },

    -- C / C++
    c = native "gcc",
    cpp = native "g++",

    -- Go
    go = {
      [RUN .. " Run"] = 'go run "%"',
      [BUILD .. " Build"] = 'go build -o "$fileBase' .. shell.EXE_SUFFIX .. '"',
    },

    -- Rust
    rust = {
      [BUILD .. " Build"] = "cargo build",
      [RUN .. " Run"] = "cargo run",
    },

    -- Kotlin
    kt = {
      [BUILD .. " Compile"] = 'kotlinc "%" -include-runtime -d "$fileBase.jar"',
      [RUN .. " Run"] = 'java -jar "$fileBase.jar"',
      [RUN .. BUILD .. " Compile & Run"] = 'kotlinc "%" -include-runtime -d "$fileBase.jar" && java -jar "$fileBase.jar"',
    },

    -- Swift
    swift = native "swiftc",

    -- Fortran
    f90 = native "gfortran",

    -- Zig (en Windows genera .exe sin -o)
    zig = (function()
      local build = shell.IS_WIN and 'zig build-exe "%"' or 'zig build-exe "%" -o "$fileBase"'
      local run = "$binRun"

      return {
        [BUILD .. " Build"] = build,
        [RUN .. " Run"] = run,
        [RUN .. BUILD .. " Build & Run"] = build .. " && $binRun",
      }
    end)(),

    -- D
    d = {
      [RUN .. " Run"] = 'rdmd "%"',
    },

    adb = native "gnatmake",

    pas = {
      [BUILD .. " Compile"] = 'fpc "%" -o"$fileBase' .. shell.EXE_SUFFIX .. '"',
      [RUN .. " Run"] = "$binRun",
      [RUN .. BUILD .. " Compile & Run"] = 'fpc "%" -o"$fileBase' .. shell.EXE_SUFFIX .. '" && $binRun',
    },

    cu = native "nvcc",

    vala = {
      [RUN .. " Run"] = 'vala "%"',
    },
  }
end

return M
