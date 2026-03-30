import Foundation

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

    /// Live Activity service — updates Lock Screen and Dynamic Island.
    var liveActivityService: LiveActivityService?

    /// Callbacks for device list updates
    var onDeviceListUpdate: (([DeviceInfo]) -> Void)?

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
        liveActivityService?.endActivity()
        clearSessionState()
        WidgetDataProvider.updateSessionStatus(.init(
            isActive: false,
            activeAgentCount: 0,
            totalAgentCount: 0,
            costUsd: 0,
            isConnected: false
        ))
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
                // Start Live Activity for new session
                liveActivityService?.startActivity(
                    sessionId: event.sessionId,
                    workingDirectory: currentSession?.workingDir ?? "~"
                )
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
                liveActivityService?.handleCostUpdate(costUsd: event.costUsd)
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
                    liveActivityService?.handleSessionEnd()
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
                liveActivityService?.handleToolStart(toolName: event.tool)
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
                liveActivityService?.handleToolComplete()
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
                liveActivityService?.handleAgentSpawn(role: event.role)
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
                liveActivityService?.handleAgentComplete()
                updateWidgetData()
            }

        case .agentDismissed:
            if let event = try? MessageCodec.decode(AgentDismissedEvent.self, from: data) {
                officeViewModel?.handleAgentDismissed(id: event.agentId)
                liveActivityService?.handleAgentComplete()
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
    }

    /// Push latest session state to the widget data store.
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
