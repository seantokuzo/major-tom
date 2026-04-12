import Foundation

/// Authentication mode for the relay server.
enum AuthMode: String, Codable, CaseIterable, Identifiable {
    case none
    case pin
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .pin: "PIN"
        case .google: "Google OAuth"
        }
    }
}

/// Log level matching pino's levels.
enum LogLevel: String, Codable, CaseIterable, Identifiable {
    case trace
    case debug
    case info
    case warn
    case error

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

/// Typed configuration model for the relay server.
///
/// Persisted to `~/.major-tom/config.json`. Secrets (OAuth credentials,
/// Cloudflare token) are NOT stored here — they live in macOS Keychain.
struct RelayConfig: Equatable {
    var port: Int
    var hookPort: Int
    var authMode: AuthMode
    var multiUserEnabled: Bool
    var claudeWorkDir: String
    var logLevel: LogLevel
    var cloudflareEnabled: Bool
    /// Optional display-only tunnel name (e.g., "major-tom") shown in the UI.
    /// `cloudflared tunnel run --token <token>` picks the tunnel from the token
    /// itself, so this field is informational.
    var cloudflareTunnelName: String
    var autoStart: Bool
    /// Whether to register as a Login Item so the app launches at system startup.
    var launchAtLogin: Bool

    /// Sensible defaults for a fresh install.
    static let defaults = RelayConfig(
        port: 9090,
        hookPort: 9091,
        authMode: .pin,
        multiUserEnabled: false,
        claudeWorkDir: "~",
        logLevel: .info,
        cloudflareEnabled: false,
        cloudflareTunnelName: "",
        autoStart: true,
        launchAtLogin: false
    )

    // MARK: - Validation

    /// Validation errors for the current config state.
    struct ValidationResult {
        var portError: String?
        var hookPortError: String?

        var isValid: Bool {
            portError == nil && hookPortError == nil
        }
    }

    /// Validate the config and return any errors.
    func validate() -> ValidationResult {
        var result = ValidationResult()

        if port < 1024 || port > 65535 {
            result.portError = "Port must be between 1024 and 65535"
        }

        if hookPort < 1024 || hookPort > 65535 {
            result.hookPortError = "Hook port must be between 1024 and 65535"
        }

        if result.portError == nil && result.hookPortError == nil && port == hookPort {
            result.hookPortError = "Hook port must differ from relay port"
        }

        return result
    }

    /// Expand `~` in claudeWorkDir to the full home directory path.
    var expandedClaudeWorkDir: String {
        if claudeWorkDir.hasPrefix("~") {
            return (claudeWorkDir as NSString).expandingTildeInPath
        }
        return claudeWorkDir
    }
}

// MARK: - Codable

/// Hand-rolled Codable so newly-added fields backfill from older on-disk
/// configs instead of failing to decode.
extension RelayConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case port, hookPort, authMode, multiUserEnabled, claudeWorkDir
        case logLevel, cloudflareEnabled, cloudflareTunnelName, autoStart
        case launchAtLogin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.port = try c.decode(Int.self, forKey: .port)
        self.hookPort = try c.decode(Int.self, forKey: .hookPort)
        self.authMode = try c.decode(AuthMode.self, forKey: .authMode)
        self.multiUserEnabled = try c.decode(Bool.self, forKey: .multiUserEnabled)
        self.claudeWorkDir = try c.decode(String.self, forKey: .claudeWorkDir)
        self.logLevel = try c.decode(LogLevel.self, forKey: .logLevel)
        self.cloudflareEnabled = try c.decode(Bool.self, forKey: .cloudflareEnabled)
        self.cloudflareTunnelName = try c.decodeIfPresent(String.self, forKey: .cloudflareTunnelName) ?? ""
        self.autoStart = try c.decode(Bool.self, forKey: .autoStart)
        // Backfill: older configs won't have this field
        self.launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(port, forKey: .port)
        try c.encode(hookPort, forKey: .hookPort)
        try c.encode(authMode, forKey: .authMode)
        try c.encode(multiUserEnabled, forKey: .multiUserEnabled)
        try c.encode(claudeWorkDir, forKey: .claudeWorkDir)
        try c.encode(logLevel, forKey: .logLevel)
        try c.encode(cloudflareEnabled, forKey: .cloudflareEnabled)
        try c.encode(cloudflareTunnelName, forKey: .cloudflareTunnelName)
        try c.encode(autoStart, forKey: .autoStart)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
    }
}
