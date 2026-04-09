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
    }

    var processState: ProcessState = .idle
    var port: Int = 9090
    var hookPort: Int = 9091
    var clientCount: Int = 0

    // MARK: - Computed Properties

    var isRunning: Bool {
        processState == .running
    }

    var canStart: Bool {
        switch processState {
        case .idle, .error:
            return true
        default:
            return false
        }
    }

    var canStop: Bool {
        processState == .running
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
        }
    }

    var statusColor: String {
        switch processState {
        case .idle, .stopping:
            return "gray"
        case .starting:
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
