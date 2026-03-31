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
        case sendPrompt
        case quickApprove
        case toggleGodMode
        case checkAchievements
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

// MARK: - Fleet Status Intent

struct FleetStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Fleet Status"
    static var description: IntentDescription = "Shows fleet status with worker count, total cost, and active sessions"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let snapshot = WidgetDataProvider.readFleetSnapshot()
        let costStr = String(format: "$%.4f", snapshot.totalCost)

        let summary: String
        if snapshot.workerCount == 0 {
            summary = "Fleet offline — no workers connected."
        } else {
            summary = "\(snapshot.workerCount) worker\(snapshot.workerCount == 1 ? "" : "s"), \(snapshot.activeSessionCount) active session\(snapshot.activeSessionCount == 1 ? "" : "s"), \(costStr) total cost."
        }

        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

// MARK: - Send Prompt Intent

struct SendPromptIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Prompt"
    static var description: IntentDescription = "Sends a prompt to the active Claude Code session in Major Tom"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Prompt", description: "What should I send to Claude?", requestValueDialog: "What should I send?")
    var promptText: String

    func perform() async throws -> some IntentResult {
        // Write prompt to shared UserDefaults for the app to consume on foreground
        WidgetDataProvider.writePendingPrompt(promptText)
        ShortcutActionKey.postAction(.sendPrompt)
        NotificationCenter.default.post(name: .sendPromptFromShortcut, object: nil)
        return .result()
    }
}

// MARK: - Quick Approve Intent

struct QuickApproveIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Approve"
    static var description: IntentDescription = "Approves the most recent pending tool request in Major Tom"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let pending = WidgetDataProvider.readPendingApproval()

        guard let tool = pending.tool else {
            return .result(value: "No pending approvals.", dialog: IntentDialog("No pending approvals to approve."))
        }

        // Post action so app handles the actual approval on foreground (safety)
        ShortcutActionKey.postAction(.quickApprove)
        NotificationCenter.default.post(name: .quickApproveFromShortcut, object: nil)

        let message = "Approving \(tool)..."
        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Session Summary Intent

struct SessionSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Session Summary"
    static var description: IntentDescription = "Shows a summary of the active Claude Code session"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let session = WidgetDataProvider.readSessionSummary()

        guard session.name != "No Session" else {
            return .result(value: "No active session.", dialog: IntentDialog("No active session in Major Tom."))
        }

        let costStr = String(format: "$%.4f", session.costUsd)
        let totalTokens = session.tokensIn + session.tokensOut
        let tokenStr = formatTokenCount(totalTokens)
        let durationStr = formatDuration(ms: session.durationMs)

        let summary = "\(session.name): \(costStr), \(tokenStr) tokens, \(session.turnCount) turn\(session.turnCount == 1 ? "" : "s"), \(durationStr)."

        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func formatDuration(ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Toggle God Mode Intent

struct ToggleGodModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle God Mode"
    static var description: IntentDescription = "Toggles between Manual and God permission modes in Major Tom"
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let currentMode = WidgetDataProvider.readPermissionMode()

        // Only toggle between manual and god — other modes (smart/delay) are left unchanged
        guard currentMode == "manual" || currentMode == "god" else {
            let message = "Cannot toggle — currently in \(currentMode) mode. Only Manual and God modes can be toggled."
            return .result(value: message, dialog: IntentDialog(stringLiteral: message))
        }

        // Write toggle request for the app to consume
        WidgetDataProvider.writeGodModeToggle()
        ShortcutActionKey.postAction(.toggleGodMode)
        NotificationCenter.default.post(name: .toggleGodModeFromShortcut, object: nil)

        let newMode = currentMode == "god" ? "Manual" : "God"
        let message = "\(newMode) mode will activate when Major Tom opens."

        return .result(value: message, dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Check Achievements Intent

struct CheckAchievementsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Achievements"
    static var description: IntentDescription = "Opens Major Tom to the Achievements tab to see your progress"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        ShortcutActionKey.postAction(.checkAchievements)
        NotificationCenter.default.post(name: .checkAchievementsFromShortcut, object: nil)
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

        AppShortcut(
            intent: FleetStatusIntent(),
            phrases: [
                "How's my fleet in \(.applicationName)",
                "Fleet status in \(.applicationName)",
                "\(.applicationName) fleet overview",
                "Show workers in \(.applicationName)"
            ],
            shortTitle: "Fleet Status",
            systemImageName: "server.rack"
        )

        AppShortcut(
            intent: SendPromptIntent(),
            phrases: [
                "Send a prompt to \(.applicationName)",
                "Tell \(.applicationName) something",
                "Prompt \(.applicationName)",
                "Send to \(.applicationName)"
            ],
            shortTitle: "Send Prompt",
            systemImageName: "text.bubble"
        )

        AppShortcut(
            intent: QuickApproveIntent(),
            phrases: [
                "Approve in \(.applicationName)",
                "Quick approve \(.applicationName)",
                "Allow in \(.applicationName)",
                "Approve tool in \(.applicationName)"
            ],
            shortTitle: "Quick Approve",
            systemImageName: "checkmark.circle"
        )

        AppShortcut(
            intent: SessionSummaryIntent(),
            phrases: [
                "\(.applicationName) session summary",
                "Session summary in \(.applicationName)",
                "How's my session in \(.applicationName)",
                "Session stats in \(.applicationName)"
            ],
            shortTitle: "Session Summary",
            systemImageName: "chart.bar.doc.horizontal"
        )

        AppShortcut(
            intent: ToggleGodModeIntent(),
            phrases: [
                "Toggle God mode in \(.applicationName)",
                "Switch God mode in \(.applicationName)",
                "\(.applicationName) God mode",
                "Enable God mode in \(.applicationName)"
            ],
            shortTitle: "Toggle God Mode",
            systemImageName: "bolt.circle"
        )

        AppShortcut(
            intent: CheckAchievementsIntent(),
            phrases: [
                "Show my \(.applicationName) achievements",
                "Check achievements in \(.applicationName)",
                "\(.applicationName) achievements",
                "Achievement progress in \(.applicationName)"
            ],
            shortTitle: "Check Achievements",
            systemImageName: "trophy"
        )
    }
}

// MARK: - Notification Names for In-Process Shortcut Actions

extension Notification.Name {
    static let startSessionFromShortcut = Notification.Name("com.majortom.shortcut.startSession")
    static let navigateToOfficeFromShortcut = Notification.Name("com.majortom.shortcut.navigateToOffice")
    static let showCostFromShortcut = Notification.Name("com.majortom.shortcut.showCost")
    static let sendPromptFromShortcut = Notification.Name("com.majortom.shortcut.sendPrompt")
    static let quickApproveFromShortcut = Notification.Name("com.majortom.shortcut.quickApprove")
    static let toggleGodModeFromShortcut = Notification.Name("com.majortom.shortcut.toggleGodMode")
    static let checkAchievementsFromShortcut = Notification.Name("com.majortom.shortcut.checkAchievements")
}
