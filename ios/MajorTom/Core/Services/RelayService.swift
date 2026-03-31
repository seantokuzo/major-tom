import Foundation
import WidgetKit

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

    // Team / multi-user state
    var teamPresence: [UserPresence] = []
    var teamUsers: [TeamUser] = []
    var annotations: [String: [SessionAnnotation]] = [:]  // keyed by sessionId
    var activityEntries: [ActivityEntry] = []
    var currentUserRole: UserRole = .viewer
    var currentUserId: String?

    // Session-scoped allowlist (tool names auto-approved via "Always")
    var sessionAllowlist: Set<String> = []

    // Auto-approved tools log
    var autoApprovedTools: [AutoApprovedTool] = []

    /// Office view model — receives agent lifecycle events.
    var officeViewModel: OfficeViewModel?

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
                updateWidgetData()
            }

        case .agentSpawn:
            if let event = try? MessageCodec.decode(AgentSpawnEvent.self, from: data) {
                officeViewModel?.handleAgentSpawn(id: event.agentId, role: event.role, task: event.task)
                notificationService?.postAgentSpawnNotification(
                    agentId: event.agentId,
                    role: event.role,
                    task: event.task
                )
                if let sid = currentSession?.id {
                    liveActivityManager?.handleAgentSpawn(sessionId: sid, role: event.role)
                }
                updateWidgetData()
            }

        case .agentWorking:
            if let event = try? MessageCodec.decode(AgentWorkingEvent.self, from: data) {
                officeViewModel?.handleAgentWorking(id: event.agentId, task: event.task)
            }

        case .agentIdle:
            if let event = try? MessageCodec.decode(AgentIdleEvent.self, from: data) {
                officeViewModel?.handleAgentIdle(id: event.agentId)
            }

        case .agentComplete:
            if let event = try? MessageCodec.decode(AgentCompleteEvent.self, from: data) {
                officeViewModel?.handleAgentComplete(id: event.agentId, result: event.result)
                notificationService?.postAgentCompleteNotification(
                    agentId: event.agentId,
                    result: event.result
                )
                if let sid = currentSession?.id {
                    liveActivityManager?.handleAgentComplete(sessionId: sid)
                }
                updateWidgetData()
            }

        case .agentDismissed:
            if let event = try? MessageCodec.decode(AgentDismissedEvent.self, from: data) {
                officeViewModel?.handleAgentDismissed(id: event.agentId)
                if let sid = currentSession?.id {
                    liveActivityManager?.handleAgentComplete(sessionId: sid)
                }
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
                // Trigger office celebration for a random agent
                if let agentId = officeViewModel?.agents.filter({ $0.status == .working || $0.status == .idle }).randomElement()?.id {
                    officeViewModel?.handleAgentCelebration(id: agentId)
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
    }

    /// Push latest session state to the widget data store and watch.
    private func updateWidgetData() {
        let agentCount = officeViewModel?.agents.count ?? 0
        let activeAgents = officeViewModel?.agents.filter { $0.status == .working || $0.status == .spawning }.count ?? 0

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
            let agentCount = officeViewModel?.agents.count ?? 0
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
