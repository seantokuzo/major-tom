import Foundation

/// Dev-only toggle for the SpriteKit debug HUD (FPS + node/draw/quad counts).
///
/// Persisted in UserDefaults so it survives app restarts without a rebuild, and
/// can be flipped in Release builds too (measurement is the whole point of
/// optimization Wave 1). Flipping posts `didChangeNotification` — `OfficeScene`
/// observes that and re-applies the HUD flags live.
enum PerfHUDPreferences {
    private static let defaultsKey = "sprite.perfHUD.enabled"

    static let didChangeNotification = Notification.Name("PerfHUDPreferencesDidChange")

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
