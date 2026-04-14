import Foundation

extension Notification.Name {
    /// Posted when `PerfHUDPreferences.isEnabled` actually changes.
    static let perfHUDPreferencesDidChange = Notification.Name("com.majortom.perfHUD.didChange")
}

/// Dev-only toggle for the SpriteKit debug HUD (FPS + node/draw/quad counts).
///
/// Persisted in UserDefaults so it survives app restarts without a rebuild, and
/// can be flipped in Release builds too (measurement is the whole point of
/// optimization Wave 1). Flipping posts `.perfHUDPreferencesDidChange` —
/// `OfficeScene` observes that and re-applies the HUD flags live.
enum PerfHUDPreferences {
    private static let defaultsKey = "sprite.perfHUD.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set {
            guard newValue != UserDefaults.standard.bool(forKey: defaultsKey) else { return }
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: .perfHUDPreferencesDidChange, object: nil)
        }
    }
}
