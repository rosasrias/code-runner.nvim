# ⚡ code-runner.nvim

![CI](https://img.shields.io/github/actions/workflow/status/rosasrias/code-runner.nvim/ci.yml?branch=main&label=CI)

Runner de código para Neovim con selector de acciones (picker propio basado en [nvzone/volt](https://github.com/nvzone/volt), con fallback a `vim.ui.select`).

## Características

- Selector de acciones por filetype: Java (Maven/Spring/smart run), C, C++, C#, Go, Rust, Kotlin (+ `.kts`), Zig, Swift, Fortran, Python, JS/TS (+ Deno, Bun), PHP, Ruby (+ Raku), Shell/zsh/fish, Lua, PowerShell, Batch, VBScript, R, Julia, Perl, Dart, Elixir, Haskell, OCaml, Nim, Crystal, V, Scala (+ clojure/clojure-script), Groovy, CoffeeScript, Erlang, F#, D, Ada, Pascal, Cuda, Scheme/Guile, Racket, Common Lisp, Tcl, Odin, Godot, Vala, Markdown, Makefile, HTML, LaTeX
- Búsqueda de acciones por extensión **y por filetype** (ej: `Makefile` no tiene extensión)
- `Java smart run`: detecta package + método main, compila con `javac` a un directorio temporal y ejecuta con el classpath correcto
- `Maven auto-run`: busca `pom.xml`, deduce la clase principal y ejecuta `mvn exec:java`
- Repetir la última ejecución sin abrir el selector (`:CodeRunLast`)
- Autosave opcional antes de ejecutar
- Comandos con múltiples `&&` soportados en PowerShell y bash
- Rutas con espacios seguras; binarios `.exe` correctos en Windows
- **Contexto inteligente**: si el cursor está dentro de un test, la primera acción del picker es `Run test` con su comando por lenguaje (Go, Python, JS/TS, Lua, Rust, Java, PHP, Ruby). Detecta el test bajo el cursor (treesitter con fallback por línea) y el entry point (`main` / `__main__`) para mostrar `· main:NN` en el título
- **Ejecuta desde la raíz del proyecto**: sube buscando marcadores (`go.mod`, `pom.xml`, `package.json`, `.git`, ...) y lanza el comando en ese directorio (`go test`, `pytest`, `mvn test`, ...). Fallback: directorio del archivo
- **Terminal con autoclose**: ventana horizontal/vertical o **flotante** (`direction = "float"`); se cierra sola al terminar con éxito (`autoclose`, configurable) y si falla se queda abierta con el quickfix listo. Reutiliza solo las terminales del plugin (buffer propio `code-runner`) y nunca deja la sesión sin ventanas
- **Quickfix con errores**: al terminar un build/test parsea la salida (gcc/clang/rustc/go `file:line:col`, Maven `[ERROR]`, MSVC `file(line,col)`, `--- FAIL:`) y llena la lista quickfix para saltar al error con `:cn` / `:cp`. Se abre automáticamente si el comando falla
- **Historial persistente**: cada ejecución se guarda (con su `cwd` y lenguaje) en `stdpath("data")`. `:CodeRunHistory` lo abre en el picker para re-ejecutar cualquier entrada; las repetidas suben sin duplicarse y muestran cuántas veces corrieron
- Variables de contexto: `$testName` (test bajo el cursor), `$stem` (nombre sin extensión), `%l` (línea del cursor) y `$project` (raíz del proyecto) en cualquier comando

## Comandos

| Comando | Descripción |
| --- | --- |
| `:CodeRun` | Selecciona build/run en el picker |
| `:CodeRunLast` | Repite la última ejecución |
| `:CodeRunHistory` | Re-ejecuta desde el historial |

## Instalación

Con [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  dir = "C:/Users/rosas/Documents/code/plugins/code-runner.nvim",
  dependencies = { "nvzone/volt" }, -- opcional, para el picker
  opts = {
    ui = "auto", -- "volt" | "select" | "auto"
    terminal = {
      direction = "horizontal", -- "horizontal" | "vertical" | "float"
      height = 12,
      vertical_width = 45,
      float = { width = 0.8, height = 0.6 }, -- fracciones del editor
      autoclose = true, -- cerrar la terminal al terminar con éxito
    },
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
    -- quickfix: errores de build/test a la lista quickfix (:cn/:cp).
    -- open=true abre la ventana solo cuando el comando falla con errores:
    -- quickfix = {
    --   enabled = true,
    --   open = true,
    --   height = 8,
    -- },
    -- history: historial persistente de ejecuciones (:CodeRunHistory).
    -- enabled=false lo desactiva; max limita las entradas:
    -- history = {
    --   enabled = true,
    --   max = 50,
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

Suite propia sin dependencias externas (121 tests). Corre con:

```powershell
nvim --headless -l tests/run.lua
```

Cubre: sustitución de variables (`%`, `$fileBase`, `$binRun`, `$testName`, `$stem`, `$project`, `%l`, ...), wrapping de comandos PowerShell/bash, catálogo completo de acciones y orden estable (60+ lenguajes), overrides de usuario, internals de Java (package/source-root/fqcn), resolución por extensión/filetype, picker volt y fallback, detección de tests y entry points por lenguaje, detección de la raíz del proyecto (marcadores por lenguaje, globs, monorepo, `max_depth`), parsing de errores a quickfix (gcc, Maven, MSVC, ANSI, go FAIL), terminal (direcciones, flotante y autoclose al éxito), historial persistente (dedupe, límites, archivos corruptos, integración con `:CodeRun`/`:CodeRunHistory`) y E2E que **compilan y ejecutan código real** (C, Java, Python — incluida una compilación con error validada contra el quickfix). Los tests que requieren herramientas ausentes se marcan `SKIP` automáticamente.

Exit code `1` si algo falla, apto para CI.

