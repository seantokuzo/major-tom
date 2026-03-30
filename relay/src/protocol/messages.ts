// ============================================================
// Major Tom WebSocket Protocol — Message Types
// All messages are JSON with a `type` field for routing.
// See docs/PLANNING.md for the full protocol spec.
// ============================================================

import { randomUUID } from 'node:crypto';

// ── Client → Server (iOS → Relay) ──────────────────────────

export interface PromptMessage {
  type: 'prompt';
  sessionId: string;
  text: string;
  context?: string[];
}

export interface ApprovalMessage {
  type: 'approval';
  requestId: string;
  decision: 'allow' | 'deny' | 'skip' | 'allow_always';
  toolUseId?: string;
}

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

export interface AgentMessageMessage {
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

export interface SessionResumeMessage {
  type: 'session.resume';
  sessionId: string;
  /** Sequence number of last event the client received. Events after this will be replayed. */
  lastSeq?: number;
}

export interface FleetStatusMessage {
  type: 'fleet.status';
}

export interface AchievementListMessage {
  type: 'achievement.list';
}


export type ClientMessage =
  | PromptMessage
  | ApprovalMessage
  | CancelMessage
  | SessionStartMessage
  | SessionAttachMessage
  | SessionEndMessage
  | AgentMessageMessage
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
  | SessionResumeMessage
  | FleetStatusMessage
  | AchievementListMessage;

// ── Server → Client (Relay → iOS) ──────────────────────────

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
  details: Record<string, unknown>;
  priority?: {
    level: 'high' | 'medium' | 'low';
    reason: string;
  };
}

export interface ToolStartMessage {
  type: 'tool.start';
  sessionId: string;
  tool: string;
  input: Record<string, unknown>;
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

export interface FileNode {
  name: string;
  path: string;
  isDirectory: boolean;
  children?: FileNode[];
}

export interface WorkspaceTreeResponseMessage {
  type: 'workspace.tree.response';
  files: FileNode[];
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

export interface NotificationMessage {
  type: 'notification';
  title: string;
  message: string;
  notificationType: string;
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

export interface SessionEndedMessage {
  type: 'session.ended';
  sessionId: string;
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

export interface SessionMetaMessage {
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
  sessions: SessionMetaMessage[];
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

export interface SessionResumeResponseMessage {
  type: 'session.resume.response';
  sessionId: string;
  /** Whether the session was found and resumed */
  success: boolean;
  /** Number of events replayed to the client */
  replayedCount: number;
  /** Current sequence number (client should track this for next resume) */
  currentSeq: number;
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


/** Base server message union (without envelope fields). */
type ServerMessageBase =
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
  | WorkspaceTreeResponseMessage
  | ContextAddResponseMessage
  | ContextRemoveResponseMessage
  | SessionResultMessage
  | NotificationMessage
  | DeviceListResponseMessage
  | DeviceRevokeResponseMessage
  | SessionEndedMessage
  | ErrorMessage
  | SessionListResponseMessage
  | SessionHistoryMessage
  | ApprovalAutoMessage
  | PermissionModeMessage
  | FsLsResponseMessage
  | FsReadFileResponseMessage
  | FsCwdResponseMessage
  | FsErrorMessage
  | SessionResumeResponseMessage
  | FleetStatusResponseMessage
  | FleetWorkerSpawnedMessage
  | FleetWorkerCrashedMessage
  | FleetWorkerRestartedMessage
  | AchievementUnlockedMessage
  | AchievementProgressMessage
  | AchievementListResponseMessage;

/**
 * Every outbound server message may carry an optional `seq` —
 * a monotonically-increasing sequence number stamped by the relay
 * for session-scoped events. Clients use `lastSeq` during
 * `session.resume` to request only events they missed.
 */
export type ServerMessage = ServerMessageBase & { seq?: number };

// ── Utilities ───────────────────────────────────────────────

export type MessageType = ClientMessage['type'] | ServerMessage['type'];

export function newRequestId(): string {
  return randomUUID();
}

// ── Analytics types (shared between relay HTTP API and clients) ──

export interface AnalyticsQuery {
  from?: string;      // ISO 8601
  to?: string;        // ISO 8601
  groupBy?: 'hour' | 'day' | 'week' | 'month';
  sessionId?: string;
  workerId?: string;
}

export interface AnalyticsTimeSeriesEntry {
  period: string;
  cost: number;
  inputTokens: number;
  outputTokens: number;
  cacheTokens: number;
  turnCount: number;
}

export interface AnalyticsBySession {
  sessionId: string;
  workingDir: string;
  totalCost: number;
  totalTokens: number;
  turnCount: number;
}

export interface AnalyticsByModel {
  model: string;
  cost: number;
  tokens: number;
  turnCount: number;
}

export interface AnalyticsByTool {
  tool: string;
  count: number;
  avgDurationMs: number;
}

export interface AnalyticsTotals {
  cost: number;
  inputTokens: number;
  outputTokens: number;
  turnCount: number;
  sessionCount: number;
}

export interface AnalyticsResponse {
  timeSeries: AnalyticsTimeSeriesEntry[];
  bySession: AnalyticsBySession[];
  byModel: AnalyticsByModel[];
  byTool: AnalyticsByTool[];
  totals: AnalyticsTotals;
}
