import Foundation

@Observable
@MainActor
final class PermissionViewModel {
    var currentMode: PermissionMode { relay.permissionMode }
    var delaySeconds: Int { relay.delaySeconds }
    var godSubMode: GodSubMode { relay.godSubMode }

    var isShowingGodConfirmation = false
    var pendingGodSubMode: GodSubMode = .normal

    // Active delay countdowns keyed by approval request ID
    var activeCountdowns: [String: DelayCountdownState] = [:]

    // Tracks running countdown Tasks so we can cancel duplicates and cancel-all on mode switch
    private var countdownTasks: [String: Task<Void, Never>] = [:]

    private let relay: RelayService

    init(relay: RelayService) {
        self.relay = relay
    }

    var pendingApprovalCount: Int {
        relay.pendingApprovals.count
    }

    // MARK: - Mode Switching

    func setMode(_ mode: PermissionMode) async {
        if mode == .god {
            // Show confirmation before switching to god mode
            pendingGodSubMode = .normal
            isShowingGodConfirmation = true
            return
        }

        await applyMode(mode)
    }

    func confirmGodMode(subMode: GodSubMode) async {
        isShowingGodConfirmation = false
        await applyMode(.god, godSubMode: subMode)
    }

    func cancelGodMode() {
        isShowingGodConfirmation = false
    }

    func setDelaySeconds(_ seconds: Int) async {
        do {
            try await relay.setPermissionMode(.delay, delaySeconds: seconds)
        } catch {
            // Relay service handles error state
        }
    }

    // MARK: - Delay Countdown

    func startCountdown(for requestId: String) {
        // Skip if a countdown for this requestId is already running
        if countdownTasks[requestId] != nil { return }

        let seconds = delaySeconds
        let state = DelayCountdownState(
            requestId: requestId,
            totalSeconds: seconds,
            remainingSeconds: seconds
        )
        activeCountdowns[requestId] = state

        let task = Task {
            await runCountdown(requestId: requestId, seconds: seconds)
        }
        countdownTasks[requestId] = task
    }

    func cancelCountdown(for requestId: String) {
        countdownTasks[requestId]?.cancel()
        countdownTasks.removeValue(forKey: requestId)
        activeCountdowns.removeValue(forKey: requestId)
    }

    // MARK: - Private

    private func cancelAllCountdowns() {
        for (_, task) in countdownTasks {
            task.cancel()
        }
        countdownTasks.removeAll()
        activeCountdowns.removeAll()
    }

    private func applyMode(_ mode: PermissionMode, godSubMode: GodSubMode? = nil) async {
        HapticService.modeSwitch()

        // Cancel all active countdowns when switching modes — they belong to the previous mode
        cancelAllCountdowns()

        do {
            let delay = mode == .delay ? delaySeconds : nil
            try await relay.setPermissionMode(mode, delaySeconds: delay, godSubMode: godSubMode)

            // Flush pending approvals based on new mode
            await flushPendingApprovals(for: mode)
        } catch {
            // Relay service handles error state
        }
    }

    /// Flush pending approvals client-side on mode switch.
    ///
    /// NOTE: This intentionally performs client-side approval for god/smart modes
    /// to provide immediate UX feedback when switching modes. The relay still validates
    /// and enforces the actual permission decision server-side.
    private func flushPendingApprovals(for mode: PermissionMode) async {
        let pending = relay.pendingApprovals
        guard !pending.isEmpty else { return }

        switch mode {
        case .god, .smart:
            // Auto-approve all pending
            for request in pending {
                try? await relay.sendApproval(requestId: request.id, decision: .allow)
            }
        case .delay:
            // Start countdowns for all pending
            for request in pending {
                startCountdown(for: request.id)
            }
        case .manual:
            // Keep all pending for manual review
            break
        }
    }

    private func runCountdown(requestId: String, seconds: Int) async {
        for tick in stride(from: seconds, through: 1, by: -1) {
            guard activeCountdowns[requestId] != nil else { return }
            activeCountdowns[requestId]?.remainingSeconds = tick

            try? await Task.sleep(for: .seconds(1))

            // Check for cancellation after sleep
            guard !Task.isCancelled else { return }
        }

        // Countdown finished -- auto-approve
        guard activeCountdowns[requestId] != nil else { return }
        activeCountdowns.removeValue(forKey: requestId)
        countdownTasks.removeValue(forKey: requestId)

        do {
            try await relay.sendApproval(requestId: requestId, decision: .allow)
        } catch {
            // Failed to auto-approve; it will remain in manual queue
        }
    }
}

// MARK: - Delay Countdown State

struct DelayCountdownState: Identifiable {
    let requestId: String
    let totalSeconds: Int
    var remainingSeconds: Int

    var id: String { requestId }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }
}
