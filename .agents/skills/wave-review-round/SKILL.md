---
name: wave-review-round
description: Deep code review of completed waves against spec requirements. Spawns parallel review agents per component (relay, iOS), cross-references spec, identifies gaps, regressions, and architectural risks. Run at wave boundaries before proceeding to the next wave.
---

# Wave Review Round

Deep verification of shipped waves against spec requirements. This is NOT a PR review — it's a holistic audit of the merged code on `main` against the phase spec, research docs, and design decisions.

## When to Use

At wave boundaries — after shipping N waves, before starting wave N+1. The user will say something like "review round before we proceed" or "let's review waves 1-3".

## Inputs

- **Waves to review** (e.g., "Waves 1-3")
- **Phase spec path** (e.g., `docs/PHASE-SPRITE-AGENT-WIRING.md`)
- **Research docs** (e.g., `docs/SPRITE-WIRING-RESEARCH-IOS.md`, `docs/SPRITE-WIRING-RESEARCH-RELAY.md`)

## Review Strategy

**Parallel agents, cohesive output.** Spawn 3 agents simultaneously:

1. **Relay Review Agent** — reviews all relay-side changes
2. **iOS Review Agent** — reviews all iOS-side changes
3. **Cross-Cut Review Agent** — reviews protocol compliance, state machine coherence, edge cases

Each agent gets the same spec + research docs as context and produces a structured report. The orchestrator synthesizes into a single review summary.

## Agent Prompts

### Agent 1: Relay Review

```
## Task: Deep review of relay changes for Waves {N}-{M}

Read the phase spec at {spec_path} and the relay research at {relay_research_path}.

Then review all relay code touched by Waves {N}-{M}. Key files to read:
- relay/src/protocol/messages.ts — all sprite.* message types
- relay/src/routes/ws.ts — sprite.state.request handler, sprite event emission
- relay/src/sprites/sprite-mapper.ts — role classification, character mapping
- relay/src/sprites/sprite-mapping-persistence.ts — disk persistence
- Any other relay files with "sprite" in the path

For each file, check:

1. **Spec compliance** — Does the implementation match every requirement in the spec for these waves?
2. **Protocol correctness** — Do message shapes match the spec? Are all required fields present?
3. **Persistence lifecycle** — Are cleanup hooks correct? (session destroy, relay shutdown, cold boot)
4. **Error handling** — Are failures handled gracefully? Silent catches? Missing error responses?
5. **Security** — Session auth checks on sensitive endpoints? Data leakage between sessions?
6. **Edge cases from scenario table** — Check spec scenarios S8 (relay restart), S9 (new session), S10 (PWA client)
7. **TODOs / FIXMEs** — Any deferred work that should have been done in these waves?
8. **Dead code** — Any code from pre-wave implementation that's now unreachable?

Output format:
## Relay Review — Waves {N}-{M}

### Spec Compliance
[checklist: each spec requirement → PASS/FAIL/PARTIAL with line references]

### Issues Found
[severity: CRITICAL / HIGH / MEDIUM / LOW]
[file:line — description — suggested fix]

### Risks & Warnings
[things that aren't bugs yet but could become problems]

### Dead Code / Cleanup
[unreachable code, stale comments, obsolete TODOs]

### Verdict
[SHIP / SHIP WITH FIXES / BLOCK — summary sentence]
```

### Agent 2: iOS Review

```
## Task: Deep review of iOS changes for Waves {N}-{M}

Read the phase spec at {spec_path} and the iOS research at {ios_research_path}.

Then review all iOS code touched by Waves {N}-{M}. Key files to read:
- ios/MajorTom/Features/Office/ViewModels/OfficeSceneManager.swift
- ios/MajorTom/Features/Office/ViewModels/OfficeViewModel.swift
- ios/MajorTom/Features/Office/Views/OfficeManagerView.swift
- ios/MajorTom/Features/Office/Views/OfficeView.swift
- ios/MajorTom/Features/Office/Models/AgentState.swift
- ios/MajorTom/Features/Office/Models/RoleMapper.swift
- ios/MajorTom/Core/Services/RelayService.swift (agent/sprite event routing)
- ios/MajorTom/Core/Models/Message.swift (sprite event types)
- ios/MajorTom/App/MajorTomApp.swift (wiring)

For each file, check:

1. **Spec compliance** — Does the implementation match every requirement in the spec?
2. **Convention compliance** — @Observable (not ObservableObject), async/await (not Combine), SwiftUI only, iOS 17+
3. **MVVM architecture** — Views observe ViewModels, ViewModels call Services. No business logic in Views.
4. **Scene lifecycle** — Active/warm/cold states correct? LRU eviction logic sound? Memory budgets reasonable?
5. **Event routing** — All agent.* and sprite.* events route by sessionId? No events silently dropped?
6. **Clone-not-consume** — Agent sprites never consume idle sprites? Dog fallback removed?
7. **Role-stable binding** — Per-session role→CharacterType locks correctly? Multiple same-role agents handled?
8. **Edge cases from scenario table** — Check spec scenarios A-D (multi-session), S1-S7 (allocation)
9. **SwiftUI render safety** — No mutations in `body` or computed properties called from `body`? No render loops?
10. **TODOs / FIXMEs** — Any deferred work that should have been done?
11. **Dead code** — Old singleton patterns still lingering? Unreachable branches?

Output format:
## iOS Review — Waves {N}-{M}

### Spec Compliance
[checklist: each spec requirement → PASS/FAIL/PARTIAL with line references]

### Issues Found
[severity: CRITICAL / HIGH / MEDIUM / LOW]
[file:line — description — suggested fix]

### Risks & Warnings
[things that aren't bugs yet but could become problems]

### Convention Violations
[any use of ObservableObject, Combine, UIKit, etc.]

### Dead Code / Cleanup
[old patterns, stale comments, obsolete TODOs]

### Verdict
[SHIP / SHIP WITH FIXES / BLOCK — summary sentence]
```

### Agent 3: Cross-Cut Review

```
## Task: Cross-cutting review of Waves {N}-{M} — protocol, state machines, edge cases

Read the phase spec at {spec_path}, relay research at {relay_research_path}, and iOS research at {ios_research_path}.

This review focuses on the SEAMS between relay and iOS — the protocol contract, state machine coherence, and edge cases that span both components.

Check:

1. **Protocol contract** — Do iOS message structs exactly match relay TypeScript interfaces? Field names, types, optionality?
   Compare: Message.swift sprite types vs messages.ts sprite types (field by field)

2. **State machine coherence** — Does the relay's sprite lifecycle (link → working → idle → unlink) match iOS's expectation? Are there any states the relay can enter that iOS doesn't handle (or vice versa)?

3. **Reconnect/resume flow** — When iOS reconnects:
   - Does relay send sprite.state on session.resume?
   - Does iOS request sprite.state.request for cold scenes?
   - Are there any gaps where state could be lost?

4. **Multi-session correctness** — If Terminal 1 spawns agents while user views Terminal 2's Office:
   - Does relay still send sprite.link for Terminal 1?
   - Does iOS ensureViewModel accumulate state?
   - When user opens Terminal 1's Office later, is state complete?

5. **Persistence cascade** — Check the failure cascade from the spec:
   - iOS crash → relay has mappings → iOS reconnects, pulls from relay ✓?
   - Relay crash → reload from disk, else client-authoritative ✓?
   - Both crash → best-effort rebuild ✓?
   - Mapping file corrupted ✓?

6. **Race conditions** — From the scenario table:
   - Sprite claimed between tap and send (scenario 9)
   - Session ends while Office is open (scenario D)
   - Same role in both sessions (scenario C)

7. **Missing integration points** — Are there any spec requirements that need BOTH relay and iOS changes but only one side was implemented?

8. **Wave 4+ readiness** — Are the foundations solid for:
   - /btw messaging (relay queue + iOS modal flow)?
   - Visual differentiation (role auras, tool-event bubbles)?
   - Local notifications?

Output format:
## Cross-Cut Review — Waves {N}-{M}

### Protocol Contract
[field-by-field comparison of iOS vs relay message types]

### State Machine Coherence
[lifecycle diagram check]

### Reconnect/Resume Gaps
[any state loss scenarios]

### Multi-Session Correctness
[event routing check across sessions]

### Persistence Cascade
[each failure scenario → verified/gap]

### Race Conditions
[each scenario → handled/gap]

### Wave 4+ Readiness
[foundation check for upcoming waves]

### Verdict
[SHIP / SHIP WITH FIXES / BLOCK — summary sentence]
```

## Synthesis

After all 3 agents report, the orchestrator:

1. **Collects all CRITICAL and HIGH issues** across all 3 reports
2. **De-duplicates** (same issue found by multiple agents)
3. **Produces a single review summary** with:
   - Overall verdict (SHIP / SHIP WITH FIXES / BLOCK)
   - Ranked issue list (critical first)
   - Recommended fix plan (which issues to fix now vs defer)
4. **If SHIP WITH FIXES:** spawns fix agents to address critical/high issues before proceeding
5. **If SHIP:** updates STATE.md and proceeds to next wave planning

## Integration with Wave Workflow

```
Wave N shipped → Review Round → Fix critical issues → Update STATE.md → Plan Wave N+1
```

The review round is a checkpoint gate. Nothing proceeds to the next wave until the review round passes with at most LOW-severity open items.
