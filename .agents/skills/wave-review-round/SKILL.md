---
name: wave-review-round
description: Wave-boundary audit of merged code on main against a phase spec. Spawns parallel read-only audit subagents split by component, cross-references the spec's requirements and scenario table, and gates the next wave on the synthesis. NOT a PR review — use CLAUDE.md "Local Code Review" for diffs.
---

# Wave Review Round

A holistic audit of **merged code on `main`** against a phase spec. PR review looks at one diff in isolation; this looks at everything N waves have accumulated and asks whether the phase is actually being delivered.

## When to Use

At wave boundaries — after shipping N waves, before starting wave N+1. The user asks for "a review round before we proceed" or "review waves 1-3".

Don't reach for this on a PR. PR diffs go through `CLAUDE.md` **"Local Code Review"**.

## Inputs

Nail these down before spawning anything:

- **Waves under audit** (e.g. Waves 1-3)
- **Phase spec path** (`docs/PHASE-*.md`) — the requirement list and scenario table are the audit's checklist
- **Research docs**, if the phase had a research wave
- **The actual file set** — `git log --oneline <first-wave-merge>..main` and `git diff --name-only <first-wave-merge>..main`. Derive the file list from git; never hand an auditor a file list you typed from memory.

## Picking the panel

Split by **component boundary**, one auditor per component the waves touched, plus one cross-cut auditor whenever the phase spans more than one component. Typically 2-4 agents, spawned in parallel in one message.

| Waves touched | Auditor |
|---|---|
| `relay/` | Relay auditor — protocol shapes, handler coverage, persistence lifecycle, sandbox/auth guards |
| `ios/` | iOS auditor — spec compliance plus the framework rules in `CLAUDE.md` "What NOT To Do" |
| `web/` | PWA auditor — protocol mirroring against the relay types, store/lifecycle correctness |
| two or more of the above | Cross-cut auditor — the **seams**: field-by-field protocol contract, state-machine coherence across the wire, reconnect/resume gaps, multi-session routing, failure cascades |

## The auditor brief

Every auditor is **READ-ONLY** — no `Edit`, `Write`, `NotebookEdit`, no commits. They report; the orchestrator decides.

Hand each one:

- the spec path, the research doc paths, and the git-derived file list for its component
- the path to `CLAUDE.md` — its "Standing review priorities", "What NOT to flag", and "The evidence rule" apply here unchanged
- the evidence rule verbatim: *every finding must come with a concrete failure scenario — the inputs or state that trigger it, and the bad outcome. If you cannot write the scenario, drop the finding.*

What an auditor checks that a PR review can't:

1. **Spec compliance** — every requirement for these waves → PASS / FAIL / PARTIAL with `file:line`. This is the point of the exercise; do it first and do it exhaustively.
2. **Scenario table** — walk each scenario the spec enumerates and mark it verified or gapped.
3. **Cross-wave regressions** — did a later wave undo or orphan something an earlier wave shipped?
4. **Half-built integrations** — a requirement needing both relay and client changes where only one side landed.
5. **Dead code** — pre-wave implementations now unreachable, obsolete TODOs, stale comments describing the old design.
6. **Deferred work** — TODO/FIXME that the wave's own acceptance criteria said would be done.

## Auditor output

```
## {Component} Audit — Waves {N}-{M}

### Spec compliance
[requirement → PASS/FAIL/PARTIAL, file:line]

### Scenario table
[scenario id → verified / gapped, with the gap described]

### Findings
[blocking → advisory; file:line, failure scenario, suggested fix]

### Dead code / cleanup

verdict: ship | fix-then-ship | rethink
blocking: N   advisory: N
```

Same verdict vocabulary as `CLAUDE.md` "Local Code Review" — one review language across the project.

## Synthesis and the gate

The orchestrator:

1. Collects every blocking finding, de-duplicates across auditors
2. Triages each `fix-now` / `respond` / `defer` — pushback with evidence is expected, an auditor's confidence is not proof
3. Produces one summary: overall verdict, ranked findings, fix plan
4. **`fix-then-ship`** → spawn fix agents, then an independent verifier per `CLAUDE.md` "Verifying fixes" — the auditor who raised a finding never verifies its own fix
5. **`ship`** → update `docs/STATE.md` + `.claude/STATE.md`, plan wave N+1
6. **`rethink`** → stop, surface to the user

The review round is a checkpoint gate. Nothing proceeds to the next wave with an open blocking finding.
