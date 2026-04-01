import Foundation

// MARK: - Message Type Routing

enum MessageType: String, Codable {
    // Client → Server
    case prompt
    case approval
    case cancel
    case sessionStart = "session.start"
    case sessionAttach = "session.attach"
    case sessionEnd = "session.end"
    case sessionList = "session.list"
    case agentMessage = "agent.message"
    case workspaceTree = "workspace.tree"
    case contextAdd = "context.add"
    case contextRemove = "context.remove"
    case settingsApproval = "settings.approval"
    case deviceList = "device.list"
    case deviceRevoke = "device.revoke"
    case fsLs = "fs.ls"
    case fsReadFile = "fs.readFile"
    case fsCwd = "fs.cwd"
    case fleetStatus = "fleet.status"
    case presenceWatch = "presence.watch"
    case presenceUnwatch = "presence.unwatch"
    case userList = "user.list"
    case userInvite = "user.invite"
    case userRevoke = "user.revoke"
    case userUpdateRole = "user.updateRole"
    case annotationAdd = "annotation.add"
    case annotationList = "annotation.list"
    case sessionHandoff = "session.handoff"
    case activityList = "activity.list"
    case sandboxGetUserPaths = "sandbox.getUserPaths"
    case sandboxSetUserPaths = "sandbox.setUserPaths"
    case sandboxClearUserPaths = "sandbox.clearUserPaths"
    case auditQuery = "audit.query"
    case rateLimitGetConfig = "rateLimit.getConfig"
    case rateLimitSetRoleLimit = "rateLimit.setRoleLimit"
    case rateLimitSetUserOverride = "rateLimit.setUserOverride"
    case rateLimitClearUserOverride = "rateLimit.clearUserOverride"
    case gitStatus = "git.status"
    case gitDiff = "git.diff"
    case gitLog = "git.log"
    case gitBranches = "git.branches"
    case gitShow = "git.show"
    case githubPullRequests = "github.pullRequests"
    case githubPullRequestDetail = "github.pullRequest.detail"
    case githubIssues = "github.issues"
    case githubIssueDetail = "github.issue.detail"

    // Server → Client
    case output
    case approvalRequest = "approval.request"
    case approvalAuto = "approval.auto"
    case toolStart = "tool.start"
    case toolComplete = "tool.complete"
    case agentSpawn = "agent.spawn"
    case agentWorking = "agent.working"
    case agentIdle = "agent.idle"
    case agentComplete = "agent.complete"
    case agentDismissed = "agent.dismissed"
    case connectionStatus = "connection.status"
    case sessionInfo = "session.info"
    case sessionResult = "session.result"
    case sessionEnded = "session.ended"
    case sessionListResponse = "session.list.response"
    case sessionHistory = "session.history"
    case workspaceTreeResponse = "workspace.tree.response"
    case contextAddResponse = "context.add.response"
    case contextRemoveResponse = "context.remove.response"
    case permissionMode = "permission.mode"
    case notification
    case deviceListResponse = "device.list.response"
    case deviceRevokeResponse = "device.revoke.response"
    case fsLsResponse = "fs.ls.response"
    case fsReadFileResponse = "fs.readFile.response"
    case fsCwdResponse = "fs.cwd.response"
    case fsError = "fs.error"
    case fleetStatusResponse = "fleet.status.response"
    case fleetWorkerSpawned = "fleet.worker.spawned"
    case fleetWorkerCrashed = "fleet.worker.crashed"
    case fleetWorkerRestarted = "fleet.worker.restarted"
    case achievementUnlocked = "achievement.unlocked"
    case achievementProgress = "achievement.progress"
    case achievementListResponse = "achievement.list.response"
    case presenceUpdate = "presence.update"
    case annotationAdded = "annotation.added"
    case annotationListResponse = "annotation.list.response"
    case sessionHandoffResponse = "session.handoff.response"
    case activityFeed = "activity.feed"
    case userListResponse = "user.list.response"
    case userInviteResponse = "user.invite.response"
    case userRevokeResponse = "user.revoke.response"
    case userRoleUpdated = "user.roleUpdated"
    case approvalResolved = "approval.resolved"
    case sandboxUserPaths = "sandbox.userPaths"
    case auditResponse = "audit.response"
    case rateLimitConfig = "rateLimit.config"
    case gitStatusResponse = "git.status.response"
    case gitDiffResponse = "git.diff.response"
    case gitLogResponse = "git.log.response"
    case gitBranchesResponse = "git.branches.response"
    case gitShowResponse = "git.show.response"
    case gitError = "git.error"
    case githubPullRequestsResponse = "github.pullRequests.response"
    case githubPullRequestDetailResponse = "github.pullRequest.detail.response"
    case githubIssuesResponse = "github.issues.response"
    case githubIssueDetailResponse = "github.issue.detail.response"
    case githubError = "github.error"
    case error
}

// MARK: - Client → Server Messages

struct PromptMessage: Codable {
    let type: String = "prompt"
    let sessionId: String
    let text: String
    var context: [String]?
}

struct ApprovalDecisionMessage: Codable {
    let type: String = "approval"
    let requestId: String
    let decision: ApprovalDecision
    var toolUseId: String?
}

enum ApprovalDecision: String, Codable {
    case allow
    case deny
    case skip
    case allowAlways = "allow_always"
}

struct CancelMessage: Codable {
    let type: String = "cancel"
    let sessionId: String
}

struct SessionStartMessage: Codable {
    let type: String = "session.start"
    let adapter: AdapterType
    var workingDir: String?
}

enum AdapterType: String, Codable {
    case cli
    case vscode
}

struct SessionAttachMessage: Codable {
    let type: String = "session.attach"
    let sessionId: String
}

struct SessionEndMessage: Codable {
    let type: String = "session.end"
    let sessionId: String
}

struct SessionListRequestMessage: Codable {
    let type: String = "session.list"
}

struct AgentMessageMessage: Codable {
    let type: String = "agent.message"
    let sessionId: String
    let agentId: String
    let text: String
}

struct WorkspaceTreeRequestMessage: Codable {
    let type: String = "workspace.tree"
    var path: String?
    var sessionId: String?
}

struct ContextAddMessage: Codable {
    let type: String = "context.add"
    let sessionId: String
    let path: String
    let contextType: ContextType
}

struct ContextRemoveMessage: Codable {
    let type: String = "context.remove"
    let sessionId: String
    let path: String
}

enum ContextType: String, Codable {
    case file
    case folder
}

struct SettingsApprovalMessage: Codable {
    let type: String = "settings.approval"
    let mode: PermissionMode
    var delaySeconds: Int?
    var godSubMode: GodSubMode?
}

enum PermissionMode: String, Codable {
    case manual
    case smart
    case delay
    case god
}

enum GodSubMode: String, Codable {
    case normal
    case yolo
}

struct DeviceListRequestMessage: Codable {
    let type: String = "device.list"
}

struct DeviceRevokeRequestMessage: Codable {
    let type: String = "device.revoke"
    let deviceId: String
}

struct FsLsRequestMessage: Codable {
    let type: String = "fs.ls"
    let path: String
}

struct FsReadFileRequestMessage: Codable {
    let type: String = "fs.readFile"
    let path: String
}

struct FsCwdRequestMessage: Codable {
    let type: String = "fs.cwd"
}

struct FleetStatusRequestMessage: Codable {
    let type: String = "fleet.status"
}

struct PresenceWatchMessage: Codable {
    let type: String = "presence.watch"
    let sessionId: String
}

struct PresenceUnwatchMessage: Codable {
    let type: String = "presence.unwatch"
}

struct UserListRequestMessage: Codable {
    let type: String = "user.list"
}

struct UserInviteRequestMessage: Codable {
    let type: String = "user.invite"
    let role: String
}

struct UserRevokeRequestMessage: Codable {
    let type: String = "user.revoke"
    let userId: String
}

struct UserUpdateRoleRequestMessage: Codable {
    let type: String = "user.updateRole"
    let userId: String
    let role: String
}

struct AnnotationAddRequestMessage: Codable {
    let type: String = "annotation.add"
    let sessionId: String
    let turnIndex: Int?
    let text: String
    let mentions: [String]?
}

struct AnnotationListRequestMessage: Codable {
    let type: String = "annotation.list"
    let sessionId: String
}

struct SessionHandoffRequestMessage: Codable {
    let type: String = "session.handoff"
    let sessionId: String
    let toUserId: String
}

struct ActivityListRequestMessage: Codable {
    let type: String = "activity.list"
}

// MARK: - Sandbox Directory Permissions

struct SandboxGetUserPathsMessage: Codable {
    let type: String = "sandbox.getUserPaths"
    let userId: String
}

struct SandboxSetUserPathsMessage: Codable {
    let type: String = "sandbox.setUserPaths"
    let userId: String
    let paths: [String]
}

struct SandboxClearUserPathsMessage: Codable {
    let type: String = "sandbox.clearUserPaths"
    let userId: String
}

struct SandboxUserPathsResponseEvent: Codable {
    let type: String
    let userId: String
    let paths: [String]
}

// MARK: - Audit & Rate Limit Client Messages

struct AuditQueryRequestMessage: Codable {
    let type: String = "audit.query"
    var startTime: String?
    var endTime: String?
    var userId: String?
    var action: String?
    var limit: Int?
}

struct RateLimitGetConfigRequestMessage: Codable {
    let type: String = "rateLimit.getConfig"
}

struct RateLimitSetRoleLimitMessage: Codable {
    let type: String = "rateLimit.setRoleLimit"
    let role: String
    let promptsPerMinute: Int
    let approvalsPerMinute: Int
}

struct RateLimitSetUserOverrideMessage: Codable {
    let type: String = "rateLimit.setUserOverride"
    let userId: String
    var promptsPerMinute: Int?
    var approvalsPerMinute: Int?
}

struct RateLimitClearUserOverrideMessage: Codable {
    let type: String = "rateLimit.clearUserOverride"
    let userId: String
}

// MARK: - Git Client Messages

struct GitStatusRequestMessage: Encodable {
    let type = "git.status"
    let sessionId: String
}

struct GitDiffRequestMessage: Encodable {
    let type = "git.diff"
    let sessionId: String
    var path: String?
    var staged: Bool?
}

struct GitLogRequestMessage: Encodable {
    let type = "git.log"
    let sessionId: String
    var count: Int?
}

struct GitBranchesRequestMessage: Encodable {
    let type = "git.branches"
    let sessionId: String
}

struct GitShowRequestMessage: Encodable {
    let type = "git.show"
    let sessionId: String
    let commitHash: String
}

// MARK: - Git Server Response Events

struct GitStatusEntry: Codable, Identifiable {
    var id: String { "\(path):\(staged)" }
    let path: String
    let status: String // "added", "modified", "deleted", "renamed", "copied", "untracked"
    let staged: Bool
    let oldPath: String?
}

struct GitStatusResponseEvent: Decodable {
    let type: String
    let sessionId: String
    let branch: String
    let entries: [GitStatusEntry]
}

struct GitDiffResponseEvent: Decodable {
    let type: String
    let sessionId: String
    let diff: String
    let path: String?
    let staged: Bool
}

struct GitLogEntry: Codable, Identifiable {
    var id: String { hash }
    let hash: String
    let shortHash: String
    let author: String
    let authorEmail: String
    let date: String
    let message: String
}

struct GitLogResponseEvent: Decodable {
    let type: String
    let sessionId: String
    let entries: [GitLogEntry]
}

struct GitBranchEntry: Codable, Identifiable {
    var id: String { name }
    let name: String
    let current: Bool
    let remote: Bool
    let upstream: String?
    let ahead: Int?
    let behind: Int?
}

struct GitBranchesResponseEvent: Decodable {
    let type: String
    let sessionId: String
    let branches: [GitBranchEntry]
}

struct GitShowResponseEvent: Decodable {
    let type: String
    let sessionId: String
    let hash: String
    let shortHash: String
    let author: String
    let authorEmail: String
    let date: String
    let message: String
    let diff: String
}

struct GitErrorEvent: Decodable {
    let type: String
    let sessionId: String
    let message: String
}

// MARK: - GitHub Client Messages

struct GitHubPullRequestsRequestMessage: Encodable {
    let type = "github.pullRequests"
    let sessionId: String
    var state: String?
}

struct GitHubPullRequestDetailRequestMessage: Encodable {
    let type = "github.pullRequest.detail"
    let sessionId: String
    let number: Int
}

struct GitHubIssuesRequestMessage: Encodable {
    let type = "github.issues"
    let sessionId: String
    var state: String?
}

struct GitHubIssueDetailRequestMessage: Encodable {
    let type = "github.issue.detail"
    let sessionId: String
    let number: Int
}

// MARK: - GitHub Server Response Events

struct GitHubPullRequestEntry: Codable, Identifiable {
    var id: Int { number }
    let number: Int
    let title: String
    let state: String
    let author: String
    let createdAt: String
    let updatedAt: String
    let url: String
    let draft: Bool
    let headBranch: String
    let baseBranch: String
    let additions: Int
    let deletions: Int
    let reviewDecision: String
}

struct GitHubIssueEntry: Codable, Identifiable {
    var id: Int { number }
    let number: Int
    let title: String
    let state: String
    let author: String
    let createdAt: String
    let updatedAt: String
    let url: String
    let labels: [String]
    let assignees: [String]
    let commentCount: Int
}

struct GitHubCheckEntry: Codable, Identifiable {
    var id: String { name }
    let name: String
    let status: String
    let conclusion: String
}

struct GitHubReviewEntry: Codable, Identifiable {
    var id: String { "\(author):\(submittedAt)" }
    let author: String
    let state: String
    let body: String
    let submittedAt: String
}

struct GitHubCommentEntry: Codable, Identifiable {
    var id: String { "\(author):\(createdAt)" }
    let author: String
    let body: String
    let createdAt: String
}

struct GitHubPullRequestDetail: Codable {
    let number: Int
    let title: String
    let body: String
    let state: String
    let author: String
    let createdAt: String
    let updatedAt: String
    let mergedAt: String?
    let url: String
    let draft: Bool
    let headBranch: String
    let baseBranch: String
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let reviewDecision: String
    let checks: [GitHubCheckEntry]
    let reviews: [GitHubReviewEntry]
    let comments: [GitHubCommentEntry]
}

struct GitHubIssueDetail: Codable {
    let number: Int
    let title: String
    let body: String
    let state: String
    let author: String
    let createdAt: String
    let updatedAt: String
    let url: String
    let labels: [String]
    let assignees: [String]
    let comments: [GitHubCommentEntry]
}

struct GitHubPullRequestsResponseEvent: Decodable {
    let type: String
    let sessionId: String
    let pullRequests: [GitHubPullRequestEntry]
}

struct GitHubPullRequestDetailResponseEvent: Decodable {
    let type: String
    let sessionId: String
    let detail: GitHubPullRequestDetail
}

struct GitHubIssuesResponseEvent: Decodable {
    let type: String
    let sessionId: String
    let issues: [GitHubIssueEntry]
}

struct GitHubIssueDetailResponseEvent: Decodable {
    let type: String
    let sessionId: String
    let detail: GitHubIssueDetail
}

struct GitHubErrorEvent: Decodable {
    let type: String
    let sessionId: String
    let message: String
}

// MARK: - Server → Client Messages

struct OutputEvent: Codable, Identifiable {
    let type: String
    let sessionId: String
    let chunk: String
    let format: OutputFormat

    let id = UUID().uuidString

    enum CodingKeys: String, CodingKey {
        case type, sessionId, chunk, format
    }
}

enum OutputFormat: String, Codable {
    case markdown
    case plain
}

struct ApprovalPriority: Codable {
    let level: String // "high" | "medium" | "low"
    let reason: String
}

struct ApprovalRequestEvent: Codable, Identifiable {
    let type: String
    let requestId: String
    let tool: String
    let description: String
    let details: [String: AnyCodableValue]?
    let priority: ApprovalPriority?

    var id: String { requestId }

    init(type: String, requestId: String, tool: String, description: String, details: [String: AnyCodableValue]?, priority: ApprovalPriority? = nil) {
        self.type = type
        self.requestId = requestId
        self.tool = tool
        self.description = description
        self.details = details
        self.priority = priority
    }
}

struct ApprovalAutoEvent: Codable {
    let type: String
    let tool: String
    let description: String
    let reason: AutoApprovalReason
    var toolUseId: String?
}

enum AutoApprovalReason: String, Codable {
    case smartSettings = "smart:settings"
    case smartSession = "smart:session"
    case godYolo = "god:yolo"
    case godNormal = "god:normal"
}

struct ToolStartEvent: Codable {
    let type: String
    let sessionId: String
    let tool: String
    let input: [String: AnyCodableValue]?
}

struct ToolCompleteEvent: Codable {
    let type: String
    let sessionId: String
    let tool: String
    var toolUseId: String?
    let output: String
    let success: Bool
}

struct AgentSpawnEvent: Codable, Identifiable {
    let type: String
    let agentId: String
    var parentId: String?
    let task: String
    let role: String

    var id: String { agentId }
}

struct AgentWorkingEvent: Codable {
    let type: String
    let agentId: String
    let task: String
}

struct AgentIdleEvent: Codable {
    let type: String
    let agentId: String
}

struct AgentCompleteEvent: Codable {
    let type: String
    let agentId: String
    let result: String
}

struct AgentDismissedEvent: Codable {
    let type: String
    let agentId: String
}

struct ConnectionStatusEvent: Codable {
    let type: String
    let status: String
    let adapter: String
}

struct SessionInfoEvent: Codable, Identifiable {
    let type: String
    let sessionId: String
    let adapter: String
    let startedAt: String
    var tokenUsage: TokenUsage?

    var id: String { sessionId }
}

struct TokenUsage: Codable {
    let used: Int
    let remaining: Int
}

struct SessionResultEvent: Codable {
    let type: String
    let sessionId: String
    let costUsd: Double
    let numTurns: Int
    let durationMs: Int
    var inputTokens: Int?
    var outputTokens: Int?
}

struct SessionEndedEvent: Codable {
    let type: String
    let sessionId: String
}

struct SessionMetaInfo: Codable, Identifiable {
    let id: String
    let adapter: String
    let workingDirName: String
    let status: String
    let startedAt: String
    let totalCost: Double
    let inputTokens: Int
    let outputTokens: Int
    let turnCount: Int
    let totalDuration: Int
}

struct SessionListResponseEvent: Codable {
    let type: String
    let sessions: [SessionMetaInfo]
}

struct TranscriptEntry: Codable, Identifiable {
    let type: String
    let content: String
    let timestamp: String
    var meta: [String: AnyCodableValue]?

    let id = UUID().uuidString

    enum CodingKeys: String, CodingKey {
        case type, content, timestamp, meta
    }
}

struct SessionHistoryEvent: Codable {
    let type: String
    let sessionId: String
    let entries: [TranscriptEntry]
}

struct PermissionModeEvent: Codable {
    let type: String
    let mode: PermissionMode
    let delaySeconds: Int
    let godSubMode: GodSubMode
}

struct NotificationEvent: Codable {
    let type: String
    let title: String
    let message: String
    let notificationType: String
}

struct DeviceInfo: Codable, Identifiable {
    let id: String
    let name: String
    let createdAt: String
    let lastSeenAt: String
}

struct DeviceListResponseEvent: Codable {
    let type: String
    let devices: [DeviceInfo]
}

struct DeviceRevokeResponseEvent: Codable {
    let type: String
    let deviceId: String
    let success: Bool
}

struct FileNode: Codable, Identifiable {
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileNode]?

    var id: String { path }
}

struct WorkspaceTreeResponseEvent: Codable {
    let type: String
    let files: [FileNode]
}

struct ContextAddResponseEvent: Codable {
    let type: String
    let path: String
    let success: Bool
    var error: String?
    let totalContextSize: Int
}

struct ContextRemoveResponseEvent: Codable {
    let type: String
    let path: String
    let success: Bool
    var error: String?
    let totalContextSize: Int
}

struct FsEntry: Codable, Identifiable {
    let name: String
    let type: String
    let size: Int
    let modified: String
    var permissions: String?
    var restricted: Bool?

    var id: String { name }

    var isDirectory: Bool { type == "directory" }
    var isRestricted: Bool { restricted ?? false }
}

struct FsLsResponseEvent: Codable {
    let type: String
    let path: String
    let entries: [FsEntry]
}

struct FsReadFileResponseEvent: Codable {
    let type: String
    let path: String
    let content: String
    let size: Int
}

struct FsCwdResponseEvent: Codable {
    let type: String
    let path: String
}

struct FsErrorEvent: Codable {
    let type: String
    let message: String
    var path: String?
}

// MARK: - Multi-User / Presence Messages

struct PresenceUpdateEvent: Codable {
    let type: String
    let users: [PresenceUser]

    struct PresenceUser: Codable {
        let userId: String
        let email: String
        let name: String?
        let picture: String?
        let role: String
        let connectedAt: String
        let watchingSessionId: String?
    }
}

struct AnnotationAddedEvent: Codable {
    let type: String
    let sessionId: String
    let annotation: AnnotationData

    struct AnnotationData: Codable {
        let id: String
        let userId: String
        let userName: String
        let turnIndex: Int?
        let text: String
        let mentions: [String]
        let createdAt: String
    }
}

struct AnnotationListResponseEvent: Codable {
    let type: String
    let sessionId: String
    let annotations: [AnnotationAddedEvent.AnnotationData]
}

struct SessionHandoffResponseEvent: Codable {
    let type: String
    let sessionId: String
    let fromUserId: String
    let toUserId: String
    let success: Bool
    let error: String?
}

struct ActivityFeedEvent: Codable {
    let type: String
    let entries: [ActivityEntryData]

    struct ActivityEntryData: Codable {
        let id: String
        let userId: String
        let userName: String
        let action: String
        let sessionId: String?
        let timestamp: String
    }
}

struct UserListResponseEvent: Codable {
    let type: String
    let users: [UserData]

    struct UserData: Codable {
        let id: String
        let email: String
        let name: String?
        let picture: String?
        let role: String
        let isOnline: Bool
        let lastLoginAt: String?
    }
}

struct UserInviteResponseEvent: Codable {
    let type: String
    let code: String?
    let expiresAt: String?
    let success: Bool
    let error: String?
}

struct UserRevokeResponseEvent: Codable {
    let type: String
    let userId: String
    let success: Bool
}

struct UserRoleUpdatedEvent: Codable {
    let type: String
    let userId: String
    let role: String
}

struct ApprovalResolvedEvent: Codable {
    let type: String
    let requestId: String
    let decision: String
    let resolvedBy: ResolvedByInfo

    struct ResolvedByInfo: Codable {
        let userId: String
        let name: String?
    }
}

// MARK: - Fleet Messages

struct FleetSessionInfo: Codable, Identifiable {
    let sessionId: String
    let status: String
    let totalCost: Double
    let turnCount: Int
    let inputTokens: Int
    let outputTokens: Int

    var id: String { sessionId }
}

struct FleetWorkerInfo: Codable, Identifiable {
    let workerId: String
    let workingDir: String
    let dirName: String
    let sessionCount: Int
    let uptimeMs: Int
    let restartCount: Int
    let healthy: Bool
    let sessions: [FleetSessionInfo]

    var id: String { workerId }
}

struct FleetAggregateTokens: Codable {
    let input: Int
    let output: Int
}

struct FleetStatusResponseEvent: Codable {
    let type: String
    let totalWorkers: Int
    let totalSessions: Int
    let aggregateCost: Double
    let aggregateTokens: FleetAggregateTokens
    let workers: [FleetWorkerInfo]
}

struct FleetWorkerSpawnedEvent: Codable {
    let type: String
    let workerId: String
    let workingDir: String
}

struct FleetWorkerCrashedEvent: Codable {
    let type: String
    let workerId: String
    let workingDir: String
    let exitCode: Int
}

struct FleetWorkerRestartedEvent: Codable {
    let type: String
    let workerId: String
    let workingDir: String
}

// MARK: - Audit & Rate Limit Messages

struct AuditEntryData: Codable, Identifiable {
    let timestamp: String
    let userId: String
    let email: String
    let role: String
    let action: String
    var sessionId: String?
    var path: String?
    var details: String?

    var id: String { "\(timestamp)-\(userId)-\(action)" }
}

struct AuditQueryResponseEvent: Codable {
    let type: String
    let entries: [AuditEntryData]
}

struct RateLimitRoleConfigData: Codable, Equatable {
    let promptsPerMinute: Int
    let approvalsPerMinute: Int
}

struct RateLimitUserOverrideData: Codable {
    var promptsPerMinute: Int?
    var approvalsPerMinute: Int?
}

struct RateLimitConfigResponseEvent: Codable {
    let type: String
    let roles: [String: RateLimitRoleConfigData]
    let userOverrides: [String: RateLimitUserOverrideData]
}

struct ErrorEvent: Codable {
    let type: String
    let code: String
    let message: String
}

// MARK: - Type-erased JSON value for dynamic fields

enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: AnyCodableValue])
    case array([AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let val = try? container.decode(Bool.self) {
            self = .bool(val)
        } else if let val = try? container.decode(Int.self) {
            self = .int(val)
        } else if let val = try? container.decode(Double.self) {
            self = .double(val)
        } else if let val = try? container.decode(String.self) {
            self = .string(val)
        } else if let val = try? container.decode([String: AnyCodableValue].self) {
            self = .object(val)
        } else if let val = try? container.decode([AnyCodableValue].self) {
            self = .array(val)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let val): try container.encode(val)
        case .int(let val): try container.encode(val)
        case .double(let val): try container.encode(val)
        case .bool(let val): try container.encode(val)
        case .object(let val): try container.encode(val)
        case .array(let val): try container.encode(val)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let val) = self { return val }
        return nil
    }

    var intValue: Int? {
        if case .int(let val) = self { return val }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let val) = self { return val }
        if case .int(let val) = self { return Double(val) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let val) = self { return val }
        return nil
    }

    var dictionaryValue: [String: AnyCodableValue]? {
        if case .object(let val) = self { return val }
        return nil
    }
}

// MARK: - Server message routing envelope

struct MessageEnvelope: Codable {
    let type: String
}
