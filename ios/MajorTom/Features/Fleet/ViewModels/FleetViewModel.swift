import Foundation

@Observable
@MainActor
final class FleetViewModel {
    var fleetStatus: FleetStatus?
    var isLoading = false
    var autoRefreshEnabled = true

    private let relay: RelayService
    private let storage: SessionStorageService
    private var refreshTask: Task<Void, Never>?

    init(relay: RelayService, storage: SessionStorageService) {
        self.relay = relay
        self.storage = storage
    }

    // MARK: - Computed

    var healthSummary: String {
        guard let status = fleetStatus else { return "No workers" }
        let healthy = status.workers.filter(\.healthy).count
        let total = status.workers.count
        if total == 0 { return "No workers" }
        if healthy == total { return "All healthy" }
        return "\(healthy)/\(total) healthy"
    }

    var formattedTotalCost: String {
        guard let status = fleetStatus else { return "$0.00" }
        if status.aggregateCost < 0.01 && status.aggregateCost > 0 {
            return "<$0.01"
        }
        return String(format: "$%.2f", status.aggregateCost)
    }

    var isFleetHealthy: Bool {
        guard let status = fleetStatus else { return true }
        return status.workers.allSatisfy(\.healthy)
    }

    var workerCount: Int {
        fleetStatus?.totalWorkers ?? 0
    }

    var sessionCount: Int {
        fleetStatus?.totalSessions ?? 0
    }

    var formattedInputTokens: String {
        abbreviateTokens(fleetStatus?.aggregateTokens.input ?? 0)
    }

    var formattedOutputTokens: String {
        abbreviateTokens(fleetStatus?.aggregateTokens.output ?? 0)
    }

    var fleetHealthColor: FleetHealthLevel {
        guard let status = fleetStatus, !status.workers.isEmpty else { return .green }
        let unhealthy = status.workers.filter { !$0.healthy }.count
        if unhealthy == 0 { return .green }
        if unhealthy < status.workers.count { return .yellow }
        return .red
    }

    // MARK: - Actions

    func requestFleetStatus() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let counterBefore = relay.responseCounter
            try await relay.requestFleetStatus()
            // Poll until the relay response arrives
            for _ in 0..<40 {
                if Task.isCancelled { break }
                if relay.responseCounter != counterBefore { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            // Sync from relay
            if let status = relay.fleetStatus {
                self.fleetStatus = status
            }
        } catch {
            // Silently fail — includes CancellationError
        }
    }

    func handleFleetResponse(_ event: FleetStatusResponseEvent) {
        self.fleetStatus = FleetStatus(from: event)
    }

    func handleWorkerSpawned(workerId: String, workingDir: String) {
        var status = fleetStatus ?? FleetStatus(
            totalWorkers: 0, totalSessions: 0, aggregateCost: 0,
            aggregateTokens: TokenCount(input: 0, output: 0), workers: []
        )
        // Add a new worker placeholder
        let dirName = (workingDir as NSString).lastPathComponent
        let worker = FleetWorker(
            workerId: workerId,
            workingDir: workingDir,
            dirName: dirName,
            sessionCount: 0,
            uptimeMs: 0,
            restartCount: 0,
            healthy: true,
            sessions: []
        )
        status.workers.append(worker)
        status.totalWorkers = status.workers.count
        self.fleetStatus = status
    }

    func handleWorkerCrashed(workerId: String) {
        guard var status = fleetStatus else { return }
        if let index = status.workers.firstIndex(where: { $0.workerId == workerId }) {
            status.workers[index].healthy = false
        }
        self.fleetStatus = status
    }

    func handleWorkerRestarted(newWorkerId: String, workingDir: String) {
        guard var status = fleetStatus else { return }
        // Match by workingDir since the restarted worker has a new workerId
        if let index = status.workers.firstIndex(where: { $0.workingDir == workingDir }) {
            status.workers[index] = FleetWorker(
                workerId: newWorkerId,
                workingDir: workingDir,
                dirName: status.workers[index].dirName,
                sessionCount: 0,
                uptimeMs: 0,
                restartCount: status.workers[index].restartCount + 1,
                healthy: true,
                sessions: []
            )
        }
        self.fleetStatus = status
    }

    func switchToSession(sessionId: String) async {
        guard sessionId != relay.currentSession?.id else { return }

        HapticService.modeSwitch()

        // Save current messages before switching
        if let currentSession = relay.currentSession {
            storage.saveMessages(relay.chatMessages, for: currentSession.id)
            storage.saveFromSessionInfo(currentSession, messageCount: relay.chatMessages.count)
        }

        do {
            try await relay.attachSession(id: sessionId)
            relay.chatMessages.removeAll()

            // Poll until session.info arrives for the target session
            let counterBefore = relay.responseCounter
            for _ in 0..<40 {
                if Task.isCancelled { break }
                if relay.responseCounter != counterBefore,
                   relay.currentSession?.id == sessionId {
                    break
                }
                try await Task.sleep(for: .milliseconds(50))
            }

            // Restore locally saved messages
            let restored = storage.loadMessages(for: sessionId)
            if !restored.isEmpty {
                relay.chatMessages = restored
            }
        } catch {
            // Silently fail
        }
    }

    // MARK: - Auto Refresh

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled && autoRefreshEnabled {
                await requestFleetStatus()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Helpers

    private func abbreviateTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

enum FleetHealthLevel {
    case green
    case yellow
    case red
}
