# CodeRunner.nvim Domain Contracts

This document defines the conceptual contracts between the main architectural components.

These contracts are more important than the current implementation.

Implementation may change.

The concepts should remain stable.

______________________________________________________________________

# 1. TaskSpec

A TaskSpec describes something the user can execute.

Conceptual shape:

```lua
---@class CodeRunnerTaskSpec
---@field id string
---@field name string
---@field kind CodeRunnerTaskKind
---@field filetypes string[]|nil
---@field command string|CodeRunnerCommandSpec|function
---@field cwd string|function|nil
---@field condition function|nil
---@field enabled boolean|function|nil
---@field description string|nil
```

Required:

```text
id
name
kind
command
```

______________________________________________________________________

# 2. Task ID

Task IDs are stable identifiers.

Examples:

```text
go.run
go.build
go.test

rust.run
rust.build
rust.test

python.run
python.test
```

Rules:

- IDs must be deterministic.
- IDs must not contain presentation text.
- IDs must not depend on icons.
- IDs must not depend on localization.
- IDs should remain stable across UI changes.

______________________________________________________________________

# 3. Task Kind

Initial supported kinds:

```text
run
build
test
debug
lint
format
misc
```

The list may grow through an ADR.

Kind is metadata.

It must not determine execution implementation.

______________________________________________________________________

# 4. Runner Contract

A Runner provides:

```text
identity
detection metadata
tasks
optional context resolvers
optional task generators
```

Conceptual:

```lua
---@class CodeRunnerRunner
---@field id string
---@field filetypes string[]|nil
---@field project table|nil
---@field tasks CodeRunnerTaskSpec[]|function
```

A Runner does not:

```text
spawn processes
open terminal windows
write diagnostics
modify quickfix
render picker UI
```

______________________________________________________________________

# 5. Execution Contract

Execution represents one attempt to execute a Task.

Conceptual:

```lua
---@class CodeRunnerExecution
---@field id integer|string
---@field task_id string
---@field context CodeRunnerContext
---@field command CodeRunnerCommandSpec
---@field status CodeRunnerExecutionStatus
---@field started_at number|nil
---@field finished_at number|nil
---@field result CodeRunnerResult|nil
```

Possible statuses:

```text
created
starting
running
success
failed
cancelled
```

______________________________________________________________________

# 6. Execution Identity

Every execution must have a unique identity during its lifetime.

Example:

```text
Execution #42
```

This identity is used to prevent stale callbacks from modifying newer executions.

______________________________________________________________________

# 7. Execution Result

Conceptual:

```lua
---@class CodeRunnerResult
---@field code integer|nil
---@field signal integer|nil
---@field stdout string|nil
---@field stderr string|nil
---@field duration number|nil
```

A non-zero process exit code is normally:

```text
ExecutionResult
```

rather than:

```text
InternalPluginError
```

______________________________________________________________________

# 8. CommandSpec

CommandSpec represents an executable command after resolution.

Conceptual:

```lua
---@class CodeRunnerCommandSpec
---@field executable string
---@field args string[]
---@field cwd string|nil
---@field env table<string,string>|nil
```

Optional future fields:

```text
stdin
timeout
shell
shell_args
```

Do not add these until required.

______________________________________________________________________

# 9. Command String Syntax

Human-friendly commands may use:

```text
$file
$filePath
$dir
$stem
$project
$testName
```

The exact variable list must be defined in implementation documentation.

Command strings are input syntax.

They are not the internal execution model.

______________________________________________________________________

# 10. Context Contract

Conceptual:

```lua
---@class CodeRunnerContext
---@field file string|nil
---@field filetype string|nil
---@field extension string|nil
---@field cursor CodeRunnerCursor|nil
---@field project CodeRunnerProjectContext|nil
---@field test CodeRunnerTestContext|nil
---@field entrypoint CodeRunnerEntrypointContext|nil
```

Context should be treated as read-only by task resolution.

______________________________________________________________________

# 11. Project Context

Conceptual:

```lua
---@class CodeRunnerProjectContext
---@field root string|nil
---@field marker string|nil
---@field kind string|nil
```

Future metadata may include:

```text
package manager
workspace
manifest
source roots
```

Only add metadata when real task resolution needs it.

______________________________________________________________________

# 12. Test Context

Conceptual:

```lua
---@class CodeRunnerTestContext
---@field name string|nil
---@field file string|nil
---@field line integer|nil
---@field framework string|nil
```

A test detector must not execute the test.

It only describes the detected test context.

______________________________________________________________________

# 13. Entrypoint Context

Conceptual:

```lua
---@class CodeRunnerEntrypointContext
---@field name string|nil
---@field file string|nil
---@field line integer|nil
```

______________________________________________________________________

# 14. Task Resolution Contract

Input:

```text
Context
+
Runner Registry
+
Task Registry
+
Configuration
```

Output:

```text
Resolved Task[]
```

Resolution must be deterministic for identical inputs.

______________________________________________________________________

# 15. Task Resolver

The Task Resolver may:

- filter by filetype
- filter by project
- evaluate conditions
- resolve dynamic commands
- resolve context variables
- apply configuration
- generate contextual tasks

It must not:

- open UI
- spawn processes
- manipulate terminal buffers
- write quickfix
- write diagnostics

______________________________________________________________________

# 16. Task Registry

Required operations:

```text
register(task)
unregister(task_id)
get(task_id)
list()
```

Potential future:

```text
resolve(context)
```

The registry must preserve Task identity.

______________________________________________________________________

# 17. Runner Registry

Required operations:

```text
register(runner)
unregister(runner_id)
get(runner_id)
list()
```

Runner registration should be independent from execution.

______________________________________________________________________

# 18. Execution Engine Contract

Input:

```text
CommandSpec
Context
Task identity
```

Output:

```text
Execution
```

Responsibilities:

```text
start
stream
cancel
finish
produce result
emit lifecycle events
```

The engine must not decide what UI should display.

______________________________________________________________________

# 19. Process Adapter Contract

A process adapter provides:

```text
spawn
send input
terminate
receive stdout
receive stderr
receive exit
```

The exact Neovim implementation may use:

```text
vim.system
vim.fn.jobstart
vim.fn.termopen
```

but the rest of the application must not depend on those APIs directly.

______________________________________________________________________

# 20. Terminal Adapter Contract

The terminal adapter consumes execution output.

It may:

- create terminal buffers
- display output
- reuse terminal buffers
- close terminal buffers
- manage terminal window layout

It must not:

- resolve Tasks
- detect projects
- decide task identity
- implement workflows

______________________________________________________________________

# 21. Output Parser Contract

Input:

```text
stdout/stderr lines
```

Output:

```text
Diagnostic[]
```

Conceptual:

```lua
{
    file = "...",
    line = 10,
    column = 5,
    severity = "error",
    message = "...",
}
```

Parser must not directly mutate:

```text
quickfix
diagnostics
buffers
UI
```

______________________________________________________________________

# 22. Diagnostics Adapter

Input:

```text
Diagnostic[]
```

Output:

```text
Neovim diagnostics
```

The adapter owns:

```text
namespace
buffer diagnostics
clear/update
```

______________________________________________________________________

# 23. Quickfix Adapter

Input:

```text
Diagnostic[]
```

Output:

```text
quickfix list
```

Quickfix presentation is independent from parser implementation.

______________________________________________________________________

# 24. History Contract

History stores completed or relevant executions.

Required capabilities:

```text
add
list
clear
```

History must not become a hidden Task Registry.

______________________________________________________________________

# 25. Last Run Contract

Last Run stores enough information to resolve a previous Task again.

Preferred:

```lua
{
    task_id = "go.test",
    context = ...,
}
```

Avoid treating the last raw shell command as the canonical identity.

______________________________________________________________________

# 26. Workflow Contract

A Workflow is a composition of Tasks.

Example:

```lua
{
    id = "verify",
    tasks = {
        "build",
        "test",
    },
}
```

A workflow may eventually support:

```text
sequential execution
parallel execution
dependencies
conditions
failure policies
```

These features must build on the Execution Engine.

______________________________________________________________________

# 27. Event Contract

Internal event names should describe domain events.

Examples:

```text
execution.created
execution.started
execution.output
execution.completed
execution.failed
execution.cancelled
```

Neovim autocmd names are external presentation/integration details.

______________________________________________________________________

# 28. Public API Contract

The public API should remain intentionally small.

Target API:

```lua
require("code-runner").setup()

require("code-runner").run()

require("code-runner").run_last()

require("code-runner").stop()

require("code-runner").restart()

require("code-runner").register_task(task)

require("code-runner").register_runner(runner)
```

Internal modules are not automatically public API.

Anything beginning with `_` is not automatically safe to rely on.

______________________________________________________________________

# 29. Contract Evolution

When changing a contract:

1. Update this document.
1. Add an ADR.
1. Update tests.
1. Update implementation.
1. Update affected documentation.
1. Verify no architectural boundary was violated.

Do not silently change domain semantics.
