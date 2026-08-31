# CHANGELOG — code-runner.nvim

Cambios arquitectónicos y features importantes. Lanzamientos una vez existan tags.

## P2 · `:checkhealth code-runner`

- Nuevo `health.lua`: diagnostica core (config/canal de errores) y la
  disponibilidad de las herramientas reales de las acciones.
- Las herramientas se **derivan** del catálogo resuelto (primer token de cada
  `command` string; ignora `$vars` y rutas: `cargo`, `go`, `mvn`, `dotnet`...)
  y solo se revisan para los **lenguajes que el usuario usa** (historial +
  buffer actual): un toolchain no instalado no es error si no se ha usado.
  `glow` se reporta como recomendada para preview de Markdown.
- +5 tests (derivación). Total: **212 tests verdes**.

## P2 · Canal de errores `vim.diagnostic` (elegible)

- `quickfix.style` ahora es `"quickfix"` (default) | `"diagnostic"` | `"both"`.
- Nuevo `diagnostics.lua`: vuelca las entradas parseadas a `vim.diagnostic`
  bajo un namespace propio (`code-runner`) que solo limpia lo suyo; agrupa por
  buffer, coordenadas en base 0, `--- FAIL:` (sin archivo) se descarta.
- La quickfix se mantiene intacta como canal por defecto.
- +6 tests (diagnostics + routing). Total: **207 tests verdes**.

## P1 · Profiles (presets opt-in)

- Nuevo `actions/profiles.lua`: variantes de perfil para lenguajes con un modo
  real, aplicadas al catálogo al nivel built-in (el usuario/registry pueden
  sobrescribirlas):
  - **Rust**: `cargo build --release` y `cargo run --release`.
  - **Go**: `go test -bench . -benchmem`.
  - **C/C++**: compilar y compile&run con `-O2` (release).
- **Opt-in**: `profiles.enabled=false` por defecto → el picker del zero-config
  no cambia. Se activa con `profiles.enabled=true`. No hay motor genérico de
  perfiles: solo presets donde la herramienta difiere de verdad.
- **Fase P1 completa.** +7 tests (profiles). Total: **201 tests verdes**.

## P1 · Custom tasks con variables de contexto

- Las acciones y tasks (incl. las definidas en `.code-runner.lua`) reciben ahora
  las **variables de contexto** derivadas del contexto detectado al ejecutar:
  - `$testName` — nombre del test bajo el cursor (antes solo disponible en la
    acción contextual "Run test").
  - `$entry` — entry point del archivo (el `fqcn` si existe, si no el `name`).
  - `$entryLine` — línea del entry point.
- `context_vars(cctx)` en `init.lua` deriva esas vars; `build_run` las inyecta a
  cualquier acción elegida. Así una task `command = 'go test -run "$testName"'`
  funciona sin ser la acción contextual de test.
- `last_choice` persiste `vars`; `run_last`/`:CodeRunRestart` reproducen la task
  con las mismas variables (fiel al contexto original).
- +6 tests (integración de task con contexto end-to-end y run_last con vars).
  Total: **194 tests verdes**.

## Sesión actual (P0: auditoría + contexto persistente)

- Auditoría completa de arquitectura, tests y CI.
- Nuevos `.opencode/` (README, ROADMAP, ARCHITECTURE, CHANGELOG, TODO) y `AGENTS.md`.
- Estado real documentado: 136 tests verdes (ninguna feature nueva en esta sesión).

## Estado central de ejecución + state() API

- Nuevo `lua/code-runner/state.lua`: `idle|running|success|failed|cancelled`. Cada
  job nuevo incrementa un `run_id` (generación): un `on_exit` asíncrono de un job
  viejo jamás pisa el estado del actual. API pública `require("code-runner").state()`.
- `terminal.open` registra `running` (action/cwd/filetype del buffer previo a
  cambiar de ventana); `_on_exit` registra `success`/`failed` con el exit code;
  cerrar con `q` mientras corre registra `cancelled`.
- **Bug latente destapado y corregido (E95)**: al re-ejecutar `:CodeRun` con
  `autoclose=false` (o sin cerrar con `q`), se creaba un segundo buffer de
  terminal nombrado `code-runner` y `nvim_buf_set_name` lanzaba
  `E95: Buffer with this name already exists` → la segunda ejecución fallaba.
  Ahora se reutiliza la ventana/buffer de terminal existente (`termopen` reinicia
  en él) y se limpia su `modified`; si el job anterior seguía corriendo, se
  cancela y se abre desde cero. +11 tests (state: 11, incl. 2 de regresión E95).

## :CodeRunStop (nunca procesos ajenos)

- `init.stop()`: detiene SOLO el job cuyo buffer registra el estado (via
  `terminal._close_current`: cierra la ventana y elimina el buffer → el job de
  terminal muere con él). Sin job en marcha → WARN. Job con buffer ya muerto →
  marca `cancelled`.
- Comando `:CodeRunStop` en `plugin/code-runner.lua`.
- **Identificación de buffers del plugin endurecida**: `termopen` renombra el
  buffer a `term://cwd//pid:cmd`, así que el nombre dejaba de ser `code-runner`.
  Ahora se marca el buffer al crearlo (`b:code_runner_term`) — sobrevive al
  rename — y la purga de huérfanos usa basename exacto + buffer sin listar
  (protege archivos reales del usuario y terminales ajenas cuyo path solo
  contiene "code-runner", p.ej. dentro del propio repo; `buflisted` acepta
  forma 0/1 y true/false según la build). +3 tests (stop: 3).

## :CodeRunRestart

- `init.restart()` = `_stop_silent()` (stop sin notificar) + `run_last()`. Sin
  job en marcha, aborta el stop; sin ejecución previa, `run_last` avisa WARN.
- `init.stop()` refactoriza a `_stop_silent()` (sin notificación) para
  reutilizarlo; la API pública `stop()` queda igual de efectiva (cancela el
  job y libera su buffer, terminales ajenas intactas) pero ya no "notifica
  cancelación" — el gesto del usuario es la confirmación.
- Comando `:CodeRunRestart` en `plugin/code-runner.lua`. +2 tests (restart: 2).

## Run Last robusto (persiste la última acción)

- Nuevo `lua/code-runner/last.lua`: guarda la última ejecución en
  `stdpath("data")/code-runner/last.json` (misma forma que `last_choice`).
  `init.setup` la recarga al arrancar, así `:CodeRunLast` y `:CodeRunRestart`
  siguen funcionando en una sesión nueva de Neovim. `last_choice` en memoria
  queda como cache de uso rápido.
- `build_run`/`run_history` persisten vía `remember_choice()`.
- Nueva opción `last_run.persist` (default true) para desactivarlo.
- +6 tests (last: 5, integración setup-reload: 1).

## P1 · `.code-runner.lua` por proyecto

- Nuevo `projectrc.lua`: carga `.code-runner.lua` desde la raíz del proyecto
  (mismo root de `project.resolve`), cacheado por raíz y con `pcall` seguro.
- El dotfile puede:
  - llamar a la API: `require("code-runner").register_action{...}`; o
  - devolver tasks: `return { tasks = { name = { filetypes, kind, command } } }`
    (se registran vía el registry, máxima prioridad).
- Se carga en `build_run` antes de construir el catálogo → las tasks del
  proyecto aparecen en el picker de ese proyecto.
- Opción `projectrc.enabled` (default true) y `projectrc.clear_cache()`.
- **188 tests verdes.**

## P1 · API pública completa

- `require("code-runner")` expone ya: `run` (alias de `build_run`),
  `run_last`, `run_history`, `stop`, `restart`, `state(context?)`, `context(key)`,
  `register_action`, `unregister_action`, `list_registered_actions`.
- `context(key)` con `key` opcional (extensión → filetype del buffer).
- **183 tests verdes.**

## P1 · Action registry + register_action

- Nuevo `actions/registry.lua`: registrar/sobrescribir/deshabilitar acciones
  por lenguaje de forma programática.
  ```lua
  require("code-runner").register_action {
    id = "mytool", filetypes = { "py" }, kind = "run", command = "mytool %",
  }
  ```
  - `kind` run|build|test|misc determina el icono del label del picker.
  - `command` (string sustituible) o `run` (función).
  - `name` (opcional) personaliza el label; default = `id`.
  - `disable=true` elimina el lenguaje del catálogo.
  - `unregister_action(id)` y `list_registered_actions()`.
- Se aplica en `actions.get_actions()` como override de máxima prioridad
  (built-in < config.options.actions < registry).
- API en `require("code-runner")`: `register_action` / `unregister_action` /
  `list_registered_actions`. **181 tests verdes.**

## Refactor de arquitectura: modularización (módulos <= ~300 líneas)

- Regla nueva (AGENTS.md/ARCHITECTURE): ningún archivo supera ~300 líneas.
- `actions.lua` 597→54: catálogo movido a `actions/` (catalog.lua agrega los
  grupos; java.lua smart run + Maven; latex.lua; languages/compiled.lua y
  script.lua). `_internals` preservado para tests.
- `context.lua` 535→147: detección en `context/test.lua`, entry points en
  `context/entry.lua`. `_internals`/`detect`/cache intactos.
- `terminal.lua` 412→241: identificador/locación de buffers en
  `terminal/buffer.lua`, UI en `terminal/ui.lua`; helpers re-exportados desde
  `terminal` para conservar la API pública sujeta a tests.
- Sin cambios de comportamiento: **172 tests verdes**.

## Cleanup de temporales Java + state.reset()

- El smart run de Java creaba `vim.fn.tempname()` en `actions.lua` y nunca se
  borraba: quedaban clases compiladas en disco. Ahora `terminal.open` acepta
  una lista de rutas (`cleanup`) y las registra en `vim.b[buf].code_runner_cleanup`; `terminal._on_exit` las borra (`vim.fn.delete(p, "rf")`) al terminar el job, con éxito o error. +2 tests.
- Nueva `state.reset()`: vuelve a un estado `idle` completamente limpio
  (borra `code`/`action`/`cwd`/etc.), para tests y reinicios sin arrastrar
  campos del job anterior. Resuelve acoplamiento de orden entre specs.

## context.lua: cache de detección

- `context.detect` re-parseaba el buffer (TS/regex) en cada `:CodeRun`. Ahora
  cachea el resultado por `{ bufnr, changedtick, cursor, key }`: reutiliza si
  el buffer no cambió y el cursor sigue en la misma línea; no comparte entre
  idiomas; `context._clear_cache()` fuerza recomputación (tests). +5 tests.

## shell.lua: wrap_command respeta `&&` dentro de comillas

- `vim.split(cmd, "&&", { plain = true })` partía también un `&&` literal
  dentro de `"..."`/`'...'`, reescribiéndolo mal para PowerShell y corrompiendo
  strings per se (p.ej. un argumento `"a && b"`). Nuevo `split_and_outside_quotes`
  (tokenizer con estado de comillas, incl. escapes `\"`) que solo divide en `&&`
  fuera de comillas. +3 tests (wrap_command).

## 33ec363 — Quickfix se cierra y vacía sola en éxito

- `quickfix.close_on_success` (default `true`): al re-ejecutar con éxito la
  ventana quickfix se cierra y la lista se vacía; con warnings parseables la
  lista se refresca sin forzar apertura. +3 tests.

## 052292b — E42 "No Errors" corregido

- Regla de parseo para tracebacks de Python (`File "path", line N`).
- `quickfix.handle` devuelve el conteo; el aviso deja de prometer quickfix
  cuando no hay entradas parseables. +3 tests.

## c1afb77 — Crash tree-sitter en detección de main

- `node:start()[1]` (bug latente) → `node:start() + 1` (row, col).
- Query python `if __name__` corregida a `(string) @main_str` + línea desde el
  `if_statement` contenedor. +2 tests de regresión.

## 2b07914 — Grupos de resaltado propios

- `highlight.lua`: `CodeRunnerActionRun/Build/Misc`, `CodeRunnerTermTitle/Ok/Err`
  definidos con `default=true` enlazados a `opts.picker`/`opts.terminal`;
  personalizables en base46.

## 3cb437a — Título y mensajes en color

- Winbar/float `title` por segmentos con `%#Grupo#texto%*` / array de arrays.
- `M.notify` colorea por nivel con el provider del core (INFO→Question, WARN→
  WarningMsg, ERROR→ErrorMsg); respeta proveedores propios (nvim-notify).

## a16e5b4 — Terminal queda abierta con ayuda

- Autoclose pasa a opt-in (`terminal.autoclose=false`). Al terminar: se queda
  abierta, avisa con código de salida, `q` cierra, winbar/título con estado
  OK/error. Prerrequisito de UX para marketing/demos.

## df8ed88 — Historial persistente

- `history.lua`: JSON en `stdpath("data")/code-runner/history.json`, dedupe por
  cmd+cwd, `count`, `ts`, límite `history.max`, tolerancia a archivos corruptos.
- `:CodeRunHistory`.

## Antes (resumen)

- Contexto inteligente (tests + entry main) con TS y fallback regex.
- Project root por marcadores; ejecución desde raíz.
- Java smart run (package/source-root/FQCN, javac temporal) + Maven auto-run.
- Quickfix con reglas gcc/Maven/MSVC/go-FAIL + autoopen.
- Terminal h/v/float reutilizada solo del plugin; PowerShell/bash wrap;
  `.exe`/rutas con espacios.
- Pickers volt con fallback; `$testName/$stem/$project/%l`.
- Suite propia (runner.lua) + E2E (C, Java, Python) + CI ubuntu/windows/macos.