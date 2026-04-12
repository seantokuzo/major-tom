import Foundation
import Network

/// Lightweight HTTP control API for Ground Control, bound to loopback only.
///
/// Exposes relay/tunnel lifecycle, logs, and config via REST endpoints so that
/// external tools (e.g. an MCP server bridge) can programmatically manage
/// the app without touching the GUI.
///
/// Security: NWListener is bound to `127.0.0.1` exclusively. Every incoming
/// connection is validated against loopback before processing. Same model as
/// the relay's own admin API.
@Observable
final class ControlServer {
    private(set) var isRunning = false

    private var listener: NWListener?
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.majortom.groundcontrol.control-server")

    /// Maximum allowed size for a single request buffer (1 MB). Connections that
    /// exceed this without delivering a complete HTTP request are terminated with
    /// a 413 response to prevent memory exhaustion from misbehaving clients.
    private static let maxBufferSize = 1_048_576

    /// Timestamp when the control server started (used for uptime calculation).
    private var startTime: Date?

    // MARK: - Dependencies (injected from app)

    /// Per-connection buffer for accumulating TCP frames until a complete HTTP
    /// request has been received (headers + body).
    private var connectionBuffers: [ObjectIdentifier: Data] = [:]

    private weak var relay: RelayProcess?
    private weak var configManager: ConfigManager?

    // MARK: - Init

    init(port: UInt16, relay: RelayProcess, configManager: ConfigManager) {
        self.port = port
        self.relay = relay
        self.configManager = configManager
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            // Bind to loopback only — reject non-local connections at the network level
            params.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: NWEndpoint.Port(rawValue: port)!
            )

            let nwListener = try NWListener(using: params)
            nwListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    Task { @MainActor [weak self] in
                        self?.isRunning = true
                        self?.startTime = Date()
                    }
                    print("[ControlServer] Listening on 127.0.0.1:\(self?.port ?? 0)")
                case .failed(let error):
                    print("[ControlServer] Failed: \(error)")
                    Task { @MainActor [weak self] in
                        self?.isRunning = false
                    }
                case .cancelled:
                    Task { @MainActor [weak self] in
                        self?.isRunning = false
                    }
                default:
                    break
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            nwListener.start(queue: queue)
            self.listener = nwListener
        } catch {
            print("[ControlServer] Failed to create listener: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        startTime = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        let connID = ObjectIdentifier(connection)
        connectionBuffers[connID] = Data()
        connection.start(queue: queue)
        receiveMore(connection: connection, connID: connID)
    }

    /// Byte sequence for HTTP header terminator `\r\n\r\n`.
    private static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A])

    /// Accumulates TCP frames into `connectionBuffers` until a full HTTP
    /// request (headers + optional body based on Content-Length) is available,
    /// then dispatches to `routeRequest`.
    ///
    /// Header terminator detection operates at the byte/Data level so that
    /// a multibyte UTF-8 character split across TCP frames doesn't stall the
    /// connection (String decoding is deferred until the full payload is ready).
    private func receiveMore(connection: NWConnection, connID: ObjectIdentifier) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let data {
                self.connectionBuffers[connID, default: Data()].append(data)
            }

            // Guard against unbounded buffer growth — reject oversized requests
            if let currentSize = self.connectionBuffers[connID]?.count, currentSize > Self.maxBufferSize {
                self.connectionBuffers.removeValue(forKey: connID)
                self.sendResponse(connection: connection, status: 413, body: ["error": "Request too large"])
                return
            }

            guard let buffer = self.connectionBuffers[connID] else {
                if isComplete || error != nil {
                    self.connectionBuffers.removeValue(forKey: connID)
                    connection.cancel()
                }
                return
            }

            // Search for header terminator at the byte level — avoids UTF-8
            // decode failures when multibyte characters are split across frames.
            guard let terminatorRange = buffer.range(of: Self.headerTerminator) else {
                if isComplete || error != nil {
                    self.connectionBuffers.removeValue(forKey: connID)
                    connection.cancel()
                } else {
                    self.receiveMore(connection: connection, connID: connID)
                }
                return
            }

            // If Content-Length is present, wait for the full body too.
            // Parse the header bytes to find the value.
            let headerBytes = buffer[buffer.startIndex..<terminatorRange.lowerBound]
            let bodyStartIndex = terminatorRange.upperBound
            if let headerString = String(data: headerBytes, encoding: .utf8),
               let clLine = headerString.components(separatedBy: "\r\n")
                .first(where: { $0.lowercased().hasPrefix("content-length:") }),
               let clValue = Int(clLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") {
                let bodyLength = buffer.count - bodyStartIndex
                if bodyLength < clValue {
                    if isComplete || error != nil {
                        self.connectionBuffers.removeValue(forKey: connID)
                        connection.cancel()
                    } else {
                        self.receiveMore(connection: connection, connID: connID)
                    }
                    return
                }
            }

            // Full request received — decode to String, clean up buffer and process.
            guard let requestString = String(data: buffer, encoding: .utf8) else {
                self.connectionBuffers.removeValue(forKey: connID)
                self.sendResponse(connection: connection, status: 400, body: ["error": "Invalid UTF-8 in request"])
                return
            }
            self.connectionBuffers.removeValue(forKey: connID)

            // Validate loopback — defense in depth beyond the bind
            if let endpoint = connection.currentPath?.remoteEndpoint,
               case let .hostPort(host, _) = endpoint {
                let hostStr = "\(host)"
                let isLoopback = hostStr == "127.0.0.1" || hostStr == "::1" || hostStr == "::ffff:127.0.0.1"
                if !isLoopback {
                    self.sendResponse(connection: connection, status: 403, body: ["error": "Forbidden — loopback only"])
                    return
                }
            }

            self.routeRequest(requestString, rawData: buffer, connection: connection)
        }
    }

    // MARK: - Routing

    private func routeRequest(_ request: String, rawData: Data, connection: NWConnection) {
        // Parse HTTP method and path from first line
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: ["error": "Empty request"])
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: ["error": "Malformed request line"])
            return
        }

        let method = String(parts[0])
        let fullPath = String(parts[1])
        // Strip query string for routing
        let path = fullPath.components(separatedBy: "?").first ?? fullPath
        let queryString = fullPath.contains("?") ? String(fullPath.split(separator: "?", maxSplits: 1).last ?? "") : ""

        // Extract body from request (after blank line)
        let bodyString: String? = {
            if let range = request.range(of: "\r\n\r\n") {
                let body = String(request[range.upperBound...])
                return body.isEmpty ? nil : body
            }
            return nil
        }()

        switch (method, path) {
        case ("GET", "/control/status"):
            handleGetStatus(connection: connection)
        case ("POST", "/control/relay/start"):
            handleRelayStart(connection: connection)
        case ("POST", "/control/relay/stop"):
            handleRelayStop(connection: connection)
        case ("POST", "/control/relay/restart"):
            handleRelayRestart(connection: connection)
        case ("POST", "/control/tunnel/start"):
            handleTunnelStart(connection: connection)
        case ("POST", "/control/tunnel/stop"):
            handleTunnelStop(connection: connection)
        case ("GET", "/control/logs"):
            handleGetLogs(queryString: queryString, connection: connection)
        case ("GET", "/control/logs/stream"):
            handleLogStream(connection: connection)
        case ("GET", "/control/config"):
            handleGetConfig(connection: connection)
        case ("PATCH", "/control/config"):
            handlePatchConfig(body: bodyString, connection: connection)
        default:
            sendResponse(connection: connection, status: 404, body: ["error": "Not found"])
        }
    }

    // MARK: - Endpoint Handlers

    private func handleGetStatus(connection: NWConnection) {
        guard let relay else {
            sendResponse(connection: connection, status: 503, body: ["error": "Relay not available"])
            return
        }

        Task { [weak self] in
            // Snapshot relay state on @MainActor to avoid data races
            let body: [String: Any] = await MainActor.run {
                let relayStateStr: String
                let relayRunning: Bool
                switch relay.state.processState {
                case .idle: relayStateStr = "idle"; relayRunning = false
                case .starting: relayStateStr = "starting"; relayRunning = false
                case .running: relayStateStr = "running"; relayRunning = true
                case .stopping: relayStateStr = "stopping"; relayRunning = false
                case .error(let msg): relayStateStr = "error: \(msg)"; relayRunning = false
                case .restarting(let attempt): relayStateStr = "restarting (attempt \(attempt))"; relayRunning = false
                }

                let tunnelStateStr: String
                switch relay.tunnel.state {
                case .idle: tunnelStateStr = "idle"
                case .starting: tunnelStateStr = "starting"
                case .running: tunnelStateStr = "running"
                case .stopping: tunnelStateStr = "stopping"
                case .error(let msg): tunnelStateStr = "error: \(msg)"
                case .restarting(let attempt): tunnelStateStr = "restarting (attempt \(attempt))"
                }

                var result: [String: Any] = [
                    "relay": [
                        "state": relayStateStr,
                        "running": relayRunning,
                        "port": relay.state.port,
                        "hookPort": relay.state.hookPort,
                        "restartCount": relay.state.restartCount,
                    ] as [String: Any],
                    "tunnel": [
                        "state": tunnelStateStr,
                        "running": relay.tunnel.isRunning,
                        "restartCount": relay.tunnel.restartCount,
                    ] as [String: Any],
                ]

                if let start = self?.startTime {
                    result["uptime"] = Date().timeIntervalSince(start)
                }

                return result
            }

            guard let self else { return }
            self.sendResponse(connection: connection, status: 200, body: body)
        }
    }

    private func handleRelayStart(connection: NWConnection) {
        guard let relay else {
            sendResponse(connection: connection, status: 503, body: ["error": "Relay not available"])
            return
        }

        Task { @MainActor in
            await relay.start()
            self.sendResponse(connection: connection, status: 200, body: ["ok": true, "state": "starting"])
        }
    }

    private func handleRelayStop(connection: NWConnection) {
        guard let relay else {
            sendResponse(connection: connection, status: 503, body: ["error": "Relay not available"])
            return
        }

        Task { @MainActor in
            await relay.stop()
            self.sendResponse(connection: connection, status: 200, body: ["ok": true, "state": "stopped"])
        }
    }

    private func handleRelayRestart(connection: NWConnection) {
        guard let relay else {
            sendResponse(connection: connection, status: 503, body: ["error": "Relay not available"])
            return
        }

        Task { @MainActor in
            await relay.restart()
            self.sendResponse(connection: connection, status: 200, body: ["ok": true, "state": "restarting"])
        }
    }

    private func handleTunnelStart(connection: NWConnection) {
        guard let relay, let configManager else {
            sendResponse(connection: connection, status: 503, body: ["error": "Relay or config not available"])
            return
        }

        Task { @MainActor [weak self] in
            let config = configManager.config
            guard config.cloudflareEnabled else {
                self?.sendResponse(connection: connection, status: 400, body: ["error": "Cloudflare tunnel not enabled in config"])
                return
            }

            guard let token = configManager.getSecret(ConfigManager.SecretKey.cloudflareToken),
                  !token.isEmpty else {
                self?.sendResponse(connection: connection, status: 400, body: ["error": "Cloudflare tunnel token not configured"])
                return
            }

            await relay.tunnel.start(token: token)
            self?.sendResponse(connection: connection, status: 200, body: ["ok": true, "state": "starting"])
        }
    }

    private func handleTunnelStop(connection: NWConnection) {
        guard let relay else {
            sendResponse(connection: connection, status: 503, body: ["error": "Relay not available"])
            return
        }

        Task { @MainActor in
            await relay.tunnel.stop()
            self.sendResponse(connection: connection, status: 200, body: ["ok": true, "state": "stopped"])
        }
    }

    private func handleGetLogs(queryString: String, connection: NWConnection) {
        guard let relay else {
            sendResponse(connection: connection, status: 503, body: ["error": "Relay not available"])
            return
        }

        // Parse query parameters
        let params = parseQueryString(queryString)
        let count: Int
        if let countString = params["count"] {
            guard let parsedCount = Int(countString), (1...1000).contains(parsedCount) else {
                sendResponse(connection: connection, status: 400, body: ["error": "Invalid count; expected integer in range 1...1000"])
                return
            }
            count = parsedCount
        } else {
            count = 100
        }
        let level = params["level"]
        let since = params["since"].flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }

        Task { [weak self] in
            // Snapshot entries on @MainActor — Deque isn't thread-safe
            let entries = await MainActor.run {
                Array(relay.logStore.entries)
            }
            guard let self else { return }

            var filtered = entries

            // Filter by timestamp if provided
            if let sinceDate = since {
                filtered = filtered.filter { $0.timestamp >= sinceDate }
            }

            // Filter by level if provided
            if let levelStr = level, let pinoLevel = self.pinoLevelFromString(levelStr) {
                filtered = filtered.filter { $0.level.rawValue >= pinoLevel }
            }

            // Take last N entries
            let clamped = min(count, filtered.count)
            let result = Array(filtered.suffix(clamped))

            let logEntries: [[String: Any]] = result.map { entry in
                [
                    "timestamp": entry.timestamp.timeIntervalSince1970,
                    "level": entry.level.displayName.lowercased(),
                    "message": entry.message,
                ]
            }

            self.sendResponse(connection: connection, status: 200, body: [
                "count": logEntries.count,
                "entries": logEntries,
            ])
        }
    }

    private func handleLogStream(connection: NWConnection) {
        guard let relay else {
            sendResponse(connection: connection, status: 503, body: ["error": "Relay not available"])
            return
        }

        // Send SSE headers
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        guard let headerData = headers.data(using: .utf8) else {
            connection.cancel()
            return
        }

        connection.send(content: headerData, completion: .contentProcessed { error in
            if let error {
                print("[ControlServer] SSE header send error: \(error)")
                connection.cancel()
                return
            }
        })

        // Poll for new log entries every 500ms and send as SSE events.
        // Track by last-seen timestamp instead of count — ring buffer eviction
        // causes count to plateau, which would silently stop streaming.
        var lastSeenTimestamp: Date = Date()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        timer.setEventHandler { [weak relay] in
            guard let relay else {
                timer.cancel()
                connection.cancel()
                return
            }

            // Snapshot entries on @MainActor — Deque isn't thread-safe.
            // Use a Task to hop to main, snapshot, then send SSE events.
            Task { @MainActor in
                let entries = Array(relay.logStore.entries)
                let newEntries = entries.filter { $0.timestamp > lastSeenTimestamp }
                guard !newEntries.isEmpty else { return }

                lastSeenTimestamp = newEntries.last!.timestamp

                for entry in newEntries {
                    let eventData: [String: Any] = [
                        "timestamp": entry.timestamp.timeIntervalSince1970,
                        "level": entry.level.displayName.lowercased(),
                        "message": entry.message,
                    ]

                    guard let jsonData = try? JSONSerialization.data(withJSONObject: eventData),
                          let jsonStr = String(data: jsonData, encoding: .utf8) else { continue }

                    let sseEvent = "data: \(jsonStr)\n\n"
                    guard let eventBytes = sseEvent.data(using: .utf8) else { continue }

                    connection.send(content: eventBytes, completion: .contentProcessed { error in
                        if error != nil {
                            timer.cancel()
                            connection.cancel()
                        }
                    })
                }
            }
        }

        timer.resume()

        // Clean up timer when connection dies
        connection.stateUpdateHandler = { state in
            switch state {
            case .cancelled, .failed:
                timer.cancel()
            default:
                break
            }
        }
    }

    private func handleGetConfig(connection: NWConnection) {
        guard let configManager else {
            sendResponse(connection: connection, status: 503, body: ["error": "Config not available"])
            return
        }

        Task { [weak self] in
            guard let self else { return }
            // Snapshot config on @MainActor to avoid racing with SwiftUI edits
            let body: [String: Any] = await MainActor.run {
                let config = configManager.config
                return [
                    "port": config.port,
                    "hookPort": config.hookPort,
                    "authMode": config.authMode.rawValue,
                    "multiUserEnabled": config.multiUserEnabled,
                    "claudeWorkDir": config.claudeWorkDir,
                    "logLevel": config.logLevel.rawValue,
                    "cloudflareEnabled": config.cloudflareEnabled,
                    "cloudflareTunnelName": config.cloudflareTunnelName,
                    "autoStart": config.autoStart,
                    "controlPort": config.controlPort,
                ]
            }

            self.sendResponse(connection: connection, status: 200, body: body)
        }
    }

    private func handlePatchConfig(body: String?, connection: NWConnection) {
        guard let configManager else {
            sendResponse(connection: connection, status: 503, body: ["error": "Config not available"])
            return
        }

        guard let body, let data = body.data(using: .utf8),
              let updates = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid JSON body"])
            return
        }

        Task { [weak self] in
            guard let self else { return }

            // Snapshot initial config on @MainActor — ConfigManager is @Observable
            // and bound to SwiftUI on main actor
            let initialConfig = await MainActor.run { configManager.config }
            var updatedConfig = initialConfig
            let previousControlPort = updatedConfig.controlPort

            if let port = updates["port"] as? Int {
                updatedConfig.port = port
            }
            if let hookPort = updates["hookPort"] as? Int {
                updatedConfig.hookPort = hookPort
            }
            if let controlPort = updates["controlPort"] as? Int {
                updatedConfig.controlPort = controlPort
            }
            if let authModeStr = updates["authMode"] as? String, let authMode = AuthMode(rawValue: authModeStr) {
                updatedConfig.authMode = authMode
            }
            if let multiUser = updates["multiUserEnabled"] as? Bool {
                updatedConfig.multiUserEnabled = multiUser
            }
            if let workDir = updates["claudeWorkDir"] as? String {
                updatedConfig.claudeWorkDir = workDir
            }
            if let logLevelStr = updates["logLevel"] as? String, let logLevel = LogLevel(rawValue: logLevelStr) {
                updatedConfig.logLevel = logLevel
            }
            if let cfEnabled = updates["cloudflareEnabled"] as? Bool {
                updatedConfig.cloudflareEnabled = cfEnabled
            }
            if let tunnelName = updates["cloudflareTunnelName"] as? String {
                updatedConfig.cloudflareTunnelName = tunnelName
            }
            if let autoStart = updates["autoStart"] as? Bool {
                updatedConfig.autoStart = autoStart
            }

            // Validate the copy before mutating the live config
            let validation = updatedConfig.validate()
            guard validation.isValid else {
                var errors: [String: String] = [:]
                if let portErr = validation.portError { errors["port"] = portErr }
                if let hookErr = validation.hookPortError { errors["hookPort"] = hookErr }
                if let controlPortErr = validation.controlPortError { errors["controlPort"] = controlPortErr }
                self.sendResponse(connection: connection, status: 400, body: ["error": "Validation failed", "details": errors])
                return
            }

            // Assign back + save on @MainActor
            do {
                try await MainActor.run {
                    configManager.config = updatedConfig
                    try configManager.save()
                }
                let controlPortChanged = updatedConfig.controlPort != previousControlPort
                var responseBody: [String: Any] = [
                    "ok": true,
                    "message": "Config updated — restart relay to apply changes",
                ]
                if controlPortChanged {
                    responseBody["requiresRestart"] = true
                    responseBody["message"] = "Config updated — restart Ground Control to apply control port change, restart relay for other changes"
                }
                self.sendResponse(connection: connection, status: 200, body: responseBody)
            } catch {
                self.sendResponse(connection: connection, status: 500, body: ["error": "Failed to save config: \(error.localizedDescription)"])
            }
        }
    }

    // MARK: - Response Helpers

    private func sendResponse(connection: NWConnection, status: Int, body: [String: Any]) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        case 503: statusText = "Service Unavailable"
        default: statusText = "Unknown"
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            connection.cancel()
            return
        }

        let response = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\nConnection: close\r\n\r\n\(jsonStr)"

        guard let responseData = response.data(using: .utf8) else {
            connection.cancel()
            return
        }

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Utilities

    private func parseQueryString(_ query: String) -> [String: String] {
        guard !query.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                let val = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                result[key] = val
            }
        }
        return result
    }

    private func pinoLevelFromString(_ str: String) -> Int? {
        switch str.lowercased() {
        case "trace": return 10
        case "debug": return 20
        case "info": return 30
        case "warn": return 40
        case "error": return 50
        case "fatal": return 60
        default: return Int(str)
        }
    }

    deinit {
        stop()
    }
}
