# OpenCode Development Workflow

This document defines how an AI coding session should operate in CodeRunner.nvim.

______________________________________________________________________

# Session Start

Every session starts with:

```text
1. Read AGENTS.md
2. Read .opencode/README.md
3. Read .opencode/STATE.md
4. Read .opencode/ARCHITECTURE.md
5. Read .opencode/CONTRACTS.md
6. Read .opencode/BOUNDARIES.md
7. Read relevant ADRs
8. Read active TODO task
9. Inspect git status
```

Do not start coding before completing this context pass.

______________________________________________________________________

# Step 1 — Understand

Before changing code, answer:

```text
What problem are we solving?

What architectural layer owns the problem?

What contract is involved?

Which existing module currently owns this behavior?

What tests cover it?

What should NOT change?
```

______________________________________________________________________

# Step 2 — Plan

Produce a small implementation plan.

The plan should contain:

```text
Files to change
Files to add
Tests to add/update
Architectural impact
```

Avoid speculative changes.

______________________________________________________________________

# Step 3 — Implement

Make the smallest coherent change.

Prefer:

```text
one concept
one boundary
one migration step
```

over large rewrites.

______________________________________________________________________

# Step 4 — Verify

Run:

```text
focused tests
```

then:

```text
broader test suite
```

when practical.

Inspect:

```text
git diff
```

for accidental changes.

______________________________________________________________________

# Step 5 — Architecture Check

Before declaring completion, verify:

```text
Does this introduce a new dependency?

Does this violate BOUNDARIES.md?

Does this create a second implementation of an existing concept?

Does this make adding a runner harder?

Does this leak UI into Core?

Does this make zero-config harder?

Does this require an ADR?
```

______________________________________________________________________

# Step 6 — Update State

If the task changed project progress:

Update:

```text
STATE.md
TODO.md
```

If architecture changed:

Update:

```text
ARCHITECTURE.md
CONTRACTS.md
BOUNDARIES.md
DECISIONS.md
```

as appropriate.

______________________________________________________________________

# Session End

Before ending a session, leave enough information for another agent to continue.

State should include:

```text
Current task
Completed work
Remaining work
Tests run
Known blockers
Next recommended action
```

Never leave:

```text
"continued next time"
```

as the only state.

______________________________________________________________________

# Recovery From Previous Session

If the repository contains unfinished work:

1. inspect `git status`
1. inspect `git diff`
1. read `STATE.md`
1. identify whether changes are intentional
1. do not discard work automatically
1. continue only after understanding the current state

______________________________________________________________________

# Handling Architectural Discovery

Sometimes implementation reveals that the current architecture is insufficient.

Do NOT immediately patch around the problem.

Instead:

```text
Discover problem
    ↓
Describe architectural conflict
    ↓
Evaluate existing contracts
    ↓
Determine whether existing concept can be extended
    ↓
If genuinely new concept:
    document ADR
    update contracts
    implement
```

______________________________________________________________________

# AI Refactoring Rule

Refactoring is allowed when necessary for the active task.

Unrelated cleanup is not.

A messy nearby module is not automatically part of the current task.

Prefer leaving a clearly documented follow-up task over expanding scope.

______________________________________________________________________

# Success Condition

A successful AI session should leave the repository:

```text
more correct
more tested
more explicit
more maintainable
```

without making the architecture harder to understand.
