# ROADMAP V1.0 — code-runner.nvim

Convención: `[x]` completado · `[~]` en progreso · `[ ]` pendiente.
Regla de orden: no avanzar a una fase si la anterior arrastra problemas.

## P0 — Estabilidad del core

- [x] Auditar arquitectura actual (sesión `.opencode/`, inspección completa)
- [x] Crear contexto persistente `.opencode/` (README/ROADMAP/ARCHITECTURE/CHANGELOG/TODO)
- [x] Crear `AGENTS.md`
- [x] Estado central de ejecución (`idle|running|success|failed|cancelled`) + `state()` API
- [x] Fix invocado por el estado: terminal reutilizada sin E95 / job anterior en marcha se cancela
- [x] `:CodeRunStop` — cancelar el proceso activo del plugin (nunca procesos ajenos)
- [x] `:CodeRunRestart` — detener y re-ejecutar la última acción
- [x] Run Last robusto — `last_choice` se persiste (last.json) y se recarga en `setup`; `last_choice` en memoria queda como cache
- [x] Revisar `shell.lua` — `wrap_command` respeta `&&` dentro de comillas (splitter quote-aware; `vim.split` naive lo rompía)
- [x] Cache de contexto — `context.detect` cachea por `bufnr + changedtick + cursor + key`; evita re-parsear TS/regex en cada `:CodeRun`; `_clear_cache()` para tests
- [x] Cleanup de temporales Java — el smart run registra su dir `tempname()` en el buffer; `terminal._on_exit` lo borra al terminar (éxito o error); `state.reset()`

## P1 — Extensibilidad

- [x] Action registry (`register_action`: registrar/sobrescribir/deshabilitar/ordenar/tipo run|build|test|misc)
- [x] API pública `require("code-runner"): run / run_last / stop / restart / state / context / register_action`
- [x] Configuración por proyecto `.code-runner.lua` (tasks), carga segura y con defaults
- [x] Custom tasks (`tasks.dev/build/test`) con variables de contexto (`$testName`/`$entry`/`$entryLine`) — sustituidas en el command y reproducidas por run_last/restart
- [x] Profiles (Run/Build/Test/Debug/Release/Benchmark) — solo donde tengan sentido: presets opt-in (Rust `--release`, Go `-bench`, C/C++ `-O2`); `profiles.enabled=false` por defecto

## P2 — Integraciones y pulido

- [x] `vim.diagnostic` para errores de build/test (manteniendo Quickfix; elegible) — nuevo `quickfix.style` (`quickfix`/`diagnostic`/`both`) + módulo `diagnostics.lua`
- [x] `:checkhealth code-runner` — requiere/opcional/recomendada: deriva las herramientas del catálogo resuelto y solo revisa los lenguajes que el usuario usa (historial + buffer actual);   `glow` va como recomendada para markdown
- [x] Events `CodeRunnerStart/Exit/Success/Failed/Cancelled` — autocmds User emitidos desde `state.lua` (un solo punto), opt-out con `events.enabled`; `Exit` cubre cualquier estado final
- [x] Maven/Gradle Wrapper (`./mvnw` → `mvn`, `./gradlew` → `gradle`) + marcadores `pom.xml`/`build.gradle*` ya presentes — `shell.use_wrappers` en `terminal.open` (usa `cwd`); la auto-run de Java pasa el dir del pom como cwd
- [x] Windows restante — quoting PowerShell quote-aware y acciones `.bat`/`.cmd`/`.ps1` ya estaban; se añade build C# con **msbuild/csc** (`compiled.cs_build_cmd`: `.sln`/`.csproj` → msbuild > dotnet build; `.cs` suelto → csc > dotnet single-file), cross-platform con fallback

**P2 completa** → pasar a P3 (V1.0).

## P3 — Task engine

- [ ] Workflows básicos: ejecución secuencial `build → test → run`, stop-si-falla, resultado por etapa
- [ ] Tareas paralelas/acotadas (no un scheduler gigante)

## P4 — Integraciones externas

- [ ] VS Code tasks
- [ ] DAP
- [ ] Neotest
- [ ] Otras integraciones según demanda

## Notas

- NO agregar más lenguajes al catálogo por ahora (demanda real + mantenibilidad + tests antes).
- NO MCPs/agentes/subagentes/orquestadores/servidores externos. El contexto persistente ES
  `AGENTS.md` + `.opencode/`.
- Feature creep: antes de una feature evaluar #1 objetivo #2 usuarios #3 complejidad
  #4 mantenibilidad #5 tests #6 alternativa más simple.
- V1.0 = estabilidad, no features infinitas. Workflows/DAP/Neotest pueden ir a V1.1+.