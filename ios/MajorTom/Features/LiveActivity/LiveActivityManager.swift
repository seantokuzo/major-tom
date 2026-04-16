import Foundation
import ActivityKit

// MARK: - Preferences

extension Notification.Name {
    /// Posted when `LiveActivityPreferences.isEnabled` actually changes.
    static let liveActivityPreferencesDidChange = Notification.Name("com.majortom.liveActivity.didChange")
}

/// User-facing toggle for Dynamic Island / Lock Screen Live Activities.
///
/// Default is OFF — activities are opt-in so the Dynamic Island doesn't persist
/// with a deep-link gesture that can be triggered inadvertently. When the user
/// flips this off, `LiveActivityManager` ends any currently running activities
/// so the shut-up is immediate, not "wait for the next session to end."
enum LiveActivityPreferences {
    private static let defaultsKey = "liveActivity.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set {
            guard newValue != UserDefaults.standard.bool(forKey: defaultsKey) else { return }
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: .liveActivityPreferencesDidChange, object: nil)
        }
    }
}

// MARK: - Live Activity Manager

/// Manages the lifecycle of Major Tom Live Activities on Lock Screen and Dynamic Island.
///
/// Supports multiple concurrent sessions, debounced updates (3-second batching for
/// non-urgent updates), and immediate push for approval requests.
@Observable
@MainActor
final class LiveActivityManager {

    // MARK: - State

    /// Whether Live Activities are supported and enabled on this device.
    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Active activities keyed by sessionId.
    private(set) var activities: [String: Activity<MajorTomActivityAttributes>] = [:]

    /// Per-session state snapshots driving ContentState updates.
    private var snapshots: [String: SessionSnapshot] = [:]

    /// Debounce tasks keyed by sessionId — cancelled and reset on each low-priority update.
    private var debounceTasks: [String: Task<Void, Never>] = [:]

    /// Debounce interval for non-urgent updates (seconds).
    private let debounceInterval: TimeInterval = 3.0

    // MARK: - Lifecycle

    /// Start a new Live Activity for the given session.
    func startActivity(for session: SessionInfo) async {
        guard isSupported else { return }
        // User-facing opt-in — default off. Avoids the Dynamic Island persisting
        // and its deep-link widget gesture being triggered inadvertently.
        guard LiveActivityPreferences.isEnabled else { return }

        // Prune orphaned snapshots that no longer have an active activity
        pruneOrphanedSnapshots()

        let sessionId = session.sessionId
        let sessionName = session.sessionName
        let workingDir = session.workingDir

        // End any existing activity for this session first
        await endActivity(for: sessionId)

        let snapshot = SessionSnapshot(
            sessionName: sessionName,
            startDate: Date()
        )
        snapshots[sessionId] = snapshot

        let attributes = MajorTomActivityAttributes(
            sessionId: sessionId,
            workingDir: workingDir
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: snapshot.contentState, staleDate: nil),
                pushType: nil  // Local updates only; APNs can be added later
            )
            activities[sessionId] = activity
        } catch {
            // Live Activity request failed — non-fatal, log silently
            snapshots.removeValue(forKey: sessionId)
        }
    }

    /// Update the Live Activity for a given session with new state.
    func updateActivity(for sessionId: String, state: MajorTomActivityAttributes.ContentState) async {
        guard let activity = activities[sessionId] else { return }
        await activity.update(.init(state: state, staleDate: nil))
    }

    /// End the Live Activity for a given session.
    func endActivity(for sessionId: String) async {
        debounceTasks[sessionId]?.cancel()
        debounceTasks.removeValue(forKey: sessionId)

        guard let activity = activities[sessionId] else { return }

        var finalSnapshot = snapshots[sessionId] ?? SessionSnapshot(sessionName: "Session", startDate: Date())
        finalSnapshot.status = "idle"
        let finalState = finalSnapshot.contentState

        await activity.end(
            .init(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate  // Dismiss from Lock Screen / DI immediately
        )

        activities.removeValue(forKey: sessionId)
        snapshots.removeValue(forKey: sessionId)
    }

    /// End all active Live Activities (e.g. on app termination or relay disconnect).
    func endAllActivities() async {
        let sessionIds = Array(activities.keys)
        for sessionId in sessionIds {
            await endActivity(for: sessionId)
        }
        // Prune any orphaned snapshots that survived (defensive)
        let activeIds = Set(activities.keys)
        let orphanedSnapshotKeys = Array(snapshots.keys.filter { !activeIds.contains($0) })
        for key in orphanedSnapshotKeys {
            snapshots.removeValue(forKey: key)
        }
    }

    /// Clean up any Live Activities that survived a prior app process — e.g. when
    /// the app was force-killed or crashed without calling `.end()`. Without this,
    /// activities can linger on Lock Screen / Dynamic Island for up to 8 hours.
    ///
    /// Call once on app launch. Enumerates `Activity<Attributes>.activities` which
    /// returns system-wide activities for this app, not just ones in our local dict.
    func cleanupOrphanedActivities() async {
        guard isSupported else { return }
        for activity in Activity<MajorTomActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activities.removeAll()
        snapshots.removeAll()
        for (_, task) in debounceTasks { task.cancel() }
        debounceTasks.removeAll()
    }

    /// Observe the user toggling Live Activities off — ends all running activities
    /// immediately so the shut-up is instant instead of "wait for the next session
    /// to end." Called once from app startup.
    func observePreferenceChanges() {
        NotificationCenter.default.addObserver(
            forName: .liveActivityPreferencesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if !LiveActivityPreferences.isEnabled {
                Task { @MainActor in
                    await self.endAllActivities()
                }
            }
        }
    }

    // MARK: - Terminal Session Events

    /// Update the Live Activity for an active terminal session.
    /// Called from TerminalView when terminal state changes (title, tab switch, etc.).
    func updateTerminalSession(sessionId: String, sessionName: String, tabCount: Int) {
        guard snapshots[sessionId] != nil else { return }
        snapshots[sessionId]!.sessionName = sessionName
        snapshots[sessionId]!.status = "active"
        snapshots[sessionId]!.activeAgents = tabCount
        snapshots[sessionId]!.latestTool = "shell"
        debouncedUpdate(for: sessionId)
    }

    // MARK: - Event Handlers

    /// Called when an agent spawns in a session.
    func handleAgentSpawn(sessionId: String, role: String) {
        guard snapshots[sessionId] != nil else { return }
        snapshots[sessionId]!.activeAgents += 1
        snapshots[sessionId]!.latestAgentRole = role
        debouncedUpdate(for: sessionId)
    }

    /// Called when an agent completes in a session.
    func handleAgentComplete(sessionId: String) {
        guard snapshots[sessionId] != nil else { return }
        snapshots[sessionId]!.activeAgents = max(0, snapshots[sessionId]!.activeAgents - 1)
        debouncedUpdate(for: sessionId)
    }

    /// Called when a tool starts executing.
    func handleToolStart(sessionId: String, toolName: String) {
        guard snapshots[sessionId] != nil else { return }
        snapshots[sessionId]!.latestTool = toolName
        snapshots[sessionId]!.status = "active"
        debouncedUpdate(for: sessionId)
    }

    /// Called when a tool completes.
    func handleToolComplete(sessionId: String) {
        guard snapshots[sessionId] != nil else { return }
        snapshots[sessionId]!.latestTool = nil
        debouncedUpdate(for: sessionId)
    }

    /// Called when session cost is updated.
    func handleCostUpdate(sessionId: String, costDollars: Double) {
        guard snapshots[sessionId] != nil else { return }
        snapshots[sessionId]!.costDollars = costDollars
        debouncedUpdate(for: sessionId)
    }

    /// Called when an approval request arrives — updates immediately (high priority).
    func handleApprovalRequest(sessionId: String, pendingCount: Int) {
        guard snapshots[sessionId] != nil else { return }
        snapshots[sessionId]!.pendingApprovals = pendingCount
        snapshots[sessionId]!.status = pendingCount > 0 ? "waiting" : "active"
        // Approval requests bypass debounce — update immediately
        immediateUpdate(for: sessionId)
    }

    /// Called when an approval is resolved.
    func handleApprovalResolved(sessionId: String, pendingCount: Int) {
        guard snapshots[sessionId] != nil else { return }
        snapshots[sessionId]!.pendingApprovals = pendingCount
        snapshots[sessionId]!.status = pendingCount > 0 ? "waiting" : "active"
        immediateUpdate(for: sessionId)
    }

    /// Called when the session ends.
    func handleSessionEnd(sessionId: String) {
        guard snapshots[sessionId] != nil else { return }
        snapshots[sessionId]!.status = "idle"
        Task {
            await endActivity(for: sessionId)
        }
    }

    // MARK: - Private — Cleanup

    /// Remove snapshots that have no corresponding active activity.
    private func pruneOrphanedSnapshots() {
        let activeIds = Set(activities.keys)
        let orphanedKeys = snapshots.keys.filter { !activeIds.contains($0) }
        for key in orphanedKeys {
            snapshots.removeValue(forKey: key)
            debounceTasks[key]?.cancel()
            debounceTasks.removeValue(forKey: key)
        }
    }

    // MARK: - Private — Update Dispatch

    /// Debounced update: batches rapid-fire state changes with a 3-second window.
    private func debouncedUpdate(for sessionId: String) {
        debounceTasks[sessionId]?.cancel()
        debounceTasks[sessionId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.debounceInterval ?? 3.0))
            guard !Task.isCancelled else { return }
            self?.immediateUpdate(for: sessionId)
        }
    }

    /// Immediate update: pushes current snapshot to the Live Activity right now.
    private func immediateUpdate(for sessionId: String) {
        guard let activity = activities[sessionId],
              var snapshot = snapshots[sessionId] else { return }

        // Update elapsed seconds from start date
        snapshot.elapsedSeconds = Int(Date().timeIntervalSince(snapshot.startDate))
        snapshots[sessionId] = snapshot

        let state = snapshot.contentState
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }
}

// MARK: - Session Snapshot

/// Internal state tracking for a single session's Live Activity.
private struct SessionSnapshot {
    var sessionName: String
    var startDate: Date
    var status: String = "active"
    var costDollars: Double = 0
    var pendingApprovals: Int = 0
    var activeAgents: Int = 0
    var latestTool: String?
    var latestAgentRole: String?
    var elapsedSeconds: Int = 0

    var contentState: MajorTomActivityAttributes.ContentState {
        .init(
            sessionName: sessionName,
            status: status,
            elapsedSeconds: elapsedSeconds,
            costDollars: costDollars,
            pendingApprovals: pendingApprovals,
            activeAgents: activeAgents,
            latestTool: latestTool
        )
    }
}

// MARK: - Session Info (input struct for startActivity)

/// Lightweight struct for passing session info to LiveActivityManager.
struct SessionInfo {
    let sessionId: String
    let sessionName: String
    let workingDir: String
}
