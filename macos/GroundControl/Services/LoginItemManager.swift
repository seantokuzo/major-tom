import ServiceManagement
import os

/// Manages the app's Login Item registration via SMAppService.
///
/// SMAppService.mainApp requires macOS 13+; our minimum target is macOS 14
/// so this is always available. The Login Item shows up in System Settings >
/// General > Login Items, and the user can also toggle it there.
enum LoginItemManager {
    private static let logger = Logger(
        subsystem: "com.majortom.groundcontrol",
        category: "LoginItemManager"
    )

    /// Register or unregister the app as a Login Item.
    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            if enabled {
                try service.register()
                logger.info("Registered as Login Item")
            } else {
                try service.unregister()
                logger.info("Unregistered as Login Item")
            }
        } catch {
            logger.error("Login Item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }

    /// Synchronize the Login Item state with the current config value.
    ///
    /// Called at app launch to ensure the SMAppService state matches what
    /// the user last saved in config. Handles the case where the user
    /// toggled the Login Item in System Settings independently.
    static func syncWithConfig(launchAtLogin: Bool) {
        let service = SMAppService.mainApp
        let currentStatus = service.status

        switch (launchAtLogin, currentStatus) {
        case (true, .notRegistered), (true, .notFound):
            // Config says enabled but not registered — register it
            setEnabled(true)

        case (false, .enabled), (false, .requiresApproval):
            // Config says disabled but it's registered or pending — unregister it
            setEnabled(false)

        default:
            // Already in sync or in a transitional state — leave it alone
            break
        }
    }
}
