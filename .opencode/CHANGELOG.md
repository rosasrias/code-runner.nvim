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