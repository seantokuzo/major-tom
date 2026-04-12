import Foundation

/// Observable state for the relay server process.
@Observable
final class RelayState {
    /// Process lifecycle states.
    enum ProcessState: Equatable {
        case idle
        case starting
        case running
        case stopping
        case error(String)
        /// Relay crashed and is waiting to auto-restart. `attempt` is 1-based.
        case restarting(attempt: Int)
    }

    var processState: ProcessState = .idle
    var port: Int = 9090
    var hookPort: Int = 9091
    var clientCount: Int = 0

    /// Total number of auto-restart attempts since the last successful long-lived run.
    /// Reset to 0 when the process stays up past the "healthy" window.
    var restartCount: Int = 0

    /// Timestamp of the last auto-restart attempt (nil if never restarted this session).
    var lastRestartAt: Date?

    // MARK: - Computed Properties

    var isRunning: Bool {
        processState == .running
    }

    var isRestarting: Bool {
        if case .restarting = processState { return true }
        return false
    }

    var canStart: Bool {
        switch processState {
        case .idle, .error:
            return true
        default:
            // `canStart` excludes `.restarting` so button-driven callers see
            // "already starting" — but `RelayProcess.start()` has an internal
            // `|| isRestarting` escape that lets a manual start cancel the
            // pending auto-restart and launch immediately. Same applies to
            // the transitional states .starting / .running / .stopping.
            return false
        }
    }

    var canStop: Bool {
        switch processState {
        case .running, .restarting:
            // Allow stop during auto-restart wait so the user can cancel the retry.
            return true
        default:
            return false
        }
    }

    var statusText: String {
        switch processState {
        case .idle:
            return "Relay Stopped"
        case .starting:
            return "Relay Starting..."
        case .running:
            return "Relay Running"
        case .stopping:
            return "Relay Stopping..."
        case .error(let message):
            return "Error: \(message)"
        case .restarting(let attempt):
            return "Relay Restarting (attempt \(attempt)/5)..."
        }
    }

    var statusColor: String {
        switch processState {
        case .idle, .stopping:
            return "gray"
        case .starting, .restarting:
            return "yellow"
        case .running:
            return "green"
        case .error:
            return "red"
        }
    }

    var errorMessage: String? {
        if case .error(let message) = processState {
            return message
        }
        return nil
    }
}
