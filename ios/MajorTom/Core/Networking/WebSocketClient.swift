import Foundation

// MARK: - Connection State

enum ConnectionState: String {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

// MARK: - WebSocket Client

@Observable
@MainActor
final class WebSocketClient {
    var connectionState: ConnectionState = .disconnected
    private(set) var lastError: String?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var serverURL: URL?
    private var isIntentionalDisconnect = false
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 10
    private var receiveTask: Task<Void, Never>?

    var onMessage: ((Data) -> Void)?

    init() {
        self.session = URLSession(configuration: .default)
    }

    // MARK: - Connection

    func connect(url: URL) async throws {
        serverURL = url
        isIntentionalDisconnect = false
        reconnectAttempt = 0
        connectionState = .connecting
        lastError = nil

        establishConnection(url: url)
    }

    func disconnect() {
        isIntentionalDisconnect = true
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
    }

    // MARK: - Sending

    func send<T: Encodable>(_ message: T) async throws {
        guard let task = webSocketTask else {
            throw WebSocketError.notConnected
        }
        let data = try MessageCodec.encode(message)
        let string = String(data: data, encoding: .utf8) ?? ""
        try await task.send(.string(string))
    }

    // MARK: - Private

    private func establishConnection(url: URL) {
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        connectionState = .connected

        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        schedulePing()
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        onMessage?(data)
                    }
                case .data(let data):
                    onMessage?(data)
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled && !isIntentionalDisconnect {
                    await handleDisconnect()
                }
                return
            }
        }
    }

    private func schedulePing() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.connectionState == .connected else { return }
                self.webSocketTask?.sendPing { error in
                    if error != nil {
                        Task { @MainActor [weak self] in
                            await self?.handleDisconnect()
                        }
                    }
                }
            }
        }
    }

    private func handleDisconnect() async {
        guard !isIntentionalDisconnect else { return }

        webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .reconnecting

        guard reconnectAttempt < maxReconnectAttempts, let url = serverURL else {
            connectionState = .disconnected
            lastError = "Max reconnect attempts reached"
            return
        }

        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), 30.0)
        lastError = "Reconnecting (attempt \(reconnectAttempt))..."

        try? await Task.sleep(for: .seconds(delay))

        guard !isIntentionalDisconnect else { return }
        establishConnection(url: url)
    }
}

// MARK: - Errors

enum WebSocketError: LocalizedError {
    case notConnected
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket is not connected"
        case .invalidURL: return "Invalid server URL"
        }
    }
}
