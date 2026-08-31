-- Catálogo de acciones por lenguaje: agrega los grupos de lenguajes
-- (compilados, scripting, especiales) en una sola tabla `actions`. Separado en
-- `actions/languages/*` para mantener los módulos pequeños y preparar el
-- action registry (P1).
--
-- `build(open_runner, notify)` devuelve la tabla cruda (sin overrides de
-- usuario ni orden); eso lo hace `actions.lua`.
local config = require "code-runner.config"
local shell = require "code-runner.shell"
local java = require "code-runner.actions.java"
local latex = require "code-runner.actions.latex"
local compiled = require "code-runner.actions.languages.compiled"
local script = require "code-runner.actions.languages.script"

local M = {}

function M.build(open_runner, notify)
  local RUN = config.options.icons.run
  local BUILD = config.options.icons.build

  local env = {
    RUN = RUN,
    BUILD = BUILD,
    shell = shell,
    open_runner = open_runner,
    notify = notify,
  }

  local actions = {
    -- JAVA
    java = {
      [RUN .. " Maven auto-run"] = java.maven_run,
      [BUILD .. " Maven build"] = "mvn -q clean package",
      [RUN .. " Spring Boot run"] = "mvn spring-boot:run",
      [BUILD .. " Spring Boot build"] = "mvn -q clean install",
      [RUN .. BUILD .. " Java smart run"] = java.plain_run,
    },

    -- Markdown (vista previa con glow)
    md = {
      [RUN .. " Preview"] = function()
        if vim.fn.executable "glow" == 0 then
          notify("glow no está instalado", vim.log.levels.ERROR)
          return
        end
        open_runner('glow "%"')
      end,
    },

    -- Makefile (se accede por filetype, sin extensión)
    make = {
      [BUILD .. " make"] = "make",
      [BUILD .. " make clean"] = "make clean",
    },

    -- HTML
    html = {
      [RUN .. " Live Server"] = function()
        if vim.fn.executable "live-server" == 0 then
          notify("live-server no está instalado", vim.log.levels.ERROR)
          return
        end
        open_runner('live-server "$dir"')
      end,
    },

    -- LaTeX
    tex = {
      [BUILD .. " Build PDF"] = latex.build_pdf,
      [RUN .. BUILD .. " Continuous Build"] = latex.continuous_build,
      [RUN .. " Open PDF"] = latex.open_pdf,
      [BUILD .. " Clean Aux Files"] = latex.clean_aux,
    },

    -- Lisps y similares
    scm = {
      [RUN .. " Run"] = 'guile "%"',
    },

    rkt = {
      [RUN .. " Run"] = 'racket "%"',
    },

    lisp = {
      [RUN .. " Run"] = 'sbcl --script "%"',
    },

    clojure = {
      [RUN .. " Run"] = 'clojure "%"',
    },
  }

  -- Grupos de lenguajes (compilados + scripting)
  local function merge(group)
    for lang, entry in pairs(group) do
      actions[lang] = entry
    end
  end

  merge(compiled.build(env))
  merge(script.build(env))

  return actions
end

return M
