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
- [ ] **shell.lua**: evaluar `wrap_command`; si el comando contiene `&&`
      dentro de comillas la partición actual se rompe. Decidir entre tokenizar
      con respeto a quoting o pasar el chain completo a PowerShell/bash.
      Cubrir con tests (`shell_spec`).
- [ ] **Cache de contexto**: en `context.detect`, cache por
      `{ bufnr, changedtick, cursor, key }`; invalidar por changedtick/cursor.
      TS parse sin re-parseear cada llamada.
- [ ] **Cleanup Java**: el `tempname()` del smart run queda en disco; borrar el
      directorio al final del job o con autocmd WinClosed de la terminal.

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