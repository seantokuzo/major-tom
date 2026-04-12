@preconcurrency import Dispatch
import Foundation

/// Manages the `cloudflared` tunnel as a child process.
///
/// Spawns `cloudflared tunnel --no-autoupdate run --token <token>` alongside
/// the relay and tracks lifecycle. Auto-restarts on unexpected termination
/// using the same exponential-backoff strategy as `RelayProcess`, and pipes
/// stdout/stderr into the shared `LogStore` so tunnel events appear in the
/// Ground Control log viewer.
///
/// Same isolation story as `RelayProcess`: lifecycle methods are `@MainActor`
/// so state mutations are race-free; the pipe reader runs non-isolated since
/// `FileHandle.readabilityHandler` lives on a background dispatch thread.
@Observable
final class TunnelProcess {
    /// Tunnel lifecycle state — mirrors `RelayState.ProcessState` loosely but
    /// keeps its own type so the two processes are independently observable.
    enum TunnelState: Equatable {
        case idle
        case starting
        case running
        case stopping
        case error(String)
        case restarting(attempt: Int)
    }

    /// Errors surfaced by `TunnelProcess`. `localizedDescription` is shown in the UI.
    enum TunnelError: LocalizedError {
        case cloudflaredNotFound
        case emptyToken

        var errorDescription: String? {
            switch self {
            case .cloudflaredNotFound:
                return "cloudflared not found — install with 'brew install cloudflared'"
            case .emptyToken:
                return "Cloudflare tunnel token is empty — paste it in Config"
            }
        }
    }

    private(set) var state: TunnelState = .idle

    /// Total number of auto-restart attempts since the last healthy run.
    private(set) var restartCount: Int = 0
    /// Timestamp of the last auto-restart attempt.
    private(set) var lastRestartAt: Date?

    /// Shared log store — tunnel output is routed here so it shows up alongside relay logs.
    private let logStore: LogStore

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var terminationObserver: NSObjectProtocol?
    private var pendingRestartTask: Task<Void, Never>?

    /// The token we launched with — needed to relaunch on crash without
    /// touching the Keychain on every retry.
    private var activeToken: String?
    private var lastSuccessfulStart: Date?

    /// Memoized result of `findCloudflared`. Populated lazily on first
    /// successful lookup so auto-restart attempts don't re-spawn `which`.
    /// Reset when we detect the binary has moved/disappeared.
    private var cachedCloudflaredURL: URL?

    // MARK: - Tuning

    private let shutdownTimeout: TimeInterval = 5.0
    private let maxRestartAttempts = 5
    private let healthyRunThreshold: TimeInterval = 30.0
    private let maxRestartDelay: TimeInterval = 30.0

    // MARK: - Init

    init(logStore: LogStore) {
        self.logStore = logStore
    }

    // MARK: - Binary discovery

    /// Candidate paths where `cloudflared` is typically installed. Ordered by
    /// most-likely-first for Apple Silicon machines.
    private static let knownBinaryPaths = [
        "/opt/homebrew/bin/cloudflared",   // Apple Silicon Homebrew
        "/usr/local/bin/cloudflared",      // Intel Homebrew
        "/opt/homebrew/sbin/cloudflared",  // Alt Homebrew prefix
        "/usr/bin/cloudflared",            // System (rare)
    ]

    /// Check the well-known install paths without spawning any subprocess.
    /// Cheap enough to call from MainActor — just a few filesystem stats.
    static func findCloudflaredInKnownPaths() -> URL? {
        for path in knownBinaryPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Slow fallback — spawns `/usr/bin/which cloudflared` with an augmented
    /// PATH (GUI-launched apps often have a minimal PATH). This MUST NOT be
    /// called from MainActor; it blocks until the child process exits.
    static func findCloudflaredViaWhich() -> URL? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["cloudflared"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env

        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.availableData
            guard let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty,
                  FileManager.default.isExecutableFile(atPath: output)
            else { return nil }
            return URL(fileURLWithPath: output)
        } catch {
            return nil
        }
    }

    /// Resolve the path to `cloudflared`. Checks known locations inline
    /// (fast), and only falls back to `which` off the main actor to avoid
    /// blocking the UI. Retained for callers (like `CloudflareTunnelView`)
    /// that already hop off main via `Task.detached`.
    static func findCloudflared() -> URL? {
        if let known = findCloudflaredInKnownPaths() { return known }
        return findCloudflaredViaWhich()
    }

    /// Main-actor-friendly resolver: returns the cached URL if still valid,
    /// otherwise checks known paths inline and hops off-main for the `which`
    /// fallback. Updates the cache on success.
    @MainActor
    private func resolveCloudflared() async -> URL? {
        // Re-validate the cache — the binary may have been moved/deleted.
        if let cached = cachedCloudflaredURL,
           FileManager.default.isExecutableFile(atPath: cached.path) {
            return cached
        }
        cachedCloudflaredURL = nil

        // Fast path: inline known-path check.
        if let known = Self.findCloudflaredInKnownPaths() {
            cachedCloudflaredURL = known
            return known
        }

        // Slow path: hop off main so `/usr/bin/which` can run synchronously
        // without stalling the UI.
        let resolved = await Task.detached { Self.findCloudflaredViaWhich() }.value
        cachedCloudflaredURL = resolved
        return resolved
    }

    // MARK: - Lifecycle

    /// Start the tunnel with the given token. Does nothing if already running.
    @MainActor
    func start(token: String) async {
        // Starting manually cancels any pending auto-restart.
        pendingRestartTask?.cancel()
        pendingRestartTask = nil

        // Allow starting from .idle, .error, or from inside an auto-restart
        // wait. `canStart` excludes `.restarting` so that external callers
        // can't blow up a pending auto-restart — but the auto-restart task
        // itself needs to relaunch cloudflared from this state.
        switch state {
        case .idle, .error, .restarting:
            break
        case .starting, .running, .stopping:
            return
        }

        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .error(TunnelError.emptyToken.localizedDescription)
            return
        }

        guard let binary = await resolveCloudflared() else {
            state = .error(TunnelError.cloudflaredNotFound.localizedDescription)
            return
        }

        state = .starting

        do {
            try launchProcess(binary: binary, token: trimmed)
            activeToken = trimmed
            state = .running
            lastSuccessfulStart = Date()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Stop the tunnel. Cancels any pending auto-restart.
    @MainActor
    func stop() async {
        pendingRestartTask?.cancel()
        pendingRestartTask = nil
        restartCount = 0
        lastRestartAt = nil
        activeToken = nil

        guard let proc = process else {
            state = .idle
            return
        }

        state = .stopping

        kill(proc.processIdentifier, SIGTERM)
        let terminated = await waitForTermination(timeout: shutdownTimeout)
        if !terminated {
            kill(proc.processIdentifier, SIGKILL)
        }

        cleanup()
        state = .idle
    }

    // MARK: - Process Management

    private func launchProcess(binary: URL, token: String) throws {
        let proc = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.executableURL = binary
        // Deliberately NOT passing the token via `--token <token>` — argv is
        // world-readable on macOS via `ps` / Activity Monitor, which would
        // leak the Keychain secret. cloudflared supports `TUNNEL_TOKEN` as an
        // env var; the child's environment is per-process and not visible to
        // other users' tools.
        proc.arguments = ["tunnel", "--no-autoupdate", "run"]

        // Minimal environment — pass through HOME and PATH so cloudflared can
        // find its config/credentials directories; inject TUNNEL_TOKEN.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["TUNNEL_TOKEN"] = token
        proc.environment = env

        proc.standardOutput = stdout
        proc.standardError = stderr

        readPipeAsync(stdout, label: "cloudflared-stdout")
        readPipeAsync(stderr, label: "cloudflared-stderr")

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

        appendGroundControlLog(level: .info, message: "Cloudflare tunnel started (PID: \(proc.processIdentifier))")
    }

    @MainActor
    private func handleTermination() {
        guard let proc = process else { return }
        let status = proc.terminationStatus

        // If we're in .stopping state, this is expected.
        if state == .stopping { return }

        // Reset restart counter after a healthy run.
        if let started = lastSuccessfulStart,
           Date().timeIntervalSince(started) > healthyRunThreshold {
            restartCount = 0
        }

        if status == 0 {
            state = .idle
            restartCount = 0
            lastRestartAt = nil
            appendGroundControlLog(level: .info, message: "Cloudflare tunnel exited cleanly")
            cleanup()
            return
        }

        appendGroundControlLog(level: .warn, message: "Cloudflare tunnel exited (code \(status))")
        cleanup()

        if restartCount >= maxRestartAttempts {
            let msg = "Cloudflare tunnel crashed \(maxRestartAttempts) times — check logs"
            state = .error(msg)
            appendGroundControlLog(level: .error, message: msg)
            return
        }

        scheduleAutoRestart(previousExitCode: status)
    }

    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let exponent = max(0, attempt - 1)
        let raw = pow(2.0, Double(exponent))
        return min(raw, maxRestartDelay)
    }

    @MainActor
    private func scheduleAutoRestart(previousExitCode: Int32) {
        guard let token = activeToken else {
            state = .error("Lost tunnel token — cannot auto-restart")
            return
        }

        let nextAttempt = restartCount + 1
        let delay = backoffDelay(forAttempt: nextAttempt)

        restartCount = nextAttempt
        lastRestartAt = Date()
        state = .restarting(attempt: nextAttempt)

        let message = "Cloudflare tunnel crashed (exit \(previousExitCode)) — restarting in \(Int(delay))s (attempt \(nextAttempt)/\(maxRestartAttempts))"
        appendGroundControlLog(level: .warn, message: message)

        pendingRestartTask?.cancel()
        // Run the restart body on the main actor so state mutations inside
        // start(token:)/launchProcess() don't race with SwiftUI observation.
        pendingRestartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard case .restarting = self.state else { return }
            await self.start(token: token)
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

    /// Per-pipe partial-line buffers. cloudflared output can split mid-line
    /// across Data chunks; we hold the tail until the next newline arrives so
    /// no log output is dropped.
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private let pipeBufferLock = NSLock()

    /// Stream pipe data into the log store as plain-text INFO entries.
    /// cloudflared emits human-readable lines, not JSON — LogEntry.parse()
    /// falls back to plain-text INFO which is what we want.
    ///
    /// Buffers partial lines so a chunk that ends mid-line doesn't get flushed
    /// early, and uses `String(decoding:as:)` so partial UTF-8 sequences get
    /// replacement chars instead of being dropped.
    private func readPipeAsync(_ pipe: Pipe, label: String) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }

            // EOF — flush any remainder and detach the handler.
            guard !data.isEmpty else {
                let remainder: Data = {
                    self.pipeBufferLock.lock()
                    defer { self.pipeBufferLock.unlock() }
                    if label == "cloudflared-stdout" {
                        let r = self.stdoutBuffer
                        self.stdoutBuffer = Data()
                        return r
                    } else {
                        let r = self.stderrBuffer
                        self.stderrBuffer = Data()
                        return r
                    }
                }()
                if !remainder.isEmpty {
                    let line = String(decoding: remainder, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty {
                        DispatchQueue.main.async {
                            self.logStore.append("[cloudflared] \(line)")
                        }
                    }
                }
                handle.readabilityHandler = nil
                return
            }

            // Append, split on newlines, retain the trailing remainder.
            let linesToEmit: [String] = {
                self.pipeBufferLock.lock()
                defer { self.pipeBufferLock.unlock() }

                if label == "cloudflared-stdout" {
                    self.stdoutBuffer.append(data)
                } else {
                    self.stderrBuffer.append(data)
                }

                let buffer: Data = label == "cloudflared-stdout"
                    ? self.stdoutBuffer
                    : self.stderrBuffer

                // Non-failing decode — partial UTF-8 sequences get replacement
                // chars instead of returning nil and stalling the pipeline.
                let decoded = String(decoding: buffer, as: UTF8.self)
                let endsWithNewline = buffer.last == UInt8(ascii: "\n")
                let parts = decoded.split(separator: "\n", omittingEmptySubsequences: false)

                if endsWithNewline {
                    if label == "cloudflared-stdout" {
                        self.stdoutBuffer = Data()
                    } else {
                        self.stderrBuffer = Data()
                    }
                    return parts.map(String.init).filter { !$0.isEmpty }
                } else {
                    let remainder = parts.last.map(String.init) ?? ""
                    if label == "cloudflared-stdout" {
                        self.stdoutBuffer = Data(remainder.utf8)
                    } else {
                        self.stderrBuffer = Data(remainder.utf8)
                    }
                    return parts.dropLast().map(String.init).filter { !$0.isEmpty }
                }
            }()

            guard !linesToEmit.isEmpty else { return }
            DispatchQueue.main.async {
                for line in linesToEmit {
                    self.logStore.append("[cloudflared] \(line)")
                }
            }
        }
    }

    private func appendGroundControlLog(level: LogEntry.LogLevel, message: String) {
        let timeMs = Int(Date().timeIntervalSince1970 * 1000)
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let line = "{\"level\":\(level.rawValue),\"time\":\(timeMs),\"name\":\"tunnel\",\"msg\":\"\(escaped)\"}"
        DispatchQueue.main.async { [weak self] in
            self?.logStore.append(line)
        }
    }

    // MARK: - Computed

    var canStart: Bool {
        switch state {
        case .idle, .error:
            return true
        default:
            return false
        }
    }

    var isRunning: Bool {
        state == .running
    }

    /// Human-readable status line for the UI.
    var statusText: String {
        switch state {
        case .idle: return "Tunnel idle"
        case .starting: return "Tunnel starting..."
        case .running: return "Tunnel running"
        case .stopping: return "Tunnel stopping..."
        case .error(let msg): return "Tunnel error: \(msg)"
        case .restarting(let attempt): return "Tunnel restarting (attempt \(attempt)/5)..."
        }
    }

    deinit {
        pendingRestartTask?.cancel()
        if let proc = process, proc.isRunning {
            kill(proc.processIdentifier, SIGTERM)
        }
        cleanup()
    }
}
