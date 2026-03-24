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


export type ClientMessage =
  | PromptMessage
  | ApprovalMessage
  | CancelMessage
  | SessionStartMessage
  | SessionAttachMessage
  | AgentChatMessage
  | WorkspaceTreeMessage
  | ContextAddMessage
  | ContextRemoveMessage
  | SettingsApprovalMessage
  | SessionListMessage
  | DeviceListMessage
  | DeviceRevokeMessage;

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
  | PermissionModeMessage;
