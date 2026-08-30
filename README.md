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

Suite propia sin dependencias externas (48 tests). Corre con:

```powershell
nvim --headless -l tests/run.lua
```

Cubre: sustitución de variables (`%`, `$fileBase`, `$binRun`, ...), wrapping de comandos PowerShell/bash, catálogo completo de acciones y orden estable, overrides de usuario, internals de Java (package/source-root), resolución por extensión/filetype, picker volt y fallback, y E2E que **compilan y ejecutan código real** (C, Java, Python) validando la salida. Los tests que requieren herramientas ausentes se marcan `SKIP` automáticamente.

Exit code `1` si algo falla, apto para CI.

