import CoreGraphics

// MARK: - Waypoint Pathfinder

/// Generates waypoint paths through the space station's door network.
/// All topology is derived from `StationLayout.doors` — no hardcoded coordinates.
enum WaypointPathfinder {

    // MARK: - Derived Topology

    /// Map from door ID prefix to module type.
    private static let prefixToModule: [String: ModuleType] = [
        "eng": .engineering,
        "engineering": .engineering,
        "bridge": .commandBridge,
        "eva": .evaBay,
        "training": .trainingBay,
        "crew": .crewQuarters,
        "galley": .galley,
        "bio": .bioDome,
        "biodome": .bioDome,
        "arb": .arboretum,
        "arboretum": .arboretum,
    ]

    /// Parse a door ID (e.g., "eva_training") into the two endpoints.
    /// Returns nil for sides that don't map to a module (e.g., "corridor").
    private static func parseDoorId(_ id: String) -> (ModuleType?, ModuleType?) {
        let parts = id.split(separator: "_").map(String.init)
        guard parts.count == 2 else { return (nil, nil) }
        return (prefixToModule[parts[0]], prefixToModule[parts[1]])
    }

    /// Direct module-to-module adjacency (excludes corridor connections).
    private static let adjacency: [ModuleType: [(neighbor: ModuleType, doorPosition: CGPoint)]] = {
        var graph: [ModuleType: [(neighbor: ModuleType, doorPosition: CGPoint)]] = [:]
        for module in ModuleType.allCases {
            graph[module] = []
        }

        for door in StationLayout.doors {
            let (a, b) = parseDoorId(door.id)
            // Both sides must be modules (not corridor)
            guard let modA = a, let modB = b else { continue }
            graph[modA, default: []].append((modB, door.position))
            graph[modB, default: []].append((modA, door.position))
        }

        return graph
    }()

    /// Doors connecting modules to the corridor (one side is "corridor").
    private static let corridorDoors: [ModuleType: CGPoint] = {
        var map: [ModuleType: CGPoint] = [:]
        for door in StationLayout.doors {
            let (a, b) = parseDoorId(door.id)
            // One side is a module, the other is nil (corridor)
            if let module = a, b == nil {
                map[module] = door.position
            } else if let module = b, a == nil {
                map[module] = door.position
            }
        }
        return map
    }()

    /// Corridor vertical center, derived from StationLayout.
    private static let corridorY: CGFloat = StationLayout.corridorBounds.midY

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

    /// Determine the helmet type appropriate for a given module.
    static func helmetType(for module: ModuleType?) -> HelmetType {
        switch module {
        case .engineering, .trainingBay: return .standard
        case .evaBay: return .eva
        default: return .none
        }
    }

    // MARK: - Private Helpers

    private static func findDirectDoor(from: ModuleType, to: ModuleType) -> CGPoint? {
        adjacency[from]?.first(where: { $0.neighbor == to })?.doorPosition
    }

    private static func findOneHopPath(from src: ModuleType, to tgt: ModuleType) -> [CGPoint]? {
        guard let srcNeighbors = adjacency[src] else { return nil }
        for (mid, doorA) in srcNeighbors {
            if let doorB = findDirectDoor(from: mid, to: tgt) {
                return [doorA, doorB]
            }
        }
        return nil
    }

    private static func buildCorridorPath(from src: ModuleType, to tgt: ModuleType, target: CGPoint) -> [CGPoint] {
        var waypoints: [CGPoint] = []

        let srcEntry = findCorridorEntry(for: src)
        waypoints.append(contentsOf: srcEntry.waypoints)

        let tgtExit = findCorridorExit(for: tgt)

        let corridorStart = CGPoint(x: srcEntry.corridorX, y: corridorY)
        let corridorEnd = CGPoint(x: tgtExit.corridorX, y: corridorY)

        if abs(corridorStart.x - corridorEnd.x) > 5 {
            waypoints.append(corridorStart)
            waypoints.append(corridorEnd)
        } else {
            waypoints.append(corridorStart)
        }

        waypoints.append(contentsOf: tgtExit.waypoints)
        waypoints.append(target)

        return waypoints
    }

    private static func findCorridorEntry(for module: ModuleType) -> (waypoints: [CGPoint], corridorX: CGFloat) {
        if let door = corridorDoors[module] {
            return ([door], door.x)
        }

        // No direct corridor door — route through a neighbor that has one
        if let neighbors = adjacency[module] {
            for (neighbor, doorPos) in neighbors {
                if let corridorDoor = corridorDoors[neighbor] {
                    return ([doorPos, corridorDoor], corridorDoor.x)
                }
            }
        }

        // Fallback: nearest corridor door
        let moduleBounds = StationLayout.module(for: module)?.bounds ?? .zero
        let cx = moduleBounds.midX
        guard let nearest = corridorDoors.min(by: { abs($0.value.x - cx) < abs($1.value.x - cx) }) else {
            return ([CGPoint(x: cx, y: corridorY)], cx)
        }
        return ([nearest.value], nearest.value.x)
    }

    private static func findCorridorExit(for module: ModuleType) -> (waypoints: [CGPoint], corridorX: CGFloat) {
        if let door = corridorDoors[module] {
            return ([door], door.x)
        }

        if let neighbors = adjacency[module] {
            for (neighbor, doorPos) in neighbors {
                if let corridorDoor = corridorDoors[neighbor] {
                    return ([corridorDoor, doorPos], corridorDoor.x)
                }
            }
        }

        let moduleBounds = StationLayout.module(for: module)?.bounds ?? .zero
        let cx = moduleBounds.midX
        guard let nearest = corridorDoors.min(by: { abs($0.value.x - cx) < abs($1.value.x - cx) }) else {
            return ([CGPoint(x: cx, y: corridorY)], cx)
        }
        return ([nearest.value], nearest.value.x)
    }
}
