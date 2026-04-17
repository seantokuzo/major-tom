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
/// Updated for the 1240×2620 two-column × four-row grid layout.
struct OfficeLayout {
    /// Scene dimensions — matches StationLayout
    static let sceneWidth: CGFloat = 1240
    static let sceneHeight: CGFloat = 2620

    /// The entry point where agents appear and leave (Command Bridge airlock)
    static let doorPosition = CGPoint(x: 300, y: 2500)

    // MARK: - Areas

    /// Legacy area bounds — mapped to StationLayout module positions (2×4 grid).
    static let areas: [OfficeArea] = [
        // Column 1
        OfficeArea(type: .mainFloor, name: "Main Floor",
                   bounds: CGRect(x: 0, y: 1980, width: 600, height: 640), capacity: 8),
        OfficeArea(type: .serverRoom, name: "Server Room",
                   bounds: CGRect(x: 0, y: 1320, width: 600, height: 640), capacity: 1),
        OfficeArea(type: .breakRoom, name: "Break Room",
                   bounds: CGRect(x: 0, y: 660, width: 600, height: 640), capacity: 4),
        OfficeArea(type: .kitchen, name: "Kitchen",
                   bounds: CGRect(x: 0, y: 0, width: 600, height: 640), capacity: 3),
        // Column 2
        OfficeArea(type: .dogCorner, name: "Dog Corner",
                   bounds: CGRect(x: 640, y: 1980, width: 600, height: 640), capacity: 4),
        OfficeArea(type: .dogPark, name: "Dog Park",
                   bounds: CGRect(x: 640, y: 1320, width: 600, height: 640), capacity: 4),
        OfficeArea(type: .gym, name: "Gym",
                   bounds: CGRect(x: 640, y: 660, width: 600, height: 640), capacity: 3),
        OfficeArea(type: .rollercoaster, name: "Rollercoaster",
                   bounds: CGRect(x: 640, y: 0, width: 600, height: 640), capacity: 2),
    ]

    // MARK: - Desks

    /// 8 desks arranged in the Command Bridge module (col1, row 0: x=0–600, y=1980–2620).
    static let desks: [Desk] = [
        // Row 1 (upper row, 4 desks nicely spaced within 600w room)
        Desk(id: 0, position: CGPoint(x: 100, y: 2450)),
        Desk(id: 1, position: CGPoint(x: 220, y: 2450)),
        Desk(id: 2, position: CGPoint(x: 380, y: 2450)),
        Desk(id: 3, position: CGPoint(x: 500, y: 2450)),
        // Row 2 (lower row, 4 desks)
        Desk(id: 4, position: CGPoint(x: 100, y: 2250)),
        Desk(id: 5, position: CGPoint(x: 220, y: 2250)),
        Desk(id: 6, position: CGPoint(x: 380, y: 2250)),
        Desk(id: 7, position: CGPoint(x: 500, y: 2250)),
    ]

    // MARK: - Overflow Positions (S5)

    /// Overflow standing positions for agent sprites when all desks are taken.
    /// Placed in the empty Command Bridge floor space below the lower desk row
    /// (y=2250). These are programmatic "huddle spots" — sprites stand there
    /// instead of sitting at a desk.
    ///
    /// Command Bridge bounds: x=0–600, y=1980–2620. Desks at y=2250 and y=2450.
    /// Free span below desks: y=1990–2200 (~210pt tall). Furniture (captain's
    /// chair, tactical display, status screens) all sit at the TOP of the
    /// module, so the lower band is clear.
    ///
    /// Grid: 7 columns × 3 rows = 21 slots. Sprite width is ~32pt, so 80pt
    /// column spacing + 70pt row spacing keeps overflow sprites from overlapping.
    static let overflowPositions: [CGPoint] = {
        var points: [CGPoint] = []
        let xs: [CGFloat] = [80, 160, 240, 320, 400, 480, 560]
        let ys: [CGFloat] = [2030, 2100, 2170]
        for y in ys {
            for x in xs {
                points.append(CGPoint(x: x, y: y))
            }
        }
        return points
    }()

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
