import Foundation
import WidgetKit
import UIKit

@Observable
@MainActor
final class RelayService {
    // State exposed to views
    var connectionState: ConnectionState { webSocket.connectionState }
    var currentSession: RelaySession?
    var pendingApprovals: [ApprovalRequest] = []
    var chatMessages: [ChatMessage] = []
    var lastError: String? { webSocket.lastError }

    // Permission state
    var permissionMode: PermissionMode = .manual
    var delaySeconds: Int = 5
    var godSubMode: GodSubMode = .normal

    // Tool activity tracking
    var activeTools: [ToolActivity] = []
    var completedTools: [ToolActivity] = []

    // Session list
    var sessionList: [SessionMetaInfo] = []

    // Device list
    var deviceList: [DeviceInfo] = []

    // Session cost tracking
    var sessionCostUsd: Double = 0
    var sessionTurnCount: Int = 0
    var sessionInputTokens: Int = 0
    var sessionOutputTokens: Int = 0
    var sessionDurationMs: Int = 0

    // Workspace tree
    var workspaceFiles: [FileNode] = []

    /// Monotonic counter bumped on selected relay responses that update
    /// polled state (e.g., session info, session lists, workspace, filesystem).
    /// Poll loops can snapshot this before sending a request and break as soon
    /// as the value changes, which correctly handles empty-result responses
    /// for those message types.
    private(set) var responseCounter: UInt64 = 0

    // Context
    var contextFiles: [String] = []

    // Filesystem
    var fsEntries: [FsEntry] = []
    var fsCurrentPath: String = ""
    var fsFileContent: String?
    var fsError: String?

    // Fleet
    var fleetStatus: FleetStatus?
    weak var fleetViewModel: FleetViewModel?

    // Auth methods (fetched from relay)
    var authMethods: AuthMethods?

    // Team / multi-user state
    var teamPresence: [UserPresence] = []
    var teamUsers: [TeamUser] = []
    var annotations: [String: [SessionAnnotation]] = [:]  // keyed by sessionId
    var activityEntries: [ActivityEntry] = []
    var currentUserRole: UserRole = .viewer
    var currentUserId: String?

    // Audit log
    var auditEntries: [AuditEntryData] = []

    // Rate limit config
    var rateLimitRoles: [String: RateLimitRoleConfigData] = [:]
    var rateLimitUserOverrides: [String: RateLimitUserOverrideData] = [:]

    // Sandbox directory permissions (per-user paths)
    var userSandboxPaths: [String: [String]] = [:]

    // Git viewer state
    var gitBranch: String = ""
    var gitStatus: [GitStatusEntry] = []
    var gitLog: [GitLogEntry] = []
    var gitBranches: [GitBranchEntry] = []
    var gitDiff: String = ""
    var gitDiffPath: String?
    var gitDiffStaged: Bool = false
    var gitShowCommit: GitShowResponseEvent?
    var gitError: String?

    // GitHub viewer state
    var githubPullRequests: [GitHubPullRequestEntry] = []
    var githubIssues: [GitHubIssueEntry] = []
    var githubPullRequestDetail: GitHubPullRequestDetail?
    var githubIssueDetail: GitHubIssueDetail?
    var githubError: String?

    // CI viewer state
    var ciRuns: [CIRunEntry] = []
    var ciRunDetail: CIRunDetailEntry?
    var ciError: String?

    // Session-scoped allowlist (tool names auto-approved via "Always")
    var sessionAllowlist: Set<String> = []

    // Auto-approved tools log
    var autoApprovedTools: [AutoApprovedTool] = []

    /// Office scene manager — manages per-session OfficeViewModel + OfficeScene pairs.
    /// Agent.* and sprite.* events are routed to the session-specific OfficeViewModel.
    var officeSceneManager: OfficeSceneManager?

    /// Tab-Keyed Offices (Wave 3) — client-side cache of tabs registered with
    /// the relay. Populated by `tab.*` events; consumed by the Office Manager
    /// UI in a later wave. Present as a plain property mirror of the
    /// `sessionList` pattern (no back-reference / forwarding callbacks yet).
    let tabRegistryStore = TabRegistryStore()

    /// Auth service for token management
    var authService: AuthService?

    /// Notification service — posts local notifications for approvals and events.
    var notificationService: NotificationService?

    /// Live Activity manager — updates Lock Screen and Dynamic Island.
    var liveActivityManager: LiveActivityManager?

    /// Watch Connectivity service — forwards data to Apple Watch.
    var watchConnectivityService: PhoneWatchConnectivityService?

    /// Achievements view model — receives achievement events.
    var achievementsViewModel: AchievementsViewModel?

    /// Callbacks for device list updates
    var onDeviceListUpdate: (([DeviceInfo]) -> Void)?

    /// Multi-user callbacks
    var onPresenceUpdate: (([UserPresence]) -> Void)?
    var onAnnotationAdded: ((SessionAnnotation) -> Void)?
    var onActivityUpdate: (([ActivityEntry]) -> Void)?
    var onTeamUsersUpdate: (([TeamUser]) -> Void)?
    var onInviteGenerated: ((String, String) -> Void)?  // code, expiresAt
    var onHandoffResponse: ((Bool, String?) -> Void)?  // success, error
    var onUserRevoked: ((String, Bool) -> Void)?  // userId, success

    private let webSocket = WebSocketClient()

    init() {
        webSocket.onMessage = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.handleMessage(data)
            }
        }
    }

    // MARK: - Connection

    func connect(to urlString: String) async throws {
        // Ensure /ws path is appended for the relay WebSocket route
        let wsPath = urlString.hasSuffix("/ws") ? urlString : "\(urlString)/ws"
        guard let url = URL(string: "ws://\(wsPath)") else {
            throw WebSocketError.invalidURL
        }

        // Include session cookie for authentication if available
        if let cookie = authService?.sessionCookie {
            try await webSocket.connect(url: url, cookie: "mt-session=\(cookie)")
            return
        }

        try await webSocket.connect(url: url)
    }

    func disconnect() {
        webSocket.disconnect()
        currentSession = nil
        Task { await liveActivityManager?.endAllActivities() }
        clearSessionState()
        WidgetDataProvider.updateSessionStatus(.init(
            isActive: false,
            activeAgentCount: 0,
            totalAgentCount: 0,
            costUsd: 0,
            isConnected: false
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Auth Methods

    /// Fetch available authentication methods from the relay server.
    /// Call this early (when the relay URL is known) to adapt UI accordingly.
    func fetchAuthMethods(serverURL: String) async {
        let scheme = serverURL.contains("://") ? "" : "http://"
        let baseURL = "\(scheme)\(serverURL)"
        guard let url = URL(string: "\(baseURL)/auth/methods") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }
            let methods = try JSONDecoder().decode(AuthMethods.self, from: data)
            self.authMethods = methods
        } catch {
            // If the endpoint doesn't exist (older relay), default to nil
            // which means "show everything" for backwards compat
        }
    }

    // MARK: - Session

    func startSession(adapter: AdapterType = .cli, workingDir: String? = nil) async throws {
        let message = SessionStartMessage(adapter: adapter, workingDir: workingDir)
        try await webSocket.send(message)
    }

    func attachSession(id: String) async throws {
        let message = SessionAttachMessage(sessionId: id)
        try await webSocket.send(message)
    }

    func endSession() async throws {
        guard let session = currentSession else { return }
        let message = SessionEndMessage(sessionId: session.id)
        try await webSocket.send(message)
    }

    func requestSessionList() async throws {
        let message = SessionListRequestMessage()
        try await webSocket.send(message)
    }

    /// Tab-Keyed Offices (Wave 3) — ask the relay for the full list of
    /// registered tabs. Relay broadcasts `tab.list.response`, which is
    /// decoded into `tabRegistryStore` by the message router.
    func requestTabList() async throws {
        let message = TabListRequestMessage()
        try await webSocket.send(message)
    }

    // MARK: - Chat

    func sendPrompt(_ text: String, context: [String]? = nil) async throws {
        guard let session = currentSession else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        chatMessages.append(userMessage)

        var message = PromptMessage(sessionId: session.id, text: text)
        if let ctx = context, !ctx.isEmpty {
            message.context = ctx
        }
        try await webSocket.send(message)
    }

    // MARK: - Approvals

    func sendApproval(requestId: String, decision: ApprovalDecision) async throws {
        let message = ApprovalDecisionMessage(requestId: requestId, decision: decision)
        try await webSocket.send(message)
        pendingApprovals.removeAll { $0.id == requestId }

        // If "always", add to session allowlist
        if decision == .allowAlways {
            if let request = pendingApprovals.first(where: { $0.id == requestId }) ?? completedTools.last.map({ _ in pendingApprovals.first }).flatMap({ $0 }) {
                sessionAllowlist.insert(request.tool)
            }
        }

        // Update Live Activity with new pending count
        if let sid = currentSession?.id {
            liveActivityManager?.handleApprovalResolved(
                sessionId: sid,
                pendingCount: pendingApprovals.count
            )
        }

        // Update watch after approval removed
        updateWatchApprovals()
    }

    // MARK: - Cancel

    func cancelOperation() async throws {
        guard let session = currentSession else { return }
        let message = CancelMessage(sessionId: session.id)
        try await webSocket.send(message)
    }

    // MARK: - Permission Mode

    func setPermissionMode(_ mode: PermissionMode, delaySeconds: Int? = nil, godSubMode: GodSubMode? = nil) async throws {
        var message = SettingsApprovalMessage(mode: mode)
        message.delaySeconds = delaySeconds
        message.godSubMode = godSubMode
        try await webSocket.send(message)

        self.permissionMode = mode
        if let delay = delaySeconds { self.delaySeconds = delay }
        if let sub = godSubMode { self.godSubMode = sub }
    }

    // MARK: - Agent Messages

    func sendAgentMessage(sessionId: String, agentId: String, text: String) async throws {
        let message = AgentMessageMessage(sessionId: sessionId, agentId: agentId, text: text)
        try await webSocket.send(message)
    }

    /// Request current sprite mappings for a session from the relay.
    /// The relay responds with a `sprite.state` event containing all active links.
    func requestSpriteState(for sessionId: String) {
        let message = SpriteStateRequestMessage(sessionId: sessionId)
        Task {
            try? await webSocket.send(message)
        }
    }

    // MARK: - Sprite Messaging (Wave 4)

    /// Send a queued `/btw` sprite message to the relay.
    /// On WebSocket send failure, re-enqueue into the session's local pending
    /// queue so the next reconnect flush can retry — otherwise the sprite UI
    /// stays stuck in `.pending` forever.
    func sendSpriteMessage(_ message: QueuedSpriteMessage) async {
        let wire = SpriteMessageMessage(
            sessionId: message.sessionId,
            spriteHandle: message.spriteHandle,
            subagentId: message.subagentId,
            text: message.text,
            messageId: message.id
        )
        do {
            try await webSocket.send(wire)
        } catch {
            // Send failed (socket closed mid-send, I/O error, etc.). Re-enqueue
            // so the reconnect flush retries. Guard against duplicate enqueue
            // in case it was already persisted by the offline path.
            if let vm = officeSceneManager?.viewModel(for: message.sessionId),
               !vm.queuedSpriteMessages.contains(where: { $0.id == message.id }) {
                vm.queuedSpriteMessages.append(message)
            }
        }
    }

    /// Flush queued sprite messages for a session. Safe to call multiple
    /// times — drain is atomic per session.
    func flushQueuedSpriteMessages(for sessionId: String) {
        guard let vm = officeSceneManager?.viewModel(for: sessionId) else { return }
        let queued = vm.drainQueuedSpriteMessages()
        guard !queued.isEmpty else { return }
        Task {
            for message in queued {
                await sendSpriteMessage(message)
            }
        }
    }

    /// Flush queued messages across every active session (post-reconnect).
    func flushAllQueuedSpriteMessages() {
        guard let manager = officeSceneManager else { return }
        for sessionId in manager.offices.keys {
            flushQueuedSpriteMessages(for: sessionId)
        }
    }

    /// Short preview of a `/btw` response for the cross-session banner.
    /// Trims whitespace, drops newlines, truncates to 60 chars.
    private func bannerPreview(_ text: String) -> String {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if cleaned.count <= 60 { return cleaned }
        let idx = cleaned.index(cleaned.startIndex, offsetBy: 57)
        return String(cleaned[..<idx]) + "…"
    }

    // MARK: - Workspace & Context

    func requestWorkspaceTree(path: String? = nil) async throws {
        var message = WorkspaceTreeRequestMessage()
        message.path = path
        message.sessionId = currentSession?.id
        try await webSocket.send(message)
    }

    func addContext(path: String, type: ContextType) async throws {
        guard let session = currentSession else { return }
        let message = ContextAddMessage(sessionId: session.id, path: path, contextType: type)
        try await webSocket.send(message)
    }

    func removeContext(path: String) async throws {
        guard let session = currentSession else { return }
        let message = ContextRemoveMessage(sessionId: session.id, path: path)
        try await webSocket.send(message)
    }

    // MARK: - Device Management

    func requestDeviceList() async throws {
        let message = DeviceListRequestMessage()
        try await webSocket.send(message)
    }

    func revokeDevice(id: String) async throws {
        let message = DeviceRevokeRequestMessage(deviceId: id)
        try await webSocket.send(message)
    }

    // MARK: - Filesystem

    func fsLs(path: String) async throws {
        let message = FsLsRequestMessage(path: path)
        try await webSocket.send(message)
    }

    func fsReadFile(path: String) async throws {
        let message = FsReadFileRequestMessage(path: path)
        try await webSocket.send(message)
    }

    func fsCwd() async throws {
        let message = FsCwdRequestMessage()
        try await webSocket.send(message)
    }

    // MARK: - Fleet

    func requestFleetStatus() async throws {
        let message = FleetStatusRequestMessage()
        try await webSocket.send(message)
    }

    // MARK: - Team / Multi-User

    func requestUserList() async throws {
        let message = UserListRequestMessage()
        try await webSocket.send(message)
    }

    func generateInvite(role: UserRole) async throws {
        let message = UserInviteRequestMessage(role: role.rawValue)
        try await webSocket.send(message)
    }

    func revokeUser(userId: String) async throws {
        let message = UserRevokeRequestMessage(userId: userId)
        try await webSocket.send(message)
    }

    func updateUserRole(userId: String, role: UserRole) async throws {
        let message = UserUpdateRoleRequestMessage(userId: userId, role: role.rawValue)
        try await webSocket.send(message)
    }

    func addAnnotation(sessionId: String, text: String, turnIndex: Int? = nil, mentions: [String]? = nil) async throws {
        let message = AnnotationAddRequestMessage(sessionId: sessionId, turnIndex: turnIndex, text: text, mentions: mentions)
        try await webSocket.send(message)
    }

    func requestAnnotations(sessionId: String) async throws {
        let message = AnnotationListRequestMessage(sessionId: sessionId)
        try await webSocket.send(message)
    }

    func handoffSession(sessionId: String, toUserId: String) async throws {
        let message = SessionHandoffRequestMessage(sessionId: sessionId, toUserId: toUserId)
        try await webSocket.send(message)
    }

    func requestActivityFeed() async throws {
        let message = ActivityListRequestMessage()
        try await webSocket.send(message)
    }

    // MARK: - Audit & Rate Limits

    func queryAudit(startTime: String? = nil, endTime: String? = nil, userId: String? = nil, action: String? = nil, limit: Int? = nil) async throws {
        var message = AuditQueryRequestMessage()
        message.startTime = startTime
        message.endTime = endTime
        message.userId = userId
        message.action = action
        message.limit = limit
        try await webSocket.send(message)
    }

    func getRateLimitConfig() async throws {
        let message = RateLimitGetConfigRequestMessage()
        try await webSocket.send(message)
    }

    func setRoleRateLimit(role: String, promptsPerMinute: Int, approvalsPerMinute: Int) async throws {
        let message = RateLimitSetRoleLimitMessage(role: role, promptsPerMinute: promptsPerMinute, approvalsPerMinute: approvalsPerMinute)
        try await webSocket.send(message)
    }

    func setUserRateLimitOverride(userId: String, promptsPerMinute: Int? = nil, approvalsPerMinute: Int? = nil) async throws {
        var message = RateLimitSetUserOverrideMessage(userId: userId)
        message.promptsPerMinute = promptsPerMinute
        message.approvalsPerMinute = approvalsPerMinute
        try await webSocket.send(message)
    }

    func clearUserRateLimitOverride(userId: String) async throws {
        let message = RateLimitClearUserOverrideMessage(userId: userId)
        try await webSocket.send(message)
    }

    func watchSession(_ sessionId: String) async throws {
        let message = PresenceWatchMessage(sessionId: sessionId)
        try await webSocket.send(message)
    }

    func unwatchSession() async throws {
        let message = PresenceUnwatchMessage()
        try await webSocket.send(message)
    }

    func watchersForSession(_ sessionId: String) -> [UserPresence] {
        teamPresence.filter { $0.watchingSessionId == sessionId }
    }

    // MARK: - Sandbox Directory Permissions

    func getUserSandboxPaths(userId: String) async throws {
        let message = SandboxGetUserPathsMessage(userId: userId)
        try await webSocket.send(message)
    }

    func setUserSandboxPaths(userId: String, paths: [String]) async throws {
        let message = SandboxSetUserPathsMessage(userId: userId, paths: paths)
        try await webSocket.send(message)
    }

    func clearUserSandboxPaths(userId: String) async throws {
        let message = SandboxClearUserPathsMessage(userId: userId)
        try await webSocket.send(message)
    }

    // MARK: - Git

    func requestGitStatus() async throws {
        guard let sessionId = currentSession?.id else { return }
        gitError = nil
        let msg = GitStatusRequestMessage(sessionId: sessionId)
        try await webSocket.send(msg)
    }

    func requestGitDiff(path: String? = nil, staged: Bool? = nil) async throws {
        guard let sessionId = currentSession?.id else { return }
        gitError = nil
        gitDiff = ""
        gitDiffPath = path
        gitDiffStaged = staged ?? false
        let msg = GitDiffRequestMessage(sessionId: sessionId, path: path, staged: staged)
        try await webSocket.send(msg)
    }

    func requestGitLog(count: Int? = nil) async throws {
        guard let sessionId = currentSession?.id else { return }
        gitError = nil
        let msg = GitLogRequestMessage(sessionId: sessionId, count: count)
        try await webSocket.send(msg)
    }

    func requestGitBranches() async throws {
        guard let sessionId = currentSession?.id else { return }
        gitError = nil
        let msg = GitBranchesRequestMessage(sessionId: sessionId)
        try await webSocket.send(msg)
    }

    func requestGitShow(commitHash: String) async throws {
        guard let sessionId = currentSession?.id else { return }
        gitError = nil
        gitShowCommit = nil
        let msg = GitShowRequestMessage(sessionId: sessionId, commitHash: commitHash)
        try await webSocket.send(msg)
    }

    // MARK: - GitHub

    func requestGitHubPullRequests(state: String = "open") async throws {
        guard let sessionId = currentSession?.id else { return }
        githubError = nil
        let msg = GitHubPullRequestsRequestMessage(sessionId: sessionId, state: state)
        try await webSocket.send(msg)
    }

    func requestGitHubPullRequestDetail(number: Int) async throws {
        guard let sessionId = currentSession?.id else { return }
        githubError = nil
        githubPullRequestDetail = nil
        let msg = GitHubPullRequestDetailRequestMessage(sessionId: sessionId, number: number)
        try await webSocket.send(msg)
    }

    func requestGitHubIssues(state: String = "open") async throws {
        guard let sessionId = currentSession?.id else { return }
        githubError = nil
        let msg = GitHubIssuesRequestMessage(sessionId: sessionId, state: state)
        try await webSocket.send(msg)
    }

    func requestGitHubIssueDetail(number: Int) async throws {
        guard let sessionId = currentSession?.id else { return }
        githubError = nil
        githubIssueDetail = nil
        let msg = GitHubIssueDetailRequestMessage(sessionId: sessionId, number: number)
        try await webSocket.send(msg)
    }

    // MARK: - CI

    func requestCIRuns(branch: String? = nil) async throws {
        guard let sessionId = currentSession?.id else { return }
        ciError = nil
        let msg = CIRunsRequestMessage(sessionId: sessionId, branch: branch)
        try await webSocket.send(msg)
    }

    func requestCIRunDetail(runId: Int) async throws {
        guard let sessionId = currentSession?.id else { return }
        ciError = nil
        ciRunDetail = nil
        let msg = CIRunDetailRequestMessage(sessionId: sessionId, runId: runId)
        try await webSocket.send(msg)
    }

    // MARK: - Message Routing

    private func handleMessage(_ data: Data) {
        guard let type = MessageCodec.decodeType(from: data) else { return }

        switch type {
        case .output:
            if let event = try? MessageCodec.decode(OutputEvent.self, from: data) {
                appendOutput(event)
            }

        case .approvalRequest:
            if let event = try? MessageCodec.decode(ApprovalRequestEvent.self, from: data) {
                let request = ApprovalRequest(from: event)
                // Check session allowlist
                if sessionAllowlist.contains(event.tool) {
                    Task {
                        try? await sendApproval(requestId: event.requestId, decision: .allow)
                    }
                } else {
                    pendingApprovals.append(request)
                    // Post local notification for approval request
                    notificationService?.postApprovalNotification(
                        requestId: event.requestId,
                        toolName: event.tool,
                        description: event.description
                    )
                    // Update Live Activity immediately (high priority)
                    if let sid = currentSession?.id {
                        liveActivityManager?.handleApprovalRequest(
                            sessionId: sid,
                            pendingCount: pendingApprovals.count
                        )
                    }
                    // Forward to Apple Watch
                    updateWatchApprovals()
                    HapticService.notification(.warning)
                }
            }

        case .approvalAuto:
            if let event = try? MessageCodec.decode(ApprovalAutoEvent.self, from: data) {
                autoApprovedTools.append(AutoApprovedTool(
                    tool: event.tool,
                    description: event.description,
                    reason: event.reason,
                    timestamp: Date()
                ))
            }

        case .sessionInfo:
            if let event = try? MessageCodec.decode(SessionInfoEvent.self, from: data) {
                currentSession = RelaySession(
                    id: event.sessionId,
                    adapter: AdapterType(rawValue: event.adapter) ?? .cli,
                    startedAt: event.startedAt,
                    tokenUsage: event.tokenUsage
                )
                responseCounter &+= 1
                // Start Live Activity for new session.
                // workingDir may not be populated on sessionInfo; fall back to
                // fsCurrentPath, session list metadata, or "~".
                let resolvedDir = currentSession?.workingDir
                    ?? sessionList.first(where: { $0.id == event.sessionId })?.workingDirName
                    ?? (fsCurrentPath.isEmpty ? nil : fsCurrentPath)
                    ?? "~"
                let sessionInfo = SessionInfo(
                    sessionId: event.sessionId,
                    sessionName: resolvedDir.components(separatedBy: "/").last ?? "Session",
                    workingDir: resolvedDir
                )
                Task { await liveActivityManager?.startActivity(for: sessionInfo) }
                // Update widget data
                updateWidgetData()
            }

        case .sessionResult:
            if let event = try? MessageCodec.decode(SessionResultEvent.self, from: data) {
                sessionCostUsd = event.costUsd
                sessionTurnCount = event.numTurns
                sessionDurationMs = event.durationMs
                if let input = event.inputTokens { sessionInputTokens = input }
                if let output = event.outputTokens { sessionOutputTokens = output }
                // Update Live Activity cost
                if let sid = currentSession?.id {
                    liveActivityManager?.handleCostUpdate(sessionId: sid, costDollars: event.costUsd)
                }
                updateWidgetData()
            }

        case .sessionEnded:
            if let event = try? MessageCodec.decode(SessionEndedEvent.self, from: data) {
                if currentSession?.id == event.sessionId {
                    // Post session end notification
                    notificationService?.postSessionEndNotification(
                        sessionId: event.sessionId,
                        costUsd: sessionCostUsd
                    )
                    // End Live Activity
                    liveActivityManager?.handleSessionEnd(sessionId: event.sessionId)
                    currentSession = nil
                    updateWidgetData()
                }
                // Clean up the office entry — but only for legacy / synthetic
                // Offices whose key is this sessionId. Tab-backed Offices are
                // torn down by `tab.closed` after PTY grace expires; the
                // walk-off for the ending session is driven by
                // `tab.session.ended`, which has already fired by this point.
                let vm = officeSceneManager?.viewModel(for: event.sessionId)
                let isTabBacked = vm?.tabId != nil && vm?.tabId != event.sessionId
                if !isTabBacked {
                    officeSceneManager?.closeOffice(for: event.sessionId)
                }
            }

        case .sessionListResponse:
            if let event = try? MessageCodec.decode(SessionListResponseEvent.self, from: data) {
                sessionList = event.sessions
                responseCounter &+= 1
            }

        case .sessionHistory:
            // Handled by session management feature
            break

        case .toolStart:
            if let event = try? MessageCodec.decode(ToolStartEvent.self, from: data) {
                let activity = ToolActivity(
                    id: UUID().uuidString,
                    tool: event.tool,
                    input: event.input,
                    startedAt: Date()
                )
                activeTools.append(activity)

                let msg = ChatMessage(
                    role: .tool,
                    content: "Using \(event.tool)...",
                    toolName: event.tool,
                    toolStatus: .running
                )
                chatMessages.append(msg)
                // Update Live Activity with current tool
                if let sid = currentSession?.id {
                    liveActivityManager?.handleToolStart(sessionId: sid, toolName: event.tool)
                }
                // Wave 5: route per-sprite tool bubble when relay tags the event.
                // Tool events don't carry `tabId` on the wire; `ensureViewModel`
                // falls back via the session→tab cache populated by prior
                // sprite/agent events in the same session.
                if let subagentId = event.subagentId {
                    officeSceneManager?.ensureViewModel(for: event.sessionId)
                        .handleSpriteToolStart(
                            subagentId: subagentId,
                            toolUseId: event.toolUseId,
                            tool: event.tool,
                            input: event.input
                        )
                }
                updateWidgetData()
            }

        case .toolComplete:
            if let event = try? MessageCodec.decode(ToolCompleteEvent.self, from: data) {
                if let index = activeTools.lastIndex(where: { $0.tool == event.tool }) {
                    var completed = activeTools.remove(at: index)
                    completed.completedAt = Date()
                    completed.success = event.success
                    completed.output = event.output
                    completedTools.append(completed)
                }

                let status = event.success ? "completed" : "failed"
                let msg = ChatMessage(
                    role: .tool,
                    content: "\(event.tool) \(status)",
                    toolName: event.tool,
                    toolStatus: event.success ? .success : .failure,
                    toolOutput: event.output
                )
                chatMessages.append(msg)
                // Update Live Activity — tool finished
                if let sid = currentSession?.id {
                    liveActivityManager?.handleToolComplete(sessionId: sid)
                }
                // Wave 5: hide per-sprite tool bubble if relay tagged the event.
                // Tool events don't carry `tabId` on the wire; `ensureViewModel`
                // falls back via the session→tab cache populated by prior
                // sprite/agent events in the same session.
                if let subagentId = event.subagentId {
                    officeSceneManager?.ensureViewModel(for: event.sessionId)
                        .handleSpriteToolComplete(
                            subagentId: subagentId,
                            toolUseId: event.toolUseId
                        )
                }
                updateWidgetData()
            }

        case .agentSpawn:
            if let event = try? MessageCodec.decode(AgentSpawnEvent.self, from: data) {
                officeSceneManager?.ensureViewModel(for: event.sessionId, tabId: event.tabId).handleAgentSpawn(id: event.agentId, role: event.role, task: event.task, parentId: event.parentId)
                notificationService?.postAgentSpawnNotification(
                    agentId: event.agentId,
                    role: event.role,
                    task: event.task
                )
                liveActivityManager?.handleAgentSpawn(sessionId: event.sessionId, role: event.role)
                updateWidgetData()
            }

        case .agentWorking:
            if let event = try? MessageCodec.decode(AgentWorkingEvent.self, from: data) {
                officeSceneManager?.ensureViewModel(for: event.sessionId, tabId: event.tabId)
                    .handleAgentWorking(
                        id: event.agentId,
                        task: event.task,
                        toolCount: event.toolCount,
                        tokenCount: event.tokenCount
                    )
            }

        case .agentIdle:
            if let event = try? MessageCodec.decode(AgentIdleEvent.self, from: data) {
                officeSceneManager?.ensureViewModel(for: event.sessionId, tabId: event.tabId)
                    .handleAgentIdle(
                        id: event.agentId,
                        toolCount: event.toolCount,
                        tokenCount: event.tokenCount
                    )
            }

        case .agentComplete:
            if let event = try? MessageCodec.decode(AgentCompleteEvent.self, from: data) {
                officeSceneManager?.ensureViewModel(for: event.sessionId, tabId: event.tabId).handleAgentComplete(id: event.agentId, result: event.result)
                notificationService?.postAgentCompleteNotification(
                    agentId: event.agentId,
                    result: event.result
                )
                liveActivityManager?.handleAgentComplete(sessionId: event.sessionId)
                updateWidgetData()
            }

        case .agentDismissed:
            if let event = try? MessageCodec.decode(AgentDismissedEvent.self, from: data) {
                officeSceneManager?.ensureViewModel(for: event.sessionId, tabId: event.tabId).handleAgentDismissed(id: event.agentId)
                liveActivityManager?.handleAgentComplete(sessionId: event.sessionId)
                updateWidgetData()
            }

        case .connectionStatus:
            break

        case .permissionMode:
            if let event = try? MessageCodec.decode(PermissionModeEvent.self, from: data) {
                permissionMode = event.mode
                delaySeconds = event.delaySeconds
                godSubMode = event.godSubMode
            }

        case .notification:
            // Handled by notification service
            break

        case .workspaceTreeResponse:
            if let event = try? MessageCodec.decode(WorkspaceTreeResponseEvent.self, from: data) {
                workspaceFiles = event.files
                responseCounter &+= 1
            }

        case .contextAddResponse, .contextRemoveResponse:
            break

        case .deviceListResponse:
            if let event = try? MessageCodec.decode(DeviceListResponseEvent.self, from: data) {
                deviceList = event.devices
                onDeviceListUpdate?(event.devices)
                responseCounter &+= 1
            }

        case .deviceRevokeResponse:
            break

        case .fsLsResponse:
            if let event = try? MessageCodec.decode(FsLsResponseEvent.self, from: data) {
                fsEntries = event.entries
                fsCurrentPath = event.path
                fsError = nil
                responseCounter &+= 1
            }

        case .fsReadFileResponse:
            if let event = try? MessageCodec.decode(FsReadFileResponseEvent.self, from: data) {
                fsFileContent = event.content
                fsError = nil
                responseCounter &+= 1
            }

        case .fsCwdResponse:
            if let event = try? MessageCodec.decode(FsCwdResponseEvent.self, from: data) {
                fsCurrentPath = event.path
                fsError = nil
                responseCounter &+= 1
            }

        case .fsError:
            if let event = try? MessageCodec.decode(FsErrorEvent.self, from: data) {
                fsError = event.message
            }

        case .fleetStatusResponse:
            if let event = try? MessageCodec.decode(FleetStatusResponseEvent.self, from: data) {
                fleetStatus = FleetStatus(from: event)
                fleetViewModel?.handleFleetResponse(event)
                responseCounter &+= 1
            }

        case .fleetWorkerSpawned:
            if let event = try? MessageCodec.decode(FleetWorkerSpawnedEvent.self, from: data) {
                fleetViewModel?.handleWorkerSpawned(workerId: event.workerId, workingDir: event.workingDir)
                HapticService.notification(.success)
            }

        case .fleetWorkerCrashed:
            if let event = try? MessageCodec.decode(FleetWorkerCrashedEvent.self, from: data) {
                fleetViewModel?.handleWorkerCrashed(workerId: event.workerId)
                HapticService.notification(.error)
            }

        case .fleetWorkerRestarted:
            if let event = try? MessageCodec.decode(FleetWorkerRestartedEvent.self, from: data) {
                fleetViewModel?.handleWorkerRestarted(newWorkerId: event.workerId, workingDir: event.workingDir)
                HapticService.notification(.warning)
            }

        case .achievementUnlocked:
            if let event = try? MessageCodec.decode(AchievementUnlockedEvent.self, from: data) {
                achievementsViewModel?.handleAchievementUnlocked(event)
                // Trigger office celebration for a random agent in the current session
                if let sid = currentSession?.id,
                   let vm = officeSceneManager?.viewModel(for: sid),
                   let agentId = vm.agents.filter({ $0.status == .working || $0.status == .idle }).randomElement()?.id {
                    vm.handleAgentCelebration(id: agentId)
                }
            }

        case .achievementProgress:
            if let event = try? MessageCodec.decode(AchievementProgressEvent.self, from: data) {
                achievementsViewModel?.handleAchievementProgress(event)
            }

        case .achievementListResponse:
            // Handled via REST API — this WebSocket message is informational
            break

        case .presenceUpdate:
            if let event = try? MessageCodec.decode(PresenceUpdateEvent.self, from: data) {
                teamPresence = event.users.map { user in
                    UserPresence(
                        userId: user.userId,
                        email: user.email,
                        name: user.name,
                        picture: user.picture,
                        role: user.role,
                        connectedAt: user.connectedAt,
                        watchingSessionId: user.watchingSessionId
                    )
                }
                onPresenceUpdate?(teamPresence)
            }

        case .annotationAdded:
            if let event = try? MessageCodec.decode(AnnotationAddedEvent.self, from: data) {
                let annotation = SessionAnnotation(
                    id: event.annotation.id,
                    userId: event.annotation.userId,
                    userName: event.annotation.userName,
                    turnIndex: event.annotation.turnIndex,
                    text: event.annotation.text,
                    mentions: event.annotation.mentions,
                    createdAt: event.annotation.createdAt
                )
                var sessionAnnotations = annotations[event.sessionId] ?? []
                sessionAnnotations.append(annotation)
                annotations[event.sessionId] = sessionAnnotations
                onAnnotationAdded?(annotation)
            }

        case .annotationListResponse:
            if let event = try? MessageCodec.decode(AnnotationListResponseEvent.self, from: data) {
                annotations[event.sessionId] = event.annotations.map { data in
                    SessionAnnotation(
                        id: data.id,
                        userId: data.userId,
                        userName: data.userName,
                        turnIndex: data.turnIndex,
                        text: data.text,
                        mentions: data.mentions,
                        createdAt: data.createdAt
                    )
                }
                responseCounter &+= 1
            }

        case .sessionHandoffResponse:
            if let event = try? MessageCodec.decode(SessionHandoffResponseEvent.self, from: data) {
                onHandoffResponse?(event.success, event.error)
                if event.success {
                    HapticService.notification(.success)
                } else {
                    HapticService.notification(.error)
                }
            }

        case .activityFeed:
            if let event = try? MessageCodec.decode(ActivityFeedEvent.self, from: data) {
                activityEntries = event.entries.map { entry in
                    ActivityEntry(
                        id: entry.id,
                        userId: entry.userId,
                        userName: entry.userName,
                        action: entry.action,
                        sessionId: entry.sessionId,
                        timestamp: entry.timestamp
                    )
                }
                onActivityUpdate?(activityEntries)
                responseCounter &+= 1
            }

        case .userListResponse:
            if let event = try? MessageCodec.decode(UserListResponseEvent.self, from: data) {
                teamUsers = event.users.map { user in
                    TeamUser(
                        id: user.id,
                        email: user.email,
                        name: user.name,
                        picture: user.picture,
                        role: UserRole(rawValue: user.role) ?? .viewer,
                        isOnline: user.isOnline,
                        lastLoginAt: user.lastLoginAt
                    )
                }
                onTeamUsersUpdate?(teamUsers)
                responseCounter &+= 1
            }

        case .userInviteResponse:
            if let event = try? MessageCodec.decode(UserInviteResponseEvent.self, from: data) {
                if event.success, let code = event.code, let expiresAt = event.expiresAt {
                    onInviteGenerated?(code, expiresAt)
                    HapticService.notification(.success)
                }
            }

        case .userRevokeResponse:
            if let event = try? MessageCodec.decode(UserRevokeResponseEvent.self, from: data) {
                if event.success {
                    teamUsers.removeAll { $0.id == event.userId }
                }
                onUserRevoked?(event.userId, event.success)
            }

        case .userRoleUpdated:
            if let event = try? MessageCodec.decode(UserRoleUpdatedEvent.self, from: data) {
                if let index = teamUsers.firstIndex(where: { $0.id == event.userId }) {
                    let updated = TeamUser(
                        id: teamUsers[index].id,
                        email: teamUsers[index].email,
                        name: teamUsers[index].name,
                        picture: teamUsers[index].picture,
                        role: UserRole(rawValue: event.role) ?? teamUsers[index].role,
                        isOnline: teamUsers[index].isOnline,
                        lastLoginAt: teamUsers[index].lastLoginAt
                    )
                    teamUsers[index] = updated
                }
                // Update our own role if it changed
                if event.userId == currentUserId {
                    currentUserRole = UserRole(rawValue: event.role) ?? currentUserRole
                }
            }

        case .approvalResolved:
            if let event = try? MessageCodec.decode(ApprovalResolvedEvent.self, from: data) {
                // Remove from pending if resolved by another user
                pendingApprovals.removeAll { $0.id == event.requestId }
                let resolverName = event.resolvedBy.name ?? "teammate"
                let msg = ChatMessage(
                    role: .system,
                    content: "\(resolverName) \(event.decision) the request"
                )
                chatMessages.append(msg)
            }

        case .sandboxUserPaths:
            if let event = try? MessageCodec.decode(SandboxUserPathsResponseEvent.self, from: data) {
                userSandboxPaths[event.userId] = event.paths
            }

        case .auditResponse:
            if let event = try? MessageCodec.decode(AuditQueryResponseEvent.self, from: data) {
                auditEntries = event.entries
                responseCounter &+= 1
            }

        case .rateLimitConfig:
            if let event = try? MessageCodec.decode(RateLimitConfigResponseEvent.self, from: data) {
                rateLimitRoles = event.roles
                rateLimitUserOverrides = event.userOverrides
                responseCounter &+= 1
            }

        case .gitStatusResponse:
            if let event = try? MessageCodec.decode(GitStatusResponseEvent.self, from: data) {
                gitBranch = event.branch
                gitStatus = event.entries
                responseCounter &+= 1
            }

        case .gitDiffResponse:
            if let event = try? MessageCodec.decode(GitDiffResponseEvent.self, from: data) {
                gitDiff = event.diff
                gitDiffPath = event.path
                gitDiffStaged = event.staged
                responseCounter &+= 1
            }

        case .gitLogResponse:
            if let event = try? MessageCodec.decode(GitLogResponseEvent.self, from: data) {
                gitLog = event.entries
                responseCounter &+= 1
            }

        case .gitBranchesResponse:
            if let event = try? MessageCodec.decode(GitBranchesResponseEvent.self, from: data) {
                gitBranches = event.branches
                responseCounter &+= 1
            }

        case .gitShowResponse:
            if let event = try? MessageCodec.decode(GitShowResponseEvent.self, from: data) {
                gitShowCommit = event
                responseCounter &+= 1
            }

        case .gitError:
            if let event = try? MessageCodec.decode(GitErrorEvent.self, from: data) {
                gitError = event.message
                responseCounter &+= 1
            }

        case .githubPullRequestsResponse:
            if let event = try? MessageCodec.decode(GitHubPullRequestsResponseEvent.self, from: data) {
                githubPullRequests = event.pullRequests
                responseCounter &+= 1
            }

        case .githubPullRequestDetailResponse:
            if let event = try? MessageCodec.decode(GitHubPullRequestDetailResponseEvent.self, from: data) {
                githubPullRequestDetail = event.detail
                responseCounter &+= 1
            }

        case .githubIssuesResponse:
            if let event = try? MessageCodec.decode(GitHubIssuesResponseEvent.self, from: data) {
                githubIssues = event.issues
                responseCounter &+= 1
            }

        case .githubIssueDetailResponse:
            if let event = try? MessageCodec.decode(GitHubIssueDetailResponseEvent.self, from: data) {
                githubIssueDetail = event.detail
                responseCounter &+= 1
            }

        case .githubError:
            if let event = try? MessageCodec.decode(GitHubErrorEvent.self, from: data) {
                githubError = event.message
                responseCounter &+= 1
            }

        case .ciRunsResponse:
            if let event = try? MessageCodec.decode(CIRunsResponseEvent.self, from: data) {
                ciRuns = event.runs
                responseCounter &+= 1
            }

        case .ciRunDetailResponse:
            if let event = try? MessageCodec.decode(CIRunDetailResponseEvent.self, from: data) {
                ciRunDetail = event.run
                responseCounter &+= 1
            }

        case .ciError:
            if let event = try? MessageCodec.decode(CIErrorEvent.self, from: data) {
                ciError = event.message
                responseCounter &+= 1
            }

        // MARK: Sprite-Agent Wiring (Wave 2)

        case .spriteLink:
            if let event = try? MessageCodec.decode(SpriteLinkEvent.self, from: data) {
                officeSceneManager?.ensureViewModel(for: event.sessionId, tabId: event.tabId).handleSpriteLink(event)
            }

        case .spriteUnlink:
            if let event = try? MessageCodec.decode(SpriteUnlinkEvent.self, from: data) {
                officeSceneManager?.ensureViewModel(for: event.sessionId, tabId: event.tabId).handleSpriteUnlink(event)
            }

        case .spriteState:
            if let event = try? MessageCodec.decode(SpriteStateEvent.self, from: data) {
                officeSceneManager?.ensureViewModel(for: event.sessionId, tabId: event.tabId).handleSpriteState(event)
            }

        case .spriteResponse:
            if let event = try? MessageCodec.decode(SpriteResponseEvent.self, from: data) {
                let vm = officeSceneManager?.ensureViewModel(for: event.sessionId, tabId: event.tabId)
                vm?.handleSpriteResponse(event)

                // Only `delivered`/`dropped` affect UI; `queued` is informational.
                if event.status == "delivered" || event.status == "dropped" {
                    if currentSession?.id == event.sessionId {
                        HapticService.notification(.success)
                    } else {
                        // Cross-session (M2) — show banner unless the inspector
                        // for this sprite is open elsewhere (can't happen in
                        // our single-open-inspector model, so we just surface).
                        let sessionName = sessionList
                            .first(where: { $0.id == event.sessionId })?.workingDirName
                            ?? "Terminal"
                        let spriteId = vm?.agents.first(where: {
                            $0.linkedSubagentId == event.subagentId
                        })?.id ?? event.subagentId
                        let spriteName = vm?.agents.first(where: { $0.id == spriteId })?.name
                            ?? "\(event.subagentId.prefix(8))…"
                        // Dropped responses have empty `text` on the wire — use the
                        // synthesized text (matches OfficeViewModel.handleSpriteResponse)
                        // so the banner preview isn't empty/misleading.
                        let previewSource: String = event.status == "dropped"
                            ? (event.dropReason.map { "(Agent completed before delivery — \($0))" }
                                ?? "(Agent completed before delivery)")
                            : event.text
                        officeSceneManager?.showCrossSessionBanner(
                            sessionId: event.sessionId,
                            sessionName: sessionName,
                            spriteId: spriteId,
                            spriteName: String(spriteName),
                            preview: bannerPreview(previewSource)
                        )
                    }

                    // Wave 5 — local push when the app isn't in the active
                    // foreground. Best-effort during iOS backgrounding grace
                    // window (~10s); relay re-queues beyond that.
                    postBtwResponseNotificationIfBackgrounded(event: event, vm: vm)
                }
            }

        // MARK: Tab-Keyed Offices (Wave 3)

        case .tabSessionStarted:
            if let event = try? MessageCodec.decode(TabSessionStartedEvent.self, from: data) {
                tabRegistryStore.apply(started: event)
                officeSceneManager?.handleTabSessionStarted(
                    tabId: event.tabId,
                    sessionId: event.sessionId
                )
            }

        case .tabSessionEnded:
            if let event = try? MessageCodec.decode(TabSessionEndedEvent.self, from: data) {
                tabRegistryStore.apply(ended: event)
                officeSceneManager?.handleTabSessionEnded(
                    tabId: event.tabId,
                    sessionId: event.sessionId
                )
            }

        case .tabClosed:
            if let event = try? MessageCodec.decode(TabClosedEvent.self, from: data) {
                tabRegistryStore.remove(tabId: event.tabId)
                officeSceneManager?.closeOffice(for: event.tabId)
            }

        case .tabListResponse:
            if let event = try? MessageCodec.decode(TabListResponseEvent.self, from: data) {
                tabRegistryStore.replaceAll(with: event)
                responseCounter &+= 1
            }

        case .error:
            if let event = try? MessageCodec.decode(ErrorEvent.self, from: data) {
                let msg = ChatMessage(role: .system, content: "Error: \(event.message)")
                chatMessages.append(msg)
            }

        default:
            break
        }
    }

    private func appendOutput(_ event: OutputEvent) {
        if let last = chatMessages.last, last.role == .assistant {
            chatMessages[chatMessages.count - 1].content += event.chunk
        } else {
            let msg = ChatMessage(role: .assistant, content: event.chunk)
            chatMessages.append(msg)
        }
    }

    /// Wave 5 — post a local `/btw` response notification if the app is NOT
    /// in the active foreground state. Delivered responses only (dropped
    /// responses don't need a push, user will see the green glow on return).
    private func postBtwResponseNotificationIfBackgrounded(
        event: SpriteResponseEvent,
        vm: OfficeViewModel?
    ) {
        guard event.status == "delivered" else { return }
        guard UIApplication.shared.applicationState != .active else { return }

        let agent = vm?.agents.first(where: {
            $0.linkedSubagentId == event.subagentId || $0.id == event.subagentId
        })
        let role = agent?.canonicalRole ?? agent?.role ?? "agent"
        let spriteName = agent?.name ?? String(event.subagentId.prefix(8))
        notificationService?.postBtwResponseNotification(
            sessionId: event.sessionId,
            subagentId: event.subagentId,
            role: role,
            spriteName: spriteName,
            response: event.text
        )
    }

    private func clearSessionState() {
        pendingApprovals = []
        activeTools = []
        completedTools = []
        sessionAllowlist = []
        autoApprovedTools = []
        sessionCostUsd = 0
        sessionTurnCount = 0
        sessionInputTokens = 0
        sessionOutputTokens = 0
        sessionDurationMs = 0
        teamPresence = []
        annotations = [:]
        activityEntries = []
        auditEntries = []
        rateLimitRoles = [:]
        rateLimitUserOverrides = [:]
        gitBranch = ""
        gitStatus = []
        gitLog = []
        gitBranches = []
        gitDiff = ""
        gitDiffPath = nil
        gitDiffStaged = false
        gitShowCommit = nil
        gitError = nil
        githubPullRequests = []
        githubIssues = []
        githubPullRequestDetail = nil
        githubIssueDetail = nil
        githubError = nil
        ciRuns = []
        ciRunDetail = nil
        ciError = nil
    }

    /// Push latest session state to the widget data store and watch.
    private func updateWidgetData() {
        let currentVM = currentSession.flatMap { officeSceneManager?.viewModel(for: $0.id) }
        let agentCount = currentVM?.agents.count ?? 0
        let activeAgents = currentVM?.agents.filter { $0.status == .working || $0.status == .spawning }.count ?? 0

        WidgetDataProvider.updateSessionStatus(.init(
            isActive: currentSession != nil,
            activeAgentCount: activeAgents,
            totalAgentCount: agentCount,
            costUsd: sessionCostUsd,
            currentTool: activeTools.last?.tool,
            sessionStartDate: currentSession?.startDate,
            isConnected: connectionState == .connected,
            workingDirectory: currentSession?.workingDir
        ))

        // Write session list for medium/large widgets
        let currentId = currentSession?.id
        var summaries: [WidgetSessionSummary] = sessionList.map { meta in
            WidgetSessionSummary(
                id: meta.id,
                name: meta.workingDirName,
                status: meta.status,
                costUsd: meta.totalCost,
                agentCount: meta.id == currentId ? agentCount : 0,
                startedAt: meta.startedAt
            )
        }

        // Include current session if not already in list
        if let session = currentSession,
           !summaries.contains(where: { $0.id == session.id })
        {
            summaries.insert(WidgetSessionSummary(
                id: session.id,
                name: session.workingDir ?? "Session",
                status: "active",
                costUsd: sessionCostUsd,
                agentCount: agentCount,
                startedAt: ISO8601DateFormatter().string(from: session.startDate ?? Date())
            ), at: 0)
        }

        WidgetDataProvider.updateSessions(summaries)

        // Aggregate cost
        let totalCost = summaries.reduce(0.0) { $0 + $1.costUsd }
        WidgetDataProvider.updateTotalCost(totalCost)

        // Fleet health
        if let fleet = fleetStatus {
            let unhealthy = fleet.workers.filter { !$0.healthy }.count
            let health: String
            if fleet.workers.isEmpty {
                health = "offline"
            } else if unhealthy == 0 {
                health = "healthy"
            } else if unhealthy < fleet.workers.count {
                health = "degraded"
            } else {
                health = "offline"
            }
            WidgetDataProvider.updateFleetHealth(health)
        }

        // Siri Shortcuts: fleet snapshot
        if let fleet = fleetStatus {
            let activeSessions = fleet.workers.flatMap(\.sessions).filter { $0.status == "active" }.count
            WidgetDataProvider.updateFleetSnapshot(
                workerCount: fleet.totalWorkers,
                totalCost: fleet.aggregateCost,
                activeSessionCount: activeSessions
            )
        } else {
            WidgetDataProvider.updateFleetSnapshot(
                workerCount: 0,
                totalCost: totalCost,
                activeSessionCount: summaries.filter { $0.status == "active" }.count
            )
        }

        // Siri Shortcuts: pending approval (most recent)
        if let latest = pendingApprovals.last {
            WidgetDataProvider.updatePendingApproval(
                id: latest.id,
                tool: latest.tool,
                description: latest.description
            )
        } else {
            WidgetDataProvider.updatePendingApproval(id: nil, tool: nil, description: nil)
        }

        // Siri Shortcuts: active session summary
        let sessionName: String = {
            guard let dir = currentSession?.workingDir, !dir.isEmpty else { return "No Session" }
            let last = URL(fileURLWithPath: dir).lastPathComponent
            return last.isEmpty ? "No Session" : last
        }()
        WidgetDataProvider.updateSessionSummary(
            name: sessionName,
            costUsd: sessionCostUsd,
            tokensIn: sessionInputTokens,
            tokensOut: sessionOutputTokens,
            durationMs: sessionDurationMs,
            turnCount: sessionTurnCount
        )

        // Siri Shortcuts: current permission mode
        WidgetDataProvider.updatePermissionMode(permissionMode.rawValue)

        // Single timeline reload after all widget data is written
        WidgetCenter.shared.reloadAllTimelines()

        updateWatchData()
    }

    /// Forward current state to the Apple Watch.
    private func updateWatchData() {
        guard let watchService = watchConnectivityService else { return }

        // Build watch sessions from session list or current session
        var watchSessions: [WatchSession] = sessionList.map { meta in
            WatchSession(
                id: meta.id,
                name: meta.workingDirName,
                workingDir: meta.workingDirName,
                status: meta.status == "active" ? .active : (meta.status == "error" ? .error : .idle),
                agentCount: 0,
                cost: meta.totalCost,
                startedAt: ISO8601DateFormatter().date(from: meta.startedAt)
            )
        }

        // Include current session if not in list
        if let session = currentSession,
           !watchSessions.contains(where: { $0.id == session.id })
        {
            let agentCount = officeSceneManager?.viewModel(for: session.id)?.agents.count ?? 0
            let watchSession = WatchSession(
                id: session.id,
                name: session.workingDir ?? "Session",
                workingDir: session.workingDir ?? "~",
                status: pendingApprovals.isEmpty ? .active : .waiting,
                agentCount: agentCount,
                cost: sessionCostUsd,
                startedAt: session.startDate
            )
            watchSessions.insert(watchSession, at: 0)
        }

        // Fleet summary
        var fleetSummary: WatchFleetSummary?
        if let fleet = fleetStatus {
            fleetSummary = WatchFleetSummary(
                totalWorkers: fleet.totalWorkers,
                healthyWorkers: fleet.workers.filter(\.healthy).count,
                totalCostToday: fleet.aggregateCost
            )
        }

        watchService.updateContext(
            sessions: watchSessions,
            fleetSummary: fleetSummary,
            isRelayConnected: connectionState == .connected,
            latestToolName: activeTools.last?.tool ?? completedTools.last?.tool,
            latestToolStatus: activeTools.last != nil ? "running" : (completedTools.last?.success == true ? "completed" : nil)
        )
    }

    /// Forward pending approvals to the Apple Watch.
    private func updateWatchApprovals() {
        guard let watchService = watchConnectivityService else { return }

        let watchApprovals = pendingApprovals.map { request in
            WatchApprovalRequest(
                id: request.id,
                toolName: request.tool,
                description: request.description,
                dangerLevel: {
                    switch request.dangerLevel {
                    case .high: return .dangerous
                    case .medium: return .moderate
                    case .normal: return .safe
                    }
                }(),
                fileOrCommand: request.command ?? request.filePath
            )
        }

        watchService.sendApprovalRequests(watchApprovals)
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date
    var toolName: String?
    var toolStatus: ToolStatus?
    var toolOutput: String?
    var isCollapsed: Bool = true

    init(
        role: ChatRole,
        content: String,
        toolName: String? = nil,
        toolStatus: ToolStatus? = nil,
        toolOutput: String? = nil,
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolName = toolName
        self.toolStatus = toolStatus
        self.toolOutput = toolOutput
    }
}

enum ChatRole {
    case user
    case assistant
    case tool
    case system
}

enum ToolStatus {
    case running
    case success
    case failure
}

// MARK: - Tool Activity

struct ToolActivity: Identifiable {
    let id: String
    let tool: String
    let input: [String: AnyCodableValue]?
    let startedAt: Date
    var completedAt: Date?
    var success: Bool?
    var output: String?

    var isRunning: Bool { completedAt == nil }

    var duration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }
}

// MARK: - Auto-approved tool

struct AutoApprovedTool: Identifiable {
    let id = UUID()
    let tool: String
    let description: String
    let reason: AutoApprovalReason
    let timestamp: Date
}
