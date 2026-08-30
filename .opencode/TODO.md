# TODO — trabajo concreto

Solo tareas accionables y verificables. El roadmap vive en ROADMAP.md.

## P0 — ahora

- [ ] **Estado central de ejecución**: módulo `state.lua` (o tabla en init) con
      `idle|running|success|failed|cancelled` + `state()` API. Alimentado por
      `terminal.open`/`_on_exit`; pestaña de acciones de Java/scripts también.
- [ ] **`:CodeRunStop`**: `terminal.open` debe exponer el job id de `termopen`
      y un `stop()` que maté solo ese job (enviar señal al job del plugin, no
      matar otros). Command en `plugin/code-runner.lua`.
- [ ] **`:CodeRunRestart`**: combinar stop + re-ejecutar última acción.
- [ ] **Run Last robusto**: persistir última acción (JSON en
      `stdpath("data")/code-runner/` junto a history, o usar el tope del
      historial) y recargarla tras reiniciar Nvim. Mantener `last_choice` de
      memoria como cache.
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