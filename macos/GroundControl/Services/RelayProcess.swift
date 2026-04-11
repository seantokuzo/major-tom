@preconcurrency import Dispatch
import Foundation

/// Manages the relay server as a child process using Foundation.Process.
///
/// Spawns `node server.js` with the bundled (or system) Node binary,
/// handles graceful shutdown via SIGTERM, and tracks process state.
///
/// All lifecycle methods (`start`, `stop`, `restart`) and the termination/
/// restart handlers are pinned to `@MainActor` so that mutations to the
/// `@Observable` state don't race with SwiftUI observation. The pipe reader
/// stays non-isolated because `FileHandle.readabilityHandler` fires on a
/// background dispatch thread.
@Observable
final class RelayProcess {
    private(set) var state = RelayState()

    /// Log store fed by stdout/stderr lines from the relay process.
    let logStore = LogStore()

    /// Config manager providing relay settings and Keychain secrets.
    let configManager: ConfigManager

    /// Cloudflare tunnel child process. Shares this RelayProcess's LogStore so
    /// tunnel stdout/stderr shows up in the same log viewer.
    let tunnel: TunnelProcess

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var terminationObserver: NSObjectProtocol?

    /// Grace period before SIGKILL after SIGTERM (seconds).
    private let shutdownTimeout: TimeInterval = 5.0

    // MARK: - Auto-Restart State

    /// When the current process was launched. Used to decide whether a run was
    /// "healthy" (stayed alive past the reset threshold) before crashing.
    private var lastSuccessfulStart: Date?

    /// Pending auto-restart task, if one is scheduled. Cancelled when the user
    /// calls `stop()` or manually starts the relay.
    private var pendingRestartTask: Task<Void, Never>?

    /// Max consecutive auto-restart attempts before giving up with an error.
    private let maxRestartAttempts = 5

    /// A run that stays alive longer than this is considered healthy and resets
    /// the restart counter on the next crash.
    private let healthyRunThreshold: TimeInterval = 30.0

    /// Upper bound on backoff delay (seconds).
    private let maxRestartDelay: TimeInterval = 30.0

    // MARK: - Health Monitoring

    /// Periodic /health probe task. Kills the relay if it becomes unresponsive.
    private var healthMonitorTask: Task<Void, Never>?

    /// How often to hit /health while the relay is running.
    private let healthCheckInterval: TimeInterval = 30.0

    /// Number of consecutive failures allowed before we treat the process as a
    /// zombie and send SIGTERM (which triggers the normal auto-restart path).
    private let healthCheckFailureThreshold = 3

    // MARK: - Init

    init(configManager: ConfigManager = ConfigManager()) {
        self.configManager = configManager
        self.tunnel = TunnelProcess(logStore: logStore)
        // Sync RelayState ports from config
        self.state.port = configManager.config.port
        self.state.hookPort = configManager.config.hookPort
    }

    // MARK: - Lifecycle

    @MainActor
    func start() async {
        // Starting manually cancels any pending auto-restart.
        pendingRestartTask?.cancel()
        pendingRestartTask = nil

        // Allow starting from .idle, .error, or an in-flight .restarting wait.
        guard state.canStart || state.isRestarting else { return }

        state.processState = .starting

        do {
            let paths = try NodeBundleManager.resolve()
            let issues = NodeBundleManager.validate(paths)
            if !issues.isEmpty {
                state.processState = .error(issues.joined(separator: "; "))
                return
            }

            // Check for tmux
            if !tmuxAvailable() {
                state.processState = .error("tmux not found — install with 'brew install tmux'")
                return
            }

            try launchProcess(paths: paths)
            state.processState = .running
            lastSuccessfulStart = Date()

            if paths.isDevelopment {
                print("[GroundControl] Running in DEVELOPMENT mode")
                print("[GroundControl] Node: \(paths.nodeBinary.path)")
                print("[GroundControl] Relay: \(paths.relayEntry.path)")
            }

            // Kick off the tunnel (best-effort, in the background) once the
            // relay is confirmed listening. We don't block `start()` on this
            // since the UI should show "Running" as soon as the process is up.
            Task { [weak self] in
                await self?.startTunnelIfConfigured()
            }

            // Start the zombie-process health monitor.
            startHealthMonitor()
        } catch {
            state.processState = .error(error.localizedDescription)
        }
    }

    /// Wait for the relay's `/health` endpoint to return 200, then start the
    /// Cloudflare tunnel if it is enabled in config and has a token.
    @MainActor
    private func startTunnelIfConfigured() async {
        guard configManager.config.cloudflareEnabled else { return }

        // Wait for the relay to actually be listening before bringing up the
        // tunnel — otherwise cloudflared will open with a broken origin.
        let ready = await waitForRelayReady(timeout: 15.0)
        guard ready else {
            appendGroundControlLog(
                level: .warn,
                message: "Relay port \(state.port) not ready — skipping tunnel start"
            )
            return
        }

        guard let token = configManager.getSecret(ConfigManager.SecretKey.cloudflareToken),
              !token.isEmpty else {
            appendGroundControlLog(
                level: .warn,
                message: "Cloudflare tunnel enabled but no token in Keychain — skipping"
            )
            return
        }

        await tunnel.start(token: token)
    }

    /// Poll `http://127.0.0.1:<port>/health` every 500ms until it returns 200
    /// or the timeout elapses. Used both for tunnel-start gating and (future)
    /// zombie-process health monitoring.
    func waitForRelayReady(timeout: TimeInterval = 15.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        // Guard against a malformed/hand-edited port value in config.json. An
        // invalid port would force-unwrap-crash the app; instead just bail.
        guard let url = URL(string: "http://127.0.0.1:\(state.port)/health") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        while Date() < deadline {
            if Task.isCancelled { return false }
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    return true
                }
            } catch {
                // Not ready yet — keep polling.
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    @MainActor
    func stop() async {
        guard state.canStop else { return }

        // Stop the zombie monitor — we don't want it killing the relay during
        // a graceful shutdown.
        stopHealthMonitor()

        // Stopping cancels any pending auto-restart and resets the counter.
        pendingRestartTask?.cancel()
        pendingRestartTask = nil
        state.restartCount = 0
        state.lastRestartAt = nil

        // Tear down the tunnel first so cloudflared doesn't thrash
        // reconnecting to a dying origin.
        await tunnel.stop()

        // If we were only in .restarting (no live process), just go idle.
        guard let proc = process else {
            state.processState = .idle
            return
        }

        state.processState = .stopping

        // Send SIGTERM for graceful shutdown
        proc.interrupt() // sends SIGINT, but Node handles both
        // Actually send SIGTERM which is what the relay expects
        kill(proc.processIdentifier, SIGTERM)

        // Wait for graceful exit with timeout
        let terminated = await waitForTermination(timeout: shutdownTimeout)

        if !terminated {
            // Force kill after timeout
            print("[GroundControl] Process did not exit in \(shutdownTimeout)s — sending SIGKILL")
            proc.terminate() // SIGTERM again via Foundation
            kill(proc.processIdentifier, SIGKILL)
        }

        cleanup()
        state.processState = .idle
    }

    @MainActor
    func restart() async {
        await stop()
        // Brief pause to let the port release
        try? await Task.sleep(for: .milliseconds(500))
        // Manual restart — clear any carryover auto-restart state.
        state.restartCount = 0
        state.lastRestartAt = nil
        await start()
    }

    // MARK: - Process Management

    private func launchProcess(paths: NodeBundleManager.BundlePaths) throws {
        let proc = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.executableURL = paths.nodeBinary
        proc.arguments = [paths.relayEntry.path]
        proc.currentDirectoryURL = paths.relayDir

        // Environment — derived from ConfigManager
        let config = configManager.config
        var env = ProcessInfo.processInfo.environment
        env["NODE_ENV"] = paths.isDevelopment ? "development" : "production"
        env["WS_PORT"] = String(config.port)
        env["HOOK_PORT"] = String(config.hookPort)
        env["LOG_LEVEL"] = config.logLevel.rawValue
        env["CLAUDE_WORK_DIR"] = config.expandedClaudeWorkDir
        env["MULTI_USER_ENABLED"] = config.multiUserEnabled ? "true" : "false"
        if config.cloudflareEnabled {
            env["CLOUDFLARE_TUNNEL"] = "true"
        } else {
            env.removeValue(forKey: "CLOUDFLARE_TUNNEL")
        }

        // Auth mode → relay env vars
        switch config.authMode {
        case .none:
            env["AUTH_PIN_ENABLED"] = "false"
            env["AUTH_GOOGLE_ENABLED"] = "false"
        case .pin:
            env["AUTH_PIN_ENABLED"] = "true"
            env["AUTH_GOOGLE_ENABLED"] = "false"
        case .google:
            env["AUTH_PIN_ENABLED"] = "false"
            let clientId = configManager.getSecret(ConfigManager.SecretKey.googleClientId)
            let clientSecret = configManager.getSecret(ConfigManager.SecretKey.googleClientSecret)
            if let clientId, !clientId.isEmpty,
               let clientSecret, !clientSecret.isEmpty {
                env["AUTH_GOOGLE_ENABLED"] = "true"
                env["GOOGLE_CLIENT_ID"] = clientId
                env["GOOGLE_CLIENT_SECRET"] = clientSecret
            } else {
                env["AUTH_GOOGLE_ENABLED"] = "false"
                print("[GroundControl] WARNING: Google auth mode selected but client ID or secret is missing — disabling Google auth")
            }
        }

        // Sync RelayState ports so the UI reflects current config
        state.port = config.port
        state.hookPort = config.hookPort

        proc.environment = env

        proc.standardOutput = stdout
        proc.standardError = stderr

        // Pipe output to console (future: LogStore)
        readPipeAsync(stdout, label: "stdout")
        readPipeAsync(stderr, label: "stderr")

        // Watch for unexpected termination. The block runs on the main queue
        // but the observer API hands us a @Sendable closure, so hop through
        // an explicit main-actor Task before touching @MainActor state.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: Process.didTerminateNotification,
            object: proc,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTermination()
            }
        }

        try proc.run()

        self.process = proc
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        print("[GroundControl] Relay started (PID: \(proc.processIdentifier)) on port \(state.port)")
    }

    @MainActor
    private func handleTermination() {
        guard let proc = process else { return }

        let status = proc.terminationStatus

        // Any termination ends the old health monitor — the next start() will
        // spawn a fresh one if we auto-restart.
        stopHealthMonitor()

        // If we're in .stopping state, this is expected — stop() handles the cleanup
        if state.processState == .stopping { return }

        // If the last run was "healthy" (stayed alive past the threshold),
        // reset the restart counter before evaluating the next attempt.
        if let started = lastSuccessfulStart,
           Date().timeIntervalSince(started) > healthyRunThreshold {
            state.restartCount = 0
        }

        // Clean exit — go idle, clear restart state.
        if status == 0 {
            state.processState = .idle
            state.restartCount = 0
            state.lastRestartAt = nil
            print("[GroundControl] Relay exited cleanly")
            cleanup()
            return
        }

        // Unexpected crash — try to auto-restart if we're under the cap.
        print("[GroundControl] Relay exited unexpectedly (code: \(status))")
        cleanup()

        if state.restartCount >= maxRestartAttempts {
            let msg = "Relay crashed \(maxRestartAttempts) times — check logs"
            state.processState = .error(msg)
            appendGroundControlLog(level: .error, message: msg)
            return
        }

        scheduleAutoRestart(previousExitCode: status)
    }

    /// Compute exponential backoff delay for attempt `n` (1-based):
    /// 1s → 2s → 4s → 8s → 16s (capped at `maxRestartDelay`).
    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let raw = pow(2.0, Double(exponent))
        return min(raw, maxRestartDelay)
    }

    /// Schedule an auto-restart task with exponential backoff. Cancellable via
    /// `pendingRestartTask?.cancel()` (called from stop()/start()).
    @MainActor
    private func scheduleAutoRestart(previousExitCode: Int32) {
        let nextAttempt = state.restartCount + 1
        let delay = backoffDelay(forAttempt: nextAttempt)

        state.restartCount = nextAttempt
        state.lastRestartAt = Date()
        state.processState = .restarting(attempt: nextAttempt)

        let message = "Relay crashed (exit \(previousExitCode)) — restarting in \(Int(delay))s (attempt \(nextAttempt)/\(maxRestartAttempts))"
        print("[GroundControl] \(message)")
        appendGroundControlLog(level: .warn, message: message)

        pendingRestartTask?.cancel()
        // Run the restart body on the main actor so state mutations in
        // start()/launchProcess() observe the MainActor isolation expected by
        // an @Observable class. Without @MainActor, mutating state.* from an
        // unstructured Task can race with SwiftUI's observation bookkeeping.
        pendingRestartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            // Only proceed if we're still waiting for this restart. stop()
            // cancels this Task during its sleep; this guard catches any
            // other state transition that raced with us.
            guard self.state.isRestarting else { return }
            await self.start()
        }
    }

    // MARK: - Zombie Health Monitor

    /// Start a periodic task that polls /health. After `healthCheckFailureThreshold`
    /// consecutive failures, sends SIGTERM to the relay — the termination
    /// observer then routes through the normal auto-restart path.
    @MainActor
    private func startHealthMonitor() {
        stopHealthMonitor()
        healthMonitorTask = Task { [weak self] in
            var consecutiveFailures = 0

            while !Task.isCancelled {
                // Sleep first so the initial startup has time to bind the port
                // before we start counting failures.
                try? await Task.sleep(for: .seconds(self?.healthCheckInterval ?? 30.0))
                guard !Task.isCancelled, let self else { return }

                // Only probe when the relay is in the running state — if we're
                // already mid-restart or shutting down, skip.
                let running = await MainActor.run { self.state.processState == .running }
                guard running else { continue }

                let ok = await self.probeHealth()
                if ok {
                    consecutiveFailures = 0
                } else {
                    consecutiveFailures += 1
                    let failureCount = consecutiveFailures
                    let threshold = self.healthCheckFailureThreshold
                    await MainActor.run {
                        self.appendGroundControlLog(
                            level: .warn,
                            message: "Relay health check failed (\(failureCount)/\(threshold))"
                        )
                    }

                    if failureCount >= threshold {
                        await MainActor.run {
                            self.appendGroundControlLog(
                                level: .error,
                                message: "Relay unresponsive — sending SIGTERM to trigger auto-restart"
                            )
                            self.killUnresponsiveRelay()
                        }
                        return // Task exits; next start() will spawn a new one.
                    }
                }
            }
        }
    }

    /// Cancel the periodic health monitor task (called from stop()).
    @MainActor
    private func stopHealthMonitor() {
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
    }

    /// Signal an unresponsive relay. We deliberately do NOT set state to
    /// .stopping — we want handleTermination to treat this as an unexpected
    /// crash and kick off auto-restart.
    @MainActor
    private func killUnresponsiveRelay() {
        guard let proc = process, proc.isRunning else { return }

        // Capture the exact process we just SIGTERM'd. After the 2s delay the
        // auto-restart path may have spawned a new child — we must not escalate
        // SIGKILL against the replacement.
        let signaledProcess = proc
        let signaledPID = proc.processIdentifier
        kill(signaledPID, SIGTERM)

        Task { [weak self, weak signaledProcess] in
            try? await Task.sleep(for: .seconds(2))
            guard let self,
                  let signaledProcess,
                  let currentProcess = self.process,
                  currentProcess === signaledProcess,
                  currentProcess.isRunning
            else { return }
            kill(signaledPID, SIGKILL)
        }
    }

    /// One-shot /health probe. Returns true on HTTP 200.
    private func probeHealth() async -> Bool {
        let port = await MainActor.run { self.state.port }
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    /// Emit a synthesized pino-style log line so internal GroundControl events
    /// (restarts, tunnel lifecycle, etc.) show up in the LogStore with the
    /// right level and color.
    private func appendGroundControlLog(level: LogEntry.LogLevel, message: String) {
        let timeMs = Int(Date().timeIntervalSince1970 * 1000)
        // Escape message for JSON embedding — cover the characters that matter
        // for a one-line status string (no newlines expected in our messages).
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let line = "{\"level\":\(level.rawValue),\"time\":\(timeMs),\"name\":\"ground-control\",\"msg\":\"\(escaped)\"}"
        DispatchQueue.main.async { [weak self] in
            self?.logStore.append(line)
        }
    }

    private func cleanup() {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
            terminationObserver = nil
        }
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private func waitForTermination(timeout: TimeInterval) async -> Bool {
        guard let proc = process else { return true }

        return await withCheckedContinuation { continuation in
            let resumeLock = NSLock()
            var didResume = false

            func resumeOnce(_ result: Bool) {
                resumeLock.lock()
                defer { resumeLock.unlock() }

                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: result)
            }

            let workItem = DispatchWorkItem {
                proc.waitUntilExit()
                resumeOnce(true)
            }

            DispatchQueue.global().async(execute: workItem)

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                workItem.cancel()
                resumeOnce(false)
            }
        }
    }

    // MARK: - Output Handling

    /// Partial-line buffer per pipe (data may arrive mid-line).
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    /// Maximum buffer size before forcing a flush (256 KB).
    private let maxBufferSize = 256 * 1024

    private func readPipeAsync(_ pipe: Pipe, label: String) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // Flush any remaining partial-line buffer before removing the handler
                if let self {
                    let remainderData: Data
                    if label == "stdout" {
                        remainderData = self.stdoutBuffer
                        self.stdoutBuffer = Data()
                    } else {
                        remainderData = self.stderrBuffer
                        self.stderrBuffer = Data()
                    }

                    if !remainderData.isEmpty, let remainder = String(data: remainderData, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.logStore.append(remainder)
                        }
                    }
                }
                handle.readabilityHandler = nil
                return
            }
            guard let self else { return }

            // Append incoming data to the buffer
            if label == "stdout" {
                self.stdoutBuffer.append(data)
            } else {
                self.stderrBuffer.append(data)
            }

            let bufferRef: Data
            if label == "stdout" {
                bufferRef = self.stdoutBuffer
            } else {
                bufferRef = self.stderrBuffer
            }

            // Force flush if buffer exceeds max size
            let forceFlush = bufferRef.count > self.maxBufferSize

            // Use non-failing decoder — partial UTF-8 sequences get replacement chars
            // instead of returning nil and stalling the pipeline.
            let bufferString = String(decoding: bufferRef, as: UTF8.self)

            let newline = UInt8(ascii: "\n")
            let hasTrailingNewline = bufferRef.last == newline

            if !hasTrailingNewline && !forceFlush {
                // Split into lines, keep the partial last line in the buffer
                let lines = bufferString.split(separator: "\n", omittingEmptySubsequences: false)
                if lines.count <= 1 {
                    // No complete line yet, keep buffering
                    return
                }
                let completeLines = lines.dropLast()
                let remainder = String(lines.last ?? "")

                if label == "stdout" {
                    self.stdoutBuffer = Data(remainder.utf8)
                } else {
                    self.stderrBuffer = Data(remainder.utf8)
                }

                let lineStrings = completeLines.compactMap { line -> String? in
                    let s = String(line)
                    return s.isEmpty ? nil : s
                }

                if !lineStrings.isEmpty {
                    DispatchQueue.main.async {
                        for line in lineStrings {
                            self.logStore.append(line)
                        }
                    }
                }
            } else {
                // All data forms complete lines (or force flush)
                if label == "stdout" {
                    self.stdoutBuffer = Data()
                } else {
                    self.stderrBuffer = Data()
                }

                let lines = bufferString.split(separator: "\n", omittingEmptySubsequences: true)
                let lineStrings = lines.map { String($0) }

                if !lineStrings.isEmpty {
                    DispatchQueue.main.async {
                        for line in lineStrings {
                            self.logStore.append(line)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Dependency Checks

    private func tmuxAvailable() -> Bool {
        // Check common Homebrew and system paths first, since GUI-launched
        // macOS apps often have a minimal PATH that excludes /opt/homebrew/bin
        // and /usr/local/bin where Homebrew installs tmux.
        let knownPaths = [
            "/opt/homebrew/bin/tmux",   // Apple Silicon Homebrew
            "/usr/local/bin/tmux",      // Intel Homebrew
            "/usr/bin/tmux",            // System (unlikely but possible)
        ]

        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return true
            }
        }

        // Fall back to which(1) with an expanded PATH for any non-standard installs
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["tmux"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        // Inject Homebrew paths into the probe's PATH so which can find them
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env

        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    deinit {
        // Best-effort cleanup if the object is destroyed while running
        pendingRestartTask?.cancel()
        healthMonitorTask?.cancel()
        if let proc = process, proc.isRunning {
            kill(proc.processIdentifier, SIGTERM)
        }
        cleanup()
    }
}
