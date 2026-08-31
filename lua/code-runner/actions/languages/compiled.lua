-- Acciones de lenguajes compilados (binario nativo o build+run).
-- `build(env)` recibe { RUN, BUILD, shell } y devuelve el sub-catálogo.
local M = {}

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
