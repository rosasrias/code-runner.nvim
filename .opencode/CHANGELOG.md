# CHANGELOG — code-runner.nvim

Cambios arquitectónicos y features importantes. Lanzamientos una vez existan tags.

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