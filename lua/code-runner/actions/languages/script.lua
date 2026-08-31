-- Acciones de lenguajes interpretados / scripting (RUN directo).
-- `build(env)` recibe { RUN, BUILD, shell, open_runner, notify }.
local M = {}

function M.build(env)
  local RUN, BUILD, shell = env.RUN, env.BUILD, env.shell
  local open_runner, notify = env.open_runner, env.notify

  return {
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

    r = {
      [RUN .. " Run"] = 'Rscript "%"',
    },

    jl = {
      [RUN .. " Run"] = 'julia "%"',
    },

    pl = {
      [RUN .. " Run"] = 'perl "%"',
    },

    dart = {
      [RUN .. " Run"] = 'dart "%"',
    },

    ex = {
      [RUN .. " Run"] = 'elixir "%"',
    },

    exs = {
      [RUN .. " Run"] = 'elixir "%"',
    },

    hs = {
      [RUN .. " Run"] = 'runghc "%"',
    },

    ml = {
      [RUN .. " Run"] = 'ocaml "%"',
    },

    nim = {
      [RUN .. BUILD .. " Compile & Run"] = 'nim c -r "%"',
    },

    cr = {
      [RUN .. " Run"] = 'crystal "%"',
    },

    v = {
      [RUN .. " Run"] = 'v run "%"',
    },

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

    deno = {
      [RUN .. " Run"] = 'deno run "%"',
    },

    bun = {
      [RUN .. " Run"] = 'bun "%"',
    },

    groovy = {
      [RUN .. " Run"] = 'groovy "%"',
    },

    coffee = {
      [RUN .. " Run"] = 'coffee "%"',
    },

    fish = {
      [RUN .. " Run"] = 'fish "%"',
    },

    raku = {
      [RUN .. " Run"] = 'raku "%"',
    },

    tcl = {
      [RUN .. " Run"] = 'tclsh "%"',
    },

    vbs = {
      [RUN .. " Run"] = 'cscript //nologo "%"',
    },

    kts = {
      [RUN .. " Run"] = 'kotlinc -script "%"',
    },

    odin = {
      [RUN .. " Run"] = 'odin run "%"',
    },

    gd = {
      [RUN .. " Run"] = 'godot --headless --script "%"',
    },
  }
end

return M
