@preconcurrency import Dispatch
import Foundation

/// Manages the relay server as a child process using Foundation.Process.
///
/// Spawns `node server.js` with the bundled (or system) Node binary,
/// handles graceful shutdown via SIGTERM, and tracks process state.
@Observable
final class RelayProcess {
    private(set) var state = RelayState()

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var terminationObserver: NSObjectProtocol?

    /// Grace period before SIGKILL after SIGTERM (seconds).
    private let shutdownTimeout: TimeInterval = 5.0

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

        // Environment
        var env = ProcessInfo.processInfo.environment
        env["NODE_ENV"] = paths.isDevelopment ? "development" : "production"
        env["WS_PORT"] = String(state.port)
        env["HOOK_PORT"] = String(state.hookPort)
        env["LOG_LEVEL"] = "info"
        // Inherit CLAUDE_WORK_DIR from parent env, or use home directory
        if env["CLAUDE_WORK_DIR"] == nil {
            env["CLAUDE_WORK_DIR"] = FileManager.default.homeDirectoryForCurrentUser.path
        }
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
            let workItem = DispatchWorkItem {
                proc.waitUntilExit()
                continuation.resume(returning: true)
            }

            DispatchQueue.global().async(execute: workItem)

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if !workItem.isCancelled {
                    workItem.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - Output Handling

    private func readPipeAsync(_ pipe: Pipe, label: String) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                // Print to console for now — future: feed into LogStore
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    if !line.isEmpty {
                        print("[relay/\(label)] \(line)")
                    }
                }
            }
        }
    }

    // MARK: - Dependency Checks

    private func tmuxAvailable() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["tmux"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

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
