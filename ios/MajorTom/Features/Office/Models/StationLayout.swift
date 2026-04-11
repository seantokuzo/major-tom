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

// MARK: - Station Layout

/// The complete spatial layout of Space Station Major Tom.
/// Scene size: 1200×800 (expanded from 800×600 for camera zoom).
/// All coordinates are in SpriteKit scene points (origin bottom-left).
///
/// Station Layout:
/// ```
/// ┌────────────────┬────────────────────────────────┬────────────────┐
/// │  ENGINEERING   │   COMMAND BRIDGE              │ TRAINING BAY   │
/// │  (reactor)     │   [ws] [ws] [ws]              │ equipment      │
/// │                │   [ws] [ws] [ws]              ├────────────────│
/// │                │   [ws] [ws]    [tactical]     │ EVA BAY        │
/// │────────────────┤                               │ suits/airlock  │
/// │═══ CORRIDOR ═══════════════════════════════════════════════════ │
/// │────────────────┤                               │                │
/// │  CREW QUARTERS │   GALLEY        │  BIO-DOME   │  ARBORETUM    │
/// │  bunks/media   │   dispensers    │  glass dome  │  trees/grass  │
/// │  lounge        │   counter       │  plants      │  water        │
/// └────────────────┴────────────────┴──────────────┴───────────────┘
/// ```
enum StationLayout {

    /// Scene dimensions — expanded for camera zoom detail
    static let sceneWidth: CGFloat = 1200
    static let sceneHeight: CGFloat = 800

    /// Corridor band connecting upper and lower decks
    static let corridorBounds = CGRect(x: 20, y: 370, width: 1160, height: 60)

    /// The station airlock — entry/exit point for agents (right side of Command Bridge)
    static let airlockPosition = CGPoint(x: 760, y: 600)

    // MARK: - Camera Defaults

    static let cameraCenter = CGPoint(x: sceneWidth / 2, y: sceneHeight / 2)
    static let defaultCameraScale: CGFloat = 1.0
    static let minCameraScale: CGFloat = 0.4   // Max zoom in
    static let maxCameraScale: CGFloat = 1.3   // Max zoom out

    // MARK: - Modules

    static let modules: [StationModule] = [
        // -- Upper Deck (y: 430–760) --
        StationModule(
            type: .commandBridge,
            bounds: CGRect(x: 260, y: 430, width: 500, height: 330),
            capacity: 8,
            windows: [
                // Large viewport windows along the top wall — the showpiece
                WindowConfig(position: CGPoint(x: 420, y: 745), size: CGSize(width: 120, height: 24)),
                WindowConfig(position: CGPoint(x: 620, y: 745), size: CGSize(width: 100, height: 24)),
                // Side viewport on the right wall
                WindowConfig(position: CGPoint(x: 752, y: 600), size: CGSize(width: 16, height: 80)),
            ]
        ),
        StationModule(
            type: .engineering,
            bounds: CGRect(x: 20, y: 430, width: 220, height: 330),
            capacity: 1,
            windows: [
                // Left wall viewport
                WindowConfig(position: CGPoint(x: 28, y: 600), size: CGSize(width: 16, height: 80)),
                // Top wall viewport
                WindowConfig(position: CGPoint(x: 130, y: 745), size: CGSize(width: 80, height: 20)),
            ]
        ),
        StationModule(
            type: .trainingBay,
            bounds: CGRect(x: 780, y: 590, width: 400, height: 170),
            capacity: 3,
            windows: [
                // Right wall observation window
                WindowConfig(position: CGPoint(x: 1172, y: 675), size: CGSize(width: 16, height: 80)),
                // Top wall window
                WindowConfig(position: CGPoint(x: 980, y: 745), size: CGSize(width: 100, height: 20)),
            ]
        ),
        StationModule(
            type: .evaBay,
            bounds: CGRect(x: 780, y: 430, width: 400, height: 140),
            capacity: 2,
            windows: [
                // Large EVA observation window — can see station hull
                WindowConfig(position: CGPoint(x: 1000, y: 438), size: CGSize(width: 160, height: 16)),
                // Right wall viewport
                WindowConfig(position: CGPoint(x: 1172, y: 500), size: CGSize(width: 16, height: 60)),
            ]
        ),

        // -- Lower Deck (y: 20–370) --
        StationModule(
            type: .crewQuarters,
            bounds: CGRect(x: 20, y: 20, width: 220, height: 350),
            capacity: 4,
            windows: [
                // Left wall viewport — agents stargaze through this
                WindowConfig(position: CGPoint(x: 28, y: 230), size: CGSize(width: 16, height: 80)),
                WindowConfig(position: CGPoint(x: 28, y: 100), size: CGSize(width: 16, height: 50)),
            ]
        ),
        StationModule(
            type: .galley,
            bounds: CGRect(x: 260, y: 20, width: 260, height: 350),
            capacity: 3,
            windows: [
                // Bottom wall porthole
                WindowConfig(position: CGPoint(x: 390, y: 28), size: CGSize(width: 60, height: 16)),
            ]
        ),
        StationModule(
            type: .bioDome,
            bounds: CGRect(x: 540, y: 20, width: 300, height: 350),
            capacity: 4,
            windows: [
                // Bio-Dome "glass dome" — LARGE observation window across the top
                WindowConfig(position: CGPoint(x: 690, y: 355), size: CGSize(width: 240, height: 20)),
                // Right side viewport
                WindowConfig(position: CGPoint(x: 832, y: 200), size: CGSize(width: 16, height: 90)),
            ]
        ),
        StationModule(
            type: .arboretum,
            bounds: CGRect(x: 860, y: 20, width: 320, height: 350),
            capacity: 4,
            windows: [
                // Large floor-level window (looking down at space below)
                WindowConfig(position: CGPoint(x: 1020, y: 28), size: CGSize(width: 180, height: 16)),
                // Right wall viewport
                WindowConfig(position: CGPoint(x: 1172, y: 200), size: CGSize(width: 16, height: 80)),
            ]
        ),
    ]

    // MARK: - Airlock Doors

    /// Key airlock doors between modules and the corridor.
    static let doors: [DoorConfig] = [
        // Upper deck → corridor connections
        DoorConfig(id: "eng_corridor", position: CGPoint(x: 130, y: 430), isHorizontalSlide: true),
        DoorConfig(id: "bridge_corridor", position: CGPoint(x: 510, y: 430), isHorizontalSlide: true),
        DoorConfig(id: "eva_corridor", position: CGPoint(x: 980, y: 430), isHorizontalSlide: true),

        // Corridor → lower deck connections
        DoorConfig(id: "corridor_crew", position: CGPoint(x: 130, y: 370), isHorizontalSlide: true),
        DoorConfig(id: "corridor_galley", position: CGPoint(x: 390, y: 370), isHorizontalSlide: true),
        DoorConfig(id: "corridor_bio", position: CGPoint(x: 690, y: 370), isHorizontalSlide: true),
        DoorConfig(id: "corridor_arb", position: CGPoint(x: 1020, y: 370), isHorizontalSlide: true),

        // Horizontal doors between adjacent modules (same deck)
        DoorConfig(id: "eng_bridge", position: CGPoint(x: 250, y: 595), isHorizontalSlide: false),
        DoorConfig(id: "bridge_eva", position: CGPoint(x: 770, y: 500), isHorizontalSlide: false),
        DoorConfig(id: "crew_galley", position: CGPoint(x: 250, y: 195), isHorizontalSlide: false),
        DoorConfig(id: "galley_bio", position: CGPoint(x: 530, y: 195), isHorizontalSlide: false),
        DoorConfig(id: "bio_arb", position: CGPoint(x: 850, y: 195), isHorizontalSlide: false),

        // Training Bay ↔ EVA Bay internal
        DoorConfig(id: "training_eva", position: CGPoint(x: 980, y: 580), isHorizontalSlide: true),
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

    /// Check if a point is in the corridor.
    static func isInCorridor(_ point: CGPoint) -> Bool {
        corridorBounds.contains(point)
    }
}
