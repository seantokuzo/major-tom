# Phase: The Life Engine

> Make the station feel alive — smart behaviors, real pathfinding, and extensible activities that practically configure themselves.

---

## Executive Summary

The station has rooms, furniture, and characters. But they don't *live* there yet. Characters teleport between hardcoded waypoints, do 7 generic activities, and walk through furniture. This phase builds three interconnected systems that turn the station into a living world:

1. **Activity System** — JSON-configured, data-driven activities tied to furniture, rooms, and character groups
2. **Movement Engine** — Grid-based pathfinding using Apple's GameplayKit, with collision avoidance and smooth interpolation
3. **Haptic Layer** — CoreHaptics wired to every interaction for tactile feedback

The key design principle: **extensibility through configuration, not code**. Adding a new room, furniture item, and activity should require zero Swift changes — just JSON entries and texture assets.

---

## Current State (What We Have)

### Activity System
- 7 hardcoded `ActivityStationType` cases (pingPong, coffeeMachine, waterCooler, arcade, yoga, nap, whiteboard)
- `ActivityManager` polls every 2 seconds, randomly assigns idle agents to available stations
- Duration: random 5–15 seconds per activity
- No character-group filtering (dogs can use the coffee machine)
- No furniture awareness (activities happen at arbitrary points, not at furniture)
- No cooldowns, priorities, or mood interaction

### Movement System
- `WaypointPathfinder` — topology-driven routing through `StationLayout.doors`
- Direct-line movement between waypoints via `SKAction.move(to:duration:)`
- No obstacle avoidance — characters walk through furniture
- No collision detection — characters overlap each other
- Speed hardcoded at 120 pts/sec

### What Works (Keep)
- Agent lifecycle: spawning → walking → working → idle → celebrating → leaving
- Sprite pool pattern (31 character types recycled)
- `AgentSprite` animation system (station-specific anims, mood overrides, emotes)
- `CharacterCatalog` config pattern
- Mood/Theme engines
- Furniture factory (texture-based from StationFurniture atlas)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                    Activities.json                    │
│  (room definitions, furniture placements, activities) │
└──────────────────────┬──────────────────────────────┘
                       │ loaded at startup
                       ▼
┌──────────────────────────────────────────────────────┐
│              ActivityRegistry (singleton)              │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │  Room Defs   │  │ Furniture DB │  │ Activity DB │ │
│  └─────────────┘  └──────────────┘  └─────────────┘ │
└──────────────────────┬──────────────────────────────┘
                       │ queries
                       ▼
┌──────────────────────────────────────────────────────┐
│           ActivitySelectionEngine                      │
│  - Filter by character group, room, furniture          │
│  - Weighted random (priority + mood + variety)         │
│  - Cooldown tracking                                   │
│  - Furniture occupancy management                      │
└──────────────────────┬──────────────────────────────┘
                       │ assigns activity
                       ▼
┌──────────────────────────────────────────────────────┐
│              GridMovementEngine                        │
│  - GKGridGraph per room (30×32 cells at 20×20 res)    │
│  - A* pathfinding (<1ms per query)                     │
│  - Obstacle cells from furniture footprints            │
│  - Agent cell reservation (no overlap)                 │
│  - Catmull-Rom path smoothing                          │
└──────────────────────┬──────────────────────────────┘
                       │ smooth path
                       ▼
┌──────────────────────────────────────────────────────┐
│              AgentSprite (existing)                     │
│  - moveAlongPath() with interpolated waypoints         │
│  - Activity-specific animations                        │
│  - Facing direction from movement vector               │
└──────────────────────────────────────────────────────┘
```

---

## Pillar 1: Activity System

### Design Principle

**Adding a new activity = adding a JSON entry.** No Swift code changes. The activity knows:
- What furniture it targets
- Which room(s) it can happen in
- Which characters can do it
- How long it lasts
- What animations/texture swaps to trigger
- Where the character stands relative to the furniture

### Data Model

```swift
struct ActivityDefinition: Identifiable, Codable {
    let id: String
    let displayName: String
    let type: ActivityType           // .idle, .work
    let description: String

    // Location
    let furnitureTypes: [String]     // e.g., ["food_dispenser"]
    let roomTypes: [String]         // e.g., ["galley"]

    // Eligibility
    let characterGroup: String      // "humans", "dogs", "all", "specific"
    let specificCharacters: [String] // Used when characterGroup == "specific"

    // Timing
    let durationRange: [Double]     // [min, max] in seconds
    let cooldown: Double            // Seconds before same character repeats
    let priority: Double            // 0-1, weight for random selection

    // Animation
    let animationID: String?        // Maps to AgentSprite animation method
    let emoteFrequency: Double      // 0-1, chance of emotes during activity

    // Position
    let positionOffset: [String: [Double]]  // furniture_type → [dx, dy] offset

    // Asset transitions (texture swaps on furniture during activity)
    let assetTransitions: [AssetTransition]
}

struct AssetTransition: Codable {
    let furnitureID: String         // Which furniture to modify
    let fromTexture: String         // Original texture name
    let toTexture: String           // Swap to this during activity
    let reverseOnComplete: Bool     // Swap back when activity ends
}

enum ActivityType: String, Codable {
    case idle   // Fun/rest — cooking, gaming, sleeping, walking
    case work   // Task-oriented — research, planning, coding
}
```

### JSON Configuration

```json
{
  "activities": [
    {
      "id": "cook_dinner",
      "displayName": "Cook Dinner",
      "type": "idle",
      "description": "Whip up some space grub",
      "furnitureTypes": ["food_dispenser"],
      "roomTypes": ["galley"],
      "characterGroup": "humans",
      "specificCharacters": [],
      "durationRange": [30, 60],
      "cooldown": 120,
      "priority": 0.8,
      "animationID": "cooking",
      "emoteFrequency": 0.4,
      "positionOffset": { "food_dispenser": [-20, 0] },
      "assetTransitions": []
    },
    {
      "id": "nap_on_couch",
      "displayName": "Nap on Couch",
      "type": "idle",
      "description": "Quick power nap",
      "furnitureTypes": ["couch"],
      "roomTypes": ["crewQuarters"],
      "characterGroup": "humans",
      "specificCharacters": [],
      "durationRange": [45, 90],
      "cooldown": 300,
      "priority": 0.5,
      "animationID": "sleeping",
      "emoteFrequency": 0.1,
      "positionOffset": { "couch": [0, -5] },
      "assetTransitions": []
    },
    {
      "id": "read_by_lamp",
      "displayName": "Read by Lamplight",
      "type": "idle",
      "description": "Curl up with a good book",
      "furnitureTypes": ["floor_lamp", "couch"],
      "roomTypes": ["crewQuarters"],
      "characterGroup": "humans",
      "specificCharacters": [],
      "durationRange": [60, 120],
      "cooldown": 180,
      "priority": 0.6,
      "animationID": "reading",
      "emoteFrequency": 0.15,
      "positionOffset": { "couch": [0, -5] },
      "assetTransitions": [
        {
          "furnitureID": "floor_lamp",
          "fromTexture": "floor_lamp_on",
          "toTexture": "floor_lamp_off",
          "reverseOnComplete": true
        }
      ]
    },
    {
      "id": "fetch_ball",
      "displayName": "Fetch!",
      "type": "idle",
      "description": "Chase a ball around the dome",
      "furnitureTypes": ["open_space"],
      "roomTypes": ["bioDome", "arboretum"],
      "characterGroup": "dogs",
      "specificCharacters": [],
      "durationRange": [20, 40],
      "cooldown": 60,
      "priority": 0.9,
      "animationID": "running",
      "emoteFrequency": 0.6,
      "positionOffset": {},
      "assetTransitions": []
    },
    {
      "id": "watch_tv",
      "displayName": "Watch TV",
      "type": "idle",
      "description": "Zone out on the media screen",
      "furnitureTypes": ["couch", "media_screen"],
      "roomTypes": ["crewQuarters"],
      "characterGroup": "humans",
      "specificCharacters": [],
      "durationRange": [40, 80],
      "cooldown": 120,
      "priority": 0.7,
      "animationID": "sitting",
      "emoteFrequency": 0.3,
      "positionOffset": { "couch": [0, -5] },
      "assetTransitions": []
    },
    {
      "id": "play_arcade",
      "displayName": "Play Video Game",
      "type": "idle",
      "description": "Mash some buttons on the holo-game",
      "furnitureTypes": ["status_screen"],
      "roomTypes": ["crewQuarters"],
      "characterGroup": "humans",
      "specificCharacters": [],
      "durationRange": [30, 60],
      "cooldown": 90,
      "priority": 0.7,
      "animationID": "arcade",
      "emoteFrequency": 0.5,
      "positionOffset": { "status_screen": [0, -20] },
      "assetTransitions": []
    },
    {
      "id": "work_out",
      "displayName": "Work Out",
      "type": "idle",
      "description": "Hit the treadmill",
      "furnitureTypes": ["treadmill"],
      "roomTypes": ["trainingBay"],
      "characterGroup": "humans",
      "specificCharacters": [],
      "durationRange": [40, 80],
      "cooldown": 180,
      "priority": 0.6,
      "animationID": "exercise",
      "emoteFrequency": 0.3,
      "positionOffset": { "treadmill": [0, -10] },
      "assetTransitions": []
    },
    {
      "id": "lift_weights",
      "displayName": "Lift Weights",
      "type": "idle",
      "description": "Pump some iron",
      "furnitureTypes": ["weight_rack"],
      "roomTypes": ["trainingBay"],
      "characterGroup": "humans",
      "specificCharacters": [],
      "durationRange": [30, 60],
      "cooldown": 180,
      "priority": 0.5,
      "animationID": "exercise",
      "emoteFrequency": 0.2,
      "positionOffset": { "weight_rack": [0, -15] },
      "assetTransitions": []
    },
    {
      "id": "drink_coffee",
      "displayName": "Get Coffee",
      "type": "idle",
      "description": "Caffeine break at the beverage synth",
      "furnitureTypes": ["coffee_machine"],
      "roomTypes": ["galley"],
      "characterGroup": "all",
      "specificCharacters": [],
      "durationRange": [15, 30],
      "cooldown": 60,
      "priority": 0.9,
      "animationID": "waiting",
      "emoteFrequency": 0.3,
      "positionOffset": { "coffee_machine": [-15, 0] },
      "assetTransitions": []
    },
    {
      "id": "sleep_in_bunk",
      "displayName": "Sleep",
      "type": "idle",
      "description": "Hit the bunk for some shuteye",
      "furnitureTypes": ["bunk_bed"],
      "roomTypes": ["crewQuarters"],
      "characterGroup": "all",
      "specificCharacters": [],
      "durationRange": [60, 120],
      "cooldown": 300,
      "priority": 0.4,
      "animationID": "sleeping",
      "emoteFrequency": 0.05,
      "positionOffset": { "bunk_bed": [0, 0] },
      "assetTransitions": []
    },
    {
      "id": "touch_grass",
      "displayName": "Touch Grass",
      "type": "idle",
      "description": "Go outside and touch some grass",
      "furnitureTypes": ["open_space"],
      "roomTypes": ["arboretum", "bioDome"],
      "characterGroup": "all",
      "specificCharacters": [],
      "durationRange": [20, 45],
      "cooldown": 120,
      "priority": 0.6,
      "animationID": "walking",
      "emoteFrequency": 0.3,
      "positionOffset": {},
      "assetTransitions": []
    },
    {
      "id": "dog_nap",
      "displayName": "Dog Nap",
      "type": "idle",
      "description": "Curl up and snooze",
      "furnitureTypes": ["open_space", "couch"],
      "roomTypes": ["crewQuarters", "bioDome"],
      "characterGroup": "dogs",
      "specificCharacters": [],
      "durationRange": [30, 90],
      "cooldown": 120,
      "priority": 0.7,
      "animationID": "sleeping",
      "emoteFrequency": 0.05,
      "positionOffset": {},
      "assetTransitions": []
    },
    {
      "id": "sniff_plants",
      "displayName": "Sniff Plants",
      "type": "idle",
      "description": "Investigate the flora",
      "furnitureTypes": ["tree", "office_plant"],
      "roomTypes": ["bioDome", "arboretum"],
      "characterGroup": "dogs",
      "specificCharacters": [],
      "durationRange": [15, 30],
      "cooldown": 60,
      "priority": 0.8,
      "animationID": "sniffing",
      "emoteFrequency": 0.4,
      "positionOffset": { "tree": [15, -10], "office_plant": [10, -5] },
      "assetTransitions": []
    },
    {
      "id": "eat_dinner",
      "displayName": "Eat Dinner",
      "type": "idle",
      "description": "Sit down for a meal",
      "furnitureTypes": ["dining_table"],
      "roomTypes": ["galley"],
      "characterGroup": "all",
      "specificCharacters": [],
      "durationRange": [30, 60],
      "cooldown": 180,
      "priority": 0.7,
      "animationID": "sitting",
      "emoteFrequency": 0.3,
      "positionOffset": { "dining_table": [0, -15] },
      "assetTransitions": []
    },
    {
      "id": "pond_gaze",
      "displayName": "Gaze at Pond",
      "type": "idle",
      "description": "Watch the fish swim",
      "furnitureTypes": ["pond"],
      "roomTypes": ["arboretum"],
      "characterGroup": "all",
      "specificCharacters": [],
      "durationRange": [20, 40],
      "cooldown": 120,
      "priority": 0.5,
      "animationID": "sitting",
      "emoteFrequency": 0.2,
      "positionOffset": { "pond": [0, -20] },
      "assetTransitions": []
    }
  ]
}
```

### Selection Engine

```
When agent goes idle:
1. Determine which room they're in
2. Query ActivityRegistry: "what activities are available for this character type in this room?"
3. Filter out: furniture occupied, activity on cooldown, character not eligible
4. Weight remaining by: priority × mood affinity × variety penalty
5. Weighted random selection → assign activity
6. Pathfind to furniture position + offset
7. Start activity animation + asset transitions
8. On duration expire: complete, apply mood change, return to idle pool
```

### Extensibility Scenarios

**"We added a library room with a bookshelf, and a 'research' activity":**
1. Add room definition to room config (bounds, furniture placements)
2. Add `bookshelf.imageset` to StationFurniture atlas
3. Add JSON entry: `{ "id": "research", "furnitureTypes": ["bookshelf"], "roomTypes": ["library"], ... }`
4. Done. No Swift changes.

**"We want only the botanist to water plants":**
```json
{
  "id": "water_plants",
  "characterGroup": "specific",
  "specificCharacters": ["botanist"],
  "furnitureTypes": ["office_plant", "tree"],
  "roomTypes": ["bioDome", "arboretum"]
}
```

**"We have a lamp_on and lamp_off texture and want reading to dim the lamp":**
```json
{
  "assetTransitions": [{
    "furnitureID": "floor_lamp",
    "fromTexture": "floor_lamp_on",
    "toTexture": "floor_lamp_off",
    "reverseOnComplete": true
  }]
}
```

---

## Pillar 2: Movement Engine

### Why GameplayKit

Apple's `GKGridGraph` is purpose-built for this:
- Built-in A* pathfinding optimized for iOS
- Sub-1ms queries on our grid size
- Dynamic obstacle support (add/remove nodes at runtime)
- Ships with iOS — no dependencies
- Battle-tested in dozens of shipped games

Custom A* would take longer to build, be slower (~5-15ms vs <1ms), and we'd own all the bugs. Jump Point Search is overkill for our 960-cell rooms.

### Grid Specification

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Cell size | 20×20 scene units | Characters (80×80) = 4×4 cells, furniture maps cleanly |
| Grid per room | 30 wide × 32 tall | 600÷20 × 640÷20 = 960 cells per room |
| Movement | 8-directional | Diagonal movement for natural paths |
| Algorithm | GKGridGraph A* | Apple's optimized implementation |

### Implementation

```swift
import GameplayKit

class GridMovementEngine {
    /// One grid graph per room
    private var roomGrids: [ModuleType: GKGridGraph<GKGridGraphNode>] = [:]

    /// Agent cell reservations (prevent overlap)
    private var reservedCells: [vector_int2: String] = [:]  // cell → agentId

    func buildGrid(for module: StationModule, furniture: [FurnitureInstance]) {
        let cellsWide: Int32 = 30
        let cellsTall: Int32 = 32

        let graph = GKGridGraph(
            fromGridStartingAt: vector_int2(0, 0),
            width: cellsWide,
            height: cellsTall,
            diagonalsAllowed: true
        )

        // Block cells occupied by furniture
        var blockedNodes: [GKGridGraphNode] = []
        for item in furniture {
            let footprint = furnitureFootprint(item)
            for cell in footprint {
                if let node = graph.node(atGridPosition: cell) {
                    blockedNodes.append(node)
                }
            }
        }
        graph.remove(blockedNodes)

        roomGrids[module.type] = graph
    }

    func findPath(from: CGPoint, to: CGPoint, in room: ModuleType) -> [CGPoint]? {
        guard let graph = roomGrids[room] else { return nil }

        let startCell = sceneToGrid(from, roomBounds: bounds(for: room))
        let endCell = sceneToGrid(to, roomBounds: bounds(for: room))

        guard let startNode = graph.node(atGridPosition: startCell),
              let endNode = graph.node(atGridPosition: endCell) else { return nil }

        let path = graph.findPath(from: startNode, to: endNode)
        guard !path.isEmpty else { return nil }

        // Convert grid nodes → scene coordinates
        let waypoints = path.compactMap { node -> CGPoint? in
            guard let gridNode = node as? GKGridGraphNode else { return nil }
            return gridToScene(gridNode.gridPosition, roomBounds: bounds(for: room))
        }

        // Smooth with Catmull-Rom interpolation
        return smoothPath(waypoints)
    }
}
```

### Obstacle Mapping

Furniture registers its grid footprint at placement time:

```swift
func furnitureFootprint(_ item: FurnitureInstance) -> [vector_int2] {
    // Convert furniture scene-space bounds to grid cells
    let cellsWide = Int(ceil(item.size.width / 20))
    let cellsTall = Int(ceil(item.size.height / 20))
    let originCell = sceneToGrid(item.position, roomBounds: roomBounds)

    var cells: [vector_int2] = []
    for dx in 0..<cellsWide {
        for dy in 0..<cellsTall {
            cells.append(vector_int2(originCell.x + Int32(dx), originCell.y + Int32(dy)))
        }
    }
    return cells
}
```

### Agent Collision Avoidance

Simple destination reservation:

1. When agent pathfinds to position, **reserve the destination cell**
2. Other agents treat reserved cells as temporary obstacles
3. **300ms timeout** on reservations (prevents deadlocks)
4. If destination is occupied, pick adjacent cell and re-path

### Path Smoothing

Raw A* gives zigzag paths (cell-to-cell). Catmull-Rom spline interpolation creates natural curves:

```
A* waypoints:  [start, (20,40), (40,60), (60,80), end]
                     ↓ Catmull-Rom interpolation
Smooth path:   [start, (15,35), (20,40), (30,50), (40,60), (50,70), (60,80), end]
```

Cost: ~0.5ms per path. Worth it for silky movement.

### Performance Budget

| Metric | Budget | Actual |
|--------|--------|--------|
| Frame time | 16.67ms (60fps) | — |
| SpriteKit render | ~8-10ms | — |
| Pathfinding budget | ~6ms | — |
| A* per query | — | <1ms (GKGridGraph) |
| Agents per frame | 1-2 (staggered) | <2ms |
| **Total pathfinding/frame** | **<6ms** | **~1-2ms** |

Strategy: stagger pathfinding across 4-frame windows. Max 2 queries per frame = well within budget.

---

## Pillar 3: Haptic Layer

Wire CoreHaptics to every interaction:

| Interaction | Haptic Type | Intensity |
|-------------|-------------|-----------|
| Agent tap | `.selection` | — |
| Snap scroll | `.impact(.light)` | Already wired |
| Mini-map open | `.impact(.medium)` | — |
| Door open/close | `.impact(.light)` | Already wired |
| Agent spawn | `.impact(.medium)` | — |
| Task complete | `.notification(.success)` | — |
| Error/alert | `.notification(.error)` | — |
| Weather event | `.impact(.heavy)` | — |
| Pinch zoom | `.selection` on snap | — |
| Activity start | `.impact(.light)` | — |

Implementation: extend existing `HapticService` with new trigger points. ~30 minutes of work.

---

## New Files

| File | Purpose |
|------|---------|
| `Models/ActivityDefinition.swift` | Activity data model (Codable struct) |
| `Models/ActivityRegistry.swift` | Loads Activities.json, provides query API |
| `Models/FurnitureRegistry.swift` | Tracks placed furniture instances per room |
| `Services/ActivitySelectionEngine.swift` | Weighted random selection with filters |
| `Services/GridMovementEngine.swift` | GKGridGraph wrapper, pathfinding, collision |
| `Effects/ActivityAnimator.swift` | Animation + texture swap orchestration |
| `Resources/Activities.json` | Activity definitions (THE extensibility file) |

### Files to Modify

| File | Changes |
|------|---------|
| `OfficeViewModel.swift` | Replace ActivityManager with SelectionEngine |
| `OfficeScene.swift` | Grid init, furniture registration, path-based movement |
| `AgentSprite.swift` | New animation methods, smooth path interpolation |
| `ActivityStation.swift` | Deprecated — replaced by FurnitureRegistry |
| `ActivityManager.swift` | Deprecated — replaced by SelectionEngine |
| `WaypointPathfinder.swift` | Kept for inter-room routing, GridEngine handles intra-room |

---

## Wave Plan

### Wave 1 — Grid Movement Engine
**Goal**: Characters pathfind around furniture, no overlapping.

- Build `GridMovementEngine` with GKGridGraph
- Compute furniture footprints → blocked cells at scene init
- Replace direct-line `moveTo` with grid-pathfound `moveAlongPath`
- Agent cell reservation for collision avoidance
- Catmull-Rom path smoothing
- Inter-room routing: keep WaypointPathfinder for room-to-room, GridEngine for within-room

**Files**: GridMovementEngine.swift (new), OfficeScene.swift, AgentSprite.swift
**Shippable**: Yes — characters walk around furniture instead of through it

### Wave 2 — Activity System Core
**Goal**: JSON-configured activities replace hardcoded stations.

- Build ActivityDefinition, ActivityRegistry, FurnitureRegistry
- Build ActivitySelectionEngine with weighted random + cooldowns
- Load Activities.json at startup
- Register furniture instances from OfficeScene at scene init
- Wire selection engine to OfficeViewModel idle transition
- Ship with initial set of ~15 activities (the ones in the JSON above)
- Deprecate ActivityStation + ActivityManager

**Files**: ActivityDefinition.swift, ActivityRegistry.swift, FurnitureRegistry.swift, ActivitySelectionEngine.swift, Activities.json (all new), OfficeViewModel.swift (modify)
**Shippable**: Yes — characters do room-appropriate activities at furniture

### Wave 3 — Activity Animations + Asset Transitions
**Goal**: Activities look right — animations match activities, furniture reacts.

- Build ActivityAnimator
- Map animationIDs to AgentSprite methods (add new ones: cooking, reading, sleeping, exercise, sniffing, running)
- Implement AssetTransition texture swaps (lamp on→off, dispenser idle→active)
- Emote system during activities (frequency-based random emotes)
- Walking animation integration (when walking between activities)

**Files**: ActivityAnimator.swift (new), AgentSprite.swift (new animations)
**Shippable**: Yes — activities have proper visuals and furniture reacts

### Wave 4 — Haptics + Polish
**Goal**: Tactile feedback everywhere, final tuning.

- Wire CoreHaptics to all interactions (see haptics table above)
- Tune activity durations, cooldowns, priorities based on playtesting
- Tune grid resolution and path smoothing
- Performance profiling pass (Instruments)
- QA on physical device

**Files**: HapticService.swift, various tweaks
**Shippable**: Yes — production-ready life engine

### Wave 5 — New Rooms + Expansion (Stretch)
**Goal**: Library and Conference Room for work activities.

- Add Library room (research activities, bookshelf furniture)
- Add Conference Room (planning activities, whiteboard, table)
- New furniture textures for both rooms
- New work activities in Activities.json
- Update room grid in StationLayout

**Files**: StationLayout.swift, Activities.json, new furniture textures
**Shippable**: Yes — expanded station with work-specific rooms

---

## Key Architecture Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Activity config | JSON file | Zero-code extensibility; hot-reloadable in debug |
| Pathfinding | GKGridGraph (GameplayKit) | Apple-native, <1ms, dynamic obstacles, zero dependencies |
| Grid resolution | 20×20 cells | 4×4 character footprint, clean furniture mapping, 960 cells/room |
| Collision | Cell reservation + timeout | Simple, scales to 8 agents, no physics overhead |
| Path smoothing | Catmull-Rom spline | Natural curves, ~0.5ms cost, worth it |
| Character groups | JSON string enum | "humans", "dogs", "all", "specific" — easy to extend |
| Furniture registry | Runtime singleton | Scene registers instances at init, activities query by type+room |
| Inter-room routing | Keep WaypointPathfinder | Already works; GridEngine handles intra-room only |

---

## Dependencies

- **Map overhaul PR #121** must be merged first (new room layout)
- **Sprite regen** (green-screen prompts) in progress — not blocking, but new walk animations enhance Wave 3
- **No external dependencies** — GameplayKit ships with iOS

---

## Success Criteria

- [ ] Characters walk around furniture, never through it
- [ ] Characters never overlap each other
- [ ] Idle characters perform room-appropriate activities at furniture
- [ ] Dogs do dog things, humans do human things
- [ ] Adding a new activity requires only a JSON entry
- [ ] Adding new furniture + activity requires JSON + texture asset only
- [ ] Asset transitions work (lamp on→off during reading)
- [ ] Haptic feedback on all major interactions
- [ ] 60fps maintained with 8+ active agents
- [ ] Path movement looks smooth and natural (no zigzag)
