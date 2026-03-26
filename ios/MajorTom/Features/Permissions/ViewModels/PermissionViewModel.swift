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
        let state = DelayCountdownState(
            requestId: requestId,
            totalSeconds: delaySeconds,
            remainingSeconds: delaySeconds
        )
        activeCountdowns[requestId] = state

        Task {
            await runCountdown(requestId: requestId)
        }
    }

    func cancelCountdown(for requestId: String) {
        activeCountdowns.removeValue(forKey: requestId)
    }

    // MARK: - Private

    private func applyMode(_ mode: PermissionMode, godSubMode: GodSubMode? = nil) async {
        HapticService.modeSwitch()

        do {
            let delay = mode == .delay ? delaySeconds : nil
            try await relay.setPermissionMode(mode, delaySeconds: delay, godSubMode: godSubMode)

            // Flush pending approvals based on new mode
            await flushPendingApprovals(for: mode)
        } catch {
            // Relay service handles error state
        }
    }

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

    private func runCountdown(requestId: String) async {
        for tick in stride(from: delaySeconds, through: 1, by: -1) {
            guard activeCountdowns[requestId] != nil else { return }
            activeCountdowns[requestId]?.remainingSeconds = tick

            try? await Task.sleep(for: .seconds(1))
        }

        // Countdown finished -- auto-approve
        guard activeCountdowns[requestId] != nil else { return }
        activeCountdowns.removeValue(forKey: requestId)

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
