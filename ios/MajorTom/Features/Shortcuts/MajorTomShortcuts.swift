import AppIntents
import SwiftUI

// MARK: - Shortcut Action Keys

/// Shared keys for cross-process shortcut communication via App Groups UserDefaults.
/// NotificationCenter.default.post() does NOT work across processes (Siri/Shortcuts app).
/// We use a shared UserDefaults suite to pass the action, and the app polls on foreground.
/// 
/// NOTE: The App Group entitlement must be configured in Xcode for both the main app target
/// and any extension targets that use this suite (Signing & Capabilities > App Groups).
enum ShortcutActionKey {
    // Reuses the same App Group as WidgetDataProvider for a single shared suite.
    static let suiteName = "group.com.majortom.shared"
    static let pendingActionKey = "pendingShortcutAction"
    static let timestampKey = "shortcutActionTimestamp"

    enum Action: String {
        case startSession
        case navigateToOffice
        case showCost
    }

    /// Returns the App Group `UserDefaults` used for cross-process shortcut communication.
    /// Asserts in debug builds if the suite is not available, which typically indicates
    /// a missing or incorrect App Group entitlement configuration.
    private static func appGroupDefaults() -> UserDefaults? {
        let defaults = UserDefaults(suiteName: suiteName)
        assert(defaults != nil, "App Group UserDefaults not available. Check entitlements for suite \(suiteName).")
        return defaults
    }

    /// Write a pending action to App Groups UserDefaults.
    static func postAction(_ action: Action) {
        guard let defaults = appGroupDefaults() else { return }
        defaults.set(action.rawValue, forKey: pendingActionKey)
        defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
    }

    /// Read and consume a pending action. Returns nil if no action or stale (>10s old).
    static func consumeAction() -> Action? {
        guard let defaults = appGroupDefaults() else { return nil }
        guard let rawAction = defaults.string(forKey: pendingActionKey),
              let action = Action(rawValue: rawAction) else {
            return nil
        }

        // Check staleness — ignore actions older than 10 seconds
        let timestamp = defaults.double(forKey: timestampKey)
        let age = Date().timeIntervalSince1970 - timestamp
        guard age < 10 else {
            defaults.removeObject(forKey: pendingActionKey)
            return nil
        }

        // Consume the action
        defaults.removeObject(forKey: pendingActionKey)
        return action
    }
}

// MARK: - Start Claude Session Intent

struct StartClaudeSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Claude Session"
    static var description: IntentDescription = "Opens Major Tom and starts a new Claude Code session"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Write to shared UserDefaults so the app can react when it foregrounds.
        // Also post in-process notification for Spotlight (in-app) usage.
        ShortcutActionKey.postAction(.startSession)
        NotificationCenter.default.post(name: .startSessionFromShortcut, object: nil)
        return .result()
    }
}

// MARK: - Check Agents Intent

struct CheckAgentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Agents"
    static var description: IntentDescription = "Opens Major Tom to the Office tab to see active agents"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        ShortcutActionKey.postAction(.navigateToOffice)
        NotificationCenter.default.post(name: .navigateToOfficeFromShortcut, object: nil)
        return .result()
    }
}

// MARK: - Show Cost Intent

struct ShowCostIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Session Cost"
    static var description: IntentDescription = "Opens Major Tom and shows the current session cost summary"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        ShortcutActionKey.postAction(.showCost)
        NotificationCenter.default.post(name: .showCostFromShortcut, object: nil)
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct MajorTomShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartClaudeSessionIntent(),
            phrases: [
                "Start a \(.applicationName) session",
                "Start Claude session in \(.applicationName)",
                "Open \(.applicationName) and start coding",
                "New session in \(.applicationName)"
            ],
            shortTitle: "Start Session",
            systemImageName: "play.circle"
        )

        AppShortcut(
            intent: CheckAgentsIntent(),
            phrases: [
                "Check agents in \(.applicationName)",
                "Show agents in \(.applicationName)",
                "Open \(.applicationName) office",
                "How are my agents in \(.applicationName)"
            ],
            shortTitle: "Check Agents",
            systemImageName: "building.2"
        )

        AppShortcut(
            intent: ShowCostIntent(),
            phrases: [
                "Show cost in \(.applicationName)",
                "How much has \(.applicationName) cost",
                "Session cost in \(.applicationName)",
                "Check \(.applicationName) spending"
            ],
            shortTitle: "Show Cost",
            systemImageName: "dollarsign.circle"
        )
    }
}

// MARK: - Notification Names for In-Process Shortcut Actions

extension Notification.Name {
    static let startSessionFromShortcut = Notification.Name("com.majortom.shortcut.startSession")
    static let navigateToOfficeFromShortcut = Notification.Name("com.majortom.shortcut.navigateToOffice")
    static let showCostFromShortcut = Notification.Name("com.majortom.shortcut.showCost")
}
