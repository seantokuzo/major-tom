import GameplayKit
import SpriteKit

// MARK: - Grid Movement Engine

/// Grid-based pathfinding engine using GameplayKit's GKGridGraph.
/// One grid per room (30×32 cells at 20×20 resolution).
/// Handles intra-room pathfinding with obstacle avoidance and agent collision.
/// Inter-room routing still uses WaypointPathfinder for door-to-door navigation.
final class GridMovementEngine {

    // MARK: - Constants

    /// Cell size in scene points — characters (80×80) occupy 4×4 cells.
    static let cellSize: CGFloat = 20

    /// Grid dimensions per room (600÷20 × 640÷20).
    static let gridWidth: Int32 = 30
    static let gridHeight: Int32 = 32

    // MARK: - State

    /// One grid graph per room module.
    private var roomGrids: [ModuleType: GKGridGraph<GKGridGraphNode>] = [:]

    /// Room bounds for coordinate conversion.
    private var roomBounds: [ModuleType: CGRect] = [:]

    /// Agent cell reservations — maps cell to agent ID. Prevents overlap.
    private var reservedCells: [ModuleType: [CellKey: Reservation]] = [:]

    /// Tracks which furniture cells are blocked per room (for debug/query).
    private(set) var blockedCells: [ModuleType: Set<CellKey>] = [:]

    // MARK: - Types

    /// Hashable cell coordinate key.
    struct CellKey: Hashable {
        let x: Int32
        let y: Int32
    }

    /// A cell reservation by an agent, with expiry for deadlock prevention.
    struct Reservation {
        let agentId: String
        let expiresAt: TimeInterval
    }

    // MARK: - Initialization

    /// Build grid graphs for all station modules with furniture as obstacles.
    func buildAllGrids(furniturePlacements: [ModuleType: [FurniturePlacement]]) {
        for module in StationLayout.modules {
            buildGrid(for: module, furniture: furniturePlacements[module.type] ?? [])
        }
    }

    /// Build a single room's grid graph, blocking cells occupied by furniture.
    func buildGrid(for module: StationModule, furniture: [FurniturePlacement]) {
        let graph = GKGridGraph(
            fromGridStartingAt: vector_int2(0, 0),
            width: Self.gridWidth,
            height: Self.gridHeight,
            diagonalsAllowed: true
        )

        roomBounds[module.type] = module.bounds
        reservedCells[module.type] = [:]

        // Block cells occupied by furniture
        var blocked = Set<CellKey>()
        var blockedNodes: [GKGridGraphNode] = []

        for item in furniture {
            let footprint = furnitureFootprint(item, roomOrigin: module.bounds.origin)
            for cell in footprint {
                blocked.insert(cell)
                if let node = graph.node(atGridPosition: vector_int2(cell.x, cell.y)) {
                    blockedNodes.append(node)
                }
            }
        }

        // Block wall edges (2-cell border on outer walls) to keep agents inside
        blockWallEdges(graph: graph, module: module, blocked: &blocked, blockedNodes: &blockedNodes)

        graph.remove(blockedNodes)

        roomGrids[module.type] = graph
        blockedCells[module.type] = blocked
    }

    // MARK: - Pathfinding

    /// Find a path within a single room, avoiding furniture and reserved cells.
    /// Returns scene-space waypoints with Catmull-Rom smoothing.
    func findPath(from source: CGPoint, to target: CGPoint, in roomType: ModuleType, agentId: String? = nil, allowFallback: Bool = true) -> [CGPoint]? {
        guard let graph = roomGrids[roomType],
              let bounds = roomBounds[roomType] else { return nil }

        let startCell = sceneToGrid(source, roomOrigin: bounds.origin)
        let endCell = sceneToGrid(target, roomOrigin: bounds.origin)

        // Clamp to valid grid range
        let clampedStart = clampCell(startCell)
        let clampedEnd = clampCell(endCell)

        guard let startNode = graph.node(atGridPosition: vector_int2(clampedStart.x, clampedStart.y)),
              let endNode = graph.node(atGridPosition: vector_int2(clampedEnd.x, clampedEnd.y)) else {
            // Start or end is blocked — try adjacent cells (but don't recurse again)
            guard allowFallback else { return nil }
            return findPathToNearestOpen(from: source, to: target, in: roomType, agentId: agentId)
        }

        // Temporarily remove reserved cells (except our own) as obstacles
        let tempBlocked = temporarilyBlockReservations(in: roomType, graph: graph, excludeAgent: agentId)

        let pathNodes = graph.findPath(from: startNode, to: endNode)

        // Restore temporarily blocked nodes
        if !tempBlocked.isEmpty {
            graph.add(tempBlocked)
            reconnectNodes(tempBlocked, in: graph)
        }

        guard !pathNodes.isEmpty else { return nil }

        // Convert grid nodes → scene coordinates
        let waypoints = pathNodes.compactMap { node -> CGPoint? in
            guard let gridNode = node as? GKGridGraphNode else { return nil }
            return gridToScene(CellKey(x: gridNode.gridPosition.x, y: gridNode.gridPosition.y), roomOrigin: bounds.origin)
        }

        // Reserve the destination cell
        if let agentId {
            let destCell = clampedEnd
            reserveCell(destCell, for: agentId, in: roomType)
        }

        // Smooth with Catmull-Rom interpolation for natural movement
        return smoothPath(waypoints)
    }

    /// Full path from any point to any point, crossing rooms via doors.
    /// Combines WaypointPathfinder (inter-room) with GridMovementEngine (intra-room).
    func findFullPath(from source: CGPoint, to target: CGPoint, agentId: String? = nil) -> [CGPoint] {
        let sourceModule = StationLayout.module(at: source)?.type
        let targetModule = StationLayout.module(at: target)?.type

        // Same room — pure grid path
        if let room = sourceModule, room == targetModule {
            if let path = findPath(from: source, to: target, in: room, agentId: agentId) {
                return path
            }
            return [target] // Fallback to direct line
        }

        // Different rooms — get door waypoints from WaypointPathfinder, then grid-path each segment
        let doorWaypoints = WaypointPathfinder.findPath(from: source, to: target)
        guard !doorWaypoints.isEmpty else { return [target] }

        var fullPath: [CGPoint] = []
        var current = source

        for waypoint in doorWaypoints {
            let currentRoom = StationLayout.module(at: current)?.type
            let waypointRoom = StationLayout.module(at: waypoint)?.type

            // Try grid path within the current room to the next waypoint
            if let room = currentRoom, let gridPath = findPath(from: current, to: waypoint, in: room, agentId: agentId) {
                // Skip the first point if it duplicates the last added point
                let startIdx = (!fullPath.isEmpty && gridPath.first.map { distance($0, fullPath.last!) < Self.cellSize } == true) ? 1 : 0
                fullPath.append(contentsOf: gridPath.dropFirst(startIdx))
            } else if let room = waypointRoom, let gridPath = findPath(from: current, to: waypoint, in: room, agentId: agentId) {
                let startIdx = (!fullPath.isEmpty && gridPath.first.map { distance($0, fullPath.last!) < Self.cellSize } == true) ? 1 : 0
                fullPath.append(contentsOf: gridPath.dropFirst(startIdx))
            } else {
                // Corridor or unhandled — direct line
                fullPath.append(waypoint)
            }

            current = waypoint
        }

        return fullPath.isEmpty ? [target] : fullPath
    }

    // MARK: - Cell Reservation

    /// Reserve a cell for an agent (prevents other agents from pathfinding through it).
    func reserveCell(_ cell: CellKey, for agentId: String, in room: ModuleType, duration: TimeInterval = 0.3) {
        let now = ProcessInfo.processInfo.systemUptime
        reservedCells[room, default: [:]][cell] = Reservation(agentId: agentId, expiresAt: now + duration)
    }

    /// Release all reservations for an agent in a specific room.
    func releaseReservations(for agentId: String, in room: ModuleType) {
        reservedCells[room] = reservedCells[room]?.filter { $0.value.agentId != agentId }
    }

    /// Release all reservations for an agent across all rooms.
    func releaseAllReservations(for agentId: String) {
        for room in reservedCells.keys {
            releaseReservations(for: agentId, in: room)
        }
    }

    /// Purge expired reservations across all rooms.
    func purgeExpiredReservations() {
        let now = ProcessInfo.processInfo.systemUptime
        for room in reservedCells.keys {
            reservedCells[room] = reservedCells[room]?.filter { $0.value.expiresAt >= now }
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert scene-space point to grid cell coordinates.
    func sceneToGrid(_ point: CGPoint, roomOrigin: CGPoint) -> CellKey {
        let localX = point.x - roomOrigin.x
        let localY = point.y - roomOrigin.y
        return CellKey(
            x: Int32(max(0, min(localX / Self.cellSize, CGFloat(Self.gridWidth - 1)))),
            y: Int32(max(0, min(localY / Self.cellSize, CGFloat(Self.gridHeight - 1))))
        )
    }

    /// Convert grid cell to scene-space center point.
    func gridToScene(_ cell: CellKey, roomOrigin: CGPoint) -> CGPoint {
        CGPoint(
            x: roomOrigin.x + CGFloat(cell.x) * Self.cellSize + Self.cellSize / 2,
            y: roomOrigin.y + CGFloat(cell.y) * Self.cellSize + Self.cellSize / 2
        )
    }

    // MARK: - Furniture Footprint

    /// Calculate which grid cells a furniture item occupies.
    func furnitureFootprint(_ item: FurniturePlacement, roomOrigin: CGPoint) -> [CellKey] {
        // Furniture position is center-based; convert to bottom-left corner
        let halfW = item.size.width / 2
        let halfH = item.size.height / 2
        let bottomLeft = CGPoint(x: item.position.x - halfW, y: item.position.y - halfH)

        let cellsWide = Int(ceil(item.size.width / Self.cellSize))
        let cellsTall = Int(ceil(item.size.height / Self.cellSize))
        let originCell = sceneToGrid(bottomLeft, roomOrigin: roomOrigin)

        var cells: [CellKey] = []
        for dx in 0..<cellsWide {
            for dy in 0..<cellsTall {
                let cx = originCell.x + Int32(dx)
                let cy = originCell.y + Int32(dy)
                if cx >= 0, cx < Self.gridWidth, cy >= 0, cy < Self.gridHeight {
                    cells.append(CellKey(x: cx, y: cy))
                }
            }
        }
        return cells
    }

    // MARK: - Path Smoothing

    /// Catmull-Rom spline interpolation for natural curved paths.
    /// Inserts intermediate points between waypoints for smooth movement.
    func smoothPath(_ waypoints: [CGPoint]) -> [CGPoint] {
        guard waypoints.count > 2 else { return waypoints }

        var smoothed: [CGPoint] = []
        let segments = 3 // Interpolation points per segment

        // Extend endpoints for Catmull-Rom (needs p0, p1, p2, p3)
        let extended = [waypoints[0]] + waypoints + [waypoints[waypoints.count - 1]]

        for i in 1..<(extended.count - 2) {
            let p0 = extended[i - 1]
            let p1 = extended[i]
            let p2 = extended[i + 1]
            let p3 = extended[i + 2]

            smoothed.append(p1)

            // Only interpolate if the segment is long enough
            let segDist = distance(p1, p2)
            if segDist > Self.cellSize * 1.5 {
                for j in 1..<segments {
                    let t = CGFloat(j) / CGFloat(segments)
                    let point = catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
                    smoothed.append(point)
                }
            }
        }

        // Always include the final destination exactly
        if let last = waypoints.last {
            smoothed.append(last)
        }

        return smoothed
    }

    /// Catmull-Rom interpolation between p1 and p2.
    private func catmullRom(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint, t: CGFloat, alpha: CGFloat = 0.5) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t

        let x = alpha * (
            (2 * p1.x) +
            (-p0.x + p2.x) * t +
            (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
            (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3
        )

        let y = alpha * (
            (2 * p1.y) +
            (-p0.y + p2.y) * t +
            (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
            (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3
        )

        return CGPoint(x: x, y: y)
    }

    // MARK: - Private Helpers

    /// Clamp a cell to valid grid bounds.
    private func clampCell(_ cell: CellKey) -> CellKey {
        CellKey(
            x: max(0, min(cell.x, Self.gridWidth - 1)),
            y: max(0, min(cell.y, Self.gridHeight - 1))
        )
    }

    /// Euclidean distance between two points.
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Block wall edges so agents don't walk along the outer pixel of rooms.
    private func blockWallEdges(graph: GKGridGraph<GKGridGraphNode>, module: StationModule, blocked: inout Set<CellKey>, blockedNodes: inout [GKGridGraphNode]) {
        // Check which sides are outer walls (not adjacent to another room or corridor)
        // For simplicity, block 1-cell border on all sides — doors are handled by WaypointPathfinder
        let w = Self.gridWidth
        let h = Self.gridHeight

        // Bottom and top rows
        for x in Int32(0)..<w {
            for y: Int32 in [0, h - 1] {
                let cell = CellKey(x: x, y: y)
                if !blocked.contains(cell) {
                    blocked.insert(cell)
                    if let node = graph.node(atGridPosition: vector_int2(x, y)) {
                        blockedNodes.append(node)
                    }
                }
            }
        }

        // Left and right columns
        for y in Int32(0)..<h {
            for x: Int32 in [0, w - 1] {
                let cell = CellKey(x: x, y: y)
                if !blocked.contains(cell) {
                    blocked.insert(cell)
                    if let node = graph.node(atGridPosition: vector_int2(x, y)) {
                        blockedNodes.append(node)
                    }
                }
            }
        }
    }

    /// Temporarily remove reserved cells from the graph as obstacles (except the querying agent's own).
    private func temporarilyBlockReservations(in room: ModuleType, graph: GKGridGraph<GKGridGraphNode>, excludeAgent: String?) -> [GKGridGraphNode] {
        let now = ProcessInfo.processInfo.systemUptime
        guard let reservations = reservedCells[room] else { return [] }

        var nodesToRemove: [GKGridGraphNode] = []

        for (cell, reservation) in reservations {
            // Skip expired reservations
            guard reservation.expiresAt > now else { continue }
            // Skip our own reservations
            if let excludeAgent, reservation.agentId == excludeAgent { continue }

            if let node = graph.node(atGridPosition: vector_int2(cell.x, cell.y)) {
                nodesToRemove.append(node)
            }
        }

        if !nodesToRemove.isEmpty {
            graph.remove(nodesToRemove)
        }

        return nodesToRemove
    }

    /// Reconnect nodes that were temporarily removed back into the graph.
    private func reconnectNodes(_ nodes: [GKGridGraphNode], in graph: GKGridGraph<GKGridGraphNode>) {
        // GKGridGraph.add() reconnects nodes to their neighbors automatically
        // No manual edge management needed
    }

    /// Try to find a path when the target cell is blocked — search adjacent cells.
    private func findPathToNearestOpen(from source: CGPoint, to target: CGPoint, in room: ModuleType, agentId: String?) -> [CGPoint]? {
        guard let bounds = roomBounds[room] else { return nil }

        let targetCell = sceneToGrid(target, roomOrigin: bounds.origin)

        // Search in expanding rings around the target for an open cell
        for radius in Int32(1)...Int32(3) {
            for dx in -radius...radius {
                for dy in -radius...radius {
                    guard abs(dx) == radius || abs(dy) == radius else { continue } // Ring only
                    let candidate = CellKey(x: targetCell.x + dx, y: targetCell.y + dy)
                    guard candidate.x >= 0, candidate.x < Self.gridWidth,
                          candidate.y >= 0, candidate.y < Self.gridHeight else { continue }

                    if let graph = roomGrids[room],
                       graph.node(atGridPosition: vector_int2(candidate.x, candidate.y)) != nil {
                        let adjustedTarget = gridToScene(candidate, roomOrigin: bounds.origin)
                        return findPath(from: source, to: adjustedTarget, in: room, agentId: agentId, allowFallback: false)
                    }
                }
            }
        }

        return nil
    }
}

// MARK: - Furniture Placement

/// A placed furniture item with its scene position and size.
/// Used to register obstacles in the grid movement engine.
struct FurniturePlacement {
    let id: String
    let position: CGPoint  // Scene-space center
    let size: CGSize       // Width × Height in scene points
}
