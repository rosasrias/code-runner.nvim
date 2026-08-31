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
- **Terminal identificada, coloreada y que no se come tu salida**: ventana horizontal/vertical o **flotante** (`direction = "float"`), con **título propio en color** (`title` + `hl_title` winbar en splits / borde en float) que indica la acción elegida (Run/Build) coloreada según su icono y el estado final (OK verde / fallo amarillo). Al terminar se queda abierta para ver el resultado, avisa con el código de salida y se cierra con `q`; si activás `autoclose = true` se cierra sola cuando termina OK y los fallos quedan en el quickfix. Reutiliza solo las terminales del plugin (buffer propio `code-runner`) y nunca deja la sesión sin ventanas
- **Quickfix con errores**: al terminar un build/test parsea la salida (gcc/clang/rustc/go 
`file:line:col`, Maven `[ERROR]`, MSVC `file(line,col)`, `--- FAIL:`) y llena la lista quickfix para saltar al error 
con `:cn` / `:cp`. Se abre automáticamente si el comando falla. Elegible: podés usar `vim.diagnostic` (signos en el 
búfer) o ambos con `quickfix.style`
- **`:checkhealth code-runner`**: verificá que las herramientas de los lenguajes que usás estén instaladas. Deriva qué binarios necesitan tus acciones y solo reporta los lenguajes que ya usaste (historial + buffer actual), así un toolchain sin instalar que no usás no molesta
- **Historial persistente**: cada ejecución se guarda (con su `cwd` y lenguaje) en `stdpath("data")`. `:CodeRunHistory` lo abre en el picker para re-ejecutar cualquier entrada; las repetidas suben sin duplicarse y muestran cuántas veces corrieron
- **Última ejecución persistida**: `:CodeRunLast` / `:CodeRunRestart` recuerdan la última acción incluso tras reiniciar Neovim (`last.json`; se puede desactivar con `last_run.persist = false`)
- Variables de contexto en cualquier comando (acciones, tasks de `.code-runner.lua` y `register_action`): `$testName` (test bajo el cursor), `$entry` (entry point: `fqcn` o `name`) y `$entryLine` (su línea), más `$stem` (nombre sin extensión), `%l` (línea del cursor) y `$project` (raíz del proyecto)
- **Profiles opcionales** (`profiles.enabled = true`): variantes release/benchmark donde la herramienta tiene un modo real — Rust (`cargo --release`), Go (`go test -bench`), C/C++ (`-O2`). Por defecto están apagados para no ensuciar el picker del zero-config

## Comandos

| Comando | Descripción |
| --- | --- |
| `:CodeRun` | Selecciona build/run en el picker |
| `:CodeRunLast` | Repite la última ejecución |
| `:CodeRunHistory` | Re-ejecuta desde el historial |
| `:CodeRunStop` | Detiene la ejecución en marcha (solo la del plugin) |
| `:CodeRunRestart` | Detiene la ejecución en marcha y repite la última acción |

## Estado de ejecución

`require("code-runner").state()` devuelve el estado central (copia):

```lua
{
  status = "idle|running|success|failed|cancelled",
  action = "Run",               -- label de la última ejecución
  cwd = "C:\\proj",             -- directorio del job
  filetype = "py",              -- key resuelta del archivo
  buf = 12,                     -- buffer de terminal del job actual
  code = 0,                     -- exit code (success/failed)
  started_at = ..., ended_at = ..., run_id = 3,
}
```

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
      title = "⚡ CodeRunner · Terminal", -- título del float / winbar de los splits
      hl_title = "ExBlue", -- color del título (grupos "Ex*" del tema ecotic)
      hl_status_ok = "ExGreen", -- estado "✓ terminó OK · q cierra"
      hl_status_err = "ExYellow", -- estado "✗ error N · q cierra"
      autoclose = false, -- false: queda abierta al terminar, cierra con q; true: se cierra sola si termina OK
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
    -- open=true abre la ventana solo cuando el comando falla con errores;
    -- close_on_success cierra esa ventana y vacía la lista al re-ejecutar bien.
    -- style elige el canal: "quickfix" (default) | "diagnostic" (vim.diagnostic)
    -- | "both":
    -- quickfix = {
    --   enabled = true,
    --   open = true,
    --   height = 8,
    --   close_on_success = true,
    --   style = "quickfix",
    -- },
    -- history: historial persistente de ejecuciones (:CodeRunHistory).
    -- enabled=false lo desactiva; max limita las entradas:
    -- history = {
    --   enabled = true,
    --   max = 50,
    -- },
    -- last_run: persistir la última ejecución para :CodeRunLast/:CodeRunRestart
    -- en una sesión nueva de Neovim:
    -- last_run = { persist = true },
    -- profiles: variantes release/benchmark donde la herramienta tiene un modo
    -- real (Rust --release, Go -bench, C/C++ -O2). false (default) no añade nada:
    -- profiles = { enabled = true },
  },
  keys = {
    { "<C-b>", "<cmd>CodeRun<cr>", desc = "Ejecutar código" },
    { "<leader>rr", "<cmd>CodeRunLast<cr>", desc = "Repetir ejecución" },
  },
}
```

## Colores (base46 / highlights)

El plugin define sus **propios grupos de resaltado** como defaults (enlazados a
`opts.picker`/`opts.terminal`), así picker y terminal comparten color y los
personalizás en un solo lugar desde tu capa de highlights:

| Grupo | Default | Para qué |
|---|---|---|
| `CodeRunnerActionRun` | `picker.hl_run` | ícono+acción con ícono de ejecutar |
| `CodeRunnerActionBuild` | `picker.hl_build` | ícono+acción con ícono de compilar |
| `CodeRunnerActionMisc` | `picker.hl_misc` | otras acciones / picker sin ícono |
| `CodeRunnerTermTitle` | `terminal.hl_title` | título `⚡ CodeRunner · Terminal` |
| `CodeRunnerTermOk` | `terminal.hl_status_ok` | estado `✓ terminó OK · q cierra` |
| `CodeRunnerTermErr` | `terminal.hl_status_err` | estado `✗ error N · q cierra` |

Ejemplo: título de la terminal con **fondo azul y texto negro**, desde tu
override de highlights (base46/NvChad, `lua/plugins/highlights.lua`):

```lua
M.override = {
  CodeRunnerTermTitle = { fg = "#000000", bg = "#2E5BFF", bold = true },
  CodeRunnerTermOk     = { fg = "#9ece6a" },
  CodeRunnerTermErr    = { fg = "#f7768e" },
}
```

## Uso

| Comando        | Descripción                          |
| -------------- | ------------------------------------ |
| `:CodeRun`     | Abre el selector de acciones         |
| `:CodeRunLast` | Repite la última acción ejecutada    |
| `:CodeRunStop` | Detiene la ejecución en marcha (solo la del plugin) |
| `:CodeRunRestart` | Detiene y repite la última acción |

En el picker volt: `j/k` o flechas para moverte, `1-9` selección rápida, `<CR>` o click para ejecutar, `q` para cerrar.

## Tests

Suite propia sin dependencias externas (212 tests). Corre con:

```powershell
nvim --headless -l tests/run.lua
```

Cubre: sustitución de variables (`%`, `$fileBase`, `$binRun`, `$testName`, `$stem`, `$project`, `%l`, ...), wrapping de comandos PowerShell/bash, catálogo completo de acciones y orden estable (60+ lenguajes), overrides de usuario, internals de Java (package/source-root/fqcn), resolución por extensión/filetype, picker volt y fallback, detección de tests y entry points por lenguaje, detección de la raíz del proyecto (marcadores por lenguaje, globs, monorepo, `max_depth`), parsing de errores a quickfix (gcc, Maven, MSVC, ANSI, go FAIL), terminal (direcciones, título/winbar, flotante, autoclose opt-in, cierre con `q`, reuso de ventana y `:CodeRunStop`), historial persistente (dedupe, límites, archivos corruptos, integración con `:CodeRun`/`:CodeRunHistory`) y E2E que **compilan y ejecutan código real** (C, Java, Python — incluida una compilación con error validada contra el quickfix). Los tests que requieren herramientas ausentes se marcan `SKIP` automáticamente.

Exit code `1` si algo falla, apto para CI.

