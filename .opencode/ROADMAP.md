# CodeRunner.nvim Roadmap

The roadmap is organized around architectural maturity rather than feature quantity.

______________________________________________________________________

# P0 — Architecture Foundation

Goal:

Create stable internal domain concepts.

## Tasks

```text
ARCH-001 Characterization tests
ARCH-002 TaskSpec
ARCH-003 CommandSpec
ARCH-004 Result model
ARCH-005 Execution model
ARCH-006 Registry contracts
ARCH-007 Dependency boundaries
```

Exit criteria:

- Task is a first-class concept.
- Execution is a first-class concept.
- Commands have a normalized representation.
- Core boundaries are documented.
- Existing behavior remains covered by tests.

______________________________________________________________________

# P1 — Execution Core

Goal:

Create one reliable execution engine.

## Tasks

```text
EXEC-001 Execution lifecycle
EXEC-002 Process adapter
EXEC-003 stdout/stderr streaming
EXEC-004 cancellation
EXEC-005 restart
EXEC-006 result handling
EXEC-007 execution events
EXEC-008 history integration
EXEC-009 terminal adapter integration
```

Exit criteria:

Standalone tasks and future workflows can share the same execution engine.

______________________________________________________________________

# P2 — Runner Architecture

Goal:

Make language/ecosystem support modular.

## Tasks

```text
RUN-001 Runner contract
RUN-002 Runner registry
RUN-003 Built-in runner loader
RUN-004 Go migration
RUN-005 Rust migration
RUN-006 Python migration
RUN-007 JavaScript/TypeScript migration
RUN-008 Java migration
RUN-009 remaining runner migration
```

The first few runners are architecture probes.

Do not migrate everything blindly.

If runner migration reveals a broken abstraction, stop and improve the abstraction first.

Exit criteria:

Adding a new runner normally requires adding runner code only.

______________________________________________________________________

# P3 — Contextual Zero-Config

Goal:

Make contextual resolution the primary product differentiator.

## Tasks

```text
CTX-001 Context contract
CTX-002 project context
CTX-003 file context
CTX-004 test context
CTX-005 entrypoint context
CTX-006 caching
CTX-007 contextual task conditions
CTX-008 project-aware task resolution
```

Exit criteria:

The plugin can expose useful tasks based on:

```text
file
filetype
project
test
entrypoint
```

without user configuration.

______________________________________________________________________

# P4 — Advanced Tasks

Goal:

Expand task capabilities without changing the core execution model.

Potential features:

```text
task parameters
task variants
profiles
workflows
task dependencies
conditional tasks
retry
timeouts
parallel execution
DAG workflows
```

All advanced execution must use the same Execution Engine.

______________________________________________________________________

# P5 — Integrations

Potential integrations:

```text
DAP
Neotest
statusline
external task definitions
project task import
other Neovim ecosystem integrations
```

Integrations must be adapters.

They must not become part of Core.

______________________________________________________________________

# P6 — v1.0 Hardening

Goal:

Prepare a stable release.

Areas:

```text
API review
documentation
performance
health checks
error messages
migration documentation
test coverage
platform validation
Neovim compatibility
release process
```

______________________________________________________________________

# Feature Priority Rule

A feature that increases the complexity of Core should be considered high-risk.

Prefer implementing new capabilities as:

```text
Runner
Task
Context detector
Parser
Adapter
Integration
```

rather than modifying Core.

______________________________________________________________________

# Anti-Roadmap

The following are explicitly not priorities before the architecture stabilizes:

```text
more language count
large UI redesign
remote execution
task marketplace
plugin marketplace
complex scripting DSL
distributed execution
```

Feature count is not a v1.0 success metric.

Architectural stability is.
