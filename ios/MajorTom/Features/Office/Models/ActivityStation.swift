import Foundation

// MARK: - Activity Station Type

/// The types of idle activity stations available in the office.
enum ActivityStationType: String, CaseIterable {
    case pingPong
    case coffeeMachine
    case waterCooler
    case arcade
    case yoga
    case nap
    case whiteboard
}

// MARK: - Activity Station

/// A physical location in the office where agents can perform idle activities.
/// Each station has a position, capacity, and associated animation.
struct ActivityStation: Identifiable {
    let id: String
    let type: ActivityStationType
    let position: CGPoint
    let capacity: Int
    let label: String

    /// Currently assigned agent IDs (up to capacity).
    var occupantIds: Set<String> = []

    var isAvailable: Bool { occupantIds.count < capacity }

    init(type: ActivityStationType, position: CGPoint, capacity: Int = 2) {
        self.id = type.rawValue
        self.type = type
        self.position = position
        self.capacity = capacity

        switch type {
        case .pingPong: self.label = "Zero-G Court"
        case .coffeeMachine: self.label = "Bev Synth"
        case .waterCooler: self.label = "Hydration"
        case .arcade: self.label = "Holo-Game"
        case .yoga: self.label = "Med Pod"
        case .nap: self.label = "Sleep Pod"
        case .whiteboard: self.label = "Holo-Projector"
        }
    }

    /// The office area this station is located in.
    var areaType: OfficeAreaType {
        switch type {
        case .coffeeMachine, .waterCooler: return .kitchen
        case .pingPong, .arcade: return .breakRoom
        case .yoga, .nap: return .dogCorner
        case .whiteboard: return .mainFloor
        }
    }

    /// The station-specific sprite color for rendering in the scene.
    var spriteColor: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch type {
        case .pingPong: return (0.2, 0.7, 0.3)       // Green
        case .coffeeMachine: return (0.6, 0.4, 0.2)   // Brown
        case .waterCooler: return (0.3, 0.6, 0.9)     // Blue
        case .arcade: return (0.8, 0.3, 0.8)           // Purple
        case .yoga: return (0.9, 0.7, 0.3)             // Gold
        case .nap: return (0.4, 0.4, 0.6)              // Muted blue
        case .whiteboard: return (0.9, 0.9, 0.9)       // White
        }
    }
}

// MARK: - Activity Station Layout

/// Pre-defined positions for all activity stations in the 1200×800 station layout.
enum ActivityStationLayout {

    static let stations: [ActivityStation] = [
        // Training Bay — Zero-G Ball Court (was: Ping Pong in Break Room)
        ActivityStation(type: .pingPong, position: CGPoint(x: 900, y: 660), capacity: 2),

        // Crew Quarters — Holo-Game Terminal (was: Arcade in Break Room)
        ActivityStation(type: .arcade, position: CGPoint(x: 100, y: 150), capacity: 1),

        // Galley — Beverage Synthesizer (was: Coffee Machine in Kitchen)
        ActivityStation(type: .coffeeMachine, position: CGPoint(x: 330, y: 120), capacity: 1),

        // Galley — Hydration Station (was: Water Cooler in Kitchen)
        ActivityStation(type: .waterCooler, position: CGPoint(x: 440, y: 120), capacity: 2),

        // Bio-Dome — Meditation Pod (was: Yoga in Dog Corner)
        ActivityStation(type: .yoga, position: CGPoint(x: 680, y: 120), capacity: 2),

        // Crew Quarters — Sleep Pod (was: Nap in Dog Corner)
        ActivityStation(type: .nap, position: CGPoint(x: 100, y: 260), capacity: 2),

        // Command Bridge — Holo-Projector (was: Whiteboard on Main Floor)
        ActivityStation(type: .whiteboard, position: CGPoint(x: 700, y: 500), capacity: 2),
    ]
}
