# Arquitectura — code-runner.nvim

Estado a la fecha de este documento. Estructura mayormente plana con **subcarpetas
solo donde el tamaño lo justifica** (`actions/*`, `context/*`, `terminal/*`); los
módulos se mantienen por debajo de ~300 líneas. P1 migrará a un action registry.

## Módulos y responsabilidades

```
lua/code-runner/
├── init.lua       Orquestación del flujo de usuario (setup, picker, repeat, state)
├── config.lua     Defaults + opts; única fuente de opciones
├── actions.lua    Ensambla el catálogo + overrides de usuario + alias R + orden
├── context.lua    API: detect() con cache + acción contextual "Run test"
├── project.lua    Raíz del proyecto por marcadores (por lenguaje + genéricos)
├── terminal.lua   Ciclo de vida del job: open/_on_exit/_close_current/_exit_hint, notify
├── quickfix.lua   Parseo de salida → quickfix; auto-cierre con éxito
├── history.lua    Historial persistente estructurado (cmd/cwd/key/count/ts)
├── last.lua       Última ejecución persistida (para run_last/restart en otra sesión)
├── state.lua      Estado central: idle|running|success|failed|cancelled + run_id + buf
├── picker.lua     Selector volt (+ fallback vim.ui.select)
├── shell.lua      Sustitución de variables + wrapping PowerShell/bash
├── highlight.lua  Grupos propios CodeRunner* (defaults) para tema/picker/terminal
│
├── actions/
│   ├── catalog.lua     Construye la tabla `actions` agregando los grupos
│   ├── java.lua        Smart run de Java (sin Maven) + auto-detección de Maven
│   ├── latex.lua       Acciones de LaTeX (detectar main, build/ver/limpiar)
│   ├── profiles.lua    Presets de perfiles opt-in (release/benchmark)
│   └── languages/
│       ├── compiled.lua  Lenguajes compilados (nativo C/C++/..., go, rust, kt...)
│       └── script.lua    Lenguajes interpretados/scripting (py, js, lua, ...)
│
├── context/
│   ├── test.lua      Detección de tests bajo el cursor (regex por lenguaje)
│   └── entry.lua     Entry points (main): treesitter con fallback regex
│
└── terminal/
    ├── buffer.lua    Identificación/localización de buffers de terminal del plugin
    └── ui.lua        Ventana (h/v/float), título/winbar coloreado, autoclose

plugin/code-runner.lua   Comandos :CodeRun :CodeRunLast :CodeRunHistory
```

## Dependencias (dirección del require)

```
config.*  ← (todo)
shell ← actions, terminal, (tests)
terminal ← actions, quickfix, highlight(indirecto vía config), init, terminal.{buffer,ui}
actions ← actions.{catalog,java,latex,languages.*}
context ← context.{test,entry}, init, tests
project ← init (project_cwd), shell (permite $project), tests
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

`:CodeRunLast` re-ejecuta `last_choice` (cache en memoria, recargado desde
`last.json` al arrancar). `:CodeRunHistory` → picker sobre `history.list()` →
re-ejecuta.

## Profiles (P1)

`actions/profiles.lua` expone `for_lang(env, key)` → tabla de acciones extra o
`nil`, con presets concretos donde la herramienta tiene un modo real: Rust
`--release`, Go `-bench`, C/C++ `-O2`. Es **opt-in** (`profiles.enabled=false`):
`actions.lua` solo las aplica al catálogo si está activado, al nivel built-in
(así el usuario/registry pueden sobrescribirlas). No hay motor genérico de
perfiles: sin esto, el picker del zero-config no gana variantes.

## Terminal

- `terminal.open(cmd, direction, cwd, label, cleanup)`:
  `shell.wrap_command(cmd)` → reutiliza la última ventana del plugin (buffer
  con nombre `code-runner`) o abre h/v/float → `termopen` con `on_exit`.
  `cleanup` (opcional) es una lista de rutas que se registran en
  `vim.b[buf].code_runner_cleanup` y se borran al terminar el job.
- `_on_exit(buf, code, cwd)` → borra los temporales registrados en
  `vim.b[buf].code_runner_cleanup` (éxito o error) → `quickfix.handle`
  (parseo → `setqflist`, `copen` si falla, cierre/limpieza si éxito) →
  autoclose opcional si OK → `_exit_hint` (notify + winbar/título coloreado +
  mapa `q`).
- Nunca mata terminales ajenas: solo opera sobre buffers con nombre `code-runner`.
- Modulado en tres piezas: `terminal.lua` (ciclo de vida del job + notify),
  `terminal/ui.lua` (ventana h/v/float, título/winbar, autoclose) y
  `terminal/buffer.lua` (identificación/localización de buffers del plugin).
  Los helpers `_open_window/_maybe_autoclose/_label_parts/_apply_window_label`
  se re-exportan desde `terminal` para conservar la API pública/tests.

## Quickfix

`M.parse` con reglas en orden (primero que matchea gana): `[ERROR] path:[line,col]`,
`[ERROR] path:[line]`, MSVC `path(line,col)`, `path:line:col:`, `path:line:`,
`--- FAIL:`, `File "path", line N` (Python). `handle` devuelve count de
entradas; en éxito con `close_on_success` cierra y vacía, con warnings refresca.

## Estado central (state.lua)

`terminal.open` registra `running` (action, cwd, filetype) antes de lanzar el
job; `_on_exit` registra `success`/`failed` con el exit code si el job sigue
siendo el actual; `_close_current` (tecla `q` o `:CodeRunStop`) registra
`cancelled` si corría. `state.reset()` devuelve a un `idle` completamente limpio
(borra `code`/`action`/`cwd`/etc.), útil para tests y reinicios.

**run_id**: cada ejecución incrementa una generación; el `on_exit` captura su
propio `run_id` y solo transiciona si sigue siendo el del estado. Así, un
on_exit asíncrono de un job viejo (reemplazado o cancelado) jamás pisa el
estado del que corre ahora.

**Reuso de terminal**: la ventana del plugin se reutiliza; `termopen` reinicia
el job en el mismo buffer (antes: se creaba otro buffer con el mismo nombre →
E95). Si el job anterior seguía corriendo, se cancela (`cancelled`) y se abre
desde cero. La key/filetype se resuelve ANTES de cambiar la ventana actual.

**Identificación del buffer propio**: `termopen` renombra el buffer a
`term://cwd//pid:cmd`, así que el nombre no basta. Al crearlo se marca con
`b:code_runner_term` (sobrevive al rename). La purga de huérfanos usa basename
exacto `code-runner` + buffer no listado, para no tocar terminales ajenas
(cuyo path puede contener "code-runner") ni archivos reales del usuario.

**stop (P0 #2)**: `init.stop()` cierra el buffer del job actual vía
`_close_current`; solo ese buffer. Terminales ajenas intactas.

**restart (P0 #3)**: `init.restart()` = `_stop_silent()` (stop sin notificar)
+ `run_last()`. Sin job → solo relanza; sin previa → WARN de `run_last`.

**Run last robusto (P0 #4)**: `last.lua` persiste la última elección en
`last.json` (mismo shape que `last_choice`). `init.setup` la recarga al
arrancar → `:CodeRunLast`/`:CodeRunRestart` sobreviven al reinicio.
`last_choice` en memoria es solo cache.

## Picker

- Volt si `ui` preferido y disponible; si no `vim.ui.select`.
- Items = tablas (historial) con `format_item`; `%` y `1-9`; click; `q`.
- Color por icono: `CodeRunnerActionRun/Build/Misc` (propios del plugin).

## Contexto

- Modulado en tres piezas: `context.lua` (API + cache + acción "Run test"),
  `context/test.lua` (detección de tests bajo el cursor) y `context/entry.lua`
  (entry points / main).
- `context.detect(key)`: lee el buffer completo + cursor; `enclosing_test`
  (en `context/test.lua`, regex por lenguaje: go/py/js/ts/lua/java/rust/php/rb
  + describe_patterns) y `find_entry` (en `context/entry.lua`: `ts_entry` TS
  con fallback `regex_entry`). Con cache por `{ bufnr, changedtick, cursor,
  key }`: se reutiliza el resultado si el buffer no cambió y el cursor sigue en
  la misma línea (evita re-parsear en cada `:CodeRun`). `context._clear_cache()`
  fuerza recomputación (tests).
- `context.test_action(key, ctx)` → (label, cmd): comando por lenguaje desde
  `config.options.context.test[key]` o default; `false` desactiva.
- `context.decorate(entry, key, ctx)`: inserta "Run test · <name>" al frente.
- **Variables de contexto para cualquier acción/task** (P1): `init.build_run`
  deriva `context_vars(cctx)` → `{ $testName, $entry, $entryLine }` del cctx
  detectado y las inyecta a la acción elegida (via `shell.substitute`), tanto a
  acciones del catálogo como a tasks de `.code-runner.lua` / `register_action`
  (no solo a la acción contextual de test). `$entry` usa `fqcn` si existe, si no
  `name`. `last_choice` persiste `vars`, así `run_last`/`restart` reproducen una
  task con su contexto original.

## Diseño a futuro (objetivo)

`core/` (runner, process, state, events) · `actions/registry` +
`actions/languages/*` (ya en marcha) · `context/{tests,entrypoint}` (ya) ·
`project/` · `terminal/manager` (parcial: `terminal/{buffer,ui}`) ·
`parsers/*` (gcc/msvc/maven/...).
Regla de mantenibilidad: **ningún archivo supera ~300 líneas**; modularizar
solo con una razón real, sin crear archivos chicos por decoración.

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
8. **`wrap_command` quote-aware**: divide `&&` solo fuera de comillas (al pasar
   cadenas con `&&` literal a PowerShell no se corrompen).