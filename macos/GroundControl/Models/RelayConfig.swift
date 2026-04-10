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
struct RelayConfig: Codable, Equatable {
    var port: Int
    var hookPort: Int
    var authMode: AuthMode
    var multiUserEnabled: Bool
    var claudeWorkDir: String
    var logLevel: LogLevel
    var cloudflareEnabled: Bool
    var autoStart: Bool

    /// Sensible defaults for a fresh install.
    static let defaults = RelayConfig(
        port: 9090,
        hookPort: 9091,
        authMode: .pin,
        multiUserEnabled: false,
        claudeWorkDir: "~",
        logLevel: .info,
        cloudflareEnabled: false,
        autoStart: true
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
