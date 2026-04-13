import Foundation

/// Detects installed AI coding clients and manages Ground Control MCP server
/// registration with each.
///
/// Supports Claude Code, VS Code (Copilot), and Cursor. Each client has a
/// JSON settings file where MCP server entries live. Registration adds a
/// `ground-control` entry pointing at the bundled MCP server (if running from
/// .app) or the npx command (if installed via npm).
enum MCPRegistrar {
    enum Client: String, CaseIterable, Identifiable {
        case claudeCode = "Claude Code"
        case vscode = "VS Code"
        case cursor = "Cursor"

        var id: String { rawValue }

        var sfSymbol: String {
            switch self {
            case .claudeCode: "terminal"
            case .vscode: "chevron.left.forwardslash.chevron.right"
            case .cursor: "cursorarrow.rays"
            }
        }
    }

    enum RegistrationError: LocalizedError {
        case clientNotInstalled(Client)
        case settingsParseError(String)
        case writeError(String)

        var errorDescription: String? {
            switch self {
            case .clientNotInstalled(let client):
                return "\(client.rawValue) is not installed"
            case .settingsParseError(let detail):
                return "Failed to parse settings: \(detail)"
            case .writeError(let detail):
                return "Failed to write settings: \(detail)"
            }
        }
    }

    // MARK: - Detection

    /// Check whether a client appears to be installed on this machine.
    static func isInstalled(_ client: Client) -> Bool {
        let path = settingsDir(for: client)
        return FileManager.default.fileExists(atPath: path)
    }

    /// Return all clients that appear to be installed.
    static func detectClients() -> [Client] {
        Client.allCases.filter { isInstalled($0) }
    }

    // MARK: - Registration Status

    /// Check if Ground Control's MCP server is registered with a client.
    /// Returns false if the client isn't installed or settings can't be read.
    static func isRegistered(_ client: Client) -> Bool {
        guard let settings = try? readSettings(for: client) else { return false }

        switch client {
        case .claudeCode:
            guard let servers = settings["mcpServers"] as? [String: Any] else { return false }
            return servers["ground-control"] != nil
        case .vscode, .cursor:
            guard let servers = settings["servers"] as? [String: Any] else { return false }
            return servers["ground-control"] != nil
        }
    }

    // MARK: - Register

    /// Register Ground Control's MCP server with a client.
    static func register(_ client: Client) throws {
        guard isInstalled(client) else {
            throw RegistrationError.clientNotInstalled(client)
        }

        let entry = mcpServerEntry()

        switch client {
        case .claudeCode:
            try mergeClaudeCodeSettings(entry: entry)
        case .vscode, .cursor:
            try mergeEditorMCPSettings(client: client, entry: entry)
        }
    }

    /// Unregister Ground Control's MCP server from a client.
    static func unregister(_ client: Client) throws {
        switch client {
        case .claudeCode:
            try removeClaudeCodeEntry()
        case .vscode, .cursor:
            try removeEditorMCPEntry(client: client)
        }
    }

    // MARK: - MCP Server Entry

    /// Build the MCP server entry for registration.
    ///
    /// If running from a bundled .app, points at the embedded Node + MCP server.
    /// Otherwise, uses npx for the npm-installed version.
    private static func mcpServerEntry() -> [String: Any] {
        if NodeBundleManager.isBundledApp,
           let resourceURL = Bundle.main.resourceURL {
            let nodePath = resourceURL.appendingPathComponent("node/node").path
            let mcpPath = resourceURL.appendingPathComponent("mcp/index.js").path
            return [
                "command": nodePath,
                "args": [mcpPath],
            ]
        } else {
            return [
                "command": "npx",
                "args": ["@major-tom/ground-control-mcp"],
            ]
        }
    }

    // MARK: - Claude Code

    private static func mergeClaudeCodeSettings(entry: [String: Any]) throws {
        let path = claudeCodeSettingsPath()
        var settings = try readJSON(at: path) ?? [:]
        var servers = settings["mcpServers"] as? [String: Any] ?? [:]
        servers["ground-control"] = entry
        settings["mcpServers"] = servers
        try writeJSON(settings, to: path)
    }

    private static func removeClaudeCodeEntry() throws {
        let path = claudeCodeSettingsPath()
        guard var settings = try readJSON(at: path) else { return }
        guard var servers = settings["mcpServers"] as? [String: Any] else { return }
        servers.removeValue(forKey: "ground-control")
        settings["mcpServers"] = servers
        try writeJSON(settings, to: path)
    }

    private static func claudeCodeSettingsPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/settings.json"
    }

    // MARK: - VS Code / Cursor

    private static func mergeEditorMCPSettings(client: Client, entry: [String: Any]) throws {
        let path = editorMCPPath(for: client)

        // Create parent directory if needed
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var settings = try readJSON(at: path) ?? [:]
        var servers = settings["servers"] as? [String: Any] ?? [:]
        servers["ground-control"] = entry
        settings["servers"] = servers
        try writeJSON(settings, to: path)
    }

    private static func removeEditorMCPEntry(client: Client) throws {
        let path = editorMCPPath(for: client)
        guard var settings = try readJSON(at: path) else { return }
        guard var servers = settings["servers"] as? [String: Any] else { return }
        servers.removeValue(forKey: "ground-control")
        settings["servers"] = servers
        try writeJSON(settings, to: path)
    }

    private static func editorMCPPath(for client: Client) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch client {
        case .vscode:
            return "\(home)/Library/Application Support/Code/User/mcp.json"
        case .cursor:
            return "\(home)/Library/Application Support/Cursor/User/mcp.json"
        case .claudeCode:
            fatalError("Use claudeCodeSettingsPath for Claude Code")
        }
    }

    // MARK: - Paths

    private static func settingsDir(for client: Client) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch client {
        case .claudeCode:
            return "\(home)/.claude"
        case .vscode:
            return "\(home)/Library/Application Support/Code"
        case .cursor:
            return "\(home)/Library/Application Support/Cursor"
        }
    }

    private static func readSettings(for client: Client) throws -> [String: Any]? {
        switch client {
        case .claudeCode:
            return try readJSON(at: claudeCodeSettingsPath())
        case .vscode, .cursor:
            return try readJSON(at: editorMCPPath(for: client))
        }
    }

    // MARK: - JSON Helpers

    /// Read a JSON file as a dictionary. Returns nil if the file doesn't exist.
    /// Throws if the file exists but can't be parsed — prevents silently
    /// overwriting a corrupt settings file.
    private static func readJSON(at path: String) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw RegistrationError.settingsParseError("Could not read file at \(path)")
        }

        let parsedJSON: Any
        do {
            parsedJSON = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw RegistrationError.settingsParseError("File is not valid JSON: \(path)")
        }

        guard let json = parsedJSON as? [String: Any] else {
            throw RegistrationError.settingsParseError("Settings file must contain a JSON object: \(path)")
        }
        return json
    }

    private static func writeJSON(_ json: [String: Any], to path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw RegistrationError.writeError("Failed to encode JSON")
        }
        do {
            try string.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            throw RegistrationError.writeError(error.localizedDescription)
        }
    }
}
