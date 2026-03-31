// Major Tom WebSocket Protocol — shared types (subset of relay/src/protocol/messages.ts)

// ── Client → Server ─────────────────────────────────────────

export interface PromptMessage {
  type: 'prompt';
  sessionId: string;
  text: string;
  context?: string[];
}

export interface ApprovalMessage {
  type: 'approval';
  requestId: string;
  decision: ApprovalDecision;
  toolUseId?: string;
}

export type ApprovalDecision = 'allow' | 'deny' | 'skip' | 'allow_always';

export interface CancelMessage {
  type: 'cancel';
  sessionId: string;
}

export interface SessionStartMessage {
  type: 'session.start';
  adapter: 'cli' | 'vscode';
  workingDir?: string;
}

export interface SessionAttachMessage {
  type: 'session.attach';
  sessionId: string;
}

export interface SessionEndMessage {
  type: 'session.end';
  sessionId: string;
}

export interface AgentChatMessage {
  type: 'agent.message';
  sessionId: string;
  agentId: string;
  text: string;
}

export interface WorkspaceTreeMessage {
  type: 'workspace.tree';
  path?: string;
  sessionId?: string;
}

export interface ContextAddMessage {
  type: 'context.add';
  sessionId: string;
  path: string;
  contextType: 'file' | 'folder';
}

export interface ContextRemoveMessage {
  type: 'context.remove';
  sessionId: string;
  path: string;
}

export interface SettingsApprovalMessage {
  type: 'settings.approval';
  mode: 'manual' | 'smart' | 'delay' | 'god';
  delaySeconds?: number;
  godSubMode?: 'normal' | 'yolo';
}

export interface SessionListMessage {
  type: 'session.list';
}

export interface DeviceListMessage {
  type: 'device.list';
}

export interface DeviceRevokeMessage {
  type: 'device.revoke';
  deviceId: string;
}

export interface FsLsMessage {
  type: 'fs.ls';
  path: string;
}

export interface FsReadFileMessage {
  type: 'fs.readFile';
  path: string;
}

export interface FsCwdMessage {
  type: 'fs.cwd';
}

export interface FleetStatusMessage {
  type: 'fleet.status';
}

export interface AchievementListMessage {
  type: 'achievement.list';
}

export interface PresenceWatchMessage {
  type: 'presence.watch';
  sessionId: string;
}

export interface PresenceUnwatchMessage {
  type: 'presence.unwatch';
}

export interface UserListMessage {
  type: 'user.list';
}

export interface UserInviteMessage {
  type: 'user.invite';
  role: 'admin' | 'operator' | 'viewer';
}

export interface UserRevokeMessage {
  type: 'user.revoke';
  userId: string;
}

export interface UserUpdateRoleMessage {
  type: 'user.updateRole';
  userId: string;
  role: 'admin' | 'operator' | 'viewer';
}

export interface ActivityListMessage {
  type: 'activity.list';
}

export interface AnnotationAddMessage {
  type: 'annotation.add';
  sessionId: string;
  turnIndex?: number;
  text: string;
  mentions?: string[];
}

export interface AnnotationListMessage {
  type: 'annotation.list';
  sessionId: string;
}

export interface SessionHandoffMessage {
  type: 'session.handoff';
  sessionId: string;
  toUserId: string;
}

export type ClientMessage =
  | PromptMessage
  | ApprovalMessage
  | CancelMessage
  | SessionStartMessage
  | SessionAttachMessage
  | SessionEndMessage
  | AgentChatMessage
  | WorkspaceTreeMessage
  | ContextAddMessage
  | ContextRemoveMessage
  | SettingsApprovalMessage
  | SessionListMessage
  | DeviceListMessage
  | DeviceRevokeMessage
  | FsLsMessage
  | FsReadFileMessage
  | FsCwdMessage
  | FleetStatusMessage
  | AchievementListMessage
  | PresenceWatchMessage
  | PresenceUnwatchMessage
  | UserListMessage
  | UserInviteMessage
  | UserRevokeMessage
  | UserUpdateRoleMessage
  | ActivityListMessage
  | AnnotationAddMessage
  | AnnotationListMessage
  | SessionHandoffMessage;

// ── Server → Client ─────────────────────────────────────────

export interface OutputMessage {
  type: 'output';
  sessionId: string;
  chunk: string;
  format: 'markdown' | 'plain';
}

export interface ApprovalRequestMessage {
  type: 'approval.request';
  requestId: string;
  tool: string;
  description: string;
  details?: Record<string, unknown>;
  priority?: {
    level: 'high' | 'medium' | 'low';
    reason: string;
  };
}

// ── Notification config types ────────────────────────────────

export interface NotificationConfig {
  quietHours: {
    enabled: boolean;
    start: string;
    end: string;
  };
  priorityThreshold: 'high' | 'medium' | 'low';
  digest: {
    enabled: boolean;
    intervalMinutes: number;
  };
}

export interface DigestNotificationItem {
  toolName: string;
  target: string;
  priority: 'high' | 'medium' | 'low';
  timestamp: string;
}

export interface ToolStartMessage {
  type: 'tool.start';
  sessionId: string;
  tool: string;
  input?: Record<string, unknown>;
}

export interface ToolCompleteMessage {
  type: 'tool.complete';
  sessionId: string;
  tool: string;
  toolUseId?: string;
  output: string;
  success: boolean;
}

export interface AgentSpawnMessage {
  type: 'agent.spawn';
  agentId: string;
  parentId?: string;
  task: string;
  role: string;
}

export interface AgentWorkingMessage {
  type: 'agent.working';
  agentId: string;
  task: string;
}

export interface AgentIdleMessage {
  type: 'agent.idle';
  agentId: string;
}

export interface AgentCompleteMessage {
  type: 'agent.complete';
  agentId: string;
  result: string;
}

export interface AgentDismissedMessage {
  type: 'agent.dismissed';
  agentId: string;
}

export interface NotificationMessage {
  type: 'notification';
  title: string;
  message: string;
  notificationType: string;
}

export interface ConnectionStatusMessage {
  type: 'connection.status';
  status: 'connected' | 'disconnected';
  adapter: string;
}

export interface SessionInfoMessage {
  type: 'session.info';
  sessionId: string;
  adapter: string;
  startedAt: string;
  tokenUsage?: { used: number; remaining: number };
}

export interface SessionResultMessage {
  type: 'session.result';
  sessionId: string;
  costUsd: number;
  numTurns: number;
  durationMs: number;
  inputTokens?: number;
  outputTokens?: number;
}

export interface WorkspaceTreeResponseMessage {
  type: 'workspace.tree.response';
  files: FileNode[];
}

export interface FileNode {
  name: string;
  path: string;
  isDirectory: boolean;
  children?: FileNode[];
}

export interface DeviceInfo {
  id: string;
  name: string;
  createdAt: string;
  lastSeenAt: string;
}

export interface DeviceListResponseMessage {
  type: 'device.list.response';
  devices: DeviceInfo[];
}

export interface DeviceRevokeResponseMessage {
  type: 'device.revoke.response';
  deviceId: string;
  success: boolean;
}

export interface ContextAddResponseMessage {
  type: 'context.add.response';
  path: string;
  success: boolean;
  error?: string;
  totalContextSize: number;
}

export interface ContextRemoveResponseMessage {
  type: 'context.remove.response';
  path: string;
  success: boolean;
  error?: string;
  totalContextSize: number;
}
export interface ApprovalAutoMessage {
  type: 'approval.auto';
  tool: string;
  description: string;
  reason: 'smart:settings' | 'smart:session' | 'god:yolo' | 'god:normal';
  toolUseId?: string;
}

export interface PermissionModeMessage {
  type: 'permission.mode';
  mode: 'manual' | 'smart' | 'delay' | 'god';
  delaySeconds: number;
  godSubMode: 'normal' | 'yolo';
}

export interface ErrorMessage {
  type: 'error';
  code: string;
  message: string;
}

export interface SessionMeta {
  id: string;
  adapter: string;
  workingDirName: string;
  status: string;
  startedAt: string;
  totalCost: number;
  inputTokens: number;
  outputTokens: number;
  turnCount: number;
  totalDuration: number;
}

export interface SessionListResponseMessage {
  type: 'session.list.response';
  sessions: SessionMeta[];
}

export interface TranscriptEntry {
  type: 'user' | 'assistant' | 'tool' | 'system' | 'result';
  content: string;
  timestamp: string;
  meta?: Record<string, unknown>;
}

export interface SessionHistoryMessage {
  type: 'session.history';
  sessionId: string;
  entries: TranscriptEntry[];
}

export interface SessionEndedMessage {
  type: 'session.ended';
  sessionId: string;
}

export interface FsEntry {
  name: string;
  type: 'file' | 'directory' | 'symlink';
  size: number;
  modified: string;
  permissions?: string;
}

export interface FsLsResponseMessage {
  type: 'fs.ls.response';
  path: string;
  entries: FsEntry[];
}

export interface FsReadFileResponseMessage {
  type: 'fs.readFile.response';
  path: string;
  content: string;
  size: number;
}

export interface FsCwdResponseMessage {
  type: 'fs.cwd.response';
  path: string;
}

export interface FsErrorMessage {
  type: 'fs.error';
  message: string;
  path?: string;
}

// ── Fleet status messages ─────────────────────────────────

export interface FleetSessionInfo {
  sessionId: string;
  status: string;
  totalCost: number;
  turnCount: number;
  inputTokens: number;
  outputTokens: number;
}

export interface FleetWorkerInfo {
  workerId: string;
  workingDir: string;
  dirName: string;
  sessionCount: number;
  uptimeMs: number;
  restartCount: number;
  healthy: boolean;
  sessions: FleetSessionInfo[];
}

export interface FleetStatusResponseMessage {
  type: 'fleet.status.response';
  totalWorkers: number;
  totalSessions: number;
  aggregateCost: number;
  aggregateTokens: {
    input: number;
    output: number;
  };
  workers: FleetWorkerInfo[];
}

export interface FleetWorkerSpawnedMessage {
  type: 'fleet.worker.spawned';
  workerId: string;
  workingDir: string;
  dirName: string;
}

export interface FleetWorkerCrashedMessage {
  type: 'fleet.worker.crashed';
  workerId: string;
  workingDir: string;
  dirName: string;
  restartCount: number;
}

export interface FleetWorkerRestartedMessage {
  type: 'fleet.worker.restarted';
  workerId: string;
  workingDir: string;
  dirName: string;
  restartCount: number;
}


// ── Achievement messages ─────────────────────────────────────

export interface AchievementStatusEntry {
  id: string;
  name: string;
  description: string;
  category: string;
  icon: string;
  unlocked: boolean;
  unlockedAt: string | null;
  progress: number | null;
  target: number | null;
  percentage: number | null;
  secret: boolean;
}

export interface AchievementUnlockedMessage {
  type: 'achievement.unlocked';
  achievementId: string;
  name: string;
  description: string;
  category: string;
  icon: string;
  unlockedAt: string;
}

export interface AchievementProgressMessage {
  type: 'achievement.progress';
  achievementId: string;
  name: string;
  current: number;
  target: number;
  percentage: number;
}

export interface AchievementListResponseMessage {
  type: 'achievement.list.response';
  achievements: AchievementStatusEntry[];
  totalCount: number;
  unlockedCount: number;
}

// ── Presence & multi-user messages ─────────────────────────

export interface PresenceUpdateMessage {
  type: 'presence.update';
  users: Array<{
    userId: string;
    email: string;
    name?: string;
    picture?: string;
    role: string;
    connectedAt: string;
    watchingSessionId?: string;
  }>;
}

export interface UserListResponseMessage {
  type: 'user.list.response';
  users: Array<{
    id: string;
    email: string;
    name?: string;
    picture?: string;
    role: string;
    isOnline: boolean;
    lastLoginAt: string;
  }>;
}

export interface UserInviteResponseMessage {
  type: 'user.invite.response';
  code: string;
  expiresAt: string;
  success: boolean;
  error?: string;
}

export interface UserRevokeResponseMessage {
  type: 'user.revoke.response';
  userId: string;
  success: boolean;
}

export interface UserRoleUpdatedMessage {
  type: 'user.roleUpdated';
  userId: string;
  role: string;
}

export interface ApprovalResolvedMessage {
  type: 'approval.resolved';
  requestId: string;
  decision: string;
  resolvedBy: {
    userId: string;
    name?: string;
  };
}

// ── Annotation & activity messages ──────────────────────────

export interface AnnotationEntry {
  id: string;
  userId: string;
  userName: string;
  turnIndex?: number;
  text: string;
  mentions: string[];
  createdAt: string;
}

export interface AnnotationAddedMessage {
  type: 'annotation.added';
  sessionId: string;
  annotation: AnnotationEntry;
}

export interface AnnotationListResponseMessage {
  type: 'annotation.list.response';
  sessionId: string;
  annotations: AnnotationEntry[];
}

export interface SessionHandoffResponseMessage {
  type: 'session.handoff.response';
  sessionId: string;
  fromUserId: string;
  toUserId: string;
  success: boolean;
  error?: string;
}

export interface SessionOwnershipChangedMessage {
  type: 'session.ownership.changed';
  sessionId: string;
  fromUserId: string;
  toUserId: string;
}

export interface ActivityEntry {
  id: string;
  userId: string;
  userName: string;
  action: string;
  sessionId?: string;
  timestamp: string;
}

export interface ActivityFeedMessage {
  type: 'activity.feed';
  entries: ActivityEntry[];
}

// ── Analytics types (HTTP API, not WebSocket) ──────────────

export interface AnalyticsResponse {
  timeSeries: Array<{
    period: string;
    cost: number;
    inputTokens: number;
    outputTokens: number;
    cacheTokens: number;
    turnCount: number;
  }>;
  bySession: Array<{
    sessionId: string;
    workingDir: string;
    totalCost: number;
    totalTokens: number;
    turnCount: number;
  }>;
  byModel: Array<{
    model: string;
    cost: number;
    tokens: number;
    turnCount: number;
  }>;
  byTool: Array<{
    tool: string;
    count: number;
    avgDurationMs: number;
  }>;
  totals: {
    cost: number;
    inputTokens: number;
    outputTokens: number;
    turnCount: number;
    sessionCount: number;
  };
}

export type ServerMessage =
  | OutputMessage
  | ApprovalRequestMessage
  | ToolStartMessage
  | ToolCompleteMessage
  | AgentSpawnMessage
  | AgentWorkingMessage
  | AgentIdleMessage
  | AgentCompleteMessage
  | AgentDismissedMessage
  | ConnectionStatusMessage
  | SessionInfoMessage
  | SessionResultMessage
  | WorkspaceTreeResponseMessage
  | ContextAddResponseMessage
  | ContextRemoveResponseMessage
  | NotificationMessage
  | DeviceListResponseMessage
  | DeviceRevokeResponseMessage
  | ErrorMessage
  | SessionListResponseMessage
  | SessionHistoryMessage
  | ApprovalAutoMessage
  | PermissionModeMessage
  | SessionEndedMessage
  | FsLsResponseMessage
  | FsReadFileResponseMessage
  | FsCwdResponseMessage
  | FsErrorMessage
  | FleetStatusResponseMessage
  | FleetWorkerSpawnedMessage
  | FleetWorkerCrashedMessage
  | FleetWorkerRestartedMessage
  | AchievementUnlockedMessage
  | AchievementProgressMessage
  | AchievementListResponseMessage
  | PresenceUpdateMessage
  | UserListResponseMessage
  | UserInviteResponseMessage
  | UserRevokeResponseMessage
  | UserRoleUpdatedMessage
  | ApprovalResolvedMessage
  | AnnotationAddedMessage
  | AnnotationListResponseMessage
  | SessionHandoffResponseMessage
  | SessionOwnershipChangedMessage
  | ActivityFeedMessage;
