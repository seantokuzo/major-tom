# Phase: Sprite ↔ Agent Wiring

> **Status:** Planning / discussion / research / spec. No implementation work yet.
> **Prerequisite:** Optimization phase (PR #135) merged. Idle Office at 60fps so sprite work doesn't regress perf.

## Why this phase exists

Major Tom's sprite metaphor — "crew members do work while you're away" — is currently cosmetic. Subagent spawns claim idle sprites (see `OfficeViewModel.handleAgentSpawn:120`), but:

- No persistent link between a sprite and the subagent it represents — the sprite just gets claimed from a pool.
- The `parentId` field on `AgentSpawnEvent` (Message.swift:765) is received and discarded.
- Tapping a sprite + sending a message → `relay.sendAgentMessage` fires at the server, iOS gets no feedback, no speech bubble, no routing guarantee.
- Idle sprites (dogs, unclaimed crew) and active subagent-linked sprites are visually indistinguishable beyond a green/yellow status dot.
- Multi-session Office behavior is undefined — it's a single global scene regardless of how many terminals / sessions are active.

This phase makes the sprite system a real, functional surface: tapping a sprite does something specific and deterministic. Messaging does something specific and deterministic. Multiple sessions have a coherent story.

---

## Open design questions

Decisions here drive the entire implementation. Do these FIRST.

### Q1 — Office scope: per-session or global?

**Current:** one global Office scene, shared across all terminals / sessions.

**Problem:** if you have two terminals open (`work/repo-a` and `~/side-project`), both running Claude sessions that spawn subagents, everyone gets thrown into the same Office. Sprites lose identity — which one represents which session?

**Options:**

| Option | Pros | Cons |
|---|---|---|
| **A. Keep global, tag sprites by session** | Simple. Minimal changes. Sprites get a `sessionId` field, visual grouping or filtering UI. | Doesn't scale past 2-3 sessions visually. Two working groups in one room looks like chaos. |
| **B. Per-session Office (separate SKScenes)** | Clean mental model — each terminal has its own station. Isolation. | Tab/switch UX to add. Scene rebuild cost. Still only render one at a time so perf OK. |
| **C. Room-per-session inside one global Office** | Single scene, but each session claims a module (CommandBridge, Engineering, etc.). | Rooms have character (Engineering is for engineers, etc.) — breaks the activity assignment logic. |
| **D. Stack Offices like browser tabs with a session picker** | Most product-grade feel. Active session's Office is visible, others are suspended. | Biggest UX + engineering lift. |

**Lean:** B or D. B is faster, D is eventually right. Probably start with B and evolve to D if the metaphor earns it.

### Q2 — How tight is the sprite ↔ subagent link?

**Options:**

1. **Loose (current):** sprite is claimed at spawn, returned at complete. No bidirectional reference. Closing the inspector loses context.
2. **One-way (`sprite → subagent`):** `AgentState` stores `linkedSubagentId`. UI can show what subagent this sprite is currently representing.
3. **Bidirectional + persistent:** subagent events always carry a `spriteHandle`. Relay tracks the mapping. Reconnects restore it. Sprites have a stable identity across spawns.

**Question:** if a subagent spawns, completes, then a new one spawns immediately for a different task — does the same sprite keep its role or get re-assigned?

### Q3 — What is sprite messaging actually?

User's framing: "like a `/btw` — non-blocking, doesn't interrupt the active agent turn."

Subquestions:
- Does the message enter the subagent's context as a user turn (would interrupt), or as a system-note-style sidebar (won't interrupt)?
- Does it route through the main Claude session or directly to the subagent process?
- Does the subagent need to *acknowledge* it, or is it fire-and-forget from the user's side?
- Is there a size limit? Queueing? Can a second `/btw` while the first is pending override it, append, or get rejected?

### Q4 — What does idle-sprite messaging even mean?

Dogs. Unclaimed crew. Sprites that are cosmetic-only.

**Options:**
- **Drop the message** — explicit "this sprite isn't active" feedback.
- **Route to main session** — treat it as a regular user turn.
- **Let the sprite "respond"** cosmetically via speech bubble only (flavor text, no actual Claude involvement).
- **Queue it** — deliver when that sprite next gets claimed.

### Q5 — Visual differentiation for linked sprites

Options, from cheap to expensive:
- Colored glow / aura (hue = subagent role)
- Speech bubble on active work
- Role-tagged floating label
- Mini progress indicator (tool running, tokens remaining, etc.)
- Full "working" animation variant (typing, thinking, etc.)

---

## Scenarios to handle

Enumerate every edge case *before* implementation. Missing one is how we end up with bugs like "DI persisted permanently."

### Messaging scenarios

| # | Scenario | Expected behavior | Decision? |
|---|---|---|---|
| 1 | User taps linked sprite, types message, hits send | Message delivered to subagent context as non-blocking `/btw` | ✓ confirmed |
| 2 | User taps sprite A, starts typing, without sending taps sprite B | What happens to draft? Discard / carry over / modal warning? | OPEN |
| 3 | User taps sprite A, types, sends. Before response, taps A again to send another | Does second message queue behind first? Replace it? | OPEN |
| 4 | User sends to linked sprite, subagent completes before message delivered | Drop / deliver to parent / show error? | OPEN |
| 5 | User sends to sprite while disconnected from relay | Local queue, show pending state, send on reconnect | OPEN |
| 6 | Subagent is in middle of a tool call — does `/btw` wait or interrupt? | Probably: non-blocking means it lands at the next message boundary. Needs relay-side mechanism. | OPEN |
| 7 | User sends to idle sprite (dog/unclaimed) | See Q4 | OPEN |
| 8 | User sends empty message / whitespace only | Silently ignore | trivial |
| 9 | User sends to sprite that just got claimed between tap and send | Race — who wins? | OPEN |
| 10 | Very long message (>2000 chars) | Truncate / warn / accept? | OPEN |

### Multi-session scenarios (depends on Q1)

| # | Scenario | Expected behavior |
|---|---|---|
| A | Terminal 1 spawns subagents. User is on Terminal 2's tab. | Does Terminal 1's Office keep updating in background? Do notifications still fire? |
| B | User switches from Terminal 1 to Terminal 2 | Office view swaps? Animation? Sprites preserved / rebuilt? |
| C | Same subagent role spawns in both sessions simultaneously | Same sprite visual in both Offices, or does the roster allocate differently? |
| D | Session ends on Terminal 1 | Its sprites return to idle for that session's pool? Global? |

### Subagent lifecycle scenarios

| # | Scenario | Expected behavior |
|---|---|---|
| S1 | Subagent crashes / kills itself mid-task | Sprite returns to idle, with what visual feedback? |
| S2 | Subagent completes with error | Does the sprite show a failure state before returning? |
| S3 | User manually dismisses a subagent from the sprite inspector | Confirm → kill subagent on relay → return sprite |
| S4 | Relay disconnects mid-subagent | Sprite keeps its "working" state or grays out? Resumes on reconnect or re-allocates? |

---

## Proposed waves (rough — not finalized)

Not committing to this structure until Q1-Q5 are decided.

### Wave 1 — Decisions & Spec Freeze
Answer Q1-Q5, enumerate all remaining scenarios, lock the protocol changes.

### Wave 2 — Data Model + Protocol
- Add `linkedSubagentId` / `linkedSpriteHandle` wiring on both sides
- Persist `parentId` on `AgentState`
- New relay message types: `sprite.message`, `sprite.link`, `sprite.unlink`, `sprite.state` updates
- Wire `parentId` from `agent.spawn` into the state store

### Wave 3 — Multi-Session Scoping (depends on Q1 choice)
If B: introduce per-session SKScene instances, session picker UI
If D: tab-stack architecture for Offices

### Wave 4 — Messaging Delivery
Relay-side `/btw` implementation. Non-blocking injection into subagent stream. Queue management. Acknowledgments.

### Wave 5 — UI Polish
Visual differentiation (Q5), speech bubbles on message send + receive, pending/delivered state indicators, drafts across sprite switches.

### Wave 6 — Edge Cases + Battle Test
Race conditions from the scenarios table. Disconnect/reconnect. Concurrent sends. Happy path + 10 edge cases as automated tests on the relay.

---

## Research needed before Wave 1 closes

- **Claude Agent SDK: non-blocking message injection.** Does the SDK support mid-turn user-message injection? What does it do with a system-note-style message while a tool is running? Check `@anthropic-ai/claude-agent-sdk` docs + source.
- **Long-running subagent context windows.** How do we handle a subagent that's been "alive" on-screen for 45 minutes through multiple turns — is its context window handled the same way as the main session's?
- **PWA parity.** PWA doesn't have the Office. Does sprite messaging have a PWA analogue (agent list with direct-message) or is it iOS-only? If iOS-only, the relay-side mechanism must still degrade gracefully when a PWA is the only client.

---

## What "done" looks like for this phase

- Every scenario in the scenarios table has a confirmed, tested behavior.
- Sprite messaging works with no lost messages and no cross-session leaks.
- Multi-session Office either is a first-class UX (per Q1) or is explicitly deferred.
- Visual differentiation tells you at a glance which sprites are actively working, which are linked, which are decorative.
- User can look at a sprite doing something and know *why* it's doing it, and can message it to change what it's doing.

---

## Out of scope for this phase

- Apple Watch integration
- Ground Control desktop surfacing
- Sprite messaging → voice / transcription
- Custom sprites-per-subagent (always the same sprite for a given role)
