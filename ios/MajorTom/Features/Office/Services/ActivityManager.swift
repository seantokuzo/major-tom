import Foundation

// MARK: - Activity Assignment

/// Tracks an agent's current station assignment and timing.
struct StationAssignment {
    let agentId: String
    let stationType: ActivityStationType
    let startedAt: Date
    let duration: TimeInterval

    var isExpired: Bool {
        Date().timeIntervalSince(startedAt) >= duration
    }

    var timeRemaining: TimeInterval {
        max(0, duration - Date().timeIntervalSince(startedAt))
    }
}

// MARK: - Activity Manager

/// Manages idle activity assignments for agents.
/// When an agent goes idle, assigns them to a random available station.
/// Handles station capacity, activity timing, and rotation.
@Observable
@MainActor
final class ActivityManager {

    /// All activity stations in the office.
    var stations: [ActivityStation] = ActivityStationLayout.stations

    /// Current activity assignments by agent ID.
    private(set) var assignments: [String: StationAssignment] = [:]

    /// Timer for cycling activities.
    private var cycleTask: Task<Void, Never>?

    // MARK: - Station Assignment

    /// Assign an idle agent to a random available station.
    /// Returns the station if one is available, nil if all are at capacity.
    func assignStation(for agentId: String) -> ActivityStation? {
        // Release any existing assignment first
        releaseStation(for: agentId)

        // Find available stations
        let availableStations = stations.filter { $0.isAvailable }
        guard let station = availableStations.randomElement() else { return nil }

        // Assign agent to station
        guard let stationIndex = stations.firstIndex(where: { $0.id == station.id }) else { return nil }
        stations[stationIndex].occupantIds.insert(agentId)

        // Create assignment with random duration (5-15 seconds)
        let duration = TimeInterval.random(in: 5...15)
        let assignment = StationAssignment(
            agentId: agentId,
            stationType: station.type,
            startedAt: Date(),
            duration: duration
        )
        assignments[agentId] = assignment

        return station
    }

    /// Release an agent from their current station.
    func releaseStation(for agentId: String) {
        guard let assignment = assignments[agentId] else { return }

        // Find and update the station
        if let stationIndex = stations.firstIndex(where: { $0.type == assignment.stationType }) {
            stations[stationIndex].occupantIds.remove(agentId)
        }

        assignments.removeValue(forKey: agentId)
    }

    /// Get the current assignment for an agent.
    func currentActivity(for agentId: String) -> StationAssignment? {
        assignments[agentId]
    }

    /// Get the station for a given type.
    func station(for type: ActivityStationType) -> ActivityStation? {
        stations.first { $0.type == type }
    }

    /// Check if an agent's activity has expired and needs rotation.
    func needsRotation(agentId: String) -> Bool {
        guard let assignment = assignments[agentId] else { return false }
        return assignment.isExpired
    }

    /// Get all agents that need activity rotation.
    func agentsNeedingRotation() -> [String] {
        assignments.compactMap { agentId, assignment in
            assignment.isExpired ? agentId : nil
        }
    }

    // MARK: - Cycle Management

    /// Start the activity cycling timer.
    /// Checks every 2 seconds for expired activities and rotates agents.
    func startCycling(onRotate: @escaping (String, ActivityStation?) -> Void) {
        stopCycling()

        cycleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))

                guard let self else { return }

                let agentsToRotate = self.agentsNeedingRotation()
                for agentId in agentsToRotate {
                    let newStation = self.assignStation(for: agentId)
                    onRotate(agentId, newStation)
                }
            }
        }
    }

    /// Stop the activity cycling timer.
    func stopCycling() {
        cycleTask?.cancel()
        cycleTask = nil
    }

    /// Clear all assignments and stop cycling.
    func reset() {
        stopCycling()
        assignments.removeAll()
        stations = ActivityStationLayout.stations
    }

    // MARK: - Display Helpers

    /// Human-readable description of an agent's current activity.
    func activityDescription(for agentId: String) -> String? {
        guard let assignment = assignments[agentId] else { return nil }

        switch assignment.stationType {
        case .pingPong: return "Playing ping pong"
        case .coffeeMachine: return "Getting coffee"
        case .waterCooler: return "At the water cooler"
        case .arcade: return "Playing arcade games"
        case .yoga: return "Doing yoga"
        case .nap: return "Taking a nap"
        case .whiteboard: return "Doodling on whiteboard"
        }
    }
}
