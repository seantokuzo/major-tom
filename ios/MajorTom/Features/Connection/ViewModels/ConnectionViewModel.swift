import Foundation

@Observable
@MainActor
final class ConnectionViewModel {
    var serverAddress = "localhost:9090"
    var isConnecting = false
    var errorMessage: String?

    private let relay: RelayService

    init(relay: RelayService) {
        self.relay = relay
    }

    var connectionState: ConnectionState {
        relay.connectionState
    }

    var isConnected: Bool {
        relay.connectionState == .connected
    }

    func connect() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            try await relay.connect(to: serverAddress)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        relay.disconnect()
    }
}
