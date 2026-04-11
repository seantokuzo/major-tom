import Foundation

// MARK: - Office Area Type

/// The distinct areas within the Meta/Silicon Valley-style tech campus office.
enum OfficeAreaType: String, CaseIterable {
    case mainFloor       // Open-plan desks where agents work
    case serverRoom      // Orchestrator's private room
    case breakRoom       // Couches, coffee machine, chill vibes
    case kitchen         // Snacks, pizza, espresso bar
    case dogCorner       // Dog beds, water bowls, cozy nook
    case dogPark         // Outdoor-ish play area for the pups
    case gym             // Treadmills, weights — Silicon Valley wellness
    case rollercoaster   // Because why not. Google-campus energy.
}

// MARK: - Desk

/// A single desk on the main floor where an agent can sit and work.
struct Desk: Identifiable {
    let id: Int
    let position: CGPoint

    /// The agent currently assigned to this desk, if any.
    var occupantId: String?

    var isAvailable: Bool { occupantId == nil }
}

// MARK: - Office Area

/// Defines a named area of the office with bounds and optional capacity.
struct OfficeArea: Identifiable {
    let type: OfficeAreaType
    let name: String
    let bounds: CGRect
    let capacity: Int

    var id: String { type.rawValue }
}

// MARK: - Office Layout

/// The complete spatial layout of the office.
/// All coordinates are in SpriteKit scene points (origin bottom-left).
/// Expanded to 1200×800 for the Space Station camera zoom system.
struct OfficeLayout {
    /// Scene dimensions — matches StationLayout
    static let sceneWidth: CGFloat = 1200
    static let sceneHeight: CGFloat = 800

    /// The entry point where agents appear and leave (Command Bridge right side)
    static let doorPosition = CGPoint(x: 760, y: 600)

    // MARK: - Areas

    /// Legacy area bounds — mapped to StationLayout module positions.
    static let areas: [OfficeArea] = [
        OfficeArea(type: .mainFloor, name: "Main Floor",
                   bounds: CGRect(x: 260, y: 430, width: 500, height: 330), capacity: 8),
        OfficeArea(type: .serverRoom, name: "Server Room",
                   bounds: CGRect(x: 20, y: 430, width: 220, height: 330), capacity: 1),
        OfficeArea(type: .breakRoom, name: "Break Room",
                   bounds: CGRect(x: 20, y: 20, width: 220, height: 350), capacity: 4),
        OfficeArea(type: .kitchen, name: "Kitchen",
                   bounds: CGRect(x: 260, y: 20, width: 260, height: 350), capacity: 3),
        OfficeArea(type: .dogCorner, name: "Dog Corner",
                   bounds: CGRect(x: 540, y: 20, width: 300, height: 350), capacity: 4),
        OfficeArea(type: .dogPark, name: "Dog Park",
                   bounds: CGRect(x: 860, y: 20, width: 320, height: 350), capacity: 4),
        OfficeArea(type: .gym, name: "Gym",
                   bounds: CGRect(x: 780, y: 590, width: 400, height: 170), capacity: 3),
        OfficeArea(type: .rollercoaster, name: "Rollercoaster",
                   bounds: CGRect(x: 780, y: 430, width: 400, height: 140), capacity: 2),
    ]

    // MARK: - Desks

    /// 8 desks arranged in the Command Bridge module (x: 260-760, y: 430-760).
    static let desks: [Desk] = [
        // Row 1 (top row, 3 desks)
        Desk(id: 0, position: CGPoint(x: 370, y: 700)),
        Desk(id: 1, position: CGPoint(x: 510, y: 700)),
        Desk(id: 2, position: CGPoint(x: 650, y: 700)),
        // Row 2 (middle row, 3 desks)
        Desk(id: 3, position: CGPoint(x: 370, y: 610)),
        Desk(id: 4, position: CGPoint(x: 510, y: 610)),
        Desk(id: 5, position: CGPoint(x: 650, y: 610)),
        // Row 3 (bottom row, 2 desks)
        Desk(id: 6, position: CGPoint(x: 370, y: 520)),
        Desk(id: 7, position: CGPoint(x: 510, y: 520)),
    ]

    // MARK: - Helpers

    /// Get a random position within an area for idle/break movement.
    static func randomPosition(in areaType: OfficeAreaType) -> CGPoint {
        guard let area = areas.first(where: { $0.type == areaType }) else {
            return doorPosition
        }
        let x = CGFloat.random(in: area.bounds.minX + 30 ... area.bounds.maxX - 30)
        let y = CGFloat.random(in: area.bounds.minY + 20 ... area.bounds.maxY - 20)
        return CGPoint(x: x, y: y)
    }

    /// Get the area at a given point.
    static func area(at point: CGPoint) -> OfficeArea? {
        areas.first { $0.bounds.contains(point) }
    }
}
