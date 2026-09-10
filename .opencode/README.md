# CodeRunner.nvim — OpenCode Development Context

## Purpose

This directory contains the persistent engineering context for CodeRunner.nvim.

The goal is to make development reproducible across OpenCode sessions and prevent architectural drift.

An AI agent working on this repository MUST treat the documents in this directory as the project's engineering memory.

---

## What is CodeRunner.nvim?

CodeRunner.nvim is a Neovim plugin for running code and development tasks with a **zero-config-first** experience.

The intended user experience is:

```text
Install plugin
    ↓
Open a source file
    ↓
Run CodeRunner
    ↓
CodeRunner understands the context
    ↓
Useful tasks are immediately available
```

Users should not need to configure a runner just to perform common operations.

At the same time, the system must support progressive customization:

```text
Zero-config defaults
        ↓
User configuration
        ↓
Project configuration
        ↓
Custom runners
        ↓
Custom tasks
```

The product is therefore not merely a "code execution command".

It is a contextual task execution engine for Neovim.

---

# Development Status

The project is currently pre-v1.0.

There are no external users whose existing configuration must be preserved.

This is an intentional architecture window.

We are allowed to make breaking internal changes before v1.0 if they produce a substantially better architecture.

Do not optimize for backward compatibility with imaginary users.

Optimize for:

* correctness
* maintainability
* extensibility
* predictable behavior
* testability
* low runtime overhead
* zero-config UX
* long-term API stability

---

# Current Architectural Direction

The architecture is moving from:

```text
Action → Command → Terminal
```

toward:

```text
Context
    ↓
Task Resolution
    ↓
Task
    ↓
Command
    ↓
Execution
    ↓
Result
```

The main domain concepts are:

* Task
* Execution
* Command
* Context
* Runner
* Result

See:

* `ARCHITECTURE.md`
* `CONTRACTS.md`
* `BOUNDARIES.md`

for normative definitions.

---

# Core Principles

## 1. Zero-config is a product requirement

The plugin must work immediately after installation for common languages and ecosystems.

Configuration should enhance the experience, not bootstrap the basic functionality.

---

## 2. Adding a runner must not require changing the core

Adding support for a new language, runtime, framework, or ecosystem should normally mean adding a runner definition.

A new runner MUST NOT require modifying:

* execution engine
* terminal implementation
* picker
* history
* diagnostics
* workflow engine
* core domain objects

If adding a runner requires modifying core code, investigate whether the boundary is wrong.

---

## 3. Task and Execution are different concepts

A Task is a definition.

An Execution is a runtime instance.

Example:

```text
Task:
    go.test

Execution:
    #42
    task = go.test
    status = running
    pid = 1234
```

Never collapse these concepts.

---

## 4. Runner describes; Execution executes

A Runner provides tasks.

The Runner does not own process lifecycle.

```text
Runner
    ↓
Task
    ↓
Execution Engine
    ↓
Process
```

---

## 5. UI is not the domain

The core must not depend on:

* picker implementation
* terminal UI
* `vim.ui`
* buffer rendering
* notifications

The UI consumes application/domain data.

---

## 6. Labels are presentation

Never use a UI label as task identity.

Bad:

```lua
["▶ Run"] = "go run %"
```

Good:

```lua
{
    id = "go.run",
    name = "Run",
    command = "go run $file",
}
```

Task IDs are stable.

Labels may change.

---

## 7. One execution engine

Single tasks and workflows must ultimately use the same execution engine.

Do not implement:

```text
Normal execution engine
+
Workflow execution engine
```

Instead:

```text
Task
    ↓
Execution Engine

Workflow
    ↓
Tasks
    ↓
Execution Engine
```

---

## 8. Strings are syntax sugar

Human-friendly command strings are allowed:

```lua
command = "go run $file"
```

But internally commands should be representable as a structured `CommandSpec`.

See `CONTRACTS.md`.

---

## 9. Do not over-engineer

This project uses architectural boundaries inspired by:

* Hexagonal Architecture
* Clean Architecture
* Scream Architecture

but it is still a Neovim Lua plugin.

Do not introduce unnecessary enterprise abstractions.

Prefer:

```text
clear boundaries
+
small modules
+
explicit contracts
+
pure functions where possible
```

over:

```text
interfaces everywhere
+
factories everywhere
+
dependency injection framework
```

---

# Development Workflow

Before modifying code:

1. Read `AGENTS.md`.
2. Read this file.
3. Read `STATE.md`.
4. Read `ARCHITECTURE.md`.
5. Read `CONTRACTS.md`.
6. Read `BOUNDARIES.md`.
7. Read relevant decisions in `DECISIONS.md`.
8. Identify the active task in `TODO.md`.
9. Inspect `git status`.
10. Inspect relevant existing code and tests.
11. Run the relevant test suite.
12. Make the smallest bounded change.
13. Run tests again.
14. Update project state if the task changed progress.
15. Update architectural documentation if a decision changed.

---

# Agent Behavior

An agent MUST NOT:

* invent architectural concepts silently
* introduce a new abstraction without documenting why
* expand task scope without permission
* add unrelated features while refactoring
* migrate every runner during a single architectural change
* rewrite the repository without incremental validation
* optimize hypothetical performance problems without evidence
* modify public API casually
* bypass tests to make progress

If an architectural conflict is discovered:

```text
STOP
↓
Explain the conflict
↓
Propose alternatives
↓
Record the decision
↓
Continue only after the architecture is updated
```

---

# Current Strategic Priority

Before v1.0, architecture has priority over feature count.

Do NOT add large new capabilities until the architecture foundation is established.

Especially avoid prematurely adding:

* more language runners
* DAP integration
* Neotest integration
* complex parallel execution
* remote execution
* task marketplace
* large UI systems

The current priority is:

```text
Architecture Foundation
        ↓
Execution Core
        ↓
Task Registry
        ↓
Runner Architecture
        ↓
Contextual Resolution
        ↓
Advanced Tasks
        ↓
Integrations
        ↓
v1.0 Hardening
```

---

# Definition of Done

A change is not complete merely because the code works.

A change is complete when:

* implementation is correct
* tests cover important behavior
* architecture remains within documented boundaries
* public API is intentional
* no unrelated behavior was introduced
* documentation reflects architectural changes
* OpenCode state is updated when appropriate

---

# Mental Model

Think of CodeRunner.nvim as a small operating system for development tasks.

```text
Context
    ↓
"What can I do here?"
    ↓
Task Resolution
    ↓
"What did the user choose?"
    ↓
Command Resolution
    ↓
"What exactly should execute?"
    ↓
Execution
    ↓
"What happened?"
    ↓
Result
    ↓
History / Diagnostics / UI / Events
```

This mental model should remain stable as the project grows.
