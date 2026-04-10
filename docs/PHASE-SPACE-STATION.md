# Phase: The Space Station

> Transform the iOS Office from a flat Silicon Valley tech campus into a living, breathing space station orbiting in deep space. Leverage every SpriteKit capability the web can never match.

---

## Executive Summary

The current iOS office is a flat, colored-rectangle floor plan with 16x16 programmatic pixel art sprites, basic SKAction animations, and a day/night theme overlay. It was built as a proof-of-concept and paused while the PWA caught up. The PWA has since surpassed it: richer furniture rendering, multi-view rooms (office, dog park, gym, Sprite Street), collision avoidance, waypoint pathfinding, 14 character types, and per-furniture idle activities.

This phase completely reimagines the iOS office as **Space Station Major Tom** -- a modular orbital station where AI agents work in futuristic modules connected by corridors with windows to deep space. It exploits SpriteKit capabilities that HTML Canvas fundamentally cannot replicate: GPU particle systems, real-time lighting/shadow nodes, custom CIFilter-based shaders, SKPhysicsBody for zero-G simulation, native haptic feedback, and smooth 60fps rendering backed by Metal.

The result should make the web version look like a toy.

---

## Current Architecture (What We Have)

### iOS Office Inventory

| File | Purpose | Lines |
|------|---------|-------|
| `OfficeScene.swift` | Main SKScene -- floor plan, desks, stations, agent management, theme overlay, ambient animations, agent interactions, mood speech | ~640 |
| `OfficeViewModel.swift` | @Observable VM -- agent lifecycle (spawn/work/idle/complete/dismiss), sprite pool, desk assignment, activity cycling, mood engine | ~280 |
| `OfficeView.swift` | SwiftUI wrapper -- SpriteView, state sync diffing, inspector/gallery sheets, top bar, mini-map placeholder | ~300 |
| `OfficeLayout.swift` | Static layout -- 800x600 scene, 8 areas, 8 desks, door position, randomPosition helper | ~160 |
| `ActivityStation.swift` | Station types (7), positions, capacity, colors, labels | ~95 |
| `ActivityManager.swift` | Station assignment, rotation cycling (5-15s), release logic | ~155 |
| `AgentState.swift` | AgentStatus enum (6 states), CharacterType enum (9 types: 5 humans + 4 dogs), AgentState struct | ~90 |
| `CharacterConfig.swift` | CharacterConfig struct, CharacterCatalog with break behaviors and sprite colors | ~120 |
| `ThemeEngine.swift` | Day/night cycle (dawn/day/dusk/night), seasonal overlays (spring/summer/autumn/winter), 40 random star positions | ~230 |
| `MoodEngine.swift` | Per-agent mood derivation (happy/neutral/focused/bored/frustrated/excited), mood visuals (tint, pulse), mood speech pools | ~300 |
| `AgentSprite.swift` | SKSpriteNode subclass -- pixel art child, name label, status dot, mood tint, speech bubble, movement, 6 animation types, touch handling | ~430 |
| `PixelArtBuilder.swift` | Programmatic 16x16 pixel art for 9 characters using 2pt "pixels" as SKSpriteNode children | ~500+ |

### Key Architecture Decisions Already Made

- **SpriteKit via SpriteView** -- scene embedded in SwiftUI, touch events forward via callback
- **@Observable ViewModel** -- SwiftUI owns state, scene is a rendering target
- **State sync via onChange diffing** -- OfficeView diffs agent arrays and calls scene methods
- **Agent lifecycle** -- spawn at door -> walk to desk -> work -> idle/activity -> celebrate -> leave -> return to pool
- **Sprite pool** -- 9 character types recycled between idle pool and active agents
- **Engine separation** -- ThemeEngine and MoodEngine are independent @Observable objects wired to the scene

### What the PWA Has That iOS Doesn't (Gap Analysis)

| Feature | PWA | iOS |
|---------|-----|-----|
| Character types | 14 (10 humans + 4 dogs) | 9 (5 humans + 4 dogs) |
| Multi-view rooms | 4 views (Office, Dog Park, Gym, Sprite Street) | 1 flat view |
| Furniture rendering | 40+ furniture types with pixel-art renderers | Colored rectangles |
| Pathfinding | Waypoint-based with collision avoidance + stuck detection | Direct line movement |
| Per-furniture activities | Specific positions per furniture piece | Random area placement |
| Floor patterns | carpet, tile, wood, concrete, grass | Flat color fills |
| Agent facing direction | 4 directions (up/down/left/right) | None |
| Walk animation | Phase-based walking cycle | No walk sprite |
| Palette interpolation | Smooth transitions between time-of-day palettes | Instant palette swap |
| Bedrooms (Sprite Street) | 14 personal rooms with beds, closets, rugs | None |

---

## The Space Station Concept

### Narrative

Major Tom is now literally Major Tom -- a space station in orbit. The agents aren't office workers; they're **crew members** aboard an orbital station, running missions (coding tasks) in deep space. The name finally pays off.

### Design Philosophy

1. **Atmosphere over realism** -- This is pixel art in space, not a NASA sim. Lean into the sci-fi aesthetic: glowing consoles, particle effects, dramatic lighting. Think Hyper Light Drifter meets FTL.
2. **Every surface tells a story** -- Floor panels have wear patterns. Pipes run along ceilings. Status lights blink. The station feels lived-in.
3. **Space is the star** -- The windows are the showpiece. Deep parallax starfields, nebulae, planets drifting by. The web version can never match SpriteKit's particle system rendering.
4. **Sound design matters** -- Subtle ambient hums, airlock hisses, console beeps. The web can't do spatial audio.
5. **Haptics are free** -- Every interaction has a haptic signature. Tap a window: gentle pulse. Red alert: sharp buzz. Task complete: success pattern.

---

## Room Mapping

### Current -> Space Station

| Current Room | Station Module | Purpose | Key Visual Elements |
|-------------|---------------|---------|-------------------|
| Main Floor | **Command Bridge** | Primary workstations | Holographic desk displays, captain's chair (orchestrator), tactical screen, status wall |
| Server Room | **Core / Engineering** | Orchestrator's domain | Reactor core visual (pulsing), cable runs, power distribution panels |
| Break Room | **Crew Quarters** | Rest and social | Bunks, viewport windows, media screen, low ambient lighting |
| Kitchen | **Galley** | Space food prep | Food dispensers, zero-G drink globes, meal tray station |
| Dog Corner | **Bio-Dome** | Nature module | Glass dome ceiling showing stars, artificial plants, water feature, grow-light panels |
| Dog Park | **Arboretum** | Extended nature | Larger glass dome, trees, grass patches, artificial sky projection |
| Gym | **Training Bay** | Physical training | Zero-G training equipment, resistance machines, observation window |
| Rollercoaster | **EVA Bay** | Spacewalk staging | Airlock door, space suits on racks, exterior window showing station hull |

### New Modules (Stretch)

| Module | Purpose | Notes |
|--------|---------|-------|
| **Station Corridor** | Connecting hallway | Windows on both sides, floor lighting, directional signs |
| **Observatory** | Stargazing room | Large curved window, telescope, constellation overlays |
| **Cargo Bay** | Storage/utility | Crates, loading dock, shuttle visible through bay doors |

---

## Visual Design Specification

### Color Palette

```
-- Station Interior --
Hull Panels (primary):    #1A1E2E  (dark blue-gray)
Hull Panels (accent):     #252B3F  (slightly lighter)
Floor Panels:             #2A2F40  (metallic gray-blue)
Floor Panel Lines:        #3A4055  (subtle grid)
Ceiling Pipes:            #4A5060  (medium gray)
Wall Trim:                #5A6070  (light gray accent)

-- Lighting --
Console Glow (primary):   #00D4FF  (cyan)
Console Glow (warning):   #FF6B35  (orange)
Console Glow (danger):    #FF2D55  (red)
Console Glow (success):   #30D158  (green)
Status Light (idle):      #FFD60A  (yellow)
Ambient Panel Light:      #4488AA  (blue-white)

-- Space --
Deep Space:               #05080F  (near-black)
Nebula Pink:              #B24592  (magenta)
Nebula Blue:              #2C5F8A  (deep blue)
Nebula Teal:              #1A8F7D  (teal)
Star White:               #FFFDF0  (warm white)
Planet Surface:           #7B6B4A  (Mars-like)
```

### Floor Design

Every module uses a **paneled floor** with subtle grid lines and occasional detail:

```
Tile Pattern:
+--------+--------+--------+
|   ___  |        |  ___   |
|  |   | |   __   | |   |  |   <- Recessed panels with subtle depth
|  |___| |  |  |  | |___|  |
|        |  |__|  |        |
+--------+--------+--------+
```

Implementation: `SKTileMapNode` with a custom tile set. Each tile is a 32x32 texture with floor panel art. Variant tiles for damage/wear, grates, access hatches.

### Wall Design

Walls are built from layered elements:

1. **Base wall** -- Dark hull panel color
2. **Trim strip** -- Lighter accent line along top/bottom
3. **Pipe runs** -- Horizontal pipes/cables along ceiling area (SKShapeNode paths)
4. **Status panels** -- Small blinking rectangles on walls (random patterns)
5. **Windows** -- Rectangular cutouts showing space (see Windows section)
6. **Signage** -- Module name plates near doors

### Windows

Windows are the centerpiece visual feature. Each window is a layered composition:

```
Layer Stack (back to front):
1. Deep space background       (SKSpriteNode, darkest color)
2. Distant nebula layer        (SKEmitterNode, very slow drift)
3. Star field - far layer      (SKEmitterNode, slow parallax)
4. Star field - near layer     (SKEmitterNode, faster parallax)
5. Planet/moon (if visible)    (SKSpriteNode, very slow orbit)
6. Window frame                (SKShapeNode, metallic border)
7. Window reflection overlay   (SKSpriteNode, subtle glass effect)
```

**Parallax behavior**: When the user scrolls/pans the scene, star layers shift at different rates, creating depth. Far stars move slowly, near stars move faster. This is trivial in SpriteKit (`SKCameraNode` with layer speed multipliers) and impossible to replicate smoothly on canvas.

**Dynamic content**: The view outside changes slowly over time:
- Planets drift across windows over ~5 minutes
- Nebula colors shift gradually
- Occasional meteor streaks (SKEmitterNode with short lifetime, triggered randomly)
- Station rotation effect (very subtle parallax shift on a timer)

### Doors / Airlocks

Transitions between modules use airlock-style sliding doors:

```
     ┌──────────┐
     │  ╔════╗  │   <- Door closed
     │  ║    ║  │
     │  ║    ║  │
     │  ╚════╝  │
     └──────────┘

     ┌──────────┐
╔══╗ │          │ ╔══╗  <- Door opening (slide left/right)
║  ║ │          │ ║  ║
║  ║ │          │ ║  ║
╚══╝ │          │ ╚══╝
     └──────────┘
```

Implementation: Two `SKSpriteNode` door panels that slide apart with `SKAction.moveTo`. Triggered when agents approach. Sound effect: pneumatic hiss. Haptic: light impact.

### Lighting System

SpriteKit's `SKLightNode` enables real-time lighting that canvas cannot do:

1. **Overhead panel lights** -- `SKLightNode` at ceiling positions, white-blue color, casting soft downward glow
2. **Console glow** -- Per-workstation `SKLightNode` with cyan tint, low falloff, creates pools of light around active desks
3. **Status light strips** -- Thin `SKShapeNode` strips along walls that change color based on station status:
   - Green: all clear
   - Yellow: agents idle
   - Red: approval needed / error state
4. **Emergency lighting** -- During "red alert" (approval needed), overhead lights dim and red strip lights pulse. Dramatic.
5. **Window light spill** -- Faint light from windows casts into the room (subtle ambient contribution)

**Performance note**: `SKLightNode` requires `SKSpriteNode.lightingBitMask`. All furniture and floor nodes need lighting bitmask set. Limit to ~8 active lights per visible area for 60fps.

---

## Particle Systems

SpriteKit's `SKEmitterNode` is the single biggest advantage over web canvas. These effects are GPU-accelerated and essentially free:

### Ambient Particles

| Effect | Location | Description | Birth Rate | Lifetime |
|--------|----------|-------------|-----------|----------|
| **Star Field (far)** | Behind windows | Tiny white dots, very slow drift left | 20/s | 15s |
| **Star Field (near)** | Behind windows | Slightly larger dots, moderate drift | 10/s | 10s |
| **Nebula Glow** | Behind windows | Large soft colored circles, barely moving | 2/s | 20s |
| **Corridor Dust** | Station corridors | Ultra-faint floating specks, random drift | 5/s | 8s |
| **Console Sparks** | Active workstations | Occasional tiny spark burst (1-3 particles) | 0.3/s | 0.5s |
| **Steam/Vapor** | Galley, airlock seams | Thin white wisps rising | 3/s | 3s |
| **Bio-Dome Pollen** | Bio-Dome/Arboretum | Faint golden specks floating upward | 4/s | 6s |

### Event-Triggered Particles

| Event | Effect | Duration |
|-------|--------|----------|
| **Agent spawn** | Blue energy swirl at door (portal effect) | 1.5s |
| **Task complete** | Green starburst explosion at agent position | 1.0s |
| **Error** | Red spark shower from agent's console | 0.8s |
| **Red alert** | Ambient red particle haze across all modules | Sustained |
| **Meteor shower** | Bright streaks across all windows simultaneously | 5s |
| **Solar flare** | Golden wash from window side, particles streaming inward | 3s |

### Particle .sks Files

Create `.sks` particle files in Xcode's particle editor for each effect. Store in `ios/MajorTom/Resources/Particles/`:

```
Particles/
  StarFieldFar.sks
  StarFieldNear.sks
  NebulaGlow.sks
  CorridorDust.sks
  ConsoleSparks.sks
  SteamVapor.sks
  BioDomePollen.sks
  SpawnPortal.sks
  TaskComplete.sks
  ErrorSparks.sks
  RedAlertHaze.sks
  MeteorStreak.sks
  SolarFlare.sks
```

---

## Interactive Elements

### Tap Interactions

| Target | Action | Visual Feedback | Haptic |
|--------|--------|----------------|--------|
| **Window** | Zoom into starfield mini-view (sheet or fullscreen overlay) | Window border glows, stars brighten | Light impact |
| **Agent at workstation** | Show agent inspector (current task, thought stream) | Console glow brightens, agent looks up | Selection |
| **Idle agent** | Show agent inspector (mood, activity, idle time) | Speech bubble appears | Selection |
| **Console/status panel** | Show station status summary (agent count, alerts, uptime) | Panel highlight animation | Light impact |
| **Airlock door** | Navigate to adjacent module (if multi-view implemented) | Door opens with animation | Medium impact |
| **Reactor core (Engineering)** | Show system health metrics | Core pulses brighter | Heavy impact |

### Window Zoom View

When a window is tapped, present a full-screen overlay (or sheet) showing an expanded starfield:

- Camera slowly pans across a large star/nebula scene
- Planet(s) visible in the distance with surface detail
- Constellation labels (optional, togglable)
- Station hull visible at the bottom edge (silhouette)
- Tap anywhere to dismiss
- This is pure SpriteKit flex -- a second mini-scene rendered in the overlay

### Station Alerts

Station-wide visual state changes tied to agent events:

| Alert State | Trigger | Visual Changes |
|-------------|---------|---------------|
| **Green (All Clear)** | All agents working or idle, no pending approvals | Normal lighting, green status strips, calm ambient |
| **Yellow (Attention)** | Agent error, or agent idle >5min | Yellow status strips, subtle pulse on overhead lights |
| **Red Alert** | Approval needed (PreToolUse hook waiting) | Red status strips pulse, overhead lights dim, red particle haze, alarm sound (optional), strong haptic buzz |
| **Blue (Celebration)** | Task completed | Blue glow wave across station, starburst particles, celebration sound |

---

## Space Weather System

Environmental events that affect the station visually. Purely cosmetic, no gameplay impact. Triggered on random timers (configurable frequency).

| Event | Frequency | Duration | Visual Effect |
|-------|-----------|----------|--------------|
| **Solar Flare** | Every 10-20 min | 3-5s | Golden light washes through all windows, warm particle stream, brief screen flash. All window light intensifies. |
| **Meteor Shower** | Every 15-30 min | 5-8s | Bright streaks across all windows. Agents near windows get a speech bubble ("Whoa!" / "Look at that!") |
| **Nebula Passage** | Every 30-60 min | 2-5 min | Window background color slowly shifts to a nebula palette (pink/teal/purple), then fades back. |
| **Station Rumble** | Every 20-40 min | 1-2s | Entire scene shakes slightly (SKAction on camera node). Haptic: medium impact. Agents stumble animation. |
| **Comms Burst** | Every 5-10 min | 1s | Brief static-like flash on console screens. Purely atmospheric. |

Implementation: `SpaceWeatherEngine` class with a timer that rolls dice on each event. Each event is an `SKAction` sequence applied to relevant nodes.

---

## Sprite Art Direction

### Resolution Upgrade: 16x16 -> 32x32

The current 16x16 pixel art (2pt per pixel = 32pt sprites) is extremely limited. Characters are barely recognizable blobs.

**New standard: 32x32 pixel art at 2pt per pixel = 64pt sprites.**

This quadruples the detail budget:
- Recognizable faces and expressions
- Distinct clothing/uniform details
- Clear directional facing (front/back/left/right)
- Room for accessories (helmets, tools, badges)

### Character Redesign: Space Crew

Each character type gets a space crew variant:

| Current Type | Station Role | Visual Description |
|-------------|-------------|-------------------|
| dev | **Systems Engineer** | Dark blue flight suit, headset, tool belt. Hair visible. |
| officeWorker | **Operations Officer** | Light gray uniform, clipboard tablet, ID badge. |
| pm | **Mission Commander** | Gold-trimmed uniform, shoulder insignia, confident stance. |
| clown | **Morale Officer** | Standard uniform but with colorful patches, silly hat stowed. |
| frankenstein | **Chief Engineer** | Heavy-duty suit, welding visor (up/down), grease smudges. |
| dachshund | **Station Mascot (Dachshund)** | Tiny space vest, wagging tail. Elongated body. |
| cattleDog | **K-9 Unit (Cattle Dog)** | Tactical vest with station patch, alert ears. |
| schnauzerBlack | **Station Dog (Black Schnauzer)** | Space bandana, beard visible even at 32x32. |
| schnauzerPepper | **Station Dog (Pepper Schnauzer)** | Matching bandana (different color), salt-and-pepper fur pattern. |

### Sprite Sheets vs Programmatic Art

**Decision: Hybrid approach.**

- **Body frames**: Pre-rendered sprite sheets (PNG) loaded as `SKTextureAtlas`. 4 directional frames x 3 animation frames (idle, walk1, walk2) = 12 frames per character.
- **Accessories/overlays**: Programmatic SKNode children (helmet, status indicator, mood tint) layered on top of the texture.
- **Facial expressions**: Small overlay textures swapped based on mood (neutral, happy, frustrated, excited).

This gives us the detail quality of hand-drawn sprites with the dynamic flexibility of programmatic overlays.

**Asset pipeline:**
1. Design sprites in Aseprite (or similar pixel art tool) at 32x32
2. Export as sprite sheets with consistent frame layout
3. Import into Xcode asset catalog as `SpriteAtlas` bundles
4. `PixelArtBuilder` refactored to `SpriteBuilder` -- loads textures instead of placing individual pixel nodes

### Helmet Mechanic

Agents wear helmets based on which module they're in:

| Module | Helmet State |
|--------|-------------|
| Command Bridge | Off |
| Engineering / Core | On (safety) |
| Crew Quarters | Off |
| Galley | Off |
| Bio-Dome / Arboretum | Off |
| Training Bay | On (training variant) |
| EVA Bay | On (full space helmet) |
| Corridor | Off (but visible on belt) |

Implementation: `SKSpriteNode` child of the agent sprite, toggled via `isHidden`. Helmet texture swapped per module type.

### Animated Emotes

Small animated overlays above agent sprites:

| Emote | Trigger | Visual |
|-------|---------|--------|
| Thought bubble (`...`) | Agent processing/thinking | Three dots that pulse in sequence |
| Exclamation (`!`) | Error or alert | Red exclamation with shake |
| Light bulb | Task insight/breakthrough | Yellow bulb that flashes on |
| Heart | Happy mood, celebration | Pink heart that floats up and fades |
| Zzz | Napping/long idle | Z letters that drift upward |
| Wrench | Working on code | Small wrench that rotates |
| Star | Achievement/milestone | Gold star with sparkle particles |

Implementation: Pre-built `SKAction` sequences stored as named actions, triggered by mood/status changes.

---

## Technical Architecture

### Scene Hierarchy

```
OfficeScene (SKScene)
├── backgroundLayer (SKNode, zPosition: -100)
│   ├── deepSpaceBackground (SKSpriteNode)
│   ├── nebulaEmitter (SKEmitterNode)
│   ├── starFieldFar (SKEmitterNode)
│   └── starFieldNear (SKEmitterNode)
├── stationLayer (SKNode, zPosition: 0)
│   ├── floorTileMap (SKTileMapNode)
│   ├── wallNodes[] (SKSpriteNode)
│   ├── windowNodes[] (SKNode -- composite)
│   │   ├── windowSpaceView (clips to window rect)
│   │   ├── windowFrame (SKShapeNode)
│   │   └── windowReflection (SKSpriteNode)
│   ├── doorNodes[] (SKNode -- two sliding panels each)
│   ├── furnitureNodes[] (SKSpriteNode)
│   ├── lightNodes[] (SKLightNode)
│   └── statusStrips[] (SKShapeNode)
├── agentLayer (SKNode, zPosition: 50)
│   └── agentSprites[] (AgentSprite -- SKSpriteNode subclass)
│       ├── bodyTexture (SKSpriteNode -- from atlas)
│       ├── helmetOverlay (SKSpriteNode)
│       ├── emoteNode (SKNode)
│       ├── nameLabel (SKLabelNode)
│       ├── statusDot (SKShapeNode)
│       ├── moodTintNode (SKShapeNode)
│       └── speechBubble (SKNode)
├── effectsLayer (SKNode, zPosition: 75)
│   ├── corridorDust (SKEmitterNode)
│   ├── alertHaze (SKEmitterNode, hidden by default)
│   └── eventParticles[] (SKEmitterNode, transient)
├── uiLayer (SKNode, zPosition: 100)
│   ├── themeOverlay (SKSpriteNode)
│   └── alertOverlay (SKSpriteNode)
└── cameraNode (SKCameraNode)
    └── controls parallax + zoom
```

### Camera System

Replace fixed scene with a scrollable, zoomable camera:

```swift
class StationCamera: SKCameraNode {
    /// Current zoom level (1.0 = default, 0.5 = zoomed out, 2.0 = zoomed in)
    var zoomLevel: CGFloat = 1.0

    /// Zoom range
    let minZoom: CGFloat = 0.6
    let maxZoom: CGFloat = 2.5

    /// Pan limits (prevent scrolling past station bounds)
    var panBounds: CGRect = .zero

    func handlePinch(_ scale: CGFloat) { ... }
    func handlePan(_ translation: CGPoint) { ... }
}
```

- **Pinch to zoom**: Scale the camera, which scales the scene
- **Pan to scroll**: Move the camera within bounds
- **Parallax**: Background layers have different `SKNode` speed multipliers relative to camera movement
- **Auto-follow**: Option to track a selected agent (camera smoothly follows their movement)

The web version can only scroll by redrawing the entire canvas. SpriteKit's camera system is zero-cost GPU compositing.

### Tile Map System

Replace programmatic colored rectangles with `SKTileMapNode`:

```swift
// Floor tile groups
enum FloorTileType {
    case standardPanel      // Basic metal floor
    case wornPanel          // Scuffed/worn variant
    case gratePanel         // Ventilation grate
    case accessHatch        // Hatch cover
    case bioFloor           // Bio-Dome grass/soil tile
    case corridorPanel      // Corridor-specific with guide lines
}

// Create tile set
let tileSet = SKTileSet(named: "StationFloors")
let tileMap = SKTileMapNode(
    tileSet: tileSet,
    columns: 25,    // 800 / 32
    rows: 19,       // 600 / 32
    tileSize: CGSize(width: 32, height: 32)
)
```

Tile textures are 32x32 PNG files in the asset catalog. `SKTileMapNode` handles rendering efficiently with GPU instancing.

### Module Layout System

Refactor `OfficeLayout` into a module-based system:

```swift
/// A station module -- replaces OfficeArea
struct StationModule: Identifiable {
    let id: String
    let type: ModuleType
    let name: String
    let bounds: CGRect
    let capacity: Int

    /// Furniture positions within this module
    let furniture: [StationFurniture]

    /// Window positions (relative to module bounds)
    let windows: [WindowConfig]

    /// Door connections to adjacent modules
    let doors: [DoorConfig]

    /// Light positions
    let lights: [LightConfig]

    /// Floor tile type for this module
    let floorType: FloorTileType
}

enum ModuleType: String, CaseIterable {
    case commandBridge
    case engineering
    case crewQuarters
    case galley
    case bioDome
    case arboretum
    case trainingBay
    case evaBay
    case corridor
}
```

### Station Layout

Expanded scene size to accommodate the richer modules: **1200 x 800** (up from 800 x 600).

```
Station Layout (SpriteKit coordinates, origin bottom-left):

┌───────────────────────────────────────────────────────────────────────────┐
│                                                                           │
│    ENGINEERING      COMMAND BRIDGE                  TRAINING BAY          │
│    ┌──────────┐    ┌──────────────────────────┐    ┌──────────────┐      │
│    │          │    │                            │    │              │      │
│    │  Reactor │-D--│  [ws] [ws] [ws]           │-D--│  Equipment   │      │
│    │  Core    │    │  [ws] [ws] [ws]           │    │  Zero-G      │      │
│    │          │    │  [ws] [ws]    [tactical]  │    │              │      │
│    └──────────┘    └──────────────────────────┘    └──────────────┘      │
│         |                    |                           |                │
│    ═══CORRIDOR═══════════CORRIDOR═══════════════CORRIDOR═══              │
│         |                    |                           |                │
│    CREW QUARTERS       GALLEY              BIO-DOME / ARBORETUM          │
│    ┌──────────┐    ┌──────────────┐    ┌──────────────────────┐          │
│    │  Bunks   │    │  Dispensers  │    │  ┌──── Glass Dome ──┐ │          │
│    │  Media   │-D--│  Counter     │-D--│  │  Trees  Plants  │ │          │
│    │  Lounge  │    │  Seating     │    │  │  Water  Feature  │ │          │
│    │          │    │              │    │  └──────────────────┘ │          │
│    └──────────┘    └──────────────┘    └──────────────────────┘          │
│                                                                           │
│    D = Airlock Door    [ws] = Workstation    ═══ = Corridor              │
└───────────────────────────────────────────────────────────────────────────┘
```

### Multi-View Architecture

Like the PWA, support multiple "views" that the user can switch between:

```swift
enum StationView: String, CaseIterable {
    case upperDeck       // Command Bridge, Engineering, Training Bay
    case lowerDeck       // Crew Quarters, Galley, Bio-Dome
    case exterior        // Station exterior view (future stretch)
}
```

Each view is a pre-configured camera position + visible node set. Switching views animates the camera to the new position and toggles node visibility.

For Wave 1-2, keep it as a single scrollable view. Multi-view is Wave 4+.

### Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Frame rate | 60 fps sustained | Xcode GPU debugger |
| Frame time | < 16.6ms | SpriteKit `showsFPS` overlay |
| Node count | < 500 visible | `showsNodeCount` overlay |
| Draw calls | < 50 per frame | Xcode Metal debugger |
| Particle count | < 2000 active | Emitter birthRate tuning |
| Memory (textures) | < 50 MB | Instruments Allocations |
| Memory (total scene) | < 100 MB | Instruments Allocations |
| Haptic latency | < 50ms | Perceived responsiveness |
| Battery impact | < 15% per hour active | Instruments Energy |

**Optimization strategies:**
- Use `SKTextureAtlas` for all sprite sheets (GPU texture batching)
- Set `SKView.ignoresSiblingOrder = true` for automatic draw call batching
- Cull off-screen nodes via `SKCameraNode` containment checks
- Use `SKTileMapNode` for floors (single draw call for entire floor)
- Limit `SKLightNode` count to visible area only
- Particle emitters: tune `numParticlesToEmit` and `particleLifetime` to stay under budget
- Profile on oldest supported device (iPhone 13 mini) not just latest

---

## Sound Design

### Ambient Sounds

| Sound | Trigger | Loop | Volume |
|-------|---------|------|--------|
| Station hum | Always playing | Yes | 0.05 (barely audible) |
| Console beeps | Random, every 10-30s | No | 0.1 |
| Ventilation | Always playing (layered with hum) | Yes | 0.03 |

### Event Sounds

| Event | Sound | Duration |
|-------|-------|----------|
| Airlock open | Pneumatic hiss | 0.5s |
| Airlock close | Reverse pneumatic hiss | 0.5s |
| Agent spawn | Teleport/energy whoosh | 1.0s |
| Task complete | Chime/success tone | 0.8s |
| Error | Alert buzzer (soft) | 0.3s |
| Red alert | Klaxon (single pulse, not annoying) | 0.5s |
| Meteor shower | Distant rumble | 2.0s |
| Solar flare | Energy crackle | 1.0s |
| Station rumble | Low bass thud | 0.5s |

Implementation: `SKAudioNode` for looping ambient sounds, `SKAction.playSoundFileNamed` for one-shots. All sounds respect system mute switch. User preference toggle in settings.

### Haptic Feedback

| Interaction | Haptic Type |
|------------|-------------|
| Tap agent | `.selection` |
| Tap window | `.light` impact |
| Tap console | `.light` impact |
| Airlock open | `.medium` impact |
| Red alert trigger | `.heavy` impact + notification `.warning` |
| Task complete | Notification `.success` |
| Error | Notification `.error` |
| Station rumble | `.heavy` impact (x2, 0.1s apart) |
| Meteor shower | `.rigid` impact sequence (3x, 0.2s apart) |

---

## Gamification Concepts (Future Phases)

These are ideas for post-space-station phases. Not in scope for this phase, but the architecture should not preclude them.

### Station Upgrade System

Cosmetic upgrades earned through agent activity milestones:

| Upgrade | Unlock Condition | Visual Change |
|---------|-----------------|---------------|
| Reinforced Hull | 100 tasks completed | Hull panels get subtle shine texture |
| Advanced Sensors | 50 tools approved | Tactical screen shows more detail |
| Nebula Filter | 10 hours of agent uptime | New nebula color palette |
| Gold Trim | 500 tasks completed | Module borders get gold accent |
| Holiday Lights | During December | String lights along corridors |
| Station Name Plate | First task | Customizable station name shown on hull |

### Mini-Games

While waiting for agent tasks:

| Game | Style | Where |
|------|-------|-------|
| **Asteroid Dodge** | Asteroids-style, tap to thrust | EVA Bay window view |
| **Console Repair** | Simon Says with colored buttons | Engineering console |
| **Cargo Sort** | Tetris-like block stacking | Cargo Bay |
| **Star Chart** | Connect-the-dots constellations | Observatory |

### Crew Morale System

Aggregate mood metric that affects station ambiance:

- High morale: Brighter lights, upbeat ambient sounds, more social interactions
- Low morale: Dimmer lights, fewer social events, occasional "systems warning" beeps
- Derived from: task completion rate, error rate, idle time, approval wait time

### Easter Eggs

- Tap the reactor core 10 times rapidly: brief "overload" animation with dramatic sparks
- Leave the app open for 30+ minutes: a small alien peeks through a window briefly
- All agents celebrating simultaneously: fireworks particle effect outside windows
- Dog sprite near airlock: puts on tiny space helmet

---

## Activity Station Redesign

Map current activity stations to space station equivalents:

| Current Station | Space Station Equivalent | Module | Animation |
|----------------|------------------------|--------|-----------|
| Ping Pong | **Zero-G Ball Court** | Training Bay | Agents bat a glowing orb back and forth, slight float |
| Coffee Machine | **Beverage Synthesizer** | Galley | Agent taps dispenser, zero-G drink globe appears, sips |
| Water Cooler | **Hydration Station** | Galley/Corridor | Agent leans on console, casual chat pose |
| Arcade | **Holo-Game Terminal** | Crew Quarters | Agent faces a glowing screen, rapid tapping animation |
| Yoga | **Meditation Pod** | Bio-Dome | Agent sits cross-legged, faint glow around them |
| Nap | **Sleep Pod** | Crew Quarters | Agent lies in a recessed pod, Zzz emotes |
| Whiteboard | **Holo-Projector** | Command Bridge | Agent gestures at floating holographic display |

New stations unique to space theme:

| Station | Module | Activity | Animation |
|---------|--------|----------|-----------|
| **Observation Scope** | Bio-Dome | Stargazing | Agent peers through telescope, occasionally says "Whoa" |
| **EVA Prep** | EVA Bay | Suit check | Agent inspects space suit on rack, adjusts helmet |
| **Comms Console** | Command Bridge | Monitoring | Agent sits at large console, headset on, tapping controls |

---

## Wave Breakdown

### Wave 1 -- Foundation & Starfield (MVP)

**Goal**: Replace the flat office background with the space station shell. Get starfield working through windows. No sprite changes yet.

**Scope:**
- Refactor `OfficeLayout` -> `StationLayout` with new module system (same bounds, new types/names)
- Replace `renderFloorPlan()` colored rectangles with station-themed `SKSpriteNode` panels (not yet tile maps -- just better colors + borders)
- Add wall segments with metallic appearance
- Implement window nodes with layered starfield (3-layer parallax with SKEmitterNode)
- Replace door rendering with airlock-style door nodes (static, not yet animated)
- Update area labels to station module names
- Ambient corridor dust particles
- Update background color to deep space (#05080F)
- Wire `StationLayout` into existing `OfficeViewModel` (module types map to old area types for backward compat)

**Files touched**: `OfficeScene.swift`, `OfficeLayout.swift` (rename to `StationLayout.swift`), new `Particles/*.sks` files (StarFieldFar, StarFieldNear, CorridorDust)

**Does NOT change**: Agent sprites, ViewModel logic, activity manager, theme engine, mood engine, any SwiftUI views

**Shippable**: Yes -- station looks like a space station, agents still work exactly as before

---

### Wave 2 -- Lighting, Alerts & Atmosphere

**Goal**: Add the lighting system, station alert states, and space weather events.

**Scope:**
- Add `SKLightNode` instances for overhead panels and console glow
- Set `lightingBitMask` on floor/wall/furniture nodes
- Implement station alert system (green/yellow/red/blue) with status strip color changes
- Refactor `ThemeEngine` -> `StationThemeEngine`:
  - Remove earth-based day/night cycle (it's always "night" in space)
  - Replace with station operational modes: Normal, Low Power (dim), Alert (red tint), Celebration (blue glow)
  - Keep seasonal overlays for fun (holiday decorations on the station)
- Add space weather events: solar flare, meteor shower, nebula passage, station rumble
  - New `SpaceWeatherEngine` class with randomized timers
- Haptic feedback for weather events and alert state changes
- Sound effects: station hum ambient, airlock sounds (placeholder for future animated doors)
- Console spark particles at workstations

**Files touched**: `OfficeScene.swift`, `ThemeEngine.swift` (major refactor), new `SpaceWeatherEngine.swift`, new particle `.sks` files (ConsoleSparks, MeteorStreak, SolarFlare, RedAlertHaze), `OfficeView.swift` (alert state UI)

**Shippable**: Yes -- station has atmosphere, reacts to agent events

---

### Wave 3 -- Sprite Overhaul (32x32 + Space Crew)

**Goal**: Replace 16x16 programmatic pixel art with 32x32 sprite-sheet-based characters in space crew uniforms.

**Scope:**
- Design 32x32 space crew sprites for all 9 character types (4 directions x 3 frames each)
- Create `SpriteAtlas` bundles in asset catalog
- Refactor `PixelArtBuilder` -> `CrewSpriteBuilder`:
  - Load textures from atlas instead of placing pixel nodes
  - Support directional facing (front/back/left/right)
  - Walking animation frame cycling
- Add helmet overlay system (SKSpriteNode child, toggled per module)
- Add animated emote system (thought bubble, exclamation, heart, Zzz, wrench, star)
- Update `AgentSprite` to use texture-based rendering:
  - Body: SKSpriteNode with atlas textures
  - Overlays: helmet, emote, mood tint (still programmatic)
  - Facial expression swap based on mood
- Improve movement: basic waypoint pathfinding (door -> corridor -> target module)
- Agent facing direction updates based on movement vector

**Files touched**: `AgentSprite.swift` (major refactor), `PixelArtBuilder.swift` (replace with `CrewSpriteBuilder.swift`), `AgentState.swift` (add facing direction), new sprite assets in Xcode asset catalog

**Shippable**: Yes -- agents look dramatically better, move more naturally

---

### Wave 4 -- Furniture, Tile Maps & Multi-View

**Goal**: Rich module interiors with real furniture, tile-mapped floors, and deck-based navigation.

**Scope:**
- Create 32x32 tile textures for station floors (standard panel, worn panel, grate, access hatch, bio floor, corridor)
- Replace `SKSpriteNode` floor fills with `SKTileMapNode`
- Design and render station furniture as `SKSpriteNode` with textures:
  - Command Bridge: workstation consoles, tactical screen, captain's chair
  - Crew Quarters: bunks, media screen, lounge seating
  - Galley: food dispensers, seating, drink station
  - Bio-Dome: planters, water feature, telescope
  - Training Bay: equipment, observation window
  - Engineering: reactor core visual, power panels
- Implement animated airlock doors (slide open/close when agents approach)
- Add camera system (`StationCamera: SKCameraNode`) with pinch-to-zoom and pan
- Implement multi-view deck switching (upper deck / lower deck)
- Update activity stations to space-themed equivalents with per-furniture target positions
- Refactor `ActivityStation.swift` -> `StationActivity.swift` with new station types

**Files touched**: `OfficeScene.swift` (furniture + tile map + camera), `ActivityStation.swift` (rename + redesign), new tile/furniture assets, `OfficeView.swift` (deck switcher UI, gesture recognizers)

**Shippable**: Yes -- station feels fully realized with furniture and navigation

---

### Wave 5 -- Sound, Haptics & Interactive Windows

**Goal**: Audio atmosphere, full haptic integration, and the window zoom feature.

**Scope:**
- Implement ambient sound system (station hum, ventilation loop, random console beeps)
- Add event-triggered sounds (spawn, complete, error, alert, weather)
- Wire haptic feedback to all interactions (see Haptic Feedback table)
- Build window zoom view:
  - Tap window -> present expanded starfield overlay
  - Second SKScene rendered in a sheet/overlay with richer star detail
  - Slow camera pan across large nebula/star composition
  - Planet with surface detail visible in distance
  - Tap to dismiss
- Polish: smooth palette transitions for alert states, parallax tuning, particle density balancing
- User preferences: sound on/off, haptics on/off, particle density (low/medium/high)
- Performance profiling pass on oldest supported device

**Files touched**: Sound asset files (`.m4a` / `.caf`), `OfficeScene.swift` (audio + haptics), new `StarfieldOverlayScene.swift`, `OfficeView.swift` (window tap handling, settings), settings storage

**Shippable**: Yes -- full sensory experience, production-ready polish

---

### Wave 6 -- Parity & Integration

**Goal**: Bring iOS up to feature parity with PWA where applicable, wire to live relay data.

**Scope:**
- Add missing character types to match PWA (10 humans + 4 dogs, up from 5 humans + 4 dogs)
  - New crew roles: Architect, Lead Engineer, Eng Manager, Backend/Frontend Engineer, UX Designer, DevOps, Database Guru
  - Design 32x32 sprites for 5 new characters
- Wire `OfficeViewModel` to live `RelayService` agent events (currently mock-only per STATUS.md)
- Implement agent-to-crew-role dynamic mapping (map Claude Code agent role strings to character types)
- Add personal quarters / crew bunks (equivalent to PWA's Sprite Street bedrooms -- stretch)
- Mini-map: functional mini-map showing station layout with agent positions as dots
- Performance: final optimization pass, memory audit, battery impact measurement
- QA: test all particle effects, lighting, sounds, haptics on physical devices

**Files touched**: `CharacterConfig.swift` (new types), `OfficeViewModel.swift` (relay integration), new sprite assets, `OfficeView.swift` (mini-map), various polish across all files

**Shippable**: Yes -- feature-complete space station, production-ready

---

## Why This Destroys the Web Version

| Capability | SpriteKit (iOS) | Canvas (PWA) |
|-----------|----------------|--------------|
| **Particle systems** | GPU-accelerated SKEmitterNode, thousands of particles at zero CPU cost | Manual particle loops eating JS main thread, capped at hundreds |
| **Real-time lighting** | SKLightNode with shadow casting, normal maps, per-pixel lighting | Fake lighting via overlay blending, no real shadows |
| **Tile maps** | SKTileMapNode with GPU instancing, single draw call for entire floors | Manual tile loop, one drawImage per tile |
| **Physics** | SKPhysicsBody for zero-G floating objects, collision, joints | Manual physics math, expensive per-frame |
| **Shaders** | Custom CIFilter / SKShader GLSL programs for glow, distortion, scan lines | No shader support (WebGL possible but separate from Canvas2D) |
| **Camera** | SKCameraNode with hardware-accelerated zoom/pan/parallax | Manual transform + full redraw on every scroll |
| **Haptics** | Native CoreHaptics with fine-grained feedback patterns | Navigator.vibrate() -- binary on/off, Android only |
| **Audio** | SKAudioNode with spatial positioning, seamless looping | Web Audio API -- works but no spatial without extra libs |
| **Frame rate** | Locked 60fps via Metal/GPU compositor, scene graph diffing | requestAnimationFrame, entire scene redrawn from scratch |
| **Battery** | Metal GPU rendering is power-efficient, SpriteKit hibernates idle scenes | Canvas burns CPU constantly, no idle optimization |
| **Texture atlasing** | Automatic GPU texture batching, memory-efficient | Manual sprite sheet slicing, no GPU batching |

The web version will always be limited by the browser's rendering pipeline. SpriteKit is a native game engine backed by Metal. The gap is fundamental and permanent.

---

## Asset Requirements Summary

### Textures (PNG, in Xcode Asset Catalog)

| Asset | Size | Count | Notes |
|-------|------|-------|-------|
| Floor tiles | 32x32 | 6 variants | Standard, worn, grate, hatch, bio, corridor |
| Wall segments | 32xVariable | 4 variants | Hull panel, trim, pipe overlay, sign |
| Window frames | Variable | 3 sizes | Small (32x48), medium (64x48), large (128x48) |
| Door panels | 32x64 | 2 per door | Left + right airlock panel |
| Furniture | Variable | ~20 pieces | Workstation, bunk, dispenser, reactor, etc. |
| Character sprites | 32x32 per frame | 12 frames x 9 characters = 108 | 4 directions x 3 animation frames |
| Helmet overlays | 16x16 | 3 types | Standard, training, EVA |
| Emote icons | 16x16 | 7 types | Thought, exclamation, heart, Zzz, wrench, star, bulb |
| Facial expressions | 8x8 | 6 per character = 54 | neutral, happy, frustrated, excited, focused, bored |
| Nebula backdrop | 512x256 | 2-3 variants | Tiling nebula textures for window backgrounds |
| Planet | 128x128 | 2-3 variants | Distant planet textures |
| Station exterior | 256x128 | 1 | For window zoom view silhouette |

### Particle Files (.sks)

13 particle effect files (listed in Particle Systems section above).

### Sound Files (.m4a or .caf)

~15 sound files (listed in Sound Design section above). Keep under 1MB total. Use compressed .m4a for non-looping, .caf for seamless loops.

### Total Estimated Asset Size

~5-8 MB added to app bundle. Acceptable for an iOS app.

---

## Resolved Decisions

1. **Art creation**: Hybrid approach. Free itch.io pixel art packs for environment (floors, walls, furniture). Programmatic upgrade (PixelArtBuilder 16x16 → 32x32 space crew) for characters initially. AI-generated art (DALL-E via ChatGPT Plus) as optional upgrade later for premium character sprites.
2. **Scene size**: **1200x800** — go big. Camera pan/zoom handles the mobile screen.
3. **Multi-view vs single scroll**: **Deck-based tabs** with airlock door transitions. Multi-view UX, not scrollable map.
4. **Relay integration**: **Wave 6** — visual revamp first, wire live data when station is ready.
5. **Character identity**: **DISTINCT from PWA.** iOS gets space crew roles (Commander, Engineer, Navigator, etc.). PWA keeps office workers. iOS is the premium experience — if parity ever happens, PWA copies iOS, not the other way around.
6. **Sound**: **Off by default** with visible toggle. Full sound design is a future phase — user will collect sound FX assets.
7. **Tile map**: **SKTileMapNode** — GPU-instanced, one draw call for floors, fits the 50 draw call budget.
