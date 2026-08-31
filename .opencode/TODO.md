# TODO — trabajo concreto

Solo tareas accionables y verificables. El roadmap vive en ROADMAP.md.

## P0 — ahora

- [x] **Estado central de ejecución**: módulo `state.lua` (`idle|running|success|
      failed|cancelled`) + `state()` API. Alimentado por `terminal.open`/`_on_exit`;
      `run_id` evita que on_exit de jobs viejos pisen el estado actual. Incluye
      fix E95 (reuso de buffer terminal) y `cancelled` al cerrar con `q`.
- [x] **`:CodeRunStop`**: `init.stop()` mata SOLO el buffer registrado en el
      estado (via `_close_current`); terminales ajenas intactas. Comando
      `:CodeRunStop`.
- [x] **`:CodeRunRestart`**: `init.restart()` = `_stop_silent()` + `run_last()`;
      `_stop_silent()` es `stop()` sin notificar (restart no quiere el aviso
      intermedio). Comando `:CodeRunRestart`.
- [x] **Run Last robusto**: `last.lua` persiste la última elección en
      `stdpath("data")/code-runner/last.json`; `setup` la recarga (`last_choice`
      pasa a ser cache en memoria). Ocultable con `last_run.persist=false`.
- [x] **shell.lua**: `wrap_command` ahora usa un splitter quote-aware: solo
      convierte `&&` fuera de comillas; un `&&` literal dentro de `"..."`/
      `'...'` ya no se reescribe (rompía strings al pasarlos a PowerShell).
- [x] **Cache de contexto**: `context.detect` cachea el resultado por
      `{ bufnr, changedtick, cursor, key }`; se invalida al cambiar cursor o
      editar el buffer, y no comparte entre idiomas. `_clear_cache()` para tests.
- [x] **Cleanup Java**: el smart run registra el dir `tempname()` en
      `vim.b[buf].code_runner_cleanup`; `terminal._on_exit` lo borra (`delete
      rf`) al terminar el job (éxito o error). Nueva `state.reset()` (idle
      limpio, borra code/action/etc) para tests.

## P0 — completo

- Los 7 ítems P0 del ROADMAP están terminados. Pasar a P1.

## Mantenibilidad — modularización (refactor)

- Regla: **ningún archivo > ~300 líneas**. Hecho:
  - `actions.lua` 597→54; catálogo en `actions/{catalog,java,latex,languages/*}`.
  - `context.lua` 535→147; en `context/{test,entry}.lua`.
  - `terminal.lua` 412→241; en `terminal/{buffer,ui}.lua` (+ re-export API/tests).
- P1 debería reusar esta base para el action registry (`actions/languages/*`
  ya son módulos por grupo).

## P1 — siguiente

- [ ] Action registry + `register_action` (id, filetypes, kind, command/run).
- [ ] API pública `code-runner.run/run_last/stop/restart/state/context`.
- [ ] `.code-runner.lua` por proyecto (load seguro, defaults, tasks).
- [ ] Profiles Run/Build/Test/Debug/Release/Benchmark donde apliquen.

## P2 — después

- [ ] `vim.diagnostic` para errores (Quickfix se mantiene; opción Quickfix/Diag/Ambos).
- [ ] `:checkhealth code-runner`.
- [ ] Events `CodeRunner*`.
- [ ] Maven/Gradle Wrapper (`mvnw`, `./gradlew`).
- [ ] Windows restante (quoting/msbuild).

## Notas

- Nada de lenguajes nuevos.
- Cada ítem = una sesión de trabajo: implementar → tests → docs → update ROADMAP.