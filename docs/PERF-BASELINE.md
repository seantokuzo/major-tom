# Performance Baseline — Optimization Phase Wave 1

> Captured: _YYYY-MM-DD_ · Device: _iPhone ___ · Config: _Release/Debug_ · iOS _____
>
> Goal: lock down a baseline before Wave 2+ optimizations so we know if they actually moved the needle. User reported severe battery drain on-device; the theory from the 2026-04-14 audit is allocation churn + per-frame overhead, not texture format. This baseline is the "before."

---

## SpriteKit HUD

Enable via **Settings → Developer → Performance HUD**. Overlay appears bottom-right of the Office scene.

| Line | Meaning | Target |
|---|---|---|
| FPS | Frames per second | 60 (min ≥ 55) |
| Nodes | SKNodes in scene | as low as possible |
| Draws | Draw calls per frame | fewer = better (atlas packing wins) |
| Quads | Textured quads drawn per frame | — |

Toggle is persisted in `UserDefaults` under `sprite.perfHUD.enabled` — survives restarts, works in Release builds, flips live without leaving the Office tab.

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

| Metric | Run 1 | Run 2 |
|---|---|---|
| FPS (steady) | | |
| FPS (min) | | |
| Nodes | | |
| Draws | | |
| Quads | | |
| Energy Impact | | |
| CPU % (Instruments avg) | | |
| Allocations/sec (SKAction) | | |

### B — Populated & active (21 sprites, 1 min)

Tap **Shuffle Crew** until 21 sprites are active. Let activity cycling run. No user input after that.

| Metric | Run 1 | Run 2 |
|---|---|---|
| FPS (steady) | | |
| FPS (min) | | |
| Nodes | | |
| Draws | | |
| Quads | | |
| Energy Impact | | |
| CPU % (Instruments avg) | | |
| Allocations/sec (SKAction) | | |

### C — Parallax scroll (30s)

Swipe-snap across all 8 rooms, twice. Focus on frame time during the snap transitions.

| Metric | Run 1 | Run 2 |
|---|---|---|
| FPS (min during snap) | | |
| Max frame time (ms) | | |
| `updateParallax` cost (ms/frame) | | |
| `applyAgentMoods` cost (ms/frame) | | |

---

## Suspected hotspots

From the 2026-04-14 audit, ranked by suspected impact. Confirm each with Time Profiler during Scenario B.

1. **`AgentSprite.startActivityAnimation(_:)`** — builds ~12 new SKAction objects per activity rotation, ~250 allocations/sec during idle. No pooling.
2. **`OfficeScene.applyAgentMoods()`** — runs every frame across all 21 sprites, stacks `SKAction.repeatForever` on mood changes.
3. **`OfficeScene.updateParallax()`** — `childNode(withName: "//starsFar")` per frame per window (~8 windows). `//` prefix = O(n) recursive.
4. **`ActivityAnimator.startEmoteTimer(...)`** — Task-per-activity with `Task.sleep` loops, ~0.7 new Tasks/sec.
5. **`OfficeScene.scanForInteractions()`** — 210 distance calcs + `sqrt()` every 8s, triggers closure-capturing SKActions.

---

## Acceptance — ready for Wave 2?

Baseline is "accepted" when all three scenarios have two runs captured and Energy Impact is recorded for Scenario B on-device. At that point, proceed to:

**Wave 2 — Cheap wins**
- `view.ignoresSiblingOrder = true` + zPosition discipline
- Cache parallax node refs (kill the `//` lookups)
- Verify `.filteringMode = .nearest` on all character textures
- Frame budget: move `applyAgentMoods` / `applyTheme` / `updateParallax` to every-Nth-frame or dirty-flagged

Re-measure after Wave 2 and compare against this doc. Goal for end of Wave 5: Instruments Energy Impact = **Low**.
