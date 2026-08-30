# Arquitectura — code-runner.nvim

Estado a la fecha de este documento. La estructura es **plana**; se migrará a
subcarpetas (`core/`, `actions/`, `context/`, ...) SOLO cuando haya una razón
real (mantener la simplicidad es un valor del proyecto).

## Módulos y responsabilidades

```
lua/code-runner/
├── init.lua       Orquestación del flujo de usuario (setup, picker, repeat)
├── config.lua     Defaults + opts; única fuente de opciones
├── actions.lua    Catálogo de acciones por extensión/filetype + overrides
├── context.lua    Detección: test bajo el cursor + entry point (TS con fallback regex)
├── project.lua    Raíz del proyecto por marcadores (por lenguaje + genéricos)
├── terminal.lua   Ventanas (h/v/float), título/winbar, estado, q, autoclose
├── quickfix.lua   Parseo de salida → quickfix; auto-cierre con éxito
├── history.lua    Historial persistente estructurado (cmd/cwd/key/count/ts)
├── picker.lua     Selector volt (+ fallback vim.ui.select)
├── shell.lua      Sustitución de variables + wrapping PowerShell/bash
└── highlight.lua  Grupos propios CodeRunner* (defaults) para tema/picker/terminal

plugin/code-runner.lua   Comandos :CodeRun :CodeRunLast :CodeRunHistory
```

## Dependencias (dirección del require)

```
config.*  ← (todo)
shell ← actions, terminal, (tests)
terminal ← actions, quickfix, highlight(indirecto vía config), init
project ← init (project_cwd), shell (permite $project), tests
context ← init (detect/decorate), tests
history ← init
picker ← init, tests
highlight ← init.setup
quickfix ← terminal._on_exit
```

No hay ciclos de require problematicos; `terminal.notify` lo consume todo el
mundo (incluido `quickfix` indirectamente vía `_exit_hint`).

## Flujo de ejecución (Ctrl-b / :CodeRun)

```
plugin/code-runner.lua → init.build_run
  ├─ autosave()                       (si autosave y buffer modificado)
  ├─ build_entry()                    ext → fallback filetype → actions[key]
  ├─ context.detect(key)              cctx { key, test, entry }
  ├─ context.decorate(entry, key)     inserta "Run test" contextual al frente
  ├─ project_cwd(key)                 raíz del proyecto o dir del archivo
  ├─ título contextual del picker     "⚡ CodeRunner · <file> [ · main:NN]"
  ├─ picker.select(...)               volt o vim.ui.select; callback on_choice
  └─ execute_action(action, vars, cwd)
        ├─ si función → pcall(action) (java smart run, maven, latex, ...)
        └─ si string → shell.substitute → terminal.open(cmd) → history.add
```

`:CodeRunLast` re-ejecuta `last_choice` (en memoria; pendiente respaldo
persistente). `:CodeRunHistory` → picker sobre `history.list()` → re-ejecuta.

## Terminal

- `terminal.open(cmd, direction, cwd, label)`:
  `shell.wrap_command(cmd)` → reutiliza la última ventana del plugin (buffer
  con nombre `code-runner`) o abre h/v/float → `termopen` con `on_exit`.
- `_on_exit(buf, code, cwd)` → `quickfix.handle` (parseo → `setqflist`,
  `copen` si falla, cierre/limpieza si éxito) → autoclose opcional si OK →
  `_exit_hint` (notify + winbar/título coloreado + mapa `q`).
- Nunca mata terminales ajenas: solo opera sobre buffers con nombre `code-runner`.

## Quickfix

`M.parse` con reglas en orden (primero que matchea gana): `[ERROR] path:[line,col]`,
`[ERROR] path:[line]`, MSVC `path(line,col)`, `path:line:col:`, `path:line:`,
`--- FAIL:`, `File "path", line N` (Python). `handle` devuelve count de
entradas; en éxito con `close_on_success` cierra y vacía, con warnings refresca.

## Picker

- Volt si `ui` preferido y disponible; si no `vim.ui.select`.
- Items = tablas (historial) con `format_item`; `%` y `1-9`; click; `q`.
- Color por icono: `CodeRunnerActionRun/Build/Misc` (propios del plugin).

## Contexto

- `context.detect(key)`: lee el buffer completo + cursor; `enclosing_test`
  (regex por lenguaje: go/py/js/ts/lua/java/rust/php/rb + describe_patterns) y
  `find_entry` (`ts_entry` TS con fallback `regex_entry`). Sin cache aún.
- `context.test_action(key, ctx)` → (label, cmd): comando por lenguaje desde
  `config.options.context.test[key]` o default; `false` desactiva.
- `context.decorate(entry, key, ctx)`: inserta "Run test · <name>" al frente.

## Diseño a futuro (objetivo)

`core/` (runner, process, state, events) · `actions/registry` +
`actions/languages/*` · `context/{tests,entrypoint,treesitter,cache}` ·
`project/` · `terminal/manager` · `parsers/*` (gcc/msvc/maven/...).
Migrar módulos solo cuando exista una razón real; no crear archivos chicos por
decoración.

## Decisiones de diseño clave

1. **Acciones = tabla** `{ [ext] = { [label] = cmd|fn } }`, con `__order` para
   el selector. Extensión de usuario vía `config.options.actions` (merge
   `"force"`; tabla vacía = deshabilitar). Hacia un registry explícito en P1.
2. **Runner por terminal gestionada propia**: no tocar terminales del usuario;
   identificador por nombre de buffer.
3. **Quickfix como canal de errores** (no `vim.diagnostic` todavía).
4. **Fallbacks en cascada** (picker, tests con TS→regex, project markers) para
   maximizar zero-config.
5. **Historial estructurado** ya persiste (cmd/cwd/key/count/ts) — base para
   run-last robusto en P0.
6. **Windows = ciudadano de primera** (PowerShell, `.exe`, rutas con espacios).
7. **Tests propios** (runner.lua) sin framework externo + E2E con compilación real.