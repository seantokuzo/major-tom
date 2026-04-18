import Foundation

/// Feature flags for in-development phases of the app.
///
/// Stored in `UserDefaults` so flips survive app restarts without a rebuild.
/// Flags default to `false` — each keyed-off flag represents an in-flight
/// phase that is not yet ready to light up for real users. When a phase
/// ships in full, the flag is removed alongside the old code path.
enum FeatureFlags {

    // MARK: - Tab-Keyed Offices (Wave 3/4)

    /// Route sprite + agent events by `tabId` (when present on the wire)
    /// instead of `sessionId`.
    ///
    /// **Wave 3 (this phase):** flag is exposed but unused — Offices still
    /// key by `sessionId`. The flag lets Wave 4 land the routing flip
    /// behind a toggle that can be dark-launched per device.
    ///
    /// **Wave 4:** `OfficeSceneManager` reads this and either routes by
    /// `event.tabId ?? event.sessionId` (flag on) or stays sessionId-first
    /// (flag off) for one release of backwards compatibility, after which
    /// the flag is removed.
    static var tabKeyedOffices: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.tabKeyedOffices) }
        set {
            guard newValue != UserDefaults.standard.bool(forKey: Keys.tabKeyedOffices) else { return }
            UserDefaults.standard.set(newValue, forKey: Keys.tabKeyedOffices)
        }
    }

    // MARK: - Defaults Keys

    private enum Keys {
        static let tabKeyedOffices = "featureFlag.tabKeyedOffices"
    }
}
