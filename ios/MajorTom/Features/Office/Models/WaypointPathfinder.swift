import CoreGraphics

// MARK: - Waypoint Pathfinder

/// Generates waypoint paths through the space station's door network.
/// Replaces direct-line movement with door → corridor → door routing.
enum WaypointPathfinder {

    // MARK: - Module Adjacency Graph

    /// Connections between modules via doors.
    /// Each entry maps a module to its neighbors and the door position between them.
    private static let adjacency: [ModuleType: [(neighbor: ModuleType, doorPosition: CGPoint)]] = {
        var graph: [ModuleType: [(neighbor: ModuleType, doorPosition: CGPoint)]] = [:]
        for module in ModuleType.allCases {
            graph[module] = []
        }

        func addEdge(_ a: ModuleType, _ b: ModuleType, door: CGPoint) {
            graph[a, default: []].append((b, door))
            graph[b, default: []].append((a, door))
        }

        // Direct module-to-module doors (same deck)
        addEdge(.engineering, .commandBridge, door: CGPoint(x: 250, y: 595))
        addEdge(.commandBridge, .evaBay, door: CGPoint(x: 770, y: 500))
        addEdge(.trainingBay, .evaBay, door: CGPoint(x: 980, y: 580))
        addEdge(.crewQuarters, .galley, door: CGPoint(x: 250, y: 195))
        addEdge(.galley, .bioDome, door: CGPoint(x: 530, y: 195))
        addEdge(.bioDome, .arboretum, door: CGPoint(x: 850, y: 195))

        return graph
    }()

    /// Doors from modules to the corridor.
    /// Upper deck modules connect at y=430, lower deck at y=370.
    private static let corridorDoors: [ModuleType: CGPoint] = [
        // Upper deck → corridor
        .engineering:   CGPoint(x: 130, y: 430),
        .commandBridge: CGPoint(x: 510, y: 430),
        .evaBay:        CGPoint(x: 980, y: 430),
        // Lower deck → corridor
        .crewQuarters:  CGPoint(x: 130, y: 370),
        .galley:        CGPoint(x: 390, y: 370),
        .bioDome:       CGPoint(x: 690, y: 370),
        .arboretum:     CGPoint(x: 1020, y: 370),
    ]

    /// The corridor's vertical center for horizontal traversal.
    private static let corridorY: CGFloat = 400

    // MARK: - Public API

    /// Find waypoints from source to target position.
    /// Returns an array of intermediate points (NOT including the source, but INCLUDING the target).
    static func findPath(from source: CGPoint, to target: CGPoint) -> [CGPoint] {
        let sourceModule = StationLayout.module(at: source)?.type
        let targetModule = StationLayout.module(at: target)?.type

        // Same module or no module detected — direct path
        guard let srcMod = sourceModule, let tgtMod = targetModule, srcMod != tgtMod else {
            return [target]
        }

        // Try direct adjacency first (same-deck neighbors)
        if let directDoor = findDirectDoor(from: srcMod, to: tgtMod) {
            return [directDoor, target]
        }

        // Try 1-hop through a shared neighbor (e.g., Engineering → Bridge → EVA)
        if let hopPath = findOneHopPath(from: srcMod, to: tgtMod) {
            return hopPath + [target]
        }

        // Cross-deck or distant: route through corridor
        return buildCorridorPath(from: srcMod, to: tgtMod, target: target)
    }

    // MARK: - Private Helpers

    /// Find the door position for a direct connection between two modules.
    private static func findDirectDoor(from: ModuleType, to: ModuleType) -> CGPoint? {
        adjacency[from]?.first(where: { $0.neighbor == to })?.doorPosition
    }

    /// Find a path through one intermediate module (e.g., Eng → Bridge door, Bridge → EVA door).
    private static func findOneHopPath(from src: ModuleType, to tgt: ModuleType) -> [CGPoint]? {
        guard let srcNeighbors = adjacency[src] else { return nil }
        for (mid, doorA) in srcNeighbors {
            if let doorB = findDirectDoor(from: mid, to: tgt) {
                return [doorA, doorB]
            }
        }
        return nil
    }

    /// Build a path through the corridor for cross-deck travel.
    private static func buildCorridorPath(from src: ModuleType, to tgt: ModuleType, target: CGPoint) -> [CGPoint] {
        var waypoints: [CGPoint] = []

        // Step 1: Walk to the source module's corridor door
        // If no corridor door (e.g., Training Bay), find a neighbor that has one
        let srcCorridorEntry = findCorridorEntry(for: src)
        waypoints.append(contentsOf: srcCorridorEntry.waypoints)

        // Step 2: Traverse corridor horizontally to the target's corridor door
        let tgtCorridorExit = findCorridorExit(for: tgt)

        // Walk along corridor center
        let corridorStart = CGPoint(x: srcCorridorEntry.corridorX, y: corridorY)
        let corridorEnd = CGPoint(x: tgtCorridorExit.corridorX, y: corridorY)

        if abs(corridorStart.x - corridorEnd.x) > 5 {
            waypoints.append(corridorStart)
            waypoints.append(corridorEnd)
        } else {
            waypoints.append(corridorStart)
        }

        // Step 3: Exit corridor into target module
        waypoints.append(contentsOf: tgtCorridorExit.waypoints)
        waypoints.append(target)

        return waypoints
    }

    /// Find how to get from a module into the corridor.
    private static func findCorridorEntry(for module: ModuleType) -> (waypoints: [CGPoint], corridorX: CGFloat) {
        // Module has a direct corridor door
        if let door = corridorDoors[module] {
            return ([door], door.x)
        }

        // Training Bay: go through EVA Bay's corridor door
        if module == .trainingBay {
            let evaDoor = CGPoint(x: 980, y: 580)  // training_eva door
            let evaCorridor = corridorDoors[.evaBay]!
            return ([evaDoor, evaCorridor], evaCorridor.x)
        }

        // Fallback: use nearest corridor door by X position
        let moduleBounds = StationLayout.module(for: module)?.bounds ?? .zero
        let moduleCenter = CGPoint(x: moduleBounds.midX, y: moduleBounds.midY)
        let nearest = corridorDoors.min(by: {
            abs($0.value.x - moduleCenter.x) < abs($1.value.x - moduleCenter.x)
        })!
        return ([nearest.value], nearest.value.x)
    }

    /// Find how to get from the corridor into a target module.
    private static func findCorridorExit(for module: ModuleType) -> (waypoints: [CGPoint], corridorX: CGFloat) {
        if let door = corridorDoors[module] {
            return ([door], door.x)
        }

        // Training Bay: exit through EVA Bay's corridor door, then through training_eva door
        if module == .trainingBay {
            let evaCorridor = corridorDoors[.evaBay]!
            let evaDoor = CGPoint(x: 980, y: 580)
            return ([evaCorridor, evaDoor], evaCorridor.x)
        }

        let moduleBounds = StationLayout.module(for: module)?.bounds ?? .zero
        let moduleCenter = CGPoint(x: moduleBounds.midX, y: moduleBounds.midY)
        let nearest = corridorDoors.min(by: {
            abs($0.value.x - moduleCenter.x) < abs($1.value.x - moduleCenter.x)
        })!
        return ([nearest.value], nearest.value.x)
    }

    // MARK: - Module Detection

    /// Determine the helmet type appropriate for a given module.
    static func helmetType(for module: ModuleType?) -> HelmetType {
        switch module {
        case .engineering, .trainingBay: return .standard
        case .evaBay: return .eva
        default: return .none
        }
    }
}
