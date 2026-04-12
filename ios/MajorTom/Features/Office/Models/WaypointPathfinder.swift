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

    /// Parse a door ID (e.g., "eva_training") into the two module endpoints.
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


    // MARK: - Public API

    /// Find waypoints from source to target position.
    /// Returns an array of intermediate points (NOT including the source, but INCLUDING the target).
    /// Uses BFS over the door adjacency graph to handle arbitrary path lengths in the 2×4 grid.
    static func findPath(from source: CGPoint, to target: CGPoint) -> [CGPoint] {
        let sourceModule = StationLayout.module(at: source)?.type
        let targetModule = StationLayout.module(at: target)?.type

        // Same module or no module detected — direct path
        guard let srcMod = sourceModule, let tgtMod = targetModule, srcMod != tgtMod else {
            return [target]
        }

        // Try direct adjacency first (single door)
        if let directDoor = findDirectDoor(from: srcMod, to: tgtMod) {
            return [directDoor, target]
        }

        // BFS for multi-hop paths through the door network
        if let bfsPath = findBFSPath(from: srcMod, to: tgtMod) {
            return bfsPath + [target]
        }

        // Fallback: direct line (shouldn't happen with connected graph)
        return [target]
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

    /// BFS over the adjacency graph to find multi-hop path between any two modules.
    /// Returns door waypoints along the path (not including final target position).
    private static func findBFSPath(from src: ModuleType, to tgt: ModuleType) -> [CGPoint]? {
        // BFS with parent tracking
        var visited: Set<ModuleType> = [src]
        var queue: [(module: ModuleType, path: [(door: CGPoint, module: ModuleType)])] = [
            (src, [])
        ]

        while !queue.isEmpty {
            let current = queue.removeFirst()

            guard let neighbors = adjacency[current.module] else { continue }

            for (neighbor, doorPos) in neighbors {
                if neighbor == tgt {
                    // Found target — build waypoint list from doors traversed
                    var waypoints = current.path.map(\.door)
                    waypoints.append(doorPos)
                    return waypoints
                }

                if !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    var newPath = current.path
                    newPath.append((door: doorPos, module: neighbor))
                    queue.append((neighbor, newPath))
                }
            }
        }

        return nil  // No path found (disconnected graph)
    }
}
