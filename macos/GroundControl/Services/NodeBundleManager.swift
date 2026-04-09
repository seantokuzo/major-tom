import Foundation

/// Locates bundled Node.js binary and relay dist files.
///
/// In production, everything is inside the app bundle. In development,
/// falls back to local paths (system `node`, local `relay/dist/`).
struct NodeBundleManager {
    struct BundlePaths {
        let nodeBinary: URL
        let relayEntry: URL
        let relayDir: URL
        let isDevelopment: Bool
    }

    enum BundleError: LocalizedError {
        case nodeNotFound
        case relayNotFound
        case nodeNotExecutable

        var errorDescription: String? {
            switch self {
            case .nodeNotFound:
                return "Node.js binary not found in app bundle or system PATH"
            case .relayNotFound:
                return "Relay server files not found in app bundle or local relay/dist/"
            case .nodeNotExecutable:
                return "Node.js binary exists but is not executable"
            }
        }
    }

    /// Resolve paths to the Node binary and relay dist.
    ///
    /// Tries the app bundle first, then falls back to development paths.
    static func resolve() throws -> BundlePaths {
        // Try bundled paths first
        if let bundled = tryBundledPaths() {
            return bundled
        }

        // Fall back to development paths
        if let dev = tryDevelopmentPaths() {
            return dev
        }

        // Nothing found — figure out what's missing for a useful error
        if findSystemNode() == nil {
            throw BundleError.nodeNotFound
        }
        throw BundleError.relayNotFound
    }

    // MARK: - Bundled (production)

    private static func tryBundledPaths() -> BundlePaths? {
        guard let nodeURL = Bundle.main.url(forResource: "node", withExtension: nil, subdirectory: "node"),
              let relayURL = Bundle.main.url(forResource: "server", withExtension: "js", subdirectory: "relay-dist")
        else {
            return nil
        }

        guard FileManager.default.isExecutableFile(atPath: nodeURL.path) else {
            return nil
        }

        return BundlePaths(
            nodeBinary: nodeURL,
            relayEntry: relayURL,
            relayDir: relayURL.deletingLastPathComponent(),
            isDevelopment: false
        )
    }

    // MARK: - Development fallback

    private static func tryDevelopmentPaths() -> BundlePaths? {
        guard let node = findSystemNode() else { return nil }

        // Walk up from the executable or current working directory to find
        // the project root containing relay/dist/server.js
        let candidates = projectRootCandidates()

        for root in candidates {
            let relayEntry = root.appendingPathComponent("relay/dist/server.js")
            if FileManager.default.fileExists(atPath: relayEntry.path) {
                return BundlePaths(
                    nodeBinary: node,
                    relayEntry: relayEntry,
                    relayDir: relayEntry.deletingLastPathComponent(),
                    isDevelopment: true
                )
            }
        }

        return nil
    }

    /// Find `node` on the system PATH.
    private static func findSystemNode() -> URL? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["node"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty
            else { return nil }

            let url = URL(fileURLWithPath: path)
            guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
            return url
        } catch {
            return nil
        }
    }

    /// Candidate project root directories for development mode.
    private static func projectRootCandidates() -> [URL] {
        var candidates: [URL] = []

        // 1. Working directory
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd)

        // 2. Walk up from the main bundle executable
        if let execURL = Bundle.main.executableURL {
            var dir = execURL.deletingLastPathComponent()
            for _ in 0..<6 {
                candidates.append(dir)
                let parent = dir.deletingLastPathComponent()
                if parent == dir { break }
                dir = parent
            }
        }

        return candidates
    }

    /// Validate that all required paths exist and are accessible.
    static func validate(_ paths: BundlePaths) -> [String] {
        var issues: [String] = []

        if !FileManager.default.fileExists(atPath: paths.nodeBinary.path) {
            issues.append("Node binary missing at \(paths.nodeBinary.path)")
        } else if !FileManager.default.isExecutableFile(atPath: paths.nodeBinary.path) {
            issues.append("Node binary not executable at \(paths.nodeBinary.path)")
        }

        if !FileManager.default.fileExists(atPath: paths.relayEntry.path) {
            issues.append("Relay entry not found at \(paths.relayEntry.path)")
        }

        return issues
    }
}
