import Foundation
import ActivityKit

// MARK: - Live Activity Service

/// Manages the lifecycle of Major Tom Live Activities on Lock Screen and Dynamic Island.
///
/// TODO: Widget extension target setup required.
/// The actual rendering of the Live Activity (compact, expanded, Lock Screen views)
/// requires a separate Widget Extension target that imports ActivityKit and WidgetKit.
/// Create a target named "MajorTomLiveActivity" with a Widget that provides
/// `ActivityConfiguration(for: MajorTomActivityAttributes.self)`.
@Observable
@MainActor
final class LiveActivityService {
    /// Whether Live Activities are supported on this device.
    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// The currently running activity, if any.
    private(set) var currentActivity: Activity<MajorTomActivityAttributes>?

    /// Current session snapshot — updated on every relay event.
    private var snapshot = SessionActivitySnapshot()

    // MARK: - Lifecycle

    /// Start a new Live Activity for the given session.
    func startActivity(sessionId: String, workingDirectory: String) {
        guard isSupported else { return }

        // End any existing activity first
        endActivity()

        snapshot = SessionActivitySnapshot(sessionStartDate: Date())

        let attributes = MajorTomActivityAttributes(
            sessionId: sessionId,
            workingDirectory: workingDirectory
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: snapshot.contentState, staleDate: nil),
                pushType: nil // Use local updates; APNs push updates can be added later
            )
        } catch {
            // Live Activity request failed — non-fatal, just log
        }
    }

    /// End the current Live Activity.
    func endActivity() {
        guard let activity = currentActivity else { return }
        let finalState = snapshot.contentState

        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 300) // Keep on lock screen for 5 min
            )
        }

        currentActivity = nil
        snapshot = SessionActivitySnapshot()
    }

    // MARK: - Event Handlers

    /// Called when an agent spawns.
    func handleAgentSpawn(role: String) {
        snapshot.totalAgentCount += 1
        snapshot.activeAgentCount += 1
        snapshot.latestAgentRole = role
        updateActivity()
    }

    /// Called when an agent completes.
    func handleAgentComplete() {
        snapshot.activeAgentCount = max(0, snapshot.activeAgentCount - 1)
        updateActivity()
    }

    /// Called when a tool starts executing.
    func handleToolStart(toolName: String) {
        snapshot.currentTool = toolName
        updateActivity()
    }

    /// Called when a tool completes.
    func handleToolComplete() {
        snapshot.currentTool = nil
        updateActivity()
    }

    /// Called when session cost is updated.
    func handleCostUpdate(costUsd: Double) {
        snapshot.costUsd = costUsd
        updateActivity()
    }

    /// Called when the session ends.
    func handleSessionEnd() {
        snapshot.isActive = false
        endActivity()
    }

    // MARK: - Private

    private func updateActivity() {
        guard let activity = currentActivity else { return }

        Task {
            await activity.update(
                .init(state: snapshot.contentState, staleDate: nil)
            )
        }
    }
}
