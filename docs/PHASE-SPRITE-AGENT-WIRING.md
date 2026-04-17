# Phase: Sprite ↔ Agent Wiring

> **Status:** Spec frozen. Research phase next, then implementation.
> **Prerequisite:** Optimization phase (PR #135) merged. Idle Office at 60fps.
> **Astronaut tile asset:** `assets/util/create_office_tile.png`

## Why this phase exists

Major Tom's sprite metaphor — "crew members do work while you're away" — is currently cosmetic. Subagent spawns claim idle sprites (see `OfficeViewModel.handleAgentSpawn:120`), but:

- No persistent link between a sprite and the subagent it represents — the sprite just gets claimed from a pool.
- The `parentId` field on `AgentSpawnEvent` is received and discarded.
- Tapping a sprite + sending a message → `relay.sendAgentMessage` fires at the server, iOS gets no feedback, no speech bubble, no routing guarantee.
- Idle sprites and active subagent-linked sprites are visually indistinguishable beyond a green/yellow status dot.
- Multi-session Office behavior is undefined — single global scene regardless of how many terminals / sessions are active.

This phase makes the sprite system a real, functional surface: tapping a sprite does something specific and deterministic. Messaging does something specific and deterministic. Multiple sessions have a coherent story.

---

## Design Decisions (Q1-Q5) — LOCKED

### Q1 — Office scope: per-session SKScene

**Decision: B — Per-session Office (separate SKScenes)**

Each terminal/session gets its own isolated Office (SKScene). Only one scene renders at a time; others are suspended. User navigates between Offices via the Office Manager (see below).

**Key details:**
- Scene lifecycle: active (rendering), warm (recently viewed, kept in memory briefly), cold (destroyed, rebuilt on access from relay state)
- Supports 2-3 typical sessions, up to 6-7 max
- Each Office has its own independent sprite pool — a sprite active in Office 1 has zero effect on Office 2

### Q2 — Sprite ↔ subagent link: bidirectional + persistent

**Decision: Option 3 — Bidirectional + persistent, hybrid role mapping, clone-not-consume**

**Link architecture:**
- Relay tracks `spriteHandle ↔ subagentId` mapping, persisted to disk (JSON per session)
- `AgentState` on iOS carries `linkedSubagentId`
- `AgentSpawnEvent` includes `parentId` (no longer discarded)
- Reconnects restore the mapping from the relay

**Role → sprite mapping (hybrid, 3-tier):**
1. **Agent `.md` frontmatter** — if the agent file declares `spriteCategory: frontend`, use it directly
2. **Relay classifier** — regex pattern matching task description against 8 canonical roles: `researcher, architect, qa, devops, frontend, backend, lead, engineer`
3. **Random from idle pool** — fallback for unrecognized roles

**Clone-not-consume model:**
- Idle sprites (cosmetic crew wandering around) and agent sprites (active subagent representations at desks) are separate concepts
- When role=`frontend` spawns, an agent sprite instance is **cloned into existence** with the `frontendDev` CharacterType. It does NOT consume the idle frontendDev sprite.
- Idle frontendDev can still wander the break room while two agent frontendDev sprites work at two desks.
- Multiple agents with the same role in one session = multiple identical sprites at different desks. Differentiation via tap-to-inspect (desk position provides spatial identity).
- Subagent completes → agent sprite despawns (celebration animation → poof).

**Role-stable binding:**
- First `frontend` spawn in a session reserves the `frontendDev` CharacterType for that role
- All subsequent `frontend` spawns reuse the same CharacterType
- Different sessions can independently map `frontend` → different sprites

**Dog fallback REMOVED:**
- Current code at `OfficeViewModel.swift:138` falls back to dogs when all humans are exhausted. This is incorrect.
- Dogs are NEVER claimed as agent sprites. If humans are exhausted, duplicate human sprites are used instead.

### Q3 — Messaging: `/btw` observe-only, queue at turn boundary

**Decision: Non-blocking, observe-only `/btw` messages queued until turn boundary**

**The hierarchy:**
```
User (human)  →  orchestrator Claude  →  controls subagents (full authority)
User (human)  →  sprite /btw          →  observe only (never redirect)
```

**Delivery mechanism:**
- Message sits on relay queue. When subagent finishes current turn (tool call completes, text response ends), message is injected as the next user turn with system constraint framing:
  > "The user sent a non-blocking observation via sprite tap: '{message}'. Respond in 1-2 sentences about your current progress. Do NOT change your task, plan, or approach. Continue exactly as you were."
- Subagent gives a brief natural-language status response and continues working unchanged.

**Modal `/btw` flow (1 message at a time):**
1. User taps linked sprite, types message, hits send
2. Text input becomes **read-only display** of the question (ellipsis truncation for long messages, expand/collapse toggle)
3. **"Thinking..."** indicator while waiting for response
4. Response appears below the question
5. **"Cool Beans"** button to dismiss
6. Pressing "Cool Beans" clears both question and response — back to fresh text input
7. **Cannot send another message until "Cool Beans" is pressed**
8. Answers are NOT persistent — dismissed means gone

**Closed-panel notification:**
- If user closes the sprite inspector before response arrives:
  - Speech bubble preview appears above sprite for ~5 seconds
  - Collapses to persistent **green glow** on sprite (replaces default pink working glow)
  - Green glow = "has unread /btw response"
  - Re-opening inspector shows the response + "Cool Beans" button
  - "Cool Beans" clears the green glow

**Cross-session notification (M2):**
- If user is viewing a different Office when response arrives: 3-second banner notification (only if sprite detail panel is closed)
- Green glow on sprite persists until read

**Push notifications (app not open):**
- Local notification (no APNs infrastructure) when app is backgrounded and /btw response arrives
- "Cool Beans" action button on notification to dismiss
- Only fires when app is NOT in foreground

### Q4 — Idle-sprite messaging: humans=no input, dogs=canned responses

**Decision: D for humans, B for dogs**

**Idle human sprites:**
- Tapping opens inspector with info panel only (character info, status, current activity)
- **No message input field** — messaging UI only appears for linked sprites
- Ambient random speech bubbles continue (life engine driven, not user-triggered)

**Dog sprites (always idle, never work):**
- Tapping opens inspector WITH message input field
- User can type anything — dog always responds with a random canned line (no Claude roundtrip)
- Responses pulled from shared pool + character-specific pool

**Dog response catalog:**

#### Shared pool (any dog)
- "*tail wagging intensifies*"
- "*tilts head*"
- "woof."
- "*rolls over for belly rubs*"
- "*stares at you, then at the treat jar*"
- "bork bork bork"

#### Steve & Esteban (cattle dogs — same dog, Esteban is Steve's alter ego outfit)
- "hello mama"
- "I'm a tiny dancer!"
- "Does mama need foot massage"
- "me happy!"
- "me looking for butt to sniff"

#### Elvis & Senor (dachshunds — same dog, Senor is Elvis's alter ego outfit)
- "I'm hungry, where's my eggs?!"
- "Hi mama"
- "Keep my brother out of my butt!"
- "I'm hungry, where's Steve's food?!"
- "I'm making biscuits over here"
- "Bury me in blanket please"

#### Kai & Hoku (schnauzers)
- "Death to mailmen!"
- "I love my mom and dad!"
- "Where's dad?!"
- "Is it greenie time yet?"

#### Zuckerbot (robot dog)
- "bleet bleet bleet"
- "the metaverse is the future"
- "do you like ju jitsu?"
- "me hungry for money"

> **Future:** Steve/Esteban and Elvis/Senor will be refactored into a wardrobe system (same character, alternate sprite sheets) rather than separate CharacterTypes.

### Q5 — Visual differentiation: aura + desk + bubbles + progress

**Decision: A + B + C + D from tier 1**

| Visual | What it does | When it shows |
|---|---|---|
| **Role-colored aura** | Soft glow ring, color = role category | Working sprites only. Green glow overrides when unread /btw response pending. |
| **Desk position** | Working sprites sit at desks | Always (existing behavior) |
| **Tool-event speech bubbles** | "reading files...", "writing code...", "running tests..." | During active tool calls, driven by relay tool events |
| **Mini progress indicator** | Token count, tool count, or generic progress bar | Above working sprites |

**Deferred to future:**
- Working animation variants (requires new sprite assets)
- Role-tagged floating labels (cluttery)

---

## Office Manager

The Office tab no longer opens directly into an SKScene. It opens a **manager screen** for creating, selecting, and closing Offices.

### Layout

1. **Active Office cards** (top) — one per linked Office
   - Background: screenshot/snapshot of the Office's room
   - Shows: session name, active agent count
   - Tap → enter that Office's SKScene

2. **Unlinked session cards** (below) — one per terminal session without an Office
   - Background: astronaut DALL-E tile (`assets/util/create_office_tile.png`), tinted with accent color
   - Shows: session name centered ("Terminal 1")
   - Tap → create Office for that session, enter it

3. **No sessions at all** → appropriate empty state

### Rules
- 1:1 mapping: one Office per session, can't create two for the same session
- "Close Office" (accessible from within an Office) destroys the SKScene and unlinks — **zero effect on the terminal session**, agents keep working
- Re-creating an Office for a session rebuilds from current relay state

---

## Scenarios — ALL LOCKED

### Messaging scenarios

| # | Scenario | Behavior |
|---|---|---|
| 1 | Tap linked sprite, type, send | `/btw` queued on relay, injected at turn boundary, constrained response |
| 2 | Tap A, start typing, tap B without sending | Draft discarded. New sprite's inspector opens fresh. |
| 3 | Send to A, before response tap A to send another | **Blocked.** Input is read-only showing the pending question. Must "Cool Beans" first. |
| 4 | Send to linked sprite, subagent completes before delivery | Drop with "completed before delivery" feedback in inspector. |
| 5 | Send while disconnected | Local queue, pending indicator, send on reconnect. |
| 6 | Subagent mid-tool-call | Message queues, delivered at next turn boundary (after tool completes). |
| 7 | Send to idle human sprite | No input field — inspector shows info panel only. |
| 8 | Send empty / whitespace | Silently ignore (send button disabled). |
| 9 | Sprite claimed between tap and send | Race: if sprite was idle when tapped but claimed before send, treat as a linked sprite send (the link exists now). |
| 10 | Very long message (>2000 chars) | Accept. Truncate display with expand/collapse in the read-only view. |

### New messaging scenarios

| # | Scenario | Behavior |
|---|---|---|
| M1 | Multiple /btw messages queued | Not possible — 1 message at a time, must "Cool Beans" before next. |
| M2 | /btw response arrives while in different Office | 3-second banner (if panel closed) + green glow on sprite. |
| M3 | Tool-event bubble and /btw response bubble collide | /btw response bubble takes priority for 5 seconds, then yields. Green glow persists until read. |

### Multi-session scenarios

| # | Scenario | Behavior |
|---|---|---|
| A | Terminal 1 spawns agents, user on Terminal 2's Office | Terminal 1's Office updates in background (state tracked by relay). Notifications still fire per M2. |
| B | Switch from Office 1 to Office 2 | Return to Office Manager, tap Office 2 card. Office 1's scene suspends or cold-destroys per lifecycle. |
| C | Same role spawns in both sessions | Same CharacterType in both Offices (independent pools). No collision. |
| D | Session ends on Terminal 1 | Office Manager removes that Office's card. If user is viewing it, return to Manager with brief transition. |

### Sprite allocation scenarios

| # | Scenario | Behavior |
|---|---|---|
| S1 | Subagent crashes mid-task | Sprite shows brief error animation, then despawns. |
| S2 | Subagent completes with error | Sprite shows failure state (red flash?), brief pause, then despawns. |
| S3 | User dismisses subagent from inspector | Confirm dialog → kill subagent on relay → sprite despawns. |
| S4 | Relay disconnects mid-subagent | Sprite grays out / shows disconnected indicator. Reconnect → restore from relay state. |
| S5 | More agents than desks (6 desks max) | Overflow sprites placed programmatically in empty work room space. No overlap, tappable, /btw-able. |
| S6 | Subagent spawns and completes in <1 second | Accepted as-is. Fast spawn+despawn animation is fine. |
| S7 | All human sprites exhausted | Duplicate human sprites. Dogs are NEVER fallback agents. |

### Infrastructure scenarios

| # | Scenario | Behavior |
|---|---|---|
| S8 | Relay restarts | See persistence cascade below. |
| S9 | New terminal session starts | Office NOT auto-created. Session appears as unlinked card in Office Manager. User creates Office explicitly. |
| S10 | PWA client connected | Out of scope. Relay-side /btw mechanism is client-agnostic but PWA gets no UI for it this phase. |

---

## Relay Persistence & Cascade Fallback

Sprite ↔ subagent mappings are persisted to disk (JSON file per session).

### Cleanup lifecycle

| Event | Action |
|---|---|
| Relay graceful shutdown | Delete all mapping files (all sessions gone) |
| Terminal session ended by user | Delete that session's mapping file |
| Backgrounding / disconnect | Keep (30-min grace period) |
| Grace period expires | Delete mapping file with the session |
| Relay startup (cold boot after crash) | Scan for stale files, delete any without a live session |

### Failure cascade

| Failure | Resolution |
|---|---|
| iOS app crash | Relay still has mappings → iOS reconnects, pulls from relay |
| Relay process crash (SIGKILL/OOM) | On restart: reload from disk if valid, else client-authoritative fallback |
| Mapping file corrupted / unreadable | Log warning, fall through to client-authoritative |
| Both crash simultaneously | Best-effort rebuild (fresh sprite allocation) |
| Relay disk full | In-memory only → client-authoritative on reconnect |

**Resolution cascade:**
1. **Relay-authoritative** (disk file) — primary source of truth
2. **Client-authoritative** (iOS re-sends its mappings) — first fallback
3. **Best-effort rebuild** (fresh allocation from current agent state) — always works, never fails

---

## Research Gates (BEFORE implementation)

| Item | Question | Blocks |
|---|---|---|
| Agent SDK turn-boundary injection | Can we queue a message and inject at turn end? Does the SDK expose stream-end hooks? What's the API? | Wave 4 (messaging) |
| Protocol message types | Define exact schemas for `sprite.link`, `sprite.unlink`, `sprite.message`, `sprite.response`, `sprite.state` | Wave 2 (protocol) |
| Relay message queue design | How does relay hold /btw messages, detect turn boundaries, inject? | Wave 4 (messaging) |
| Mapping persistence format | JSON file structure per session, cleanup hook points in existing session lifecycle | Wave 2 (data model) |
| Office Manager SwiftUI | View hierarchy, card layout, SKScene lifecycle management (create/suspend/destroy) | Wave 3 (multi-session) |
| Local notification setup | `UNNotificationAction` for "Cool Beans", background WebSocket handling, when to fire | Wave 5 (push) |
| Role → sprite mapping table | Lock the 8 classifier roles → CharacterType assignments | Wave 2 (data model) |

---

## Proposed Waves (pending research)

### Wave 1 — Spec Freeze + Research
- Answer all research gates above
- Produce protocol addendum (exact message schemas, sequence diagrams)
- Technical spike for anything needing prototyping
- Lock wave structure based on findings

### Wave 2 — Data Model + Protocol
- Add `linkedSubagentId` to `AgentState` (iOS)
- Persist `parentId` from `agent.spawn` events
- New relay message types: `sprite.link`, `sprite.unlink`, `sprite.message`, `sprite.response`, `sprite.state`
- Mapping persistence (JSON per session) with cleanup lifecycle
- Hybrid role → sprite mapping (frontmatter → classifier → random)
- Remove dog fallback in `OfficeViewModel` (duplicate humans instead)
- Clone-not-consume sprite allocation model

### Wave 3 — Office Manager + Multi-Session
- Office Manager SwiftUI view (cards for active Offices + unlinked sessions)
- Astronaut tile for unlinked session cards
- Room screenshot/snapshot for active Office cards
- Per-session SKScene lifecycle (create/suspend/destroy)
- "Close Office" flow (visual teardown, zero terminal effect)
- SKScene rebuild from relay state on re-creation

### Wave 4 — `/btw` Messaging Delivery
- Relay-side message queue per subagent
- Turn-boundary detection + injection with system constraint framing
- Modal `/btw` flow on iOS: send → read-only → thinking → response → "Cool Beans"
- Cross-session notifications (3s banner + green glow)
- Dog canned responses (shared + character-specific pools)
- Idle human inspector (info panel, no input)

### Wave 5 — Visual Differentiation + Notifications
- Role-colored aura on working sprites
- Tool-event speech bubbles (relay → iOS tool event piping)
- Mini progress indicator
- Green glow for unread /btw responses (overrides role aura)
- Bubble collision priority (response > tool event)
- Local push notifications with "Cool Beans" action

### Wave 6 — Edge Cases + Battle Test
- All scenario table behaviors verified
- Desk overflow placement
- Reconnect/disconnect sprite state management
- Persistence cascade testing (relay crash, iOS crash, both crash)
- Fast-complete animation handling
- Race conditions (claim between tap and send)

---

## Out of scope

- Apple Watch integration
- PWA sprite messaging UI
- Sprite messaging → voice / transcription
- Custom sprites-per-subagent
- Dog wardrobe system (planned future phase — Steve/Esteban and Elvis/Senor become outfit variants)
- APNs server push (using local notifications instead)
- Multi-user /btw (team mode)
