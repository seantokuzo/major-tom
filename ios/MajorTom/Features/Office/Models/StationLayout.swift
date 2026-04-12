import SpriteKit

// MARK: - Module Type

/// The distinct modules aboard Space Station Major Tom.
/// Maps 1:1 to the legacy OfficeAreaType for backward compatibility.
enum ModuleType: String, CaseIterable {
    case commandBridge    // Primary workstations (was: mainFloor)
    case engineering      // Orchestrator's domain (was: serverRoom)
    case crewQuarters     // Rest and social (was: breakRoom)
    case galley           // Space food prep (was: kitchen)
    case bioDome          // Nature module (was: dogCorner)
    case arboretum        // Extended nature (was: dogPark)
    case trainingBay      // Physical training (was: gym)
    case evaBay           // Spacewalk staging (was: rollercoaster)

    /// Map back to legacy OfficeAreaType for ViewModel/ActivityManager compat.
    var officeAreaType: OfficeAreaType {
        switch self {
        case .commandBridge: return .mainFloor
        case .engineering:   return .serverRoom
        case .crewQuarters:  return .breakRoom
        case .galley:        return .kitchen
        case .bioDome:       return .dogCorner
        case .arboretum:     return .dogPark
        case .trainingBay:   return .gym
        case .evaBay:        return .rollercoaster
        }
    }

    /// Create from legacy area type.
    init(from areaType: OfficeAreaType) {
        switch areaType {
        case .mainFloor:     self = .commandBridge
        case .serverRoom:    self = .engineering
        case .breakRoom:     self = .crewQuarters
        case .kitchen:       self = .galley
        case .dogCorner:     self = .bioDome
        case .dogPark:       self = .arboretum
        case .gym:           self = .trainingBay
        case .rollercoaster: self = .evaBay
        }
    }

    /// Display name for the module.
    var displayName: String {
        switch self {
        case .commandBridge: return "Command Bridge"
        case .engineering:   return "Engineering"
        case .crewQuarters:  return "Crew Quarters"
        case .galley:        return "Galley"
        case .bioDome:       return "Bio-Dome"
        case .arboretum:     return "Arboretum"
        case .trainingBay:   return "Training Bay"
        case .evaBay:        return "EVA Bay"
        }
    }
}

// MARK: - Window Config

/// A window positioned within a station module showing deep space.
struct WindowConfig {
    let position: CGPoint   // Center position relative to scene
    let size: CGSize         // Window frame size
}

// MARK: - Door Config

/// An airlock door between modules or at station entry.
struct DoorConfig: Identifiable {
    let id: String
    let position: CGPoint
    /// When true, door panels slide left/right (doorway spans vertically, e.g. corridor-to-module).
    /// When false, door panels slide up/down (doorway spans horizontally, e.g. between side-by-side modules).
    let isHorizontalSlide: Bool
    let size: CGSize

    init(id: String, position: CGPoint, isHorizontalSlide: Bool, size: CGSize = CGSize(width: 30, height: 30)) {
        self.id = id
        self.position = position
        self.isHorizontalSlide = isHorizontalSlide
        self.size = size
    }
}

// MARK: - Station Module

/// A module aboard the space station — replaces OfficeArea for rendering.
struct StationModule: Identifiable {
    let type: ModuleType
    let bounds: CGRect
    let capacity: Int
    let windows: [WindowConfig]

    var id: String { type.rawValue }
    var name: String { type.displayName }

    /// The legacy OfficeArea this maps to.
    var officeAreaType: OfficeAreaType { type.officeAreaType }
}

// MARK: - Station Palette

/// The space station color palette — all colors from the design spec.
enum StationPalette {
    // -- Station Interior --
    static let hullPrimary    = SKColor(red: 0.102, green: 0.118, blue: 0.180, alpha: 1) // #1A1E2E
    static let hullAccent     = SKColor(red: 0.145, green: 0.169, blue: 0.247, alpha: 1) // #252B3F
    static let floorPanel     = SKColor(red: 0.165, green: 0.184, blue: 0.251, alpha: 1) // #2A2F40
    static let floorGridLine  = SKColor(red: 0.227, green: 0.251, blue: 0.333, alpha: 1) // #3A4055
    static let ceilingPipe    = SKColor(red: 0.290, green: 0.314, blue: 0.376, alpha: 1) // #4A5060
    static let wallTrim       = SKColor(red: 0.353, green: 0.376, blue: 0.439, alpha: 1) // #5A6070

    // -- Lighting --
    static let consoleCyan    = SKColor(red: 0, green: 0.831, blue: 1, alpha: 1)         // #00D4FF
    static let consoleWarning = SKColor(red: 1, green: 0.420, blue: 0.208, alpha: 1)     // #FF6B35
    static let consoleDanger  = SKColor(red: 1, green: 0.176, blue: 0.333, alpha: 1)     // #FF2D55
    static let consoleSuccess = SKColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1) // #30D158
    static let statusIdle     = SKColor(red: 1, green: 0.839, blue: 0.039, alpha: 1)     // #FFD60A
    static let ambientPanel   = SKColor(red: 0.267, green: 0.533, blue: 0.667, alpha: 1) // #4488AA

    // -- Space --
    static let deepSpace      = SKColor(red: 0.020, green: 0.031, blue: 0.059, alpha: 1) // #05080F
    static let nebulaPink     = SKColor(red: 0.698, green: 0.271, blue: 0.573, alpha: 1) // #B24592
    static let nebulaBlue     = SKColor(red: 0.173, green: 0.373, blue: 0.541, alpha: 1) // #2C5F8A
    static let nebulaTeal     = SKColor(red: 0.102, green: 0.561, blue: 0.490, alpha: 1) // #1A8F7D
    static let starWhite      = SKColor(red: 1, green: 0.992, blue: 0.941, alpha: 1)     // #FFFDF0
    static let planetSurface  = SKColor(red: 0.482, green: 0.420, blue: 0.290, alpha: 1) // #7B6B4A

    // -- Corridor --
    static let corridorFloor  = SKColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 1)    // Dark corridor
    static let guideLightDim  = SKColor(red: 0.0, green: 0.5, blue: 0.7, alpha: 0.15)    // Floor guide

    // -- Per-module floor accent tints (subtle variation so modules feel distinct) --
    static func floorColor(for module: ModuleType) -> SKColor {
        switch module {
        case .commandBridge: return SKColor(red: 0.14, green: 0.16, blue: 0.22, alpha: 1) // Blue-steel
        case .engineering:   return SKColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1) // Darker, industrial
        case .crewQuarters:  return SKColor(red: 0.16, green: 0.15, blue: 0.19, alpha: 1) // Warmer gray
        case .galley:        return SKColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1) // Neutral warm
        case .bioDome:       return SKColor(red: 0.10, green: 0.16, blue: 0.14, alpha: 1) // Slight green tint
        case .arboretum:     return SKColor(red: 0.10, green: 0.17, blue: 0.13, alpha: 1) // Green-tinted
        case .trainingBay:   return SKColor(red: 0.16, green: 0.14, blue: 0.19, alpha: 1) // Purple-tinted
        case .evaBay:        return SKColor(red: 0.14, green: 0.13, blue: 0.18, alpha: 1) // Cool violet
        }
    }
}

// MARK: - Snap Position

/// The four main camera snap positions in the 2×4 grid layout.
/// Each position centers the camera on a pair of vertically-adjacent rooms in one column.
enum SnapPosition: CaseIterable {
    case col1Top      // Command Bridge + Engineering
    case col1Bottom   // Crew Quarters + Galley
    case col2Top      // Bio-Dome + Arboretum
    case col2Bottom   // Training Bay + EVA Bay
}

// MARK: - Station Layout

/// The complete spatial layout of Space Station Major Tom.
/// Scene size: 1240×2620 — 2-column × 4-row grid of 600×640 rooms.
/// Column gap: 40w. Corridor between rows: 20h.
/// All coordinates are in SpriteKit scene points (origin bottom-left, Y goes up).
///
/// Station Layout (2 columns × 4 rows):
/// ```
///  Col 1 (x: 0–600)           Col 2 (x: 640–1240)
/// ┌──────────────────┐  40  ┌──────────────────┐ y=2620
/// │  COMMAND BRIDGE  │      │    BIO-DOME      │
/// │   (row 0)        │      │    (row 0)        │ y=1980
/// ├─── corridor ─────┤      ├─── corridor ─────┤ y=1960-1980
/// │   ENGINEERING    │      │    ARBORETUM      │
/// │   (row 1)        │      │    (row 1)        │ y=1320
/// ├─── corridor ─────┤      ├─── corridor ─────┤ y=1300-1320
/// │  CREW QUARTERS   │      │   TRAINING BAY   │
/// │   (row 2)        │      │    (row 2)        │ y=660
/// ├─── corridor ─────┤      ├─── corridor ─────┤ y=640-660
/// │     GALLEY       │      │     EVA BAY      │
/// │   (row 3)        │      │    (row 3)        │ y=0
/// └──────────────────┘      └──────────────────┘
/// ```
enum StationLayout {

    /// Scene dimensions — 2-column × 4-row grid
    static let sceneWidth: CGFloat = 1240
    static let sceneHeight: CGFloat = 2620

    /// Room dimensions
    static let roomWidth: CGFloat = 600
    static let roomHeight: CGFloat = 640
    static let columnGap: CGFloat = 40
    static let corridorHeight: CGFloat = 20

    /// Column X origins
    static let col1X: CGFloat = 0
    static let col2X: CGFloat = 640  // 600 + 40 gap

    /// All corridor bands between adjacent rooms (6 corridors, 3 per column).
    static let corridors: [CGRect] = [
        // Column 1 corridors
        CGRect(x: 20, y: 640, width: 560, height: 20),    // Galley ↔ Crew Quarters
        CGRect(x: 20, y: 1300, width: 560, height: 20),   // Crew Quarters ↔ Engineering
        CGRect(x: 20, y: 1960, width: 560, height: 20),   // Engineering ↔ Command Bridge
        // Column 2 corridors
        CGRect(x: 660, y: 640, width: 560, height: 20),   // EVA Bay ↔ Training Bay
        CGRect(x: 660, y: 1300, width: 560, height: 20),  // Training Bay ↔ Arboretum
        CGRect(x: 660, y: 1960, width: 560, height: 20),  // Arboretum ↔ Bio-Dome
    ]

    /// Legacy single corridor bounds — uses the first corridor for backward compat.
    static let corridorBounds: CGRect = corridors[0]

    /// The station airlock — entry/exit point for agents (top of Command Bridge)
    static let airlockPosition = CGPoint(x: 300, y: 2500)

    // MARK: - Camera Defaults

    /// Default camera center: col1_top snap position (Command Bridge + Engineering)
    static let cameraCenter = CGPoint(x: 300, y: 1970)
    static let defaultCameraScale: CGFloat = 0.5  // Shows ~1 column × 2 rows + corridor
    static let minCameraScale: CGFloat = 0.25     // Max zoom in (fine detail)
    static let maxCameraScale: CGFloat = 0.5      // Default IS max zoom out

    /// Get the camera center point for a snap position.
    static func snapCenter(for position: SnapPosition) -> CGPoint {
        switch position {
        case .col1Top:    return CGPoint(x: 300, y: 1970)   // Command Bridge + Engineering
        case .col1Bottom: return CGPoint(x: 300, y: 650)    // Crew Quarters + Galley
        case .col2Top:    return CGPoint(x: 940, y: 1970)   // Bio-Dome + Arboretum
        case .col2Bottom: return CGPoint(x: 940, y: 650)    // Training Bay + EVA Bay
        }
    }

    // MARK: - Modules

    static let modules: [StationModule] = [
        // -- Column 1 (x: 0–600), bottom to top --

        // Galley: col1, row 3 — y=0–640
        StationModule(
            type: .galley,
            bounds: CGRect(x: 0, y: 0, width: 600, height: 640),
            capacity: 3,
            windows: [
                // Left wall (outer wall for col1)
                WindowConfig(position: CGPoint(x: 8, y: 200), size: CGSize(width: 16, height: 80)),
                WindowConfig(position: CGPoint(x: 8, y: 440), size: CGSize(width: 16, height: 60)),
                // Bottom wall
                WindowConfig(position: CGPoint(x: 300, y: 8), size: CGSize(width: 120, height: 16)),
            ]
        ),

        // Crew Quarters: col1, row 2 — y=660–1300
        StationModule(
            type: .crewQuarters,
            bounds: CGRect(x: 0, y: 660, width: 600, height: 640),
            capacity: 4,
            windows: [
                // Left wall (outer wall for col1)
                WindowConfig(position: CGPoint(x: 8, y: 880), size: CGSize(width: 16, height: 80)),
                WindowConfig(position: CGPoint(x: 8, y: 1100), size: CGSize(width: 16, height: 80)),
            ]
        ),

        // Engineering: col1, row 1 — y=1320–1960
        StationModule(
            type: .engineering,
            bounds: CGRect(x: 0, y: 1320, width: 600, height: 640),
            capacity: 1,
            windows: [
                // Left wall (outer wall for col1)
                WindowConfig(position: CGPoint(x: 8, y: 1540), size: CGSize(width: 16, height: 80)),
                WindowConfig(position: CGPoint(x: 8, y: 1760), size: CGSize(width: 16, height: 80)),
                // Top wall
                WindowConfig(position: CGPoint(x: 300, y: 1952), size: CGSize(width: 80, height: 16)),
            ]
        ),

        // Command Bridge: col1, row 0 — y=1980–2620
        StationModule(
            type: .commandBridge,
            bounds: CGRect(x: 0, y: 1980, width: 600, height: 640),
            capacity: 8,
            windows: [
                // Top wall — large viewports (the showpiece)
                WindowConfig(position: CGPoint(x: 150, y: 2605), size: CGSize(width: 100, height: 20)),
                WindowConfig(position: CGPoint(x: 300, y: 2605), size: CGSize(width: 120, height: 20)),
                WindowConfig(position: CGPoint(x: 450, y: 2605), size: CGSize(width: 100, height: 20)),
                // Left wall (outer wall for col1)
                WindowConfig(position: CGPoint(x: 8, y: 2300), size: CGSize(width: 16, height: 80)),
            ]
        ),

        // -- Column 2 (x: 640–1240), bottom to top --

        // EVA Bay: col2, row 3 — y=0–640
        StationModule(
            type: .evaBay,
            bounds: CGRect(x: 640, y: 0, width: 600, height: 640),
            capacity: 2,
            windows: [
                // Right wall (outer wall for col2)
                WindowConfig(position: CGPoint(x: 1232, y: 200), size: CGSize(width: 16, height: 80)),
                WindowConfig(position: CGPoint(x: 1232, y: 440), size: CGSize(width: 16, height: 80)),
                // Bottom wall
                WindowConfig(position: CGPoint(x: 940, y: 8), size: CGSize(width: 160, height: 16)),
            ]
        ),

        // Training Bay: col2, row 2 — y=660–1300
        StationModule(
            type: .trainingBay,
            bounds: CGRect(x: 640, y: 660, width: 600, height: 640),
            capacity: 3,
            windows: [
                // Right wall (outer wall for col2)
                WindowConfig(position: CGPoint(x: 1232, y: 880), size: CGSize(width: 16, height: 80)),
                WindowConfig(position: CGPoint(x: 1232, y: 1100), size: CGSize(width: 16, height: 80)),
            ]
        ),

        // Arboretum: col2, row 1 — y=1320–1960
        StationModule(
            type: .arboretum,
            bounds: CGRect(x: 640, y: 1320, width: 600, height: 640),
            capacity: 4,
            windows: [
                // Right wall (outer wall for col2)
                WindowConfig(position: CGPoint(x: 1232, y: 1540), size: CGSize(width: 16, height: 80)),
                WindowConfig(position: CGPoint(x: 1232, y: 1760), size: CGSize(width: 16, height: 80)),
                // Top wall
                WindowConfig(position: CGPoint(x: 940, y: 1952), size: CGSize(width: 180, height: 16)),
            ]
        ),

        // Bio-Dome: col2, row 0 — y=1980–2620
        StationModule(
            type: .bioDome,
            bounds: CGRect(x: 640, y: 1980, width: 600, height: 640),
            capacity: 4,
            windows: [
                // Glass dome — large observation window across the top
                WindowConfig(position: CGPoint(x: 940, y: 2612), size: CGSize(width: 240, height: 20)),
                // Right wall (outer wall for col2)
                WindowConfig(position: CGPoint(x: 1232, y: 2200), size: CGSize(width: 16, height: 90)),
                WindowConfig(position: CGPoint(x: 1232, y: 2420), size: CGSize(width: 16, height: 90)),
            ]
        ),
    ]

    // MARK: - Airlock Doors

    /// Doors between vertically adjacent rooms (one door per corridor, 6 total).
    static let doors: [DoorConfig] = [
        // Column 1 doors
        DoorConfig(id: "galley_crew", position: CGPoint(x: 300, y: 650), isHorizontalSlide: true),
        DoorConfig(id: "crew_engineering", position: CGPoint(x: 300, y: 1310), isHorizontalSlide: true),
        DoorConfig(id: "engineering_bridge", position: CGPoint(x: 300, y: 1970), isHorizontalSlide: true),
        // Column 2 doors
        DoorConfig(id: "eva_training", position: CGPoint(x: 940, y: 650), isHorizontalSlide: true),
        DoorConfig(id: "training_arboretum", position: CGPoint(x: 940, y: 1310), isHorizontalSlide: true),
        DoorConfig(id: "arboretum_biodome", position: CGPoint(x: 940, y: 1970), isHorizontalSlide: true),
    ]

    // MARK: - Helpers

    /// Find the module containing a given point.
    static func module(at point: CGPoint) -> StationModule? {
        modules.first { $0.bounds.contains(point) }
    }

    /// Find a module by type.
    static func module(for type: ModuleType) -> StationModule? {
        modules.first { $0.type == type }
    }

    /// Find a module by legacy area type.
    static func module(for areaType: OfficeAreaType) -> StationModule? {
        let moduleType = ModuleType(from: areaType)
        return module(for: moduleType)
    }

    /// All windows across all modules.
    static var allWindows: [(module: StationModule, window: WindowConfig)] {
        modules.flatMap { module in
            module.windows.map { (module: module, window: $0) }
        }
    }

    /// Check if a point is in any corridor.
    static func isInCorridor(_ point: CGPoint) -> Bool {
        corridors.contains { $0.contains(point) }
    }
}
