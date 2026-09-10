# CodeRunner.nvim Architecture

## Status

This document is normative.

If implementation and this document disagree, the implementation should be considered suspect until the discrepancy is intentionally resolved.

Architectural changes must be reflected here.

______________________________________________________________________

# 1. Architectural Goal

CodeRunner.nvim must support:

```text
many languages
many runtimes
many task types
many project structures
many configuration strategies
```

without turning the core into a language-specific conditional system.

The architecture must allow:

```text
Add runner
```

without:

```text
Modify core
Modify terminal
Modify picker
Modify execution
Modify history
```

______________________________________________________________________

# 2. High-Level Architecture

```text
                         User
                           │
                           ▼
                    ┌─────────────┐
                    │     UI      │
                    │ picker/cmds │
                    └──────┬──────┘
                           │
                           ▼
                 ┌───────────────────┐
                 │   Application      │
                 │                   │
                 │ run               │
                 │ stop              │
                 │ restart           │
                 │ resolve           │
                 │ workflow          │
                 └─────────┬─────────┘
                           │
                           ▼
                 ┌───────────────────┐
                 │       Core        │
                 │                   │
                 │ Task              │
                 │ Execution         │
                 │ Command           │
                 │ Context           │
                 │ Result            │
                 └─────────┬─────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
          Registry      Context      Execution
                                      Port
                                         │
                                         ▼
                                  ┌─────────────┐
                                  │  Adapters   │
                                  │             │
                                  │ terminal    │
                                  │ shell       │
                                  │ process     │
                                  │ persistence │
                                  │ diagnostics │
                                  └─────────────┘
```

______________________________________________________________________

# 3. Architectural Layers

## 3.1 Core

Contains domain concepts and rules.

Core concepts:

- Task
- Execution
- Command
- Context
- Result
- Errors

Core MUST NOT depend on Neovim UI.

Core SHOULD be testable without launching a full Neovim UI environment whenever practical.

______________________________________________________________________

## 3.2 Application

Coordinates use cases.

Examples:

```text
run
run_last
stop
restart
resolve tasks
execute task
run workflow
```

Application knows how to coordinate core objects and ports.

Application MUST NOT contain language-specific runner implementations.

______________________________________________________________________

## 3.3 Registry

Registry manages runtime definitions.

There are two primary registries:

```text
Task Registry
Runner Registry
```

Runner Registry describes available runners.

Task Registry contains resolved/registered tasks.

______________________________________________________________________

## 3.4 Context

Context provides information about the current environment.

Examples:

```text
current file
filetype
project root
project type
test
entrypoint
cursor
buffer
workspace
```

Context detection must remain independent from task execution.

______________________________________________________________________

## 3.5 Execution

Execution owns the lifecycle of a running task.

Lifecycle:

```text
created
    ↓
starting
    ↓
running
    ↓
 ┌──┼─────────┐
 ▼  ▼         ▼
success failed cancelled
```

Execution owns:

- execution identity
- status
- process lifecycle
- result
- timestamps
- cancellation
- restart semantics
- lifecycle events

______________________________________________________________________

## 3.6 Adapters

Adapters connect the application/core to external systems.

Examples:

```text
Neovim terminal
Neovim diagnostics
quickfix
shell
process spawning
filesystem
persistence
notifications
autocmd/events
```

Adapters may depend on Neovim APIs.

Core should not.

______________________________________________________________________

## 3.7 UI

UI is responsible for presentation.

Examples:

```text
picker
terminal UI
highlighting
notifications
command-line integration
```

UI must not contain domain rules.

______________________________________________________________________

# 4. Dependency Direction

The intended dependency direction is:

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

Runner definitions depend on contracts exposed by Core/Application.

The reverse is forbidden.

For example:

```text
GOOD:

runner → TaskSpec
runner → Context

BAD:

core → runner/go.lua
runner/go.lua → terminal.lua
runner/go.lua → picker.lua
```

______________________________________________________________________

# 5. Task

A Task is an executable definition.

Conceptually:

```lua
{
    id = "go.test",
    name = "Test",
    kind = "test",

    filetypes = {
        "go",
    },

    command = "go test ./...",

    cwd = "project",

    condition = function(context)
        ...
    end,
}
```

Task identity:

```text
id
```

Task presentation:

```text
name
description
icon
```

must remain separate.

______________________________________________________________________

# 6. Execution

An Execution is a runtime instance of a Task.

Conceptually:

```lua
{
    id = 42,

    task_id = "go.test",

    context = {...},

    command = {...},

    status = "running",

    process = {
        pid = 1234,
    },

    started_at = ...,
    finished_at = nil,

    result = nil,
}
```

Multiple executions may exist for the same Task.

Example:

```text
go.test
 ├── Execution #41
 ├── Execution #42
 └── Execution #43
```

The architecture must not assume one execution per task.

______________________________________________________________________

# 7. Command

A Command is the resolved executable representation of a Task.

User-friendly:

```lua
command = "go test $file"
```

may become:

```lua
{
    executable = "go",
    args = {
        "test",
        "/project/foo_test.go",
    },

    cwd = "/project",
}
```

Command resolution belongs to the application/core boundary.

Shell-specific quoting and process invocation belong to adapters.

______________________________________________________________________

# 8. Context

Context is immutable input for task resolution whenever practical.

Example:

```lua
{
    file = "/project/foo_test.go",

    filetype = "go",

    cursor = {
        line = 42,
        column = 10,
    },

    project = {
        root = "/project",
        marker = "go.mod",
    },

    test = {
        name = "TestFoo",
    },

    entrypoint = nil,
}
```

Context detection should be cached when possible.

Cache invalidation must account for relevant editor state.

______________________________________________________________________

# 9. Runner

A Runner describes a language, runtime, framework, or ecosystem.

Example:

```lua
{
    id = "go",

    filetypes = {
        "go",
    },

    project = {
        markers = {
            "go.mod",
        },
    },

    tasks = {
        {
            id = "go.run",
            name = "Run",
            kind = "run",
            command = "go run $file",
        },

        {
            id = "go.build",
            name = "Build",
            kind = "build",
            command = "go build $file",
        },

        {
            id = "go.test",
            name = "Test",
            kind = "test",
            command = "go test ./...",
        },
    },
}
```

A Runner MUST NOT own process lifecycle.

______________________________________________________________________

# 10. Runner Resolution

The resolution pipeline is:

```text
Current Editor Context
        ↓
Candidate Runners
        ↓
Runner Detection
        ↓
Available Tasks
        ↓
Task Conditions
        ↓
Resolved Tasks
        ↓
Presentation
```

The system should avoid expensive detection for every runner when cheap signals can narrow the candidates.

Potential signals:

```text
filetype
extension
project markers
known files
available executables
project configuration
current file location
```

______________________________________________________________________

# 11. Zero-Config Resolution

Zero-config behavior is implemented through built-in runners.

Conceptually:

```text
Built-in Runner Definitions
        ↓
Runner Registry
        ↓
Context Resolution
        ↓
Task Resolution
```

User configuration modifies or extends this behavior.

Configuration does not replace the core registry.

______________________________________________________________________

# 12. Configuration Precedence

Unless a future ADR explicitly changes this:

```text
Built-in defaults
        ↓
User configuration
        ↓
Project configuration
        ↓
Runtime registration
```

More specific configuration wins over less specific configuration.

The merge semantics must be deterministic and documented.

______________________________________________________________________

# 13. Project Detection

Project detection provides a project context.

Examples of markers:

```text
package.json
go.mod
Cargo.toml
pom.xml
build.gradle
.git
```

Project detection must not execute arbitrary commands.

It should primarily inspect filesystem/editor state.

______________________________________________________________________

# 14. Project Configuration

Project-local configuration may define custom tasks and overrides.

Project configuration is executable Lua when `.code-runner.lua` is used.

This must be treated as trusted project code.

The plugin must not pretend that arbitrary Lua can be safely sandboxed by superficial restrictions.

______________________________________________________________________

# 15. Execution Engine

The Execution Engine is the only component responsible for turning a resolved Command into an Execution.

Responsibilities:

```text
create execution
start process
stream output
track process
cancel process
complete execution
produce result
emit lifecycle events
```

It must not decide:

```text
which task the user wants
how the picker looks
how diagnostics are displayed
```

______________________________________________________________________

# 16. Terminal

Terminal is an execution/output adapter.

It is not the execution engine.

The intended relationship is:

```text
Execution Engine
      ↓
Process / Output
      ↓
Terminal Adapter
      ↓
Terminal UI
```

A future headless execution mode must be possible without requiring terminal UI.

______________________________________________________________________

# 17. Workflow

A Workflow composes tasks.

Example:

```text
build
  ↓
test
  ↓
run
```

Workflow does not implement process execution itself.

Instead:

```text
Workflow
   ↓
Task A
   ↓
Execution Engine

Task B
   ↓
Execution Engine
```

This guarantees consistent behavior for:

- output
- cancellation
- history
- events
- diagnostics
- errors
- result handling

______________________________________________________________________

# 18. Diagnostics

Execution output is not diagnostics.

The intended pipeline is:

```text
Process Output
      ↓
Output Parser
      ↓
Diagnostic[]
      ↓
Diagnostics Adapter
```

Quickfix is another presentation adapter:

```text
Diagnostic[]
      ↓
Quickfix Adapter
```

Parsers must not directly manipulate quickfix or diagnostic state.

______________________________________________________________________

# 19. History

History records executions.

A history entry should preserve enough information to understand and reproduce a previous execution.

At minimum:

```text
execution id
task id
command
cwd
context where relevant
result
timestamp
```

History must not become the source of truth for task definitions.

______________________________________________________________________

# 20. Last Run

`run_last` should reference task identity rather than blindly replaying an old command.

Preferred:

```lua
{
    task_id = "go.test",
    context = ...,
}
```

Then:

```text
resolve task
      ↓
resolve current command
      ↓
execute
```

This allows task definitions to evolve.

______________________________________________________________________

# 21. Events

Events communicate lifecycle changes.

Internal conceptual events:

```text
execution.created
execution.started
execution.output
execution.completed
execution.failed
execution.cancelled
```

Neovim-specific autocmds are adapters over this event model.

______________________________________________________________________

# 22. Error Handling

Errors should be categorized.

At minimum:

```text
configuration error
resolution error
command error
process error
execution failure
adapter error
```

A process exiting with a non-zero code is normally an execution result, not necessarily an internal plugin error.

______________________________________________________________________

# 23. Performance

Performance priorities:

1. low startup cost
1. lazy loading
1. cheap context resolution
1. cached expensive detection
1. avoid loading unnecessary runners
1. avoid scanning the filesystem repeatedly
1. avoid process spawning for detection unless explicitly justified

The number of supported runners should not linearly increase startup cost.

______________________________________________________________________

# 24. Architectural Invariants

These are non-negotiable unless intentionally changed through an ADR.

### Invariant 1

Adding a runner must not require modifying the execution engine.

### Invariant 2

Changing the picker must not require modifying Task.

### Invariant 3

Changing terminal UI must not require modifying Execution.

### Invariant 4

Changing diagnostics presentation must not require modifying parsers.

### Invariant 5

Workflow must use the same Execution Engine as standalone tasks.

### Invariant 6

Task identity must not depend on presentation labels.

### Invariant 7

Core must not depend directly on Neovim UI APIs.

### Invariant 8

Zero-config behavior must be provided by normal architecture, not special-case execution paths.

### Invariant 9

Expanding language support must primarily add runner definitions.

### Invariant 10

No architectural abstraction may be introduced without a documented reason.
