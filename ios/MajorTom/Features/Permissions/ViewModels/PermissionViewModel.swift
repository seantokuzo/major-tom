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

        // Tell the relay to deny this request — otherwise the relay's server-side
        // delay timer will still auto-approve after delaySeconds
        Task {
            try? await relay.sendApproval(requestId: requestId, decision: .deny)
        }
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
    /// God mode: client auto-approves all pending (relay validates server-side).
    /// Smart mode: relay handles via PermissionFilter allowlist — client doesn't intervene.
    /// Delay mode: start visual countdowns (relay's server-side timer handles actual approval).
    private func flushPendingApprovals(for mode: PermissionMode) async {
        let pending = relay.pendingApprovals
        guard !pending.isEmpty else { return }

        switch mode {
        case .god:
            // Auto-approve all pending — god mode is explicit blanket approval
            for request in pending {
                try? await relay.sendApproval(requestId: request.id, decision: .allow)
            }
        case .smart:
            // Smart mode is relay-driven via PermissionFilter/settings.json allowlist.
            // Don't blanket auto-approve — the relay will resolve each request based on
            // whether the tool matches the configured allowlist.
            break
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

        // Countdown finished — clean up local state.
        // The relay's server-side delay timer handles the actual auto-approval,
        // so we don't send an approval here. This avoids drift between client/server
        // timers and inconsistency when multiple clients are connected.
        guard activeCountdowns[requestId] != nil else { return }
        activeCountdowns.removeValue(forKey: requestId)
        countdownTasks.removeValue(forKey: requestId)
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
