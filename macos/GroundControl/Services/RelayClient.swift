import Foundation

/// HTTP client that polls the relay's admin status endpoint and publishes
/// parsed `HealthData` for the Dashboard view.
///
/// Uses `@Observable` (macOS 14+) and Swift Concurrency — no Combine.
/// Auto-refreshes every 10 seconds while polling is active.
@Observable
final class RelayClient {
    /// Latest health data from the relay. Defaults to `.offline`.
    private(set) var healthData = HealthData.offline

    /// Whether the relay is currently reachable.
    private(set) var isConnected = false

    /// Last error message (cleared on successful fetch).
    private(set) var lastError: String?

    /// The relay port to poll (matches RelayState.port).
    var port: Int = 9090

    /// Polling interval in seconds.
    private let pollInterval: TimeInterval = 10.0

    /// Active polling task — cancelled on `stopPolling()`.
    private var pollingTask: Task<Void, Never>?

    private let session: URLSession

    init() {
        // Short timeout so the dashboard doesn't hang when the relay is down
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        self.session = URLSession(configuration: config)
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Polling Lifecycle

    /// Start periodic polling. Safe to call multiple times — restarts if already running.
    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetchStatus()
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }
    }

    /// Stop periodic polling and mark as disconnected.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        markOffline(error: nil)
    }

    // MARK: - Fetch

    /// Single fetch of the admin status endpoint.
    @MainActor
    func fetchStatus() async {
        let url = URL(string: "http://127.0.0.1:\(port)/api/admin/status")!

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                markOffline(error: "HTTP \(code)")
                return
            }

            let decoded = try JSONDecoder().decode(HealthData.self, from: data)
            if healthData != decoded { healthData = decoded }
            if !isConnected { isConnected = true }
            if lastError != nil { lastError = nil }
        } catch is CancellationError {
            // Task cancelled — don't update state
        } catch let error as URLError where error.code == .timedOut || error.code == .cannotConnectToHost {
            markOffline(error: nil) // Expected when relay is stopped
        } catch {
            markOffline(error: error.localizedDescription)
        }
    }

    // MARK: - Private

    private func markOffline(error: String?) {
        if isConnected { isConnected = false }
        if healthData != .offline { healthData = .offline }
        if lastError != error { lastError = error }
    }
}
