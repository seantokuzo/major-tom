import Foundation
import Security

/// Manages relay configuration persistence and Keychain secret storage.
///
/// Config is stored in `~/.major-tom/config.json` (non-secret fields).
/// Secrets (OAuth credentials, Cloudflare token) are stored in macOS Keychain.
@Observable
final class ConfigManager {
    /// Current in-memory config. Update this then call `save()`.
    var config: RelayConfig

    /// Whether the config has unsaved changes compared to the on-disk version.
    var hasUnsavedChanges: Bool {
        config != lastSavedConfig
    }

    private var lastSavedConfig: RelayConfig

    // MARK: - Constants

    private static let configDirName = ".major-tom"
    private static let configFileName = "config.json"
    private static let keychainService = "com.majortom.groundcontrol"

    /// Well-known Keychain keys for secrets.
    enum SecretKey {
        static let googleClientId = "google-client-id"
        static let googleClientSecret = "google-client-secret"
        static let cloudflareToken = "cloudflare-token"
    }

    // MARK: - Init

    init() {
        let fileExisted = FileManager.default.fileExists(atPath: ConfigManager.configFileURL.path)
        let loaded = ConfigManager.loadFromDisk()
        self.config = loaded
        self.lastSavedConfig = loaded

        // Write defaults on first launch so config.json exists on disk
        if !fileExisted {
            try? save()
        }
    }

    // MARK: - Config File I/O

    /// Path to `~/.major-tom/config.json`.
    static var configFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(configDirName)
            .appendingPathComponent(configFileName)
    }

    /// Path to `~/.major-tom/`.
    static var configDirURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(configDirName)
    }

    /// Load config from disk, returning defaults if the file doesn't exist or is malformed.
    static func loadFromDisk() -> RelayConfig {
        let url = configFileURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            return RelayConfig.defaults
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(RelayConfig.self, from: data)
        } catch {
            print("[ConfigManager] Failed to decode config.json, using defaults: \(error)")
            return RelayConfig.defaults
        }
    }

    /// Reload config from disk.
    func reload() {
        let loaded = ConfigManager.loadFromDisk()
        config = loaded
        lastSavedConfig = loaded
    }

    /// Save current config to `~/.major-tom/config.json` atomically.
    ///
    /// Creates the `~/.major-tom/` directory if it doesn't exist.
    func save() throws {
        let dirURL = ConfigManager.configDirURL
        let fileURL = ConfigManager.configFileURL

        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: dirURL,
            withIntermediateDirectories: true
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)

        // Atomic write: write to temp file, then rename
        let tempURL = dirURL.appendingPathComponent("config.json.tmp")
        try data.write(to: tempURL, options: .atomic)

        // Replace existing file atomically
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }

        lastSavedConfig = config
    }

    /// Reset config to defaults (does not save — call `save()` after).
    func resetToDefaults() {
        config = RelayConfig.defaults
    }

    // MARK: - Keychain CRUD

    /// Store a secret in the macOS Keychain.
    func setSecret(_ key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Try to update first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ConfigManager.keychainService,
            kSecAttrAccount as String: key,
        ]

        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist yet — add it
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                print("[ConfigManager] Keychain add failed for '\(key)': \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            print("[ConfigManager] Keychain update failed for '\(key)': \(updateStatus)")
        }
    }

    /// Retrieve a secret from the macOS Keychain.
    func getSecret(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ConfigManager.keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Delete a secret from the macOS Keychain.
    func deleteSecret(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ConfigManager.keychainService,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            print("[ConfigManager] Keychain delete failed for '\(key)': \(status)")
        }
    }
}
