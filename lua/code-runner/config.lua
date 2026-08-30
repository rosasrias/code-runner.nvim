local M = {}

M.defaults = {
  -- "volt" | "select" | "auto" (volt si está disponible, si no vim.ui.select)
  ui = "auto",
  picker = {
    title = "CodeRunner", -- el título se muestra como "⚡ <title> · <archivo>"
    -- Colores de la acción en el picker y la terminal. Son los targets por
    -- default de los grupos propios CodeRunnerActionRun/Build/Misc (ver
    -- lua/code-runner/highlight.lua): se pueden tocar en base46.
    hl_selected = "ExBlue",
    hl_run = "ExGreen",
    hl_build = "ExYellow",
    hl_misc = "ExGreen",
    hl_hint = "CommentFg",
  },
  terminal = {
    direction = "horizontal", -- "horizontal" | "vertical" | "float"
    height = 12,
    vertical_width = 45,
    float = {
      -- Fracciones del editor para la terminal flotante
      width = 0.8,
      height = 0.6,
    },
    -- Título de la ventana de la terminal (winbar en splits, título en float).
    -- Se le concatena la acción elegida (Run/Build) coloreada según su icono.
    title = "⚡ CodeRunner · Terminal",
    -- El plugin expone sus propios grupos de resaltado (CodeRunnerTermTitle,
    -- CodeRunnerTermOk, CodeRunnerTermErr, CodeRunnerActionRun/Build/Misc) que
    -- por default enlazan a los colores de abajo. Vos podés personalizarlos en
    -- tu capa de highlights (base46 / override) o cambiando aquí los targets.
    hl_title = "ExBlue",
    hl_status_ok = "ExGreen",
    hl_status_err = "ExYellow",
    -- Cerrar la terminal al terminar con éxito (exit code 0).
    -- Con false (default) la terminal se queda abierta, muestra la salida y
    -- cierra con "q"; con true se cierra sola cuando el proceso termina OK.
    autoclose = false,
  },
  icons = {
    run = "",
    build = "󱤵 ",
  },
  autosave = true,
  context = {
    -- Detección de tests bajo el cursor y del entry point (main)
    enabled = true,
    -- Sobrescribir el comando de test por lenguaje (false desactiva ese lenguaje)
    -- ej: { go = "gotestsum -- -run \"^$testName$\"", py = false }
    test = {},
  },
  project = {
    -- Ejecutar desde la raíz del proyecto (sube buscando go.mod, pom.xml,
    -- package.json, .git, ...). Fallback: directorio del archivo.
    enabled = true,
    -- Marcadores extra (además de los por lenguaje y .git/.hg/.svn)
    markers = {},
    -- Límite de directorios a subir antes de rendirse
    max_depth = 30,
  },
  quickfix = {
    -- Al terminar un build/test, parsear la salida y llenar la lista
    -- quickfix para saltar a los errores (:cn / :cp)
    enabled = true,
    -- Abrir la ventana quickfix cuando el comando falla con errores
    open = true,
    height = 8,
    -- Cerrar la ventana y vaciar la lista cuando la ejecución termina bien
    -- (los errores ya se corrigieron). Con warnings parseables se refresca
    -- la lista y la ventana queda abierta.
    close_on_success = true,
  },
  history = {
    -- Historial de ejecuciones (persistente, en stdpath("data")). El
    -- selector :CodeRunHistory permite re-ejecutar y ver qué corre más.
    enabled = true,
    -- Número máximo de entradas guardadas
    max = 50,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
