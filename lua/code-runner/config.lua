local M = {}

M.defaults = {
  -- "volt" | "select" | "auto" (volt si está disponible, si no vim.ui.select)
  ui = "auto",
  picker = {
    title = "CodeRunner", -- el título se muestra como "⚡ <title> · <archivo>"
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
    -- Cerrar la terminal al terminar con éxito (exit code 0)
    autoclose = true,
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
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
