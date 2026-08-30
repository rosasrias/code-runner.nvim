# ⚡ code-runner.nvim

Runner de código para Neovim con selector de acciones (picker propio basado en [nvzone/volt](https://github.com/nvzone/volt), con fallback a `vim.ui.select`).

## Características

- Selector de acciones por filetype: Java (Maven/Spring/smart run), C, C++, C#, Go, Rust, Kotlin, Zig, Swift, Fortran, Python, JS/TS, PHP, Ruby, Shell/zsh, Lua, PowerShell, Batch, R, Julia, Perl, Dart, Elixir, Haskell, OCaml, Nim, Crystal, V, Scala, Clojure, Erlang, F#, Markdown, Makefile, HTML, LaTeX
- Búsqueda de acciones por extensión **y por filetype** (ej: `Makefile` no tiene extensión)
- `Java smart run`: detecta package + método main, compila con `javac` a un directorio temporal y ejecuta con el classpath correcto
- `Maven auto-run`: busca `pom.xml`, deduce la clase principal y ejecuta `mvn exec:java`
- Repetir la última ejecución sin abrir el selector (`:CodeRunLast`)
- Autosave opcional antes de ejecutar
- Comandos con múltiples `&&` soportados en PowerShell y bash
- Rutas con espacios seguras; binarios `.exe` correctos en Windows
- **Contexto inteligente**: si el cursor está dentro de un test, la primera acción del picker es `Run test` con su comando por lenguaje (Go, Python, JS/TS, Lua, Rust, Java, PHP, Ruby). Detecta el test bajo el cursor (treesitter con fallback por línea) y el entry point (`main` / `__main__`) para mostrar `· main:NN` en el título
- **Ejecuta desde la raíz del proyecto**: sube buscando marcadores (`go.mod`, `pom.xml`, `package.json`, `.git`, ...) y lanza el comando en ese directorio (`go test`, `pytest`, `mvn test`, ...). Fallback: directorio del archivo
- Variables de contexto: `$testName` (test bajo el cursor), `$stem` (nombre sin extensión), `%l` (línea del cursor) y `$project` (raíz del proyecto) en cualquier comando

## Instalación

Con [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  dir = "C:/Users/rosas/Documents/code/plugins/code-runner.nvim",
  dependencies = { "nvzone/volt" }, -- opcional, para el picker
  opts = {
    ui = "auto", -- "volt" | "select" | "auto"
    terminal = { direction = "horizontal", height = 12 },
    autosave = true,
    picker = {
      title = "CodeRunner", -- título del picker: "⚡ CodeRunner · App.java"
      hl_selected = "ExBlue",
      hl_run = "ExGreen",   -- acciones de ejecución
      hl_build = "ExYellow", -- acciones de compilación/build
      hl_misc = "ExLightGrey",
      hl_hint = "CommentFg",
    },
    -- actions permite añadir o sobrescribir acciones por extensión:
    -- actions = { go = { [" Run custom"] = "go vet %" } },
    -- context: detección de tests bajo el cursor y entry point (main).
    -- Comandos por lenguaje (context.test.<lang>), false para desactivar uno:
    -- context = {
    --   enabled = true,
    --   test = {
    --     go = 'go test -run "^$testName$" -v',          -- default por lenguaje
    --     py  = false,                                   -- desactiva Python
    --   },
    -- },
    -- project: ejecutar desde la raíz del proyecto.
    -- markers añade marcadores extra; max_depth limita la subida:
    -- project = {
    --   enabled = true,
    --   markers = { ".nx", "pyrightconfig.json" },
    --   max_depth = 30,
    -- },
  },
  keys = {
    { "<C-b>", "<cmd>CodeRun<cr>", desc = "Ejecutar código" },
    { "<leader>rr", "<cmd>CodeRunLast<cr>", desc = "Repetir ejecución" },
  },
}
```

## Uso

| Comando        | Descripción                          |
| -------------- | ------------------------------------ |
| `:CodeRun`     | Abre el selector de acciones         |
| `:CodeRunLast` | Repite la última acción ejecutada    |

En el picker volt: `j/k` o flechas para moverte, `1-9` selección rápida, `<CR>` o click para ejecutar, `q` para cerrar.

## Tests

Suite propia sin dependencias externas (84 tests). Corre con:

```powershell
nvim --headless -l tests/run.lua
```

Cubre: sustitución de variables (`%`, `$fileBase`, `$binRun`, `$testName`, `$stem`, `$project`, `%l`, ...), wrapping de comandos PowerShell/bash, catálogo completo de acciones y orden estable, overrides de usuario, internals de Java (package/source-root/fqcn), resolución por extensión/filetype, picker volt y fallback, detección de tests y entry points por lenguaje, detección de la raíz del proyecto (marcadores por lenguaje, globs, monorepo, `max_depth`) y E2E que **compilan y ejecutan código real** (C, Java, Python) validando la salida. Los tests que requieren herramientas ausentes se marcan `SKIP` automáticamente.

Exit code `1` si algo falla, apto para CI.

