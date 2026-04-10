@preconcurrency import Dispatch
import Foundation

/// Manages the relay server as a child process using Foundation.Process.
///
/// Spawns `node server.js` with the bundled (or system) Node binary,
/// handles graceful shutdown via SIGTERM, and tracks process state.
@Observable
final class RelayProcess {
    private(set) var state = RelayState()

    /// Log store fed by stdout/stderr lines from the relay process.
    let logStore = LogStore()

    /// Config manager providing relay settings and Keychain secrets.
    let configManager: ConfigManager

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var terminationObserver: NSObjectProtocol?

    /// Grace period before SIGKILL after SIGTERM (seconds).
    private let shutdownTimeout: TimeInterval = 5.0

    // MARK: - Init

    init(configManager: ConfigManager = ConfigManager()) {
        self.configManager = configManager
        // Sync RelayState ports from config
        self.state.port = configManager.config.port
        self.state.hookPort = configManager.config.hookPort
    }

    // MARK: - Lifecycle

    func start() async {
        guard state.canStart else { return }

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

            if paths.isDevelopment {
                print("[GroundControl] Running in DEVELOPMENT mode")
                print("[GroundControl] Node: \(paths.nodeBinary.path)")
                print("[GroundControl] Relay: \(paths.relayEntry.path)")
            }
        } catch {
            state.processState = .error(error.localizedDescription)
        }
    }

    func stop() async {
        guard state.canStop, let proc = process else { return }

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

    func restart() async {
        await stop()
        // Brief pause to let the port release
        try? await Task.sleep(for: .milliseconds(500))
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
            env["AUTH_GOOGLE_ENABLED"] = "true"
            if let clientId = configManager.getSecret(ConfigManager.SecretKey.googleClientId) {
                env["GOOGLE_CLIENT_ID"] = clientId
            }
            if let clientSecret = configManager.getSecret(ConfigManager.SecretKey.googleClientSecret) {
                env["GOOGLE_CLIENT_SECRET"] = clientSecret
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

        // Watch for unexpected termination
        terminationObserver = NotificationCenter.default.addObserver(
            forName: Process.didTerminateNotification,
            object: proc,
            queue: .main
        ) { [weak self] _ in
            self?.handleTermination()
        }

        try proc.run()

        self.process = proc
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        print("[GroundControl] Relay started (PID: \(proc.processIdentifier)) on port \(state.port)")
    }

    private func handleTermination() {
        guard let proc = process else { return }

        let status = proc.terminationStatus

        // If we're in .stopping state, this is expected — stop() handles the cleanup
        if state.processState == .stopping { return }

        // Unexpected termination
        if status != 0 {
            state.processState = .error("Process exited with code \(status)")
            print("[GroundControl] Relay exited unexpectedly (code: \(status))")
        } else {
            state.processState = .idle
            print("[GroundControl] Relay exited cleanly")
        }

        cleanup()
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
    private var stdoutBuffer = ""
    private var stderrBuffer = ""

    private func readPipeAsync(_ pipe: Pipe, label: String) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // Flush any remaining partial-line buffer before removing the handler
                if let self {
                    let remainder: String
                    if label == "stdout" {
                        remainder = self.stdoutBuffer
                        self.stdoutBuffer = ""
                    } else {
                        remainder = self.stderrBuffer
                        self.stderrBuffer = ""
                    }

                    if !remainder.isEmpty {
                        DispatchQueue.main.async {
                            self.logStore.append(remainder)
                        }
                    }
                }
                handle.readabilityHandler = nil
                return
            }
            guard let self, let text = String(data: data, encoding: .utf8) else { return }

            // Buffer management — data may arrive as partial lines
            let buffer: String
            if label == "stdout" {
                buffer = self.stdoutBuffer + text
            } else {
                buffer = self.stderrBuffer + text
            }

            let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)

            // If the chunk doesn't end with \n, the last element is a partial line — keep it
            let hasTrailingNewline = text.hasSuffix("\n")
            let completeLines: ArraySlice<Substring>
            let remainder: String

            if hasTrailingNewline {
                completeLines = lines[...]
                remainder = ""
            } else {
                completeLines = lines.dropLast()
                remainder = String(lines.last ?? "")
            }

            if label == "stdout" {
                self.stdoutBuffer = remainder
            } else {
                self.stderrBuffer = remainder
            }

            // Feed complete lines into LogStore on the main actor
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
        if let proc = process, proc.isRunning {
            kill(proc.processIdentifier, SIGTERM)
        }
        cleanup()
    }
}
