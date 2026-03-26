import AppIntents
import SwiftUI

// MARK: - Start Claude Session Intent

struct StartClaudeSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Claude Session"
    static var description: IntentDescription = "Opens Major Tom and starts a new Claude Code session"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Post notification so the app can react to this intent
        NotificationCenter.default.post(
            name: .startSessionFromShortcut,
            object: nil
        )
        return .result()
    }
}

// MARK: - Check Agents Intent

struct CheckAgentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Agents"
    static var description: IntentDescription = "Opens Major Tom to the Office tab to see active agents"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .navigateToOfficeFromShortcut,
            object: nil
        )
        return .result()
    }
}

// MARK: - Show Cost Intent

struct ShowCostIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Session Cost"
    static var description: IntentDescription = "Opens Major Tom and shows the current session cost summary"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .showCostFromShortcut,
            object: nil
        )
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

// MARK: - Notification Names for Shortcut Actions

extension Notification.Name {
    static let startSessionFromShortcut = Notification.Name("com.majortom.shortcut.startSession")
    static let navigateToOfficeFromShortcut = Notification.Name("com.majortom.shortcut.navigateToOffice")
    static let showCostFromShortcut = Notification.Name("com.majortom.shortcut.showCost")
}
