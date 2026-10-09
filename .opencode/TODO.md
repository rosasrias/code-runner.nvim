# CodeRunner.nvim Engineering Tasks

Tasks are intentionally small and bounded.

An AI agent should normally work on one task at a time.

______________________________________________________________________

# P0 — Architecture Foundation

______________________________________________________________________

## ARCH-001 — Characterization Tests

### Goal

Capture current externally observable behavior before changing the architecture.

### Scope

Inspect and strengthen tests around:

- run
- run last
- project detection
- context detection
- terminal execution
- history
- quickfix
- diagnostics
- workflow

### Must NOT

- redesign architecture
- migrate all runners
- add features

### Acceptance Criteria

- Important existing behavior has tests.
- Tests can detect regressions during migration.
- Current behavior is documented where ambiguous.

### Status

```text
DONE
```

### Resultado (2026-09-01)

- Se agregó `tests/characterization_spec.lua` (~80 tests de caracterización).
- Se protegió el comportamiento observable de: execution flow, state transitions,
  context resolution, picker integration, event emission order, history/last
  persistence, workflow end-to-end, public API surface, command resolution y
  project detection.
- Suite completa: 333 pass · 0 fail · 1 skip (headless).
- Línea base previa: 253 pass.

### Conflictos arquitectónicos detectados (input para ARCH-002/ARCH-007)

Estos NO fueron corregidos, solo documentados. Ver `STATE.md` → "Conflicts found during ARCH-001".

1. **Modelo `Action` (label→command) vs TaskSpec (ADR-001)**: el catálogo
   (`actions.lua`) y la registración (`registry.lua`) reducen la identidad a un
   label (`"▶ Run"`) mapeado a un comando. Un label es identidad y presentación a
   la vez, contradiciendo ADR-002 (Task ID independiente de presentación).
2. **UI en el núcleo de ejecución**: `terminal.lua` detecta lenguaje
   (`context._resolve_key()`), decide `cwd` y maneja el ciclo de vida completo
   del job. La línea de `terminal.lua:170` (`context._resolve_key`) acopla la
   terminal a la detección de contexto, violando la separación Execution/Terminal
   de `ARCHITECTURE.md` §16.
3. **Desde el commit `86016c4`**: `terminal.open` también consume
   `terminal.open_runner = terminal.open` dentro del catálogo. La terminal no es
   solo un adaptador de salida: el catálogo de acciones invoca directamente a la
   terminal para ejecutar, violando ADR-004 (Runner no ejecuta).
4. **`project.detect` mezcla marcadores de lenguaje + genéricos + del usuario**
   en un solo `find_from(cwd, key)`. La key se usa tanto para el marcador del
   lenguaje como para la resolución de `$project`. `ARCHITECTURE.md` §10 prevé
   señales separadas (filetype, project markers, executables); hoy todo vive en
   una sola firma `(dir, key)`.
5. **Workflow tiene su propio engine de ejecución** (`workflow.run_step` usa
   `jobstart` headless) separado de `terminal.open`. Esto contradice ADR-005 /
   `ARCHITECTURE.md` §17 (una sola Execution Engine). Hay dos mecanismos de
   ejecución de procesos: `terminal.open` (termopen + buffer) y `workflow.run_step`
   (jobstart headless).
6. **`last_choice`/`run_last` referencia a veces un comando crudo y a veces una
   acción**: `run_last` (init.lua:187) re-ejecuta `last_choice.cmd` directo cuando
   existe, sin resolver por Task ID. Contradice `ARCHITECTURE.md` §20 / CONTRACTS
   §25 que prefieren `{ task_id, context }` sobre replay del comando crudo.
7. **`registry.apply` (registry.lua:78) opera sobre labels**, convirtiendo
   `kind` en un icono de label. No hay Task ID estable; el registro es
   label-keyed. Debe migrar a Task Registry (ARCH-006).
8. **Tests de terminal dependen de `M._open_window`, `M._label_parts`,
   `_apply_window_label`** (re-export de UI en `terminal.lua:15-18`): son tests
   que tocan implementación privada re-exportada. Son candidatos a reescribirse
   como contract tests cuando la UI se separe (EXEC-009).

### Notas de tests frágiles (detectados)

- `terminal_spec` / `state_spec` usan `wait()` y crean terminales reales:
  emiten ruido de "Lua callback ... Invalid buffer id" aunque pasan. No bloquean,
  pero son difíciles de aislar.
- `shell_spec: wrap_command` devuelve una tabla de args (no un string). Los tests
  nuevos de `characterization` se escribieron contra esa API real.
- La detección de test de Go devuelve `entry.name = "main"` (no `"func main"`):
  los tests de caracterización verifican presencia, no el string exacto.

______________________________________________________________________

## ARCH-002 — Introduce TaskSpec

### Goal

Create the first-class Task domain model.

### Scope

Introduce:

```text
TaskSpec
Task identity
Task kind
Task metadata
Task command
Task conditions
```

### Must NOT

- migrate every runner
- redesign picker UI
- implement workflows
- modify terminal lifecycle

### Acceptance Criteria

- Task has stable ID.
- Presentation label is independent from ID.
- Task can be tested independently.
- Existing action behavior can be represented by TaskSpec.

### Dependencies

```text
ARCH-001
```

### Status

```text
DONE
```

### Resultado (2026-09-01)

- Nuevo módulo Core `lua/code-runner/task.lua` (puro, sin dependencias de
  vim/UI): `KINDS`, `id()`, `validate()`, `valid()`, `new()`, `new_or_error()`,
  `from_catalog()`.
- `task.id(runner, name)` genera identidad estable y determinística
  (`go.Run` → `go.run`), siempre libre de presentación (ADR-002).
- `task.new()` normaliza un TaskSpec canónico con defaults (`filetypes = {}`,
  `enabled = true`) sin mutar ni compartir el spec original.
- `task.from_catalog()` proyecta el catálogo legacy (label → command) a
  TaskSpec: kind inferido del icono, name sin iconos, id derivado del texto.
  Es una adaptación de migración, no el destino final de identidad.
- `tests/task_spec.lua` (24 tests): kinds del contrato, estabilidad del ID,
  validación, independencia, proyección del catálogo y **dos acceptance tests
  que recorren TODO el catálogo real** (`actions.get_actions()`) verificando
  que cada acción es representable por TaskSpec con id único y sin iconos.
- Registrado en `tests/run.lua` (tras `profiles_spec.lua`).
- Suite completa: 357 pass · 0 fail · 1 skip (headless).
- NO se modificó el flujo productivo actual (registry, terminal, picker,
  workflow, init). La migración del consumidor real es ARCH-006.
- Sin conflictos nuevos contra `.opencode/` en esta tarea.

______________________________________________________________________

## ARCH-003 — Introduce CommandSpec

### Goal

Normalize commands into an internal structured representation.

### Scope

Support:

```text
executable
args
cwd
env
```

while retaining command strings as shorthand.

### Must NOT

- rewrite shell adapter completely
- redesign Windows support unless required
- add new command syntax unnecessarily

### Acceptance Criteria

A command such as:

```text
go run $file
```

can be resolved into a structured executable command.

### Dependencies

```text
ARCH-002
```

### Status

```text
DONE
```

### Resultado (2026-09-01)

- Nuevo módulo Core `lua/code-runner/command.lua` (puro, sin vim/shell/UI):
  Modelo `CommandSpec = { executable, args, cwd, env }` (CONTRACTS §8).
- API pública del módulo:
  - `parse(cmd) -> CommandSpec` : shorthand string → executable + args,
    respetando comillas y escapado; placeholders de contexto (`$file`, `$dir`,
    `$testName`, ...) se preservan como tokens (CONTRACTS §9). Cadena con `&&`
    devuelve error (no es un único comando).
  - `split_chain(cmd) -> string[]` : separa sentencias por `&&` fuera de
    comillas (mismo criterio que `shell.split_and_outside_quotes`).
  - `build(spec) -> string` : reconstrucción round-trip del shorthand,
    comillando solo tokens con espacios.
  - `validate(spec) / valid(spec)` : chequeos de contrato.
  - `normalize(input) -> CommandSpec` : acepta string shorthand o tabla, y
    devuelve un spec canónico desacoplado (copia de args/env).
- `tests/command_spec.lua` (25 tests): parse con quotes/vars, split_chain con
  `&&` literal en comillas, round-trips, validación, independencia del spec y
  **un acceptance test que recorre TODO el catálogo real** verificando que
  cada comando string es representable como CommandSpec (o su chain de `&&`).
- Registrado en `tests/run.lua` (tras `shell_spec.lua`).
- Suite completa: 383 pass · 0 fail · 1 skip (headless).
- NO se modificó el flujo productivo (shell adapter, terminal, catálogo). La
  resolución de contexto + wiring a exemples queda para la capa de
  resolución/aplicación (Command Resolution, ver ARCHITECTURE §7).
- Conflito menor documentado: el split de `&&` hoy vive duplicado en
  `shell.lua:99` (adaptador) y `command.lua` (Core). Ver C9 en STATE.md.

______________________________________________________________________

## ARCH-004 — Introduce Result Model

### Goal

Create a normalized execution result.

### Scope

Model:

```text
exit code
signal
stdout
stderr
duration
```

### Acceptance Criteria

Result is independent from terminal UI.

### Dependencies

```text
ARCH-003
```

### Status

```text
DONE
```

### Resultado (2026-09-01)

- Nuevo módulo Core `lua/code-runner/result.lua` (puro, sin vim/UI):
  Modelo `Result = { code, signal, stdout, stderr, duration }` (CONTRACTS §7),
  independiente de la terminal.
- API pública:
  - `new(result)` : normaliza a un Result canónico (solo campos del contrato,
    sin compartir el spec original). Devuelve (result, nil) o (nil, error).
  - `validate(result) / valid(result)` : chequeos de contrato (code/signal/
    duration numéricos, stdout/stderr strings).
  - `from_exit(code)` : Result desde el exit code on_exit de un job
    (termopen/jobstart); stdout/stderr quedan nil hasta EXEC-006.
  - `status(result)` → `"success" | "failed" | nil`: code==0 → success;
    code~=0 o signal → failed; sin datos → nil (indeterminado).
  - `success/indeterminate/failed` (booleanos) y `describe()` (texto corto y
    determinístico para logs/notificaciones).
- `tests/result_spec.lua` (20 tests): campos, validación, clasificación por
  estado, helpers y acceptance de "Result independiente de terminal UI"
  (el modelo no conoce buffers/ventanas/quickfix y un build failure real se
  describe sin UI).
- Registrado en `tests/run.lua` (tras `command_spec.lua`).
- Suite completa: 403 pass · 0 fail · 1 skip (headless).
- NO se modificó el flujo productivo (terminal/state/workflow/quickfix):
  la conversión de finalización de job a Result es EXEC-006; `state.set`
  sigue escribiendo su código hoy.
- Sin conflictos nuevos contra `.opencode/`. `describe()` queda como texto de
  aplicación/nicho log, no como parte de la UI de terminal.

______________________________________________________________________

## ARCH-005 — Introduce Execution Model

### Goal

Create a first-class runtime Execution entity.

### Scope

Model:

```text
execution ID
task ID
context
command
status
timestamps
result
```

### Acceptance Criteria

- Execution has unique identity.
- Stale callbacks can be rejected.
- Task and Execution are distinct.
- Lifecycle states are explicit.

### Dependencies

```text
ARCH-004
```

### Status

```text
DONE
```

### Resultado (2026-09-01)

- Nuevo módulo Core `lua/code-runner/execution.lua` (puro, sin vim/state/
  terminal): entidad de primera clase `Execution = { id, task_id, context,
  command, status, started_at, finished_at, result }` — CONTRACTS §5.
- **Identidad única**: `create()` asigna `id` creciente (`_next_id`, inyectable
  con `_internals.reset_seq`). `matches(exec, id)` permite al Execution Engine
  descartar callbacks obsoletos (CONTRACTS §6 / "Stale callbacks can be
  rejected").
- **Task vs Execution**: la entidad referencia `task_id` pero tiene identidad,
  timing y resultado propios — son entidades distintas.
- **Ciclo de vida explícito** (STATUSES + TRANSITIONS con estados terminales):
  `created → starting → running → success|failed|cancelled`. `transition`/`start`/
  `running`/`finish`/`cancel` validan cada salto (running→starting o continuar
  tras cancelled/success falla); los terminales exigen un `Result` clasificable
  (success/failed) con `finished_at`.
- `validate`/`valid` corroboran id/task_id/status/timestamps/result; el
  resultado debe corresponder con el destino (exit 0 → success, exit≠0 → failed).
- `command` se normaliza con `command.normalize` (acepta string shorthand);
  `context` y `command` se clonan (independencia del spec).
- `tests/execution_spec.lua` (22 tests): identidad, validación, transiciones,
  rechazo de callbacks viejos, y acceptance de que el modelo no depende de
  terminal ni de `state.run_id`.
- Registrado en `tests/run.lua` (tras `result_spec.lua`).
- Suite completa: 425 pass · 0 fail · 1 skip (headless).
- NO se tocó `state.lua` ni el flujo productivo: el wiring del Execution Engine
  sobre `run_id`/estados queda para EXEC-005 (Execution Engine / adoptar
  Execution en el flujo real). `state.run_id` queda intacto.
- Sin conflictos contra `.opencode/`. No hay segundo motor de ejecución: el
  módulo es modelo Core puro, no ejecuta procesos.

______________________________________________________________________

## ARCH-006 — Registry Contracts

### Goal

Separate Runner Registry and Task Registry.

### Scope

Introduce:

```text
Runner Registry
Task Registry
```

### Must NOT

- migrate all language definitions yet

### Acceptance Criteria

A Task can be registered and retrieved by stable ID.

A Runner can be registered independently.

### Dependencies

```text
ARCH-002
```

### Status

```text
DONE
```

### Resultado (2026-09-01)

- Nuevo módulo Core `lua/code-runner/task_registry.lua` (puro): **Task
  Registry** por ID estable (CONTRACTS §16), separado conceptualmente del
  Runner Registry legacy (`actions/registry.lua`).
- API: `register` (acepta TaskSpec o Task ya construido; normaliza con
  `task.new` / valida identidad con `task.validate`), `register_or_error`,
  `unregister`, `get`, `list`, `has`, `count`, `reset`.
- **Identidad por id, no por label** (ADR-002): la clave del registry es
  `task.id`, no el `name`/label de presentación. Registrar el mismo id
  reemplaza el contenido sin duplicar la posición de orden (fix real de
  deduplicación).
- **A Runner se registra independientemente**: este módulo no toca ni depende
  de `actions/registry.lua`; ambos conviven. (Must NOT: NO se migró el
  catálogo/definiciones de lenguaje.)
- `tests/task_registry_spec.lua` (14 tests): registro/recuperación por id,
  orden, reemplazo sin duplicar, unregister/reset, validación, y acceptance
  de identidad estable e independencia del Runner Registry.
- Registrado en `tests/run.lua` (tras `execution_spec.lua`).
- Suite completa: 439 pass · 0 fail · 1 skip (headless).
- NO se tocó el flujo productivo ni el catálogo: `actions/registry.lua`,
  `actions.lua`, `init.lua` intactos. La migración del consumidor real queda
  para ARCH-006 siguiente fase (Task Registry adoptado en el picker/acciones).
- Sin conflictos nuevos.

______________________________________________________________________

## ARCH-007 — Dependency Boundary Validation

### Goal

Validate the architectural boundaries against the real codebase.

### Scope

Identify modules that currently violate:

```text
UI
Application
Core
Adapters
```

### Acceptance Criteria

- violations documented
- migration candidates identified
- BOUNDARIES.md matches reality or known migration state

### Dependencies

```text
ARCH-002
ARCH-005
ARCH-006
```

### Status

```text
DONE
```

### Resultado (2026-09-01)

Auditoría de dependencias (`ARCH-007`): se inventariaron los 25+ módulos de
`lua/code-runner`, se clasificaron por capa (UI / Application / Core /
Adapters) y se contrastó cada dependencia contra `BOUNDARIES.md`.

**Core limpio (objetivo alcanzado en ARCH-002..006)**: `task.lua`,
`command.lua`, `result.lua`, `execution.lua`, `task_registry.lua` — puros, sin
dependencia de vim/ui/terminal/quickfix/runner. Coinciden con BOUNDARIES §2.

**Violaciones encontradas (documentadas en STATE.md §Conflicts y BOUNDARIES.md):**

- **B1 — Runners dependen del Terminal Adapter** (viola §5):
  `actions/java.lua`→`terminal`, `actions/latex.lua`→`terminal`,
  `actions/languages/compiled.lua`→`terminal` (lazy). Es el caso proscripto
  §13 "Go Runner ↓ terminal.lua".
- **B2 — Runners dependen del Adapter de proceso `shell` (viola §5"describes, no
  executes")**: `actions/catalog.lua`→`shell`, `compiled.lua`→`shell`,
  `workflow.lua`→`shell`, `actions.lua`→`shell`. Relacionado con C9
  (duplicación de parsing `&&` entre shell y Core `command.lua`).
- **B3 — Application acopla al Terminal Adapter directamente (viola §3)**:
  `actions.lua`→`terminal`, y `workflow.lua` ejecuta vía jobstart produciendo
  `{cmd, code}` (debería producir Result vía Execution).
- **B4 — `shell`** cruza capas: es a la vez helper de interpolación (usado por
  Core-lista la cadena) y adapter de proceso (wrap_command powershell/bash) con
  dependencia de `vim.api`/`vim.fn.expand`/`project`. Se clasifica como
  **Adapter**, no Core.

**Migración candidata (no implementada, sigue el roadmap):**

1. Runners → devolver `TaskSpec`/`CommandSpec` y dejar de llamar a
   `terminal`/`shell`; Application/Execution Engine ejecuta (EXEC).
2. Unificar parsing de `&&` en `command.lua` (C9, EXEC-002 Command Resolution).
3. `actions`/`workflow` → consumir Execution/Result en vez de terminal/jobstart
   directo (EXEC).

**Acceptance:** violaciones documentadas ✓; candidatos a migración
identificados ✓; `BOUNDARIES.md` refleja la realidad/migración (se añadió una
sección de estado de migración).

No se modificó ningún módulo funcional (auditoría pura, suite intacta).

______________________________________________________________________

# P1 — Execution Core

## EXEC-001 — Execution Lifecycle

Define and implement:

```text
created
starting
running
success
failed
cancelled
```

### Status

```text
DONE
```

### Resultado (2026-09-01)

- El state machine del ciclo de vida ya venía definido en `execution.lua`
  (STATUSES + TRANSITIONS + transition/start/running/finish/cancel, ARCH-005).
- EXEC-001 añade la capa que lo **conduce y observa**: `lua/code-runner/engine.lua`
  (Core puro), un engine mínimo que orquesta created → starting → running →
  success|failed|cancelled sobre el modelo y anuncia cada transición válida a
  un listener inyectable (`set_listener(fn)`, nil para desactivar).
- El listener es el puente hacia EXEC-007 (Execution Events): `events.lua`
  mapeará estas transiciones a las autocmds `CodeRunner*` sin que el modelo ni
  el engine dependan de vim.
- El Process Adapter real (spawn/stream/terminate) NO está en este paso: es
  EXEC-002. El engine es la cebolla del ciclo de vida, no el spawner.
- `tests/engine_spec.lua` (10 tests): secuencias de transición para run
  exitoso/fallido/cancelado, emisión en orden al listener, desactivación con
  nil, y que las transiciones inválidas NO emiten.
- Registrado en `tests/run.lua` (tras `task_registry_spec.lua`).
- Suite completa: 449 pass · 0 fail · 1 skip (headless).
- NO se tocó el flujo productivo (terminal/state/actions/init intactos); este
  engine aún no está conectado al job real (EXEC-002/EXEC-009 lo harán).
- Sin conflicto nuevo; Core sigue limpio (BOUNDARIES §7).

______________________________________________________________________

## EXEC-002 — Process Adapter

Create a process boundary independent from terminal UI.

### Status

```text
DONE
```

### Resultado (2026-09-01)

- Nuevo `lua/code-runner/process.lua` (Core puro, BOUNDARIES §7):
  Puerto inyectable del Process Adapter (CONTRACTS §19). Define la interfaz
  `spawn/send/terminate` sin dependencia de `vim.fn.jobstart`, `vim.system`
  ni `termopen`.
- API: `set_adapter(port)` inyecta el adapter concreto (nil para limpiar),
  `get_adapter`, `validate_adapter`/`valid` (chequeo de shape), `spawn(opts)`,
  `send(handle, data)`, `terminate(handle)`. Valida `cmd` como `string[]`
  y todos los callbacks opcionales antes de delegar al adapter.
- El adapter real de Neovim (`jobstart`/`termopen`) no está en este paso:
  se inyecta después (EXEC-009). Los tests usan un mock adapter.
- `tests/process_spec.lua` (14 tests): validación de shape, spawn con opts
  válidas/inválidas, send/terminate, adapter inválido, sin adapter, y
  acceptance de Core puro (sin vim.fn.jobstart).
- Registrado en `tests/run.lua` (tras `engine_spec.lua`).
- Suite completa: 463 pass · 0 fail · 1 skip (headless).
- NO se tocó `terminal.lua` (el flujo productivo sigue usando termopen
  directamente); la migración real del adapter es EXEC-009 (Terminal Adapter).
- Sin conflicto nuevo; Core sigue limpio (BOUNDARIES §7).

______________________________________________________________________

## EXEC-003 — Output Streaming

Normalize stdout/stderr handling.

### Status

```text
DONE
```

### Resultado (2026-09-01)

- Nuevo `lua/code-runner/stream.lua` (Core puro, BOUNDARIES §7): normaliza la
  salida de un proceso a líneas completas EN ORDEN, sin partir líneas por el
  límite arbitrario de los chunks y conservando el canal (`stdout`|`stderr`).
- `stream.new({on_line, on_stdout, on_stderr})` → collector con
  `feed(channel, chunk)`, `lines()`, `line_count()`, `stats()`, `output()`,
  `reset()`.
- El pending de partial lines es **por canal** (una línea partida entre
  chunks se reconstruye en su propia canal). `output()` produce
  `{ stdout, stderr }` sin `\n` final; los canales sin datos dan `nil`
  (lista para un Result, CONTRACTS §7).
- Es el puente entre el Process Adapter (EXEC-002, `receive stdout/stderr`)
  y el destino: el terminal (EXEC-009) muestra, EXEC-006 consume en el Result.
- Hoy `terminal.lua` usa `termopen` (salida mezclada, sin canales): el stream
  aún NO alimenta el flujo real (eso es EXEC-009); se prueba Core puro.
- `tests/stream_spec.lua` (14 tests): reconstrucción de partial lines,
  interleaving en orden, output por canal, callbacks, stats/reset, y
  acceptance: la salida de una build de ejemplo se normaliza y alimenta un
  Result real (`result.failed`, EXEC-006) sin UI.
- Registrado en `tests/run.lua` (tras `process_spec.lua`).
- Suite completa: 477 pass · 0 fail · 1 skip (headless).
- Sin conflicto nuevo; Core sigue limpio (BOUNDARIES §7).

______________________________________________________________________

## EXEC-004 — Cancellation

Cancellation must target the correct Execution.

### Status

```text
DONE
```

### Resultado (2026-09-01)

- Nuevo `lua/code-runner/cancel.lua` (Core puro, BOUNDARIES §7): cancelación
  determinista por Execution (EXEC-004), en contraposición al `state.set
  "cancelled"` global de hoy.
- `cancel.cancel(exec, opts)` con:
  - **guard de identidad** `opts.expected`: solo cancela si `exec.id` coincide;
    una cancelación/on_exit de una Execution obsoleta se rechaza (nil + error)
    y NO toca la stale.
  - **terminate delegado** `opts.terminate(exec)`: detiene el proceso antes de
    marcar cancelled (el wiring enhebra `process.terminate(handle)`, EXEC-002).
    Si el terminate falla, NO se transiciona (el proceso sigue vivo).
  - `now` inyectable; transición vía `engine.cancel` (emite lifecycle event).
  - rechaza estados terminales (success/failed/cancelled) e inválidos.
- `tests/cancel_spec.lua` (10 tests): stale rejected, id correcto cancela,
  terminate invocado antes de cancel, failure de terminate no marca cancelled,
  estados activos vs terminales, evento del listener.
- Registrado en `tests/run.lua` (tras `stream_spec.lua`).
- Suite completa: 487 pass · 0 fail · 1 skip (headless).
- NO se tocó `terminal.lua`/`init.lua` (el stop real sigue cerrando buffer/
  `state.set "cancelled"`); el wiring de cancel al job real es EXEC-009.
- Sin conflicto nuevo; Core sigue limpio.

______________________________________________________________________

## EXEC-005 — Restart

Restart should create a new Execution.

Do not mutate the identity of an existing completed/running execution.

### Status

```text
DONE
```

### Resultado (2026-09-01)

- Nuevo `lua/code-runner/restart.lua` (Core puro, BOUNDARIES §7): re-ejecutar
  SIEMPRE como una Execution nueva (EXEC-005).
- `restart.restart(prev, spec)` → crea una Execution fresca (id nuevo, status
  `created`, timestamps/result nil) heredando task_id/context/command de `prev`
  (overrides aceptados). `prev` NUNCA se muta — identidad, status, timestamps
  y result quedan intactos.
- `restart.same_identity(a, b)` — guard de "no mutar identidad".
- `tests/restart_spec.lua` (9 tests): restart de success/failed/cancelled/
  running con identidad nueva, no-mutación del prev verificada campo a campo,
  overrides, y acceptance de repetir un fallo con identidad nueva.
- Registrado en `tests/run.lua` (tras `cancel_spec.lua`).
- Suite completa: 496 pass · 0 fail · 1 skip (headless).
- El `run_last` real (init.lua/re-run del comando guardado) sigue en el flujo
  productivo; el wiring del restart al job real es EXEC-009. Acá solo se
  garantiza el modelo de identidad.
- Sin conflicto nuevo; Core sigue limpio.

______________________________________________________________________

## EXEC-006 — Result Handling

Convert process termination into Result.

### Status

```text
DONE
```

### Resultado (2026-09-01)

- Nuevo `lua/code-runner/result_handler.lua` (Core puro, BOUNDARIES §7):
  convierte la terminación (on_exit: code/signal) en un Result (CONTRACTS §7)
  y lo adjunta a la Execution vía `engine.finish`.
- `result_handler.complete(exec, opts)` con:
  - **identity guard** `opts.expected`: un on_exit tardío de un job reemplazado
    se rechaza sin tocar la Execution actual (EXEC-004/EXEC-005 consistency).
  - stdout/stderr/duration opcionales — fuente real del stream (EXEC-003);
    un termopen no los entrega, quedan nil.
  - solo finaliza activas (starting/running); terminales se rechazan sin pisar
    el Result ya guardado; sin code ni signal se rechaza (indeterminado).
  - `from_on_exit(info)` → Result canónico (solo campos del contrato).
- `tests/result_handler_spec.lua` (11 tests): code 0→success, code!=0/signal→
  failed, capture de output/duration, canónico, acceptance de stale on_exit,
  expected correcto, estados terminales/created rechazados, signal 0 = éxito.
- Registrado en `tests/run.lua` (tras `restart_spec.lua`).
- Suite completa: 507 pass · 0 fail · 1 skip (headless).
- El `_on_exit` real (terminal.lua) sigue escribiendo estado/quickfix
  (B1 discard); el wiring del adaptador de proceso real es EXEC-009.
- Sin conflicto nuevo; Core sigue limpio.

______________________________________________________________________

## EXEC-007 — Execution Events

Emit lifecycle events.

### Status

```text
DONE
```

### Resultado (2026-10-09)

- `lua/code-runner/lifecycle_events.lua` (Core puro, ya existente) formalizado
  como contrato: `event_for/names/exits` con paridad `CodeRunnerStart/
  Success/Failed/Cancelled + Exit`, `created/starting` silenciosos como
  `events.lua` legacy. `data()` deriva payload de `Execution`
  (`status/action/task_id/command/cwd/filetype/code`); `cwd` ahora prefiere
  `command.cwd` canónico (CONTRACTS §8) con fallback a `ctx`/project root.
  `for_transition/event_names`-a descriptores en orden, sin side effects.
- `lua/code-runner/engine.lua`: `set_listener` valida `function|nil` (assert,
  programmer error) y `emit` aísla con `pcall` — un listener que lanza no
  rompe la transición (robustez EXEC-007).
- Tests: `lifecycle_events_spec.lua` (13 tests) + 2 nuevos en
  `engine_spec.lua` (rechazo no-function, listener throw no rompe).
  Suite: 527 pass · 0 fail · 2 skip.
- NO wiring al job real: el adapter vim (`nvim_exec_autocmds` sobre
  `events.lua`) queda para EXEC-009. Sin conflictos nuevos; Core limpio
  (BOUNDARIES §7).

______________________________________________________________________

## EXEC-008 — History Integration

Store Execution-derived history.

### Status

```text
DONE
```

### Resultado (2026-10-09)

- `history.from_execution(exec, now)` puro: entrada canónica `version=1`
  (`task_id/execution_id/status/cmd/command/cwd/key/context/result/ts`);
  `cmd`/`cwd`/`key` por compat con UI legacy (`run_history` sigue leyendo
  `.cmd`), clonado sin compartir refs, validación con `(nil, err)`.
- `history.add_execution(exec)`: dedup por `(task_id + cmd + cwd)` con `count`,
  upgrade de legacy mismo `cmd+cwd` sin duplicar, `trim` por `max`,
  respeta `history.enabled`, no escribe en inválido.
- Flujo real intacto (`init.lua` sigue en `add` legacy): migración del
  consumidor a EXEC-009. Tests: 7 nuevos en `history_spec.lua`.
  Suite: 534 pass · 0 fail · 2 skip. Sin conflictos nuevos.

______________________________________________________________________

## EXEC-009 — Terminal Adapter

Make terminal UI consume Execution output instead of owning execution lifecycle.

### Status

```text
IN PROGRESS (slice 1 DONE, 2026-10-09)
```

### Resultado slice 1 — tracking Engine sobre el job real

- Nuevo `lua/code-runner/terminal/tracking.lua` (dueño de `current_exec`):
  `start(cmd, key, label)` crea la Execution con `task.id(key, label)`
  (ADR-002) y la lleva a running; `finish(code, expected)` con identity guard
  (on_exit tardío ignorado); `cancel()`/`fail_launch()`; `get()/events()` para
  introspección. Todo best-effort: si el comando no normaliza se sigue legacy.
- `terminal.open/_on_exit/_close_current` delegan sin cambiar el path legacy
  (state/quickfix/buffer intactos). Además dos fixes de robustez de la
  auditoría: `.. command` (tabla) → `tostring(cmd)` y guards
  `nvim_buf_is_valid` en cleanup.
- Sin doble emisión (descriptores expuestos, despacho sigue legacy) y sin
  doble historial (registro al lanzar sigue legacy; migración a
  `add_execution` = slice 2 en init).
- Excepción documentada: el spawn sigue siendo `termopen`; el puerto
  `process` con PTY queda para un slice posterior.
- Tests: 3 nuevos en `terminal_spec.lua`. Suite: 537 pass · 0 fail · 2 skip.
- Slices restantes: init → `add_execution` + task_id en `run_last` (criterios
  2 parcial/3), despacho de eventos Engine (criterio 2), spawn por puerto
  (criterio 1), workflow sobre Engine (criterio 5).

### Endurecimiento slice 1b — vigilancia de identidad/guards (2026-10-09)

Respuesta a 4 puntos de vigilancia antes de avanzar:

1. **Identidad**: `start()` crea Execution nueva (id fresco) por lanzamiento;
   `task_id` estable por key+label. El reemplazo cancela la anterior: ninguna
   queda running huérfana. `open()` también cancela el tracking al reemplazar
   un job en marcha.
2. **Guard barrera**: `finish(code, expected)` ignora stale sin tocar
   `current` (A tardía no toca B; B válida sí finaliza; doble finish no-op).
3. **Fallback explícito**: `skip_reason()` expone `{reason, detail, cmd}`
   cuando el comando no normaliza (`&&`); `get()==nil`, nada a medio
   inicializar; un start válido lo limpia.
4. **Cancelación**: `cancel → on_exit` ignorado (ya terminal); `fail_launch`
   solo con expected vigente. Reconocido: `cancel` del tracking no mata el
   proceso real (lo hace el buffer delete); el puerto con terminate es slice
   posterior.
- Nuevo `tests/tracking_spec.lua` (13 tests unitarios, sin terminales).
  Suite: 550 pass · 0 fail · 2 skip.

### Slice 2 — identidad en historial y last (2026-10-09)

- `terminal.open` devuelve el `exec_id` trackeado (nil si no normalizó);
  `execute_action` usa el id devuelto (nunca el global) para no leer tracking
  obsoleto con open stubbeado.
- `history.add(cmd, cwd, key, opts?)` con `{task_id, execution_id, status}`
  opcional; relanzamiento legacy hereda task_id/status sin degradar (pero
  nunca hereda execution_id viejo).
- `build_run/run_history/run_last` propagan `task_id` a `last_choice`
  (persistido); `run_last` sigue re-ejecutando el comando — la resolución por
  task_id es slice 3. `run_history` nunca degrada identidad existente.
- Tests: 3 en `history_spec.lua` + 2 en `init_spec.lua`.
  Suite: 555 pass · 0 fail · 2 skip. Sin cambios de comportamiento.

### Slice 3 — task_id operativo en run_last/run_history (2026-10-09)

Contrato (salvedad del brief): la identidad persistida alcanza para
reconstruir la intención porque `last` persiste `vars` (`$testName`, ...)
e historial persiste `vars` desde este slice (`history.add` opts `vars`,
clonadas). Sin vars, solo replay del comando guardado (siempre persistido).

- Nuevo `lua/code-runner/task_resolve.lua` (Application, extraído por
  responsabilidad con contrato claro — no por líneas): `resolve(task_id,
  {lang, test_name})` → def `{label, template, key}` o `(nil, reason)` con
  `no-catalog-entry|task-desconocida|command-funcion|test-no-aplica`.
  Catálogo por comparación de `task.id` (icon-proof); test contextual
  reconstruido desde `$testName` y VERIFICADO (sin resolución silenciosa).
- `run_last`: con task_id resuelve plantilla vigente + re-sustituye con vars
  persistidas; si no resuelve, fallback legacy explícito (replay). Nunca duro.
- `run_history`: con task_id + vars resuelve; sin task_id, sin vars o sin
  resolución, replay del comando guardado. El `status` registrado nunca
  decide (invariante 3). Cada relanzamiento crea Execution nueva: el
  `execution_id` del historial siempre apunta a la última (invariante 1).
- Tests: 9 en `task_resolve_spec.lua` + 2 vars en `history_spec.lua` + 5 en
  `init_spec.lua` (plantilla vigente vs replay, tarea eliminada, failed
  re-ejecuta, task desconocida, ids frescos).
  Suite: 571 pass · 0 fail · 2 skip.

### Slice 4 — fuente única de eventos y Result (2026-10-09)

- `state.set(status, info, opts)` con `opts.emit = false`: espeja sin
  autocmds (default emite: path legacy y tests intactos).
- `tracking.dispatch()`: dispara los descriptores como autocmds `User`,
  respeta `events.enabled`, cada listener aislado con pcall (un autocmd de
  usuario que lanza no rompe el exit). Devuelve conteo.
- `terminal._on_exit`: con `exec_id` vigente el Engine finaliza (única
  fuente de Result), el estado espeja en silencio y los eventos salen del
  dispatch — una emisión por transición; quickfix sigue consumiendo el exit.
  Sin tracking, path legacy intacto. Stale no toca nada (ninguna vía).
- `_close_current` y reemplazo en `open` vía `mirror_cancel()`: Engine
  cancela + espejo silencioso + dispatch, o legacy si no había tracking.
  `fail_launch` también expone descriptores y sigue el mismo espejo.
- Historial: sin cambios (registro al lanzar; slice 2). Ninguna duplicación.
- Tests: 3 dispatch en `tracking_spec.lua` + 3 en `terminal_spec.lua`
  (emisión única Success/Exit, Cancelled/Exit, quickfix cableado) + 1 en
  `state_spec.lua` (emit=false).
  Suite: 578 pass · 0 fail · 2 skip.
- Resta de EXEC-009: spawn por puerto `process` con PTY, workflow sobre el
  Engine, despacho legacy en `events.emit` aún sin pcall (preexistente).

### Slice 5 — spawn por el puerto con PTY (2026-10-09)

- Nuevo `lua/code-runner/terminal/pty.lua`: adapter `spawn/send/terminate`
  sobre `termopen` (CONTRACTS §19). Límites explícitos: sin `on_stdout` (el
  PTY vuelca al buffer), `signal = nil` (termopen no entrega), `opts.buf`
  obligatorio. Normaliza el fallo (`0` y `-1` → nil+err; el legacy solo
  miraba `-1`).
- `terminal.open` lanza por `process.spawn` (mismo `wrap_command` como
  `cmd[]`); `pty.launch` concentra el CÓMO e instala el PTY perezosamente
  (un mock inyectado se respeta). Sin camino paralelo de lifecycle.
- `process_spec` limpia su mock al final (higiene: los specs con jobs reales
  usan el puerto después).
- Tests: 8 en `tests/pty_spec.lua` (instalación, mock respetado, lazy
  install, exit-code real 42, buf inválido, terminate con on_exit, send,
  dos jobs sin cruzar callbacks).
  Suite: 586 pass · 0 fail · 2 skip.
- Resta de EXEC-009: workflow sobre el Engine, `events.emit` legacy sin
  pcall (preexistente).

______________________________________________________________________

# P2 — Runner Architecture

## RUN-001 — Runner Contract

Implement documented Runner contract.

______________________________________________________________________

## RUN-002 — Runner Registry

Implement built-in and runtime runner registration.

______________________________________________________________________

## RUN-003 — Built-in Runner Loader

Create lazy or efficient loading strategy.

______________________________________________________________________

## RUN-004 — Migrate Go

Use Go as first runner architecture probe.

______________________________________________________________________

## RUN-005 — Migrate Rust

Validate compiled language patterns.

______________________________________________________________________

## RUN-006 — Migrate Python

Validate script/interpreter patterns.

______________________________________________________________________

## RUN-007 — Migrate JavaScript/TypeScript

Validate ecosystem/project-aware behavior.

______________________________________________________________________

## RUN-008 — Migrate Java

Validate complex project behavior.

______________________________________________________________________

## RUN-009 — Remaining Runners

Only after the architecture proves stable.

______________________________________________________________________

# Working Rule

If a migration requires a special-case change to Core:

```text
STOP
```

Then determine whether:

```text
Runner contract
Context contract
Task contract
Command contract
```

is missing something.

Do not immediately add:

```lua
if language == ...
```

to Core.
