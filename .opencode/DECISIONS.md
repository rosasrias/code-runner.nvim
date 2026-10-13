# CodeRunner.nvim Architectural Decisions

This document contains accepted architectural decisions.

Decisions should not be casually reversed.

If a decision needs to change, add a new decision explaining why.

______________________________________________________________________

# ADR-001 — Task is the primary domain concept

Status: Accepted

## Decision

CodeRunner.nvim will model executable user actions as Tasks.

The old `action → command` representation is considered an implementation legacy.

## Reason

Tasks need stable identity and metadata beyond a label and shell command.

Tasks may eventually support:

- parameters
- conditions
- variants
- dependencies
- diagnostics
- execution policies
- workflows

A string map is insufficient as the long-term domain model.

______________________________________________________________________

# ADR-002 — Task ID is independent from presentation

Status: Accepted

## Decision

Task identity is represented by a stable ID.

Example:

```text
go.test
```

Presentation may be:

```text
▶ Test
```

## Reason

Labels and icons may change.

Identity must not.

______________________________________________________________________

# ADR-003 — Execution is separate from Task

Status: Accepted

## Decision

A Task is a definition.

An Execution is a runtime instance.

## Reason

This enables:

- concurrent executions
- history
- cancellation
- restart
- task status
- workflow composition
- stale callback protection

______________________________________________________________________

# ADR-004 — Runner does not execute

Status: Accepted

## Decision

Runners describe and expose Tasks.

The Execution Engine executes Commands.

## Reason

This prevents every language runner from implementing its own process lifecycle.

______________________________________________________________________

# ADR-005 — One Execution Engine

Status: Accepted

## Decision

Standalone tasks and workflows use the same Execution Engine.

## Reason

Execution behavior must remain consistent for:

- output
- cancellation
- result handling
- history
- events
- diagnostics

______________________________________________________________________

# ADR-006 — Zero-config is implemented through built-in runners

Status: Accepted

## Decision

Zero-config behavior is the normal result of built-in runner registration and contextual resolution.

It is not a separate execution path.

## Reason

This keeps zero-config and configured behavior on the same architecture.

______________________________________________________________________

# ADR-007 — Core must not depend on UI

Status: Accepted

## Decision

Domain and application logic must not depend on picker or terminal UI implementations.

## Reason

This improves:

- testability
- maintainability
- headless execution
- future UI integrations

______________________________________________________________________

# ADR-008 — Commands have a structured internal representation

Status: Accepted

## Decision

User-facing command strings are supported, but commands are normalized into a structured representation internally.

## Reason

Command strings are becoming a small language due to:

- variables
- quoting
- shell differences
- wrappers
- arguments
- working directories

Structured commands reduce accidental complexity.

______________________________________________________________________

# ADR-009 — Diagnostics are parsed independently

Status: Accepted

## Decision

Output parsers produce diagnostic data.

Adapters decide how to display that data.

## Reason

The same parser should be usable for:

- diagnostics
- quickfix
- future UI
- logging

______________________________________________________________________

# ADR-010 — Project-local Lua is trusted code

Status: Accepted

## Decision

`.code-runner.lua` is treated as executable project configuration.

## Reason

Lua configuration cannot be made safely sandboxed through superficial restrictions.

Users should understand that project-local configuration is code.

______________________________________________________________________

# ADR-011 — No Big Bang Rewrite

Status: Accepted

## Decision

The architecture will be migrated incrementally.

Existing behavior should be protected with characterization tests before major internal changes.

## Reason

Incremental migration makes architectural mistakes cheap to detect and revert.

______________________________________________________________________

# ADR-012 — No premature enterprise abstraction

Status: Accepted

## Decision

The project uses architectural boundaries without introducing unnecessary interface/factory/DI abstractions.

## Reason

The plugin is small enough that excessive abstraction would increase cognitive load without providing proportional value.

______________________________________________________________________

# ADR-013 — Adding a runner should not require core changes

Status: Accepted

## Decision

Runner expansion is a modular extension mechanism.

## Reason

Language support is expected to grow significantly.

The core must remain stable while the runner ecosystem grows.

______________________________________________________________________

# ADR-014 — Architecture documentation is part of the implementation

Status: Accepted

## Decision

Architectural changes require documentation changes.

## Reason

AI-assisted development requires explicit persistent context.

Documentation is part of the control mechanism that prevents architectural drift.

______________________________________________________________________

# ADR-015 — OpenCode must work from bounded tasks

Status: Accepted

## Decision

AI work is organized into bounded tasks with explicit scope and acceptance criteria.

## Reason

Large ambiguous instructions encourage agents to modify unrelated parts of the system and introduce architectural drift.

# ADR-016 — RunnerSpec is declarative data

Status: Accepted

## Decision

A Runner declares capabilities and tasks (`RunnerSpec`: id, filetypes,
project marker names, TaskSpecs) with no function values and no
infrastructure dependencies. Split of responsibilities:

```text
declares   RunnerSpec
resolves   Task Resolver (from an already-detected context)
detects    adapters (filesystem, executables)
executes   Execution Engine
```

## Reason

Detection criteria must be inspectable without running detection, and
tasks must be reusable without the runner that declared them. Behavior
(conditions, function commands) belongs to the resolver phase, not the spec.

______________________________________________________________________

# ADR-017 — Candidate resolution is scored and deterministic

Status: Accepted

## Decision

The pure resolver (`resolve.lua`) scores runners per signal (filetype or
extension hit: 2; project marker hit: 1; 0 = not a candidate) and orders by
score desc, runner id asc, declared task order. No match is an explicit
empty candidate list, never nil or an error. Registration order never
influences the result; duplicate task ids across runners are kept with
their runner (never silently hidden).

## Reason

Multi-candidate policy must be predictable without depending on load or
registration order. Scoring documents relevance (both signals beat one)
while keeping the output a pure function of declared runners + detected
context.

______________________________________________________________________

# ADR-018 — Availability conditions are data, not behavior

Status: Accepted

## Decision

A task may declare `when = { os = "win"|"unix", tools = { ... } }`
(optional, all fields optional, conjunction). The resolver evaluates it
against injected availability data (`{ os, tools }` set); detection never
runs inside specs. Missing evaluation data excludes the task — never
silent permissiveness. Multi-variant fallback (e.g. pwsh|powershell) is
modeled as explicit variant tasks, not hidden runtime branching.

## Reason

Tool/OS guards already exist scattered in closures (md, html, ps1, bat).
Centralizing them as data keeps RunnerSpec declarative, makes the policy
testable without processes, and forces each fallback to be visible.
