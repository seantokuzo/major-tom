import Foundation

/// Manages keybar layout customization, font size, and preference sync with the relay.
///
/// On init, loads from UserDefaults (device-local cache). Then async fetches
/// from the relay's `/api/user/preferences` endpoint — server wins if it has
/// a config. Local mutations save to UserDefaults immediately and debounce-sync
/// to the relay (800ms). Network errors never block the UI, though sync/push
/// failures are logged to the console.
///
/// Mirrors the web PWA's `keybar.svelte.ts` + `shell.svelte.ts` sync patterns.
@Observable
@MainActor
final class KeybarViewModel {

    // MARK: - Published State

    /// Active key IDs for the accessory row (above the iOS keyboard).
    var accessoryIds: [String]

    /// Active key IDs for the specialty grid.
    var specialtyIds: [String]

    /// Terminal font size in points (range 8-32).
    var fontSize: Int

    /// Selected terminal theme ID (persisted in UserDefaults).
    var selectedThemeId: String

    // MARK: - Computed

    /// Resolved accessory row keys for the UI.
    var accessoryKeys: [KeySpec] {
        KeyLibrary.resolve(accessoryIds)
    }

    /// Resolved specialty grid keys for the UI.
    var specialtyKeys: [KeySpec] {
        KeyLibrary.resolve(specialtyIds)
    }

    /// The currently selected theme.
    var selectedTheme: TerminalTheme {
        TerminalTheme.all.first(where: { $0.id == selectedThemeId }) ?? .majorTom
    }

    // MARK: - Constants

    private static let accessoryKey = "mt-keybar-accessory-v1"
    private static let specialtyKey = "mt-keybar-specialty-v1"
    private static let fontSizeKey = "mt-font-size"
    private static let themeKey = "mt-terminal-theme"
    private static let syncDebounceMs: UInt64 = 800

    // MARK: - Private State

    /// Reference to auth for building relay URLs.
    private let auth: AuthService

    /// Whether we've synced from the relay (prevents double-apply).
    private var synced = false

    /// Debounce task for relay sync.
    private var syncTask: Task<Void, Never>?

    /// Tracked task for the relay push request.
    private var relayTask: Task<Void, Never>?

    // MARK: - Init

    init(auth: AuthService) {
        self.auth = auth

        // Load from UserDefaults (device-local cache)
        let defaults = UserDefaults.standard

        if let savedAccessory = defaults.stringArray(forKey: Self.accessoryKey),
           !savedAccessory.isEmpty {
            self.accessoryIds = savedAccessory
        } else {
            self.accessoryIds = KeyLibrary.defaultBarIDs
        }

        if let savedSpecialty = defaults.stringArray(forKey: Self.specialtyKey),
           !savedSpecialty.isEmpty {
            self.specialtyIds = savedSpecialty
        } else {
            self.specialtyIds = KeyLibrary.defaultGridIDs
        }

        let savedFontSize = defaults.integer(forKey: Self.fontSizeKey)
        if savedFontSize >= 8 && savedFontSize <= 32 {
            self.fontSize = savedFontSize
        } else {
            self.fontSize = 14
        }

        self.selectedThemeId = defaults.string(forKey: Self.themeKey) ?? TerminalTheme.majorTom.id
    }

    // MARK: - Relay Sync

    /// Pull preferences from the relay. Server wins if it has config.
    /// Called once on app load after auth is established.
    func syncFromRelay() async {
        guard !synced else { return }

        guard let url = buildPreferencesURL() else {
            synced = true
            return
        }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            applyAuth(to: &request)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                synced = true
                return
            }

            guard let prefs = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                synced = true
                return
            }

            // Apply keybar config if server has one
            if let keybarConfig = prefs["keybarConfig"] as? [String: Any],
               let remoteAccessory = keybarConfig["accessory"] as? [String],
               !remoteAccessory.isEmpty {
                let sanitizedAccessory = sanitize(remoteAccessory)
                let remoteSpecialty = keybarConfig["specialty"] as? [String] ?? []
                let sanitizedSpecialty = sanitize(remoteSpecialty)

                if !sanitizedAccessory.isEmpty {
                    accessoryIds = sanitizedAccessory
                    specialtyIds = sanitizedSpecialty.isEmpty ? KeyLibrary.defaultGridIDs : sanitizedSpecialty
                    saveToDefaults()
                }
            } else if !isDefault() {
                // Local is customized but server is empty -- push local up
                pushToRelay()
            }

            // Apply font size if server has one
            if let remoteFontSize = prefs["fontSize"] as? Int,
               remoteFontSize >= 8 && remoteFontSize <= 32 {
                fontSize = remoteFontSize
                UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey)
            }

            synced = true
        } catch {
            // Network error -- stay with local config, allow retry
            print("[KeybarViewModel] syncFromRelay failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Accessory Row Mutators

    func addAccessoryKey(id: String) {
        guard KeyLibrary.get(id) != nil else { return }
        guard !accessoryIds.contains(id) else { return }
        accessoryIds.append(id)
        persist()
    }

    func removeAccessoryKey(id: String) {
        guard accessoryIds.contains(id) else { return }
        accessoryIds.removeAll { $0 == id }
        persist()
    }

    func moveAccessoryKey(from source: IndexSet, to destination: Int) {
        accessoryIds.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Specialty Grid Mutators

    func addSpecialtyKey(id: String) {
        guard KeyLibrary.get(id) != nil else { return }
        guard !specialtyIds.contains(id) else { return }
        specialtyIds.append(id)
        persist()
    }

    func removeSpecialtyKey(id: String) {
        guard specialtyIds.contains(id) else { return }
        specialtyIds.removeAll { $0 == id }
        persist()
    }

    func moveSpecialtyKey(from source: IndexSet, to destination: Int) {
        specialtyIds.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Font Size

    func setFontSize(_ size: Int) {
        let clamped = max(8, min(32, size))
        guard clamped != fontSize else { return }
        fontSize = clamped
        UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey)
        scheduleSyncToRelay()
    }

    // MARK: - Theme

    /// Set the active terminal theme. Theme selection is local-only (UserDefaults)
    /// and not synced to the relay — only keybar layout and font size are synced.
    func setTheme(_ theme: TerminalTheme) {
        guard theme.id != selectedThemeId else { return }
        selectedThemeId = theme.id
        UserDefaults.standard.set(selectedThemeId, forKey: Self.themeKey)
    }

    // MARK: - Reset

    func resetToDefaults() {
        accessoryIds = KeyLibrary.defaultBarIDs
        specialtyIds = KeyLibrary.defaultGridIDs
        fontSize = 14
        selectedThemeId = TerminalTheme.majorTom.id
        UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey)
        UserDefaults.standard.set(selectedThemeId, forKey: Self.themeKey)
        persist()
    }

    // MARK: - Private Helpers

    private func isDefault() -> Bool {
        accessoryIds == KeyLibrary.defaultBarIDs &&
        specialtyIds == KeyLibrary.defaultGridIDs
    }

    /// Sanitize key IDs -- filter out unrecognized IDs and duplicates.
    private func sanitize(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids {
            guard !seen.contains(id) else { continue }
            guard KeyLibrary.get(id) != nil else { continue }
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    private func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(accessoryIds, forKey: Self.accessoryKey)
        defaults.set(specialtyIds, forKey: Self.specialtyKey)
    }

    private func persist() {
        saveToDefaults()
        scheduleSyncToRelay()
    }

    private func scheduleSyncToRelay() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.syncDebounceMs * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.pushToRelay()
        }
    }

    /// Push current config to relay (fire-and-forget).
    private func pushToRelay() {
        guard let url = buildPreferencesURL() else { return }

        let payload: [String: Any] = [
            "keybarConfig": [
                "version": 1,
                "accessory": accessoryIds,
                "specialty": specialtyIds,
            ],
            "fontSize": fontSize,
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        relayTask?.cancel()
        relayTask = Task {
            guard !Task.isCancelled else { return }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                applyAuth(to: &request)
                request.httpBody = body

                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    print("[KeybarViewModel] pushToRelay got \(httpResponse.statusCode)")
                }
            } catch {
                // Network error -- local state is saved, will sync next time
                print("[KeybarViewModel] pushToRelay failed: \(error.localizedDescription)")
            }
        }
    }

    private func buildPreferencesURL() -> URL? {
        let base = auth.serverURL
        let scheme = base.contains("://") ? "" : "http://"
        let fullBase = "\(scheme)\(base)"
        return URL(string: "\(fullBase)/api/user/preferences")
    }

    /// Apply auth cookie/token to the request.
    private func applyAuth(to request: inout URLRequest) {
        if let token = auth.sessionCookie {
            request.setValue("mt-session=\(token)", forHTTPHeaderField: "Cookie")
        }
    }
}
