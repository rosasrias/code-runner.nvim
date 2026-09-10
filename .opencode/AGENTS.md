# CodeRunner.nvim — Agent Instructions

## Before doing anything

Read these files in this order:

```text
.opencode/README.md
.opencode/STATE.md
.opencode/ARCHITECTURE.md
.opencode/CONTRACTS.md
.opencode/BOUNDARIES.md
.opencode/DECISIONS.md
.opencode/TODO.md
```

Then inspect:

```text
git status
git diff
```

______________________________________________________________________

# Core Rule

Do not invent architecture while implementing a task.

The repository architecture is defined by:

```text
.opencode/ARCHITECTURE.md
.opencode/CONTRACTS.md
.opencode/BOUNDARIES.md
.opencode/DECISIONS.md
```

If implementation conflicts with those documents, stop and report the conflict.

______________________________________________________________________

# Task Scope

Work on one bounded task at a time.

Do not silently expand scope.

If the current task says:

```text
ARCH-002
```

do not also:

```text
migrate all runners
rewrite terminal
redesign picker
implement workflow
```

unless explicitly requested.

______________________________________________________________________

# Architecture Rules

Never:

- add language-specific conditionals to Core
- make Runner execute processes
- make UI construct domain commands
- make parsers mutate diagnostics directly
- create a second execution engine
- use presentation labels as Task identity
- introduce undocumented architectural concepts
- add abstractions only because they sound architecturally sophisticated

Prefer:

```text
small modules
explicit contracts
pure functions
clear dependencies
incremental migration
```

______________________________________________________________________

# Feature Freeze

Before P0/P1 completion, do not add major new features.

Especially avoid:

- new language runners
- DAP
- Neotest
- parallel workflows
- remote execution
- large UI redesigns
- unrelated refactors

______________________________________________________________________

# Code Changes

Before modifying a file:

1. Understand its current responsibility.
1. Identify its architectural layer.
1. Check allowed dependencies.
1. Check relevant tests.
1. Check relevant ADRs.

After modifying:

1. Run focused tests.
1. Run broader tests when appropriate.
1. Inspect the diff.
1. Check for accidental scope expansion.

______________________________________________________________________

# Tests

Do not delete tests simply because architecture changes.

Prefer:

```text
characterization test
    ↓
refactor
    ↓
new contract test
    ↓
remove obsolete implementation-specific test
```

Tests should verify behavior and contracts rather than private implementation details whenever possible.

______________________________________________________________________

# Documentation

If a change modifies:

- architecture
- domain contract
- public API
- dependency boundary
- architectural decision

update the corresponding `.opencode` document.

Do not leave architectural knowledge only in code.

______________________________________________________________________

# When uncertain

Do not guess silently.

Explain:

```text
Current assumption
Conflict
Possible options
Recommended option
```

Then update the appropriate architectural document before implementing a new concept.

______________________________________________________________________

# Final Principle

CodeRunner.nvim should become more capable without becoming more coupled.

The preferred direction is:

```text
more Tasks
more Runners
more Context
more Integrations

while keeping:

Core small
Execution consistent
UI replaceable
Adapters isolated
architecture understandable
```
