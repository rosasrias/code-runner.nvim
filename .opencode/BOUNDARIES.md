# CodeRunner.nvim Dependency Boundaries

This document defines which modules may depend on which architectural areas.

The goal is to prevent architectural drift, especially during AI-assisted development.

______________________________________________________________________

# 1. Dependency Rule

Dependencies point inward.

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

Concrete implementations must not leak upward.

______________________________________________________________________

# 2. Core

## May depend on

- Lua standard functionality
- internal domain modules
- pure utility modules

## Must NOT depend on

- `vim.ui`
- `vim.api` for presentation
- picker
- terminal UI
- quickfix
- diagnostics
- notifications
- specific runner implementations
- specific languages

______________________________________________________________________

# 3. Application

## May depend on

- Core
- Registry
- Context
- Ports
- configuration abstractions

## Must NOT depend directly on

- language-specific terminal logic
- picker internals
- quickfix internals
- terminal buffer implementation

______________________________________________________________________

# 4. Registry

## May depend on

- Task contracts
- Runner contracts

## Must NOT depend on

- terminal
- picker
- quickfix
- diagnostics
- process implementation

______________________________________________________________________

# 5. Runners

## May depend on

- Task contracts
- Runner contracts
- Context contracts
- runner-specific pure helpers

## Must NOT depend on

- picker
- terminal UI
- quickfix
- diagnostics
- history implementation
- global execution state

A runner describes tasks.

A runner does not execute them.

______________________________________________________________________

# 6. Context

## May depend on

- filesystem abstractions
- Neovim editor state through adapters
- pure detection logic

## Must NOT depend on

- terminal
- picker
- execution engine
- history
- quickfix

______________________________________________________________________

# 7. Execution

## May depend on

- Command contract
- Context
- process port
- event port

## Must NOT depend on

- picker
- quickfix
- language-specific runners
- terminal window layout

______________________________________________________________________

# 8. Terminal Adapter

## May depend on

- Neovim APIs
- Execution output
- terminal buffer/UI helpers

## Must NOT decide

- which Task is selected
- which Runner is active
- project detection
- task resolution

______________________________________________________________________

# 9. Diagnostics Adapter

## May depend on

- Neovim diagnostics APIs
- Diagnostic contracts

## Must NOT depend on

- compiler-specific parsing rules

______________________________________________________________________

# 10. Parsers

## May depend on

- pure parsing utilities
- Diagnostic contracts

## Must NOT depend on

- Neovim diagnostics
- quickfix
- terminal
- picker
- execution state

______________________________________________________________________

# 11. UI

## May depend on

- application API
- presentation models
- Neovim APIs

## Must NOT implement

- runner detection
- command parsing
- process lifecycle
- project detection

______________________________________________________________________

# 12. Project Configuration

Project configuration may depend on:

- public configuration API
- Task registration
- Runner registration

It should not mutate internal state directly.

______________________________________________________________________

# 13. Forbidden Dependency Examples

### Forbidden

```text
Go Runner
    ↓
terminal.lua
```

### Correct

```text
Go Runner
    ↓
TaskSpec
    ↓
Application
    ↓
Execution Engine
    ↓
Terminal Adapter
```

______________________________________________________________________

### Forbidden

```text
Parser
    ↓
vim.fn.setqflist()
```

### Correct

```text
Parser
    ↓
Diagnostic[]
    ↓
Quickfix Adapter
    ↓
vim.fn.setqflist()
```

______________________________________________________________________

### Forbidden

```text
Picker
    ↓
go.run command construction
```

### Correct

```text
Picker
    ↓
Task ID
    ↓
Application
    ↓
Task Resolver
    ↓
CommandSpec
```

______________________________________________________________________

# 14. Architecture Smell

The following patterns indicate that a boundary may be wrong:

```text
if filetype == "go" then ...
```

inside core modules.

Or:

```text
if runner == "python" then ...
```

inside execution.

Or:

```text
if terminal_mode == ... then ...
```

inside Task.

Or:

```text
vim.api...
```

inside domain objects.

These are signals to stop and reconsider the boundary.

______________________________________________________________________

# 15. Dependency Review Rule

When adding a module, the author/agent must answer:

```text
Which layer does this belong to?
What may it depend on?
What depends on it?
Why does this boundary exist?
```

If these questions cannot be answered clearly, the module is not ready to be added.

______________________________________________________________________

# 16. Current Migration State (ARCH-007, 2026-09-01)

This document describes the *target* boundaries. Not every module has migrated
yet. The following is the current (real) state as validated by ARCH-007.

## Clean Core (match §2)

```text
task.lua
command.lua
result.lua
execution.lua
task_registry.lua
```

Pure domain, no `vim.ui` / terminal / quickfix / picker / runners.

## Known Violations (migration candidates)

```text
B1  Runners depend on the Terminal Adapter                      (§5)
      actions/java.lua             -> terminal
      actions/latex.lua            -> terminal
      actions/languages/compiled.lua -> terminal (lazy)

B2  Runners depend on the process adapter `shell` ("describes, not executes")
      actions/catalog.lua          -> shell
      actions/languages/compiled.lua -> shell
      workflow.lua                 -> shell
      actions.lua                  -> shell

B3  Application couples to the Terminal Adapter directly        (§3)
      actions.lua                 -> terminal
      workflow.lua                 (EXEC-009 slice 6: lifecycle via Engine +
                                   headless adapter over jobstart; still
                                   produces {cmd, code} per step)

B4  `shell` is cross-layer: interpolation helper + process adapter; classified
    as Adapter, not Core. Duplicated `&&` parsing with Core `command.lua` (C9).

EXEC-009 slices 1–6 (2026-10-09): terminal launches through the `process`
port (terminal/pty.lua) and tracks jobs as Engine Executions with single
event dispatch; workflow steps run as Engine Executions via headless.lua
(same contract, used directly — no adapter registry yet). Residual second
paths: workflow `run_step` contract still callback-based; `state.lua` legacy
store still mirrors the Engine.

## Authority: Engine decides, state.lua reflects (slice 8, 2026-10-09)

```text
Engine                  owns Execution transitions (created → … → terminal)
state.lua               read-model projection for legacy/UI consumers
                        (status/action/cwd/filetype/buf/code + run_id)
events                  single emission per transition: tracking.dispatch()
                        on Engine paths; legacy state.emit only where no
                        Engine tracks (explicit compat branches)
```

```text
run_id                  visible-session generation, terminal-scoped, for
                        legacy stale guards. NOT Execution.id (Engine-global
                        sequence, includes workflow steps). Never
                        interchangeable; carried in parallel during migration.
```

Writers of `state.set`: terminal open/exit/cancel/replace (silent mirror
when Engine tracks, emitting legacy otherwise) + `init._stop_silent`
fallback when the buffer is already gone. Readers: running/buf/run_id
guards, public `state()`, autocmd payloads (legacy shape).

## Workflow execute* contract (slice 9, 2026-10-09)

```text
execute/execute_parallel   public sync deterministic orchestration core
                           (steps + advance rules over injected run_step);
                           transitions one Engine Execution per step.
run/run_parallel           productive async paths: same policy + Engine
                           lifecycle + headless spawn per step.
```

No parallel lifecycle anywhere: sync core and async paths share Engine
transitions with identical step identity (`task.id(name, "step-N")`).
```

These are intentional, documented migration candidates, not silent drift. Each
is tracked in `STATE.md` and resolved on the roadmap (EXEC / Registry phases).

