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
        case .pingPong: self.label = "Ping Pong"
        case .coffeeMachine: self.label = "Coffee"
        case .waterCooler: self.label = "Water Cooler"
        case .arcade: self.label = "Arcade"
        case .yoga: self.label = "Yoga"
        case .nap: self.label = "Nap Zone"
        case .whiteboard: self.label = "Whiteboard"
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

// MARK: - Station Layout

/// Pre-defined positions for all activity stations in the office.
enum StationLayout {

    static let stations: [ActivityStation] = [
        // Break room stations
        ActivityStation(type: .pingPong, position: CGPoint(x: 60, y: 350), capacity: 2),
        ActivityStation(type: .arcade, position: CGPoint(x: 150, y: 280), capacity: 1),

        // Kitchen stations
        ActivityStation(type: .coffeeMachine, position: CGPoint(x: 280, y: 220), capacity: 1),
        ActivityStation(type: .waterCooler, position: CGPoint(x: 380, y: 220), capacity: 2),

        // Chill zone stations (in dog corner area)
        ActivityStation(type: .yoga, position: CGPoint(x: 550, y: 220), capacity: 2),
        ActivityStation(type: .nap, position: CGPoint(x: 700, y: 180), capacity: 2),

        // Main floor station
        ActivityStation(type: .whiteboard, position: CGPoint(x: 720, y: 400), capacity: 2),
    ]
}
