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

export type ClientMessage =
  | PromptMessage
  | ApprovalMessage
  | CancelMessage
  | SessionStartMessage
  | SessionAttachMessage;

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

export interface ErrorMessage {
  type: 'error';
  code: string;
  message: string;
}

export type ServerMessage =
  | OutputMessage
  | ApprovalRequestMessage
  | ToolStartMessage
  | ToolCompleteMessage
  | ConnectionStatusMessage
  | SessionInfoMessage
  | NotificationMessage
  | ErrorMessage;
