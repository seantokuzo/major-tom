# Performance Baseline — Optimization Phase Wave 1

> Captured: 2026-04-15 · Device: Sean's iPhone (00008130-001625913CF0001C) · Config: Release · Low Power Mode: OFF
>
> Goal: lock down a baseline before Wave 2+ optimizations so we know if they actually moved the needle. User reported severe battery drain on-device; the theory from the 2026-04-14 audit is allocation churn + per-frame overhead, not texture format. This baseline is the "before."
>
> **Headline**: idle Office scene runs at **11.74 FPS** with **86.68 ms frame interval**. GPU time is only **1.55 ms/frame** — GPU has ~91% headroom. CPU is the bottleneck. Time Profiler confirms the audit: `OfficeScene.updateParallax` alone eats **21.7% of CPU**.

---

## On-device HUDs

Two separate overlays:

**iOS Metal HUD** (recommended for quick reads — enable in iOS Settings → Developer → Metal HUD). Shows FPS, frame interval (ms), GPU time (ms), memory — all the realtime stuff we care about for baseline.

**SpriteKit HUD** (Settings → Developer → Performance HUD inside Major Tom) — currently **hidden under the iOS tab bar** on this SpriteView layout, see #134. Use Instruments Game Performance template for node/draw/quad counts in the meantime.

| Metric | Source |
|---|---|
| FPS (steady/min) | iOS Metal HUD |
| Frame interval (ms) | iOS Metal HUD |
| GPU time (ms) | iOS Metal HUD |
| App memory (MB) | iOS Metal HUD |
| Node count | Instruments → Game Performance |
| Draw calls | Instruments → Game Performance |
| Quads per frame | Instruments → Game Performance |
| CPU % | Instruments → Game Performance |
| SKAction allocs/sec | Instruments → Allocations (Generations mode) |
| Energy Impact bucket | Instruments → Energy Log |

---

## Instruments (Xcode)

Open Xcode → Product → Profile (⌘I). Choose a template below.

1. **Game Performance** — overall FPS + GPU/CPU frame budget. Best first look.
2. **Time Profiler** — hot stacks. Watch for:
    - `OfficeScene.update(_:)` children — `applyAgentMoods`, `updateParallax`, `scanForInteractions`
    - `AgentSprite.startActivityAnimation(_:)` — SKAction churn
3. **Allocations** — use "Generations" mode around a 30s window with active sprites. Focus on `SKAction` + closure allocations.
4. **Energy Log** (on-device only) — the only real answer to "does it still kill the battery." Aim for **Low**.

Record 60–120s per scenario below. Mark scenarios with signposts if possible so the trace is easy to navigate.

---

## Scenarios

Run each scenario twice and average. Fill in the tables below.

### A — Idle station (1 min)

Launch app → Office tab → leave it alone. No swipes, no taps.

| Metric | Run 1 | Run 2 | Source |
|---|---|---|---|
| FPS (steady) | 11.74 | | Metal HUD |
| FPS (min) | ~11.74 | | Metal HUD |
| Frame interval (ms) | 86.68 | | Metal HUD |
| GPU time (ms) | 1.55 | | Metal HUD |
| App memory (MB) | 433 | | Metal HUD |
| Nodes | | | Instruments |
| Draws | | | Instruments |
| Quads | | | Instruments |
| CPU % avg | | | Instruments (Game Perf) |
| SKAction allocs/sec | | | Instruments (Allocations) |

### B — Populated & active (21 sprites, 1 min)

Tap **Shuffle Crew** until 21 sprites are active. Let activity cycling run. No user input after that.

| Metric | Run 1 | Run 2 | Source |
|---|---|---|---|
| FPS (steady) | | | Metal HUD |
| FPS (min) | | | Metal HUD |
| Frame interval (ms) | | | Metal HUD |
| GPU time (ms) | | | Metal HUD |
| App memory (MB) | | | Metal HUD |
| Nodes | | | Instruments |
| Draws | | | Instruments |
| Quads | | | Instruments |
| CPU % avg | | | Instruments (Game Perf) |
| SKAction allocs/sec | | | Instruments (Allocations) |
| Energy Impact | | | Instruments (Energy Log) |

### C — Parallax scroll (30s)

Swipe-snap across all 8 rooms, twice. Focus on frame time during the snap transitions.

| Metric | Run 1 | Run 2 | Source |
|---|---|---|---|
| FPS (min during snap) | | | Metal HUD |
| Max frame interval (ms) | | | Metal HUD |
| `updateParallax` cost (ms/frame) | | | Instruments (Time Profiler) |
| `applyAgentMoods` cost (ms/frame) | | | Instruments (Time Profiler) |

---

## Confirmed hotspots — Time Profiler (Scenario B, 21 sprites, 30s)

Captured 2026-04-15 via Xcode Instruments Time Profiler. Sorted by weight.

| Rank | Function | Weight | % of CPU | Status |
|---|---|---|---|---|
| 🥇 | `OfficeScene.updateParallax` | 832 ms | **21.7%** | Audit ✓ — `//` recursive lookups |
| 🥈 | `GridMovementEngine.buildGrid(for:furniture:)` | 199 ms | 5.1% | **NEW** — called more than expected in steady state |
| 🥉 | `SKTextureAtlas _allocating_init(named:)` | 38 ms | 1.0% | Atlas reload churn |
| — | `CrewSpriteBuilder.walkFrames(for:direction:)` | ~20 ms | 0.5% | Walk frame allocation |
| — | `CrewSpriteBuilder.texture(for:facing:)` | ~8 ms | 0.2% | Per-frame texture lookup |
| — | `OfficeScene.triggerCommsBurst` | — | — | Periodic effect |
| — | Unresolved 0x2305638751 family (likely Metal/SpriteKit render loop) | ~1600 ms | ~42% | Reducible via fewer draw calls |

### Audit predictions NOT confirmed as top hotspots

- `AgentSprite.startActivityAnimation(_:)` — did not appear in top samples. SKAction churn may be lower-cost than suspected, OR Instruments isn't catching allocation bursts at 1ms sample rate. Worth re-checking with Allocations template.
- `OfficeScene.applyAgentMoods()` — not in top list. Either cheap, or masked by parallax dominance. Re-measure after Wave 2.
- `OfficeScene.scanForInteractions()` — not visible. Only runs every 8s so could be missed by the 30s sample.

## Wave 2 priority order (revised based on data)

1. **Kill `updateParallax` cost** — cache `childNode(withName:)` refs in `didMove`, direct property access per frame. Expected impact: biggest single drop (5-10% CPU).
2. **Audit `buildGrid` call sites** — find out why it's running steady-state. Likely a room-change trigger firing on every frame. Expected impact: 5% CPU.
3. **`ignoresSiblingOrder` + zPosition discipline** — reduces Metal/SpriteKit render loop cost (the 42% unresolved bucket).
4. Defer: SKAction pooling, mood dirty-flagging, until re-measurement proves they're still top offenders.

---

## Acceptance — ready for Wave 2?

Baseline is "accepted" when all three scenarios have two runs captured and Energy Impact is recorded for Scenario B on-device. At that point, proceed to:

**Wave 2 — Cheap wins**
- `view.ignoresSiblingOrder = true` + zPosition discipline
- Cache parallax node refs (kill the `//` lookups)
- Verify `.filteringMode = .nearest` on all character textures
- Frame budget: move `applyAgentMoods` / `applyTheme` / `updateParallax` to every-Nth-frame or dirty-flagged

Re-measure after Wave 2 and compare against this doc. Goal for end of Wave 5: Instruments Energy Impact = **Low**.
