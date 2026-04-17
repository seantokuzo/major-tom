import Foundation
import UserNotifications
import UIKit

// MARK: - Notification Categories

enum NotificationCategory: String {
    case approvalRequest = "APPROVAL_REQUEST"
    case sessionEvent = "SESSION_EVENT"
    /// Wave 5 — local push when a `/btw` response arrives while the app is
    /// backgrounded. Carries a single "Cool Beans" action.
    case btwResponse = "SPRITE_BTW_RESPONSE"
}

enum NotificationAction: String {
    case allow = "ALLOW_ACTION"
    case deny = "DENY_ACTION"
    /// Wave 5 — dismisses the unread `/btw` response for the originating sprite.
    case coolBeans = "COOL_BEANS"
}

// MARK: - Notification Service

@Observable
@MainActor
final class NotificationService: NSObject {
    var isAuthorized: Bool = false
    var pendingDeepLink: NotificationDeepLink?

    /// Callback invoked when user acts on an approval notification.
    /// Parameters: requestId, approved (true = allow, false = deny)
    var onApprovalAction: ((String, Bool) -> Void)?

    /// Wave 5 — invoked when the user taps the "Cool Beans" action on a
    /// `/btw` response notification. Parameters: sessionId, subagentId.
    var onBtwCoolBeansAction: ((String, String) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
        Task { await checkAuthorizationStatus() }
    }

    // MARK: - Permission Request

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            isAuthorized = granted
            if granted {
                await registerForRemoteNotifications()
            }
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    // MARK: - Remote Notifications (APNs)

    private func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        // Store APNs token for relay server registration
        UserDefaults.standard.set(token, forKey: "apnsDeviceToken")
    }

    func handleRegistrationError(_ error: Error) {
        // APNs registration failed — local notifications will be used as fallback
    }

    // MARK: - Category Registration

    private func registerCategories() {
        let allowAction = UNNotificationAction(
            identifier: NotificationAction.allow.rawValue,
            title: "Allow",
            options: [.authenticationRequired]
        )
        let denyAction = UNNotificationAction(
            identifier: NotificationAction.deny.rawValue,
            title: "Deny",
            options: [.destructive, .authenticationRequired]
        )

        let approvalCategory = UNNotificationCategory(
            identifier: NotificationCategory.approvalRequest.rawValue,
            actions: [allowAction, denyAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let sessionCategory = UNNotificationCategory(
            identifier: NotificationCategory.sessionEvent.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // Wave 5 — "Cool Beans" action on sprite /btw response notifications.
        let coolBeansAction = UNNotificationAction(
            identifier: NotificationAction.coolBeans.rawValue,
            title: "Cool Beans",
            options: []
        )
        let btwCategory = UNNotificationCategory(
            identifier: NotificationCategory.btwResponse.rawValue,
            actions: [coolBeansAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([approvalCategory, sessionCategory, btwCategory])
    }

    // MARK: - Local Notification Posting

    /// Post an approval request as a local notification.
    func postApprovalNotification(requestId: String, toolName: String, description: String) {
        let content = UNMutableNotificationContent()
        content.title = "Approval Required"
        content.subtitle = toolName
        content.body = description
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.approvalRequest.rawValue
        content.userInfo = [
            "requestId": requestId,
            "toolName": toolName,
            "deepLink": "majortom://approval/\(requestId)"
        ]
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "approval-\(requestId)",
            content: content,
            trigger: nil // Deliver immediately
        )

        center.add(request)
    }

    /// Post a session event notification (agent spawn/complete, session end).
    func postSessionEventNotification(
        title: String,
        body: String,
        eventType: String,
        sessionId: String? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.sessionEvent.rawValue
        content.userInfo = [
            "eventType": eventType,
            "deepLink": sessionId.map { "majortom://session/\($0)" } ?? "majortom://office"
        ]

        let request = UNNotificationRequest(
            identifier: "session-\(eventType)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    /// Post an agent spawn notification.
    func postAgentSpawnNotification(agentId: String, role: String, task: String) {
        postSessionEventNotification(
            title: "Agent Spawned",
            body: "\(role.capitalized): \(task)",
            eventType: "agent.spawn"
        )
    }

    /// Post an agent completion notification.
    func postAgentCompleteNotification(agentId: String, result: String) {
        postSessionEventNotification(
            title: "Agent Complete",
            body: result,
            eventType: "agent.complete"
        )
    }

    /// Post a `/btw` response notification (Wave 5).
    ///
    /// Only fires when the app is NOT in the active foreground state. Caller
    /// is expected to gate on `UIApplication.shared.applicationState != .active`.
    /// Title: `"[{role}] {spriteName}"`, body: first ~120 chars of the response.
    /// Carries session/subagent identifiers so the "Cool Beans" action can
    /// clear the matching unread state.
    func postBtwResponseNotification(
        sessionId: String,
        subagentId: String,
        role: String,
        spriteName: String,
        response: String
    ) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "[\(role)] \(spriteName)"
        content.body = Self.truncatedBody(response)
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.btwResponse.rawValue
        content.userInfo = [
            "sessionId": sessionId,
            "subagentId": subagentId,
            "deepLink": "majortom://office"
        ]

        let request = UNNotificationRequest(
            identifier: "btw-\(subagentId)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    private static func truncatedBody(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 120 else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 117)
        return String(trimmed[..<idx]) + "…"
    }

    /// Post a session end notification.
    func postSessionEndNotification(sessionId: String, costUsd: Double) {
        let costString = String(format: "$%.4f", costUsd)
        postSessionEventNotification(
            title: "Session Ended",
            body: "Total cost: \(costString)",
            eventType: "session.ended",
            sessionId: sessionId
        )
    }

    // MARK: - Badge Management

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func removeDeliveredNotification(id: String) {
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    func removeAllPendingApprovals() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Handle notification tapped or action button pressed while app is in foreground or background.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let requestId = userInfo["requestId"] as? String

        await MainActor.run {
            switch response.actionIdentifier {
            case NotificationAction.allow.rawValue:
                if let requestId {
                    onApprovalAction?(requestId, true)
                }

            case NotificationAction.deny.rawValue:
                if let requestId {
                    onApprovalAction?(requestId, false)
                }

            case NotificationAction.coolBeans.rawValue:
                // Wave 5 — clear the unread /btw state for the originating sprite.
                if let sessionId = userInfo["sessionId"] as? String,
                   let subagentId = userInfo["subagentId"] as? String {
                    onBtwCoolBeansAction?(sessionId, subagentId)
                }

            case UNNotificationDefaultActionIdentifier:
                // User tapped the notification — navigate to relevant screen
                if let deepLink = userInfo["deepLink"] as? String {
                    pendingDeepLink = NotificationDeepLink(url: deepLink)
                }

            default:
                break
            }
        }
    }

    /// Show notifications even when app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner + sound even when app is open
        [.banner, .sound, .badge]
    }
}

// MARK: - Deep Link Model

struct NotificationDeepLink: Equatable {
    let url: String

    var isApproval: Bool { url.starts(with: "majortom://approval/") }
    var isSession: Bool { url.starts(with: "majortom://session/") }
    var isOffice: Bool { url == "majortom://office" }

    var approvalRequestId: String? {
        guard isApproval else { return nil }
        return String(url.dropFirst("majortom://approval/".count))
    }

    var sessionId: String? {
        guard isSession else { return nil }
        return String(url.dropFirst("majortom://session/".count))
    }
}
