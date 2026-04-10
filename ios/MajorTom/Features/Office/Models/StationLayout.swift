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
/// All coordinates are in SpriteKit scene points (origin bottom-left).
///
/// Station Layout:
/// ```
/// ┌───────────────────────────────────────────────────┐
/// │ ENGINEERING  │       COMMAND BRIDGE                │
/// │  (reactor)   │  [ws] [ws] [ws]                    │
/// │              │  [ws] [ws] [ws]                    │
/// │              │  [ws] [ws]         [tactical]      │
/// │──────────────┤                                    │
/// │ CREW QUARTERS├────────────────────────────────────│
/// │  bunks/media │  GALLEY       │  BIO-DOME          │
/// │              │  dispensers   │  glass dome/plants  │
/// │──────────────┼──────────────┼─────────────────────│
/// │ TRAINING BAY │  ARBORETUM   │  EVA BAY            │
/// │  equipment   │  trees/grass │  airlock/suits      │
/// └──────────────┴──────────────┴─────────────────────┘
/// ```
enum StationLayout {

    /// Scene dimensions (same as legacy OfficeLayout for backward compat)
    static let sceneWidth: CGFloat = 800
    static let sceneHeight: CGFloat = 600

    /// The station airlock — entry/exit point for agents
    static let airlockPosition = CGPoint(x: 750, y: 500)

    // MARK: - Modules

    static let modules: [StationModule] = [
        StationModule(
            type: .commandBridge,
            bounds: CGRect(x: 200, y: 300, width: 600, height: 300),
            capacity: 8,
            windows: [
                // Large viewport windows along the top wall — the showpiece
                WindowConfig(position: CGPoint(x: 420, y: 585), size: CGSize(width: 100, height: 24)),
                WindowConfig(position: CGPoint(x: 600, y: 585), size: CGSize(width: 80, height: 24)),
                // Side viewport on the right wall
                WindowConfig(position: CGPoint(x: 790, y: 470), size: CGSize(width: 16, height: 64)),
            ]
        ),
        StationModule(
            type: .engineering,
            bounds: CGRect(x: 0, y: 400, width: 200, height: 200),
            capacity: 1,
            windows: [
                // Left wall viewport
                WindowConfig(position: CGPoint(x: 8, y: 500), size: CGSize(width: 16, height: 60)),
            ]
        ),
        StationModule(
            type: .crewQuarters,
            bounds: CGRect(x: 0, y: 200, width: 200, height: 200),
            capacity: 4,
            windows: [
                // Left wall viewport — agents stargaze through this
                WindowConfig(position: CGPoint(x: 8, y: 310), size: CGSize(width: 16, height: 60)),
                WindowConfig(position: CGPoint(x: 8, y: 240), size: CGSize(width: 16, height: 40)),
            ]
        ),
        StationModule(
            type: .galley,
            bounds: CGRect(x: 200, y: 100, width: 250, height: 200),
            capacity: 3,
            windows: [
                // Small galley porthole
                WindowConfig(position: CGPoint(x: 325, y: 290), size: CGSize(width: 50, height: 16)),
            ]
        ),
        StationModule(
            type: .bioDome,
            bounds: CGRect(x: 450, y: 100, width: 350, height: 200),
            capacity: 4,
            windows: [
                // Bio-Dome "glass dome" — LARGE observation window across the top
                WindowConfig(position: CGPoint(x: 625, y: 290), size: CGSize(width: 240, height: 18)),
                // Side viewport
                WindowConfig(position: CGPoint(x: 790, y: 200), size: CGSize(width: 16, height: 70)),
            ]
        ),
        StationModule(
            type: .trainingBay,
            bounds: CGRect(x: 0, y: 0, width: 250, height: 100),
            capacity: 3,
            windows: [
                // Left wall observation window
                WindowConfig(position: CGPoint(x: 8, y: 50), size: CGSize(width: 16, height: 55)),
            ]
        ),
        StationModule(
            type: .arboretum,
            bounds: CGRect(x: 250, y: 0, width: 250, height: 100),
            capacity: 4,
            windows: [
                // Large floor-level window (looking down at space below)
                WindowConfig(position: CGPoint(x: 375, y: 10), size: CGSize(width: 140, height: 16)),
            ]
        ),
        StationModule(
            type: .evaBay,
            bounds: CGRect(x: 500, y: 0, width: 300, height: 100),
            capacity: 2,
            windows: [
                // Large EVA observation window — can see station hull
                WindowConfig(position: CGPoint(x: 660, y: 10), size: CGSize(width: 120, height: 16)),
                // Side viewport
                WindowConfig(position: CGPoint(x: 790, y: 50), size: CGSize(width: 16, height: 55)),
            ]
        ),
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
}
