# CodeRunner.nvim Development State

This file is the persistent state of the current development effort.

It must be updated when a major task starts, completes, or changes the architectural direction.

______________________________________________________________________

# Current Phase

```text
P0 — Architecture Foundation
```

______________________________________________________________________

# Current Objective

Establish the v1.0 architecture before continuing feature development.

The immediate goal is to make the internal model scalable without requiring a rewrite when additional runners, task types, workflows, and integrations are introduced.

______________________________________________________________________

# Current Task

```text
EXEC-009 — Terminal Adapter (slice 2)
```

Estado: **EN CURSO** (slices 1–5 completados 2026-10-09: tracking con guards
probados + identidad en historial/last + task_id operativo + fuente única de
eventos/Result + spawn por puerto PTY. Suite: 586 pass · 0 fail · 2 skip.
Resta de EXEC-009: workflow sobre el Engine).

______________________________________________________________________

# Completed

Initial repository architecture audit.

Current architectural direction has been defined around:

```text
Task
Execution
Command
Context
Runner
Result
```

Persistent OpenCode documentation is being established.

## ARCH-001 completado (2026-09-01)

- Suite base: 253 tests → 333 tests (0 fail · 1 skip).
- Nuevo `tests/characterization_spec.lua`: protege execution flow, state
  transitions, context resolution, picker integration, event emission order,
  history/last persistence, workflow, public API, command resolution y project
  detection.
- Conflictos arquitectónicos documentados pero NO corregidos (input para
  ARCH-002/ARCH-007). Ver abajo.

## ARCH-002 completado (2026-09-01)

- Nuevo módulo Core `lua/code-runner/task.lua` (puro, sin dependencias de
  vim/UI). `task.id(runner, name)` produce identidad estable y determinística
  (`go.Run` → `go.run`) libre de presentación (ADR-002).
- `task.new()` normaliza un TaskSpec canónico (defaults `filetypes = {}`,
  `enabled = true`) sin mutar/compartir el spec original. `task.validate()`,
  `task.valid()`, `task.new_or_error()` completan la API.
- `task.from_catalog()` proyecta el catálogo legacy (label → command) a
  TaskSpec: kind inferido del icono, name sin iconos de presentación, id
  derivado del texto.
- `tests/task_spec.lua` (24 tests) con acceptance tests que recorren TODO el
  catálogo real (`actions.get_actions()`) y verifican que cada acción es
  representable por TaskSpec con id único y sin iconos.
- Suite completa: 357 pass · 0 fail · 1 skip.
- NO se tocó el flujo productivo (registry/terminal/picker/workflow/init):
  la migración del consumidor real queda para ARCH-006 (Task Registry).
- Sin conflictos nuevos. `from_catalog` queda como adapter de migración, no
  como identidad final.

## ARCH-003 completado (2026-09-01)

- Nuevo módulo Core `lua/code-runner/command.lua`: CommandSpec
  (`{ executable, args, cwd, env }`) como representación estructurada interna
  de comandos (ADR-008 / CONTRACTS §8), aceptando strings como shorthand.
- `parse()` normaliza `go run $file` → `executable="go" args={"run","$file"}`;
  placeholders de contexto se preservan. `split_chain()` maneja cadenas con
  `&&` fuera de comillas. `build()` reconstruye el shorthand. `normalize()`
  valida, copia y desacopla.
- `tests/command_spec.lua` (25 tests) con acceptance test sobre TODO el
  catálogo real: cada comando string es representable como CommandSpec.
- Suite completa: 383 pass · 0 fail · 1 skip.
- NO se tocó el flujo productivo (shell adapter, terminal, catálogo): la
  resolución de contexto y el wiring quedan para Command Resolution.
- Conflicto nuevo documentado (C9): parsing de `&&` duplicado entre el
  adaptador `shell.lua` y Core `command.lua`.

## ARCH-004 completado (2026-09-01)

- Nuevo módulo Core `lua/code-runner/result.lua`: Result normalizado
  (`{ code, signal, stdout, stderr, duration }`, CONTRACTS §7), independiente
  de la terminal UI.
- `new()` normaliza y desacopla; `validate()/valid()` checan el contrato;
  `from_exit(code)` modela la finalización on_exit; `status()` clasifica
  success/failed/indeterminado; helpers booleanos y `describe()` para logs.
- `tests/result_spec.lua` (20 tests) con acceptance de independencia de UI.
- Suite completa: 403 pass · 0 fail · 1 skip.
- NO se tocó el flujo productivo: conversión de finalización de job a Result
  queda para EXEC-006 (Result Handling).
- Sin conflictos nuevos. `state.set` sigue guardando code|nil directamente.

## ARCH-005 completado (2026-09-01)

- Nuevo módulo Core `lua/code-runner/execution.lua`: entidad Execution
  (`{ id, task_id, context, command, status, started_at, finished_at, result }`,
  CONTRACTS §5) con identidad única y ciclo de vida explícito
  (created/starting/running/success/failed/cancelled + TRANSITIONS con
  terminales).
- `create()` normaliza command (reusa `command.normalize`), clona context/
  command y asigna id creciente. `matches()` rechaza callbacks obsoletos.
  `transition/start/running/finish/cancel` validan saltos y timestamps;
  `finish` exige Result clasificable acorde al destino. `validate/valid`.
- `tests/execution_spec.lua` (22 tests) con acceptance de rechazo de callbacks
  viejos y de independencia de state/terminal.
- Suite completa: 425 pass · 0 fail · 1 skip.
- NO se tocó `state.lua` ni el flujo productivo: adoptar Execution en el flujo
  real (engine sobre run_id) queda para EXEC-005. `state.run_id` intacto.
- Sin conflictos nuevos.

## ARCH-006 completado (2026-09-01)

- Nuevo módulo Core `lua/code-runner/task_registry.lua`: Task Registry por ID
  estable (CONTRACTS §16), separado del Runner Registry legacy. Identidad por
  `task.id` (no label). API register/unregister/get/list/has/count/reset,
  acepta TaskSpec o Task construido, reemplazo sin duplicar posición.
- `tests/task_registry_spec.lua` (14 tests) con acceptance de identidad estable
  y de registro independiente de runners.
- Suite completa: 439 pass · 0 fail · 1 skip.
- NO se tocó el flujo productivo ni el catálogo (Must NOT): `actions/registry.lua`,
  `actions.lua`, `init.lua` intactos. Migración del consumidor real queda para
  fase siguiente.
- Sin conflictos nuevos.

## ARCH-007 completado (2026-09-01)

- Auditoría de dependencias (no código): inventario de los módulos de
  `lua/code-runner`, clasificación por capa y contraste con `BOUNDARIES.md`.
- Core limpio confirmado: `task`, `command`, `result`, `execution`,
  `task_registry` (ninguno depende de vim/UI/terminal/quickfix/runner).
- Violaciones documentadas (ver sección Conflicts, B1–B4) y en
  `BOUNDARIES.md` §16:
  - B1 runners→terminal (java/latex/compiled);
  - B2 runners→shell (catalog/compiled/workflow/actions);
  - B3 application→terminal (actions/workflow);
  - B4 `shell` cross-layer (adapter de proceso, no Core; duplica `&&` con
    `command.lua` — C9).
- Candidatos de migración identificados: runners devuelven TaskSpec/Command,
  Application usa Execution/Result, unificar parsing `&&` en Core (EXEC).
- Sin cambios funcionales; suite intacta.

## EXEC-001 completado (2026-09-01)

- Nuevo `lua/code-runner/engine.lua` (Core puro): conduce el lifecycle
  created→starting→running→success|failed|cancelled sobre `execution.lua` y
  emite cada transición válida a un listener inyectable (`set_listener`).
- Puente hacia EXEC-007 (execution events); sin dependencia de vim.
- `tests/engine_spec.lua` (10 tests): secuencias de vida, emisión en orden,
  desactivación con nil, invalid sin emitir.
- Suite completa: 449 pass · 0 fail · 1 skip.
- NO conectado al job real (spawn = EXEC-002; terminal consume = EXEC-009).
- Sin conflictos nuevos.

## EXEC-002 completado (2026-09-01)

- Nuevo `lua/code-runner/process.lua` (Core puro, BOUNDARIES §7): puerto
  inyectable `spawn/send/terminate` para el Process Adapter (CONTRACTS §19),
  con validación de shape, adapter concreto seteable vía `set_adapter`, sin
  dependencia de `vim.fn.jobstart`/`termopen`/`vim.system`.
- `tests/process_spec.lua` (14 tests) con mock adapter.
- Suite completa: 463 pass · 0 fail · 1 skip.
- Adapter real de Neovim no conectado (EXEC-009). `terminal.lua` sigue
  usando termopen directamente.
- Sin conflictos nuevos.

## EXEC-003 completado (2026-09-01)

- Nuevo `lua/code-runner/stream.lua` (Core puro): normaliza chunks
  stdout/stderr a líneas completas en orden (pending por canal), output
  `{stdout, stderr}` listo para Result, callbacks on_line/on_stdout/on_stderr,
  stats/reset.
- `tests/stream_spec.lua` (14 tests) con acceptance de build → Result sin UI.
- Suite completa: 477 pass · 0 fail · 1 skip.
- `terminal.lua` (termopen, salida mezclada) intacto; el stream alimentará el
  flujo real en EXEC-009.
- Sin conflictos nuevos.

## EXEC-004 completado (2026-09-01)

- Nuevo `lua/code-runner/cancel.lua` (Core puro): cancelación por Execution con
  guard de identidad (`expected`), terminate delegado (EXEC-002 port) antes de
  marcar `cancelled`, rechazo de estados terminales/obsoletos, `now`
  inyectable, emisión vía engine.
- `tests/cancel_spec.lua` (10 tests): stale rejected, terminate failure no
  cancela, acciones terminales no cancellables.
- Suite completa: 487 pass · 0 fail · 1 skip.
- `terminal.lua`/`init.lua` intactos (stop real sigue vía buffer/state);
  wiring a job real en EXEC-009.
- Sin conflictos nuevos.

## EXEC-005 completado (2026-09-01)

- Nuevo `lua/code-runner/restart.lua` (Core puro): re-ejecución como Execution
  nueva (id fresco, created, sin timestamps/result), heredando task_id/context/
  command; `prev` nunca se muta. `same_identity` como guard.
- `tests/restart_spec.lua` (9 tests): identidad nueva tras success/failed/
  cancelled/running, prev intacto, overrides.
- Suite completa: 496 pass · 0 fail · 1 skip.
- `run_last` (init.lua) sigue en el flujo productivo; wiring a job real en
  EXEC-009.
- Sin conflictos nuevos.

## EXEC-006 completado (2026-09-01)

- Nuevo `lua/code-runner/result_handler.lua` (Core puro): on_exit (code/signal)
  → Result canónico (CONTRACTS §7, capture option de stream) adjuntado vía
  `engine.finish`; identity guard (`expected`), only activas finalizables.
- `tests/result_handler_spec.lua` (11 tests): clasificación, capture, stale
  on_exit rechazada, terminales/created rechazados.
- Suite completa: 507 pass · 0 fail · 1 skip.
- `_on_exit` real (terminal.lua) sigue escribiendo estado/quickfix; wiring a
  job real en EXEC-009.
- Sin conflictos nuevos.

## EXEC-007 completado (2026-10-09)

- `lifecycle_events.lua` formalizado como contrato puro EXEC-007: paridad
  `CodeRunnerStart/Success/Failed/Cancelled + Exit`, `created/starting`
  silenciosos, payload desde Execution con `cwd` canónico (`command.cwd`
  > `ctx`/project root).
- `engine.set_listener` valida `function|nil`; `emit` con `pcall` (listener
  que lanza no rompe transición).
- Tests: 3 nuevos (cwd canónico, rechazo no-function, throw aislado).
  Suite: 527 pass · 0 fail · 2 skip.
- Sin wiring real (adapter vim en EXEC-009). Sin conflictos nuevos.

## EXEC-008 completado (2026-10-09)

- `history.from_execution` canónico `version=1` + `add_execution` con dedup
  por task_id y upgrade de legacy mismo cmd+cwd. UI legacy intacta.
- Tests: 7 nuevos. Suite: 534 pass · 0 fail · 2 skip.
- Flujo real intacto — wiring a EXEC-009. Sin conflictos nuevos.

---

# Conflicts found during ARCH-001

La implementación actual NO fue modificada. Estos son conflictos observados
entre la arquitectura actual y las decisiones de `.opencode/`. Se dejan como
input para las tareas correspondientes.

## C1 — Action (label → command) vs TaskSpec (ADR-001/ADR-002)

`actions.lua` y `actions/registry.lua` usan un label como clave de identidad
(ej. `"▶ Run"`). El label ES la identidad y la presentación a la vez. ADR-002
exige Task ID estable independiente de la etiqueta.

Impacto: `register_action` debe migrar de `{ filetypes, label → cmd }` a un
Task Registry con IDs estables (ARCH-006). Nitidez de la migración: ARCH-002.

## C2 — Terminal acoplada a la detección de lenguaje

`terminal.lua:170` (`context._resolve_key()`) hace que el adaptador de
terminal detecte el lenguaje del archivo del usuario. `ARCHITECTURE.md` §16 y
BOUNDARIES §8 dicen que la terminal NO debe decidir qué runner/task está
activa. La resolución de contexto pertenece al Core/Application.

Impacto: EXEC-009 (Terminal Adapter) debe empujar la detección hacia arriba.

## C3 — Catálogo ejecuta directamente desde la terminal

`actions.lua:16` (`open_runner = terminal.open`) y `actions/catalog.lua`
reciben `terminal.open` como inyección de ejecución. El catálogo (source de
runners) invoca la terminal directamente, violando ADR-004 (Runner describe,
no ejecuta) y el flujo Runner → Application → Execution Engine.

Impacto: RUN-00x / EXEC-009.

## C4 — Project detection mezcla señales en una firma

`project.lua` combina marcadores de lenguaje + genéricos + del usuario dentro
de un único `find_from(dir, key)`, y usa `key` tanto para detectar como para
resolver `$project`. `ARCHITECTURE.md` §10 prevé señales separadas y
jerárquicas.

Impacto: cuando exista Context Resolver, separar marcadores por señal.

## C5 — Dos engines de ejecución (ADR-005 violado)

- Standalone: `terminal.open` → `termopen` (visible, con diagnóstico en buffer).
- Workflow: `workflow.run_step` → `jobstart` (headless, sin buffer).

Una task y un workflow NO usan hoy el mismo engine. ADR-005 / ARCHITECTURE §17
exigen una sola Execution Engine. `workflow.run` encadena jobstarts sin pasar
por terminal/state/eventos.

Impacto: arquitectura de "one execution engine". Es un conflicto real y de
gran alcance; requiere plan dedicado (P1 Execution Core).

## C6 — run_last re-ejecuta comando crudo

`init.lua:187` re-ejecuta `last_choice.cmd` directamente (comando ya
sustituido) en vez de resolver por Task ID. `ARCHITECTURE.md` §20 / CONTRACTS
§25 prefieren `{ task_id, context }` para que la definición de la task pueda
evolucionar.

Impacto: ARCH-002 (TaskSpec) debe rehacer `last`/`run_last` sobre ids.

## C7 — Registry label-keyed

`registry.apply` convierte `kind` en un icono de label y guarda por label.
No hay IDs estables. Debe migrar a Task Registry (ARCH-006).

## C8 — Tests que tocan implementación privada re-exportada

`terminal_spec`/`state_spec` usan `terminal._open_window`, `_label_parts`,
`_apply_window_label` (re-export de `terminal/ui.lua`). Son implementation
tests; reescribir como contract tests cuando la UI se separe (EXEC-009).

## C9 — Parsing de `&&` duplicado entre shell adapter y Core (ARCH-003)

`command.lua` (Core, ADR-008) introduce el split de `&&` fuera de comillas
(`split_chain`), lógica que ya existía en el adaptador `shell.lua:99`
(`split_and_outside_quotes`, usada por `wrap_command`). Hay dos copias del
mismo criterio de quoting. No se corrigió (el adaptador sigue operando sobre
strings y no debe depender de nuevo módulo todavía); el flujo Shell → Command
debe unificarse en Command Resolution / EXEC-002 (Process Adapter).

## Violaciones de límites (ARCH-007)

B1 — Runners dependen del Terminal Adapter (§5, proscrito "Runner ↓ terminal"):
`actions/java.lua`→`terminal`, `actions/latex.lua`→`terminal`,
`actions/languages/compiled.lua`→`terminal` (lazy).

B2 — Runners dependen del adapter de proceso `shell` (§5 "describes, no
executes" y smell de proceso en runner): `actions/catalog.lua`→`shell`,
`compiled.lua`→`shell`, `workflow.lua`→`shell`, `actions.lua`→`shell`.

B3 — Application acopla directo al Terminal Adapter (§3): `actions.lua`→
`terminal`; `workflow.lua` ejecuta vía jobstart y produce `{cmd, code}` en vez
de Result.

B4 — `shell` es cross-layer: helper de interpolación + adapter de proceso con
dependencia de `vim.api`/`vim.fn.expand`/`project`. Clasificado como Adapter,
no Core. (Se solapa con C9.)

Migración candidata (sin implementar, roadmap): runners → TaskSpec/Command;
Application → Execution/Result; unificar `&&` en Core (C9/EXEC-002).

---

# Next Tasks

```text
EXEC-007
```

See `TODO.md`.

______________________________________________________________________

# Current Architectural Target

```text
UI
 ↓
Application
 ↓
Core
 ↓
Ports
 ↓
Adapters
```

With:

```text
Runner Registry
Task Registry
Context Resolver
Execution Engine
Output Parsers
```

______________________________________________________________________

# Feature Freeze

Until P0 and the first Execution Core milestone are complete:

DO NOT add:

- new language runners
- major UI features
- DAP integration
- Neotest integration
- complex workflow parallelism
- remote execution
- marketplace/plugin ecosystem
- unrelated refactors

Small bug fixes are allowed when necessary for tests or correctness.

______________________________________________________________________

# Migration Strategy

Migration must be incremental.

Preferred pattern:

```text
existing behavior
        ↓
characterization test
        ↓
new abstraction
        ↓
adapter/compatibility layer
        ↓
migrate one consumer
        ↓
tests
        ↓
remove old path
```

______________________________________________________________________

# Important Existing Strengths

The current repository already contains useful foundations:

- language catalog
- registry concept
- contextual test detection
- entrypoint detection
- project detection
- history
- last-run behavior
- terminal abstraction
- diagnostics
- quickfix
- events
- workflow
- health checks
- extensive tests

These should be evolved rather than blindly discarded.

______________________________________________________________________

# Current Risks

> Todos confirmados por ARCH-001 (2026-09-01). Ver "Conflicts found during
> ARCH-001" para localizaciones concretas.

## Risk 1 — Action model

The existing label-to-command representation may become a scalability bottleneck.

Target:

```text
TaskSpec
```

______________________________________________________________________

## Risk 2 — Execution duplication

Terminal execution and workflow execution currently have overlapping lifecycle concerns.

Target:

```text
One Execution Engine
```

______________________________________________________________________

## Risk 3 — Language catalog growth

A central language catalog can become a maintenance bottleneck.

Target:

```text
Runner per ecosystem
```

______________________________________________________________________

## Risk 4 — Context responsibility

Context currently combines several types of detection.

Target:

```text
Context Resolver
+
specialized detectors
```

______________________________________________________________________

## Risk 5 — Command string complexity

Shell command strings are accumulating variables and platform behavior.

Target:

```text
CommandSpec
```

______________________________________________________________________

# Rules for Updating This File

Update this file when:

- starting a major architectural task
- completing a milestone
- discovering a blocker
- changing the active roadmap phase
- changing an architectural assumption

Do not turn this file into a changelog.

Keep it focused on current state.
