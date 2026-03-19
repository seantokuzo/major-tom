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
/// All coordinates are in SpriteKit scene points.
///
/// Visual layout (Meta/Silicon Valley tech campus vibe):
/// ```
/// ┌─────────────────────────────────────────────────┐
/// │  SERVER ROOM  │         MAIN FLOOR              │
/// │  (orchestr.)  │  [desk] [desk] [desk]           │
/// │  [desk]       │  [desk] [desk] [desk]           │
/// │               │  [desk] [desk]                  │
/// │───────────────┤                                 │
/// │  BREAK ROOM   ├─────────────────────────────────│
/// │  couches/tv   │  KITCHEN    │  DOG CORNER       │
/// │               │  snacks     │  beds/bowls       │
/// │───────────────┼─────────────┼───────────────────│
/// │  GYM          │  DOG PARK   │  ROLLERCOASTER    │
/// │  treadmills   │  play area  │  wheeee           │
/// └───────────────┴─────────────┴───────────────────┘
/// ```
struct OfficeLayout {
    /// Scene dimensions
    static let sceneWidth: CGFloat = 800
    static let sceneHeight: CGFloat = 600

    /// The entry point where agents appear and leave
    static let doorPosition = CGPoint(x: 750, y: 500)

    // MARK: - Areas

    static let areas: [OfficeArea] = [
        OfficeArea(
            type: .mainFloor,
            name: "Main Floor",
            bounds: CGRect(x: 200, y: 300, width: 600, height: 300),
            capacity: 8
        ),
        OfficeArea(
            type: .serverRoom,
            name: "Server Room",
            bounds: CGRect(x: 0, y: 400, width: 200, height: 200),
            capacity: 1
        ),
        OfficeArea(
            type: .breakRoom,
            name: "Break Room",
            bounds: CGRect(x: 0, y: 200, width: 200, height: 200),
            capacity: 4
        ),
        OfficeArea(
            type: .kitchen,
            name: "Kitchen",
            bounds: CGRect(x: 200, y: 100, width: 250, height: 200),
            capacity: 3
        ),
        OfficeArea(
            type: .dogCorner,
            name: "Dog Corner",
            bounds: CGRect(x: 450, y: 100, width: 350, height: 200),
            capacity: 4
        ),
        OfficeArea(
            type: .gym,
            name: "Gym",
            bounds: CGRect(x: 0, y: 0, width: 250, height: 100),
            capacity: 3
        ),
        OfficeArea(
            type: .dogPark,
            name: "Dog Park",
            bounds: CGRect(x: 250, y: 0, width: 250, height: 100),
            capacity: 4
        ),
        OfficeArea(
            type: .rollercoaster,
            name: "Rollercoaster",
            bounds: CGRect(x: 500, y: 0, width: 300, height: 100),
            capacity: 2
        ),
    ]

    // MARK: - Desks

    /// 8 desks arranged in a grid on the main floor.
    /// Positions are in SpriteKit coordinates (origin bottom-left).
    static let desks: [Desk] = [
        // Row 1 (top row, 3 desks)
        Desk(id: 0, position: CGPoint(x: 300, y: 520)),
        Desk(id: 1, position: CGPoint(x: 450, y: 520)),
        Desk(id: 2, position: CGPoint(x: 600, y: 520)),
        // Row 2 (middle row, 3 desks)
        Desk(id: 3, position: CGPoint(x: 300, y: 440)),
        Desk(id: 4, position: CGPoint(x: 450, y: 440)),
        Desk(id: 5, position: CGPoint(x: 600, y: 440)),
        // Row 3 (bottom row, 2 desks)
        Desk(id: 6, position: CGPoint(x: 300, y: 360)),
        Desk(id: 7, position: CGPoint(x: 450, y: 360)),
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
