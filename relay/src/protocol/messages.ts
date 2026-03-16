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

export interface AgentMessageMessage {
  type: 'agent.message';
  agentId: string;
  text: string;
}

export interface WorkspaceTreeMessage {
  type: 'workspace.tree';
  path?: string;
}

export interface ContextAddMessage {
  type: 'context.add';
  path: string;
  contextType: 'file' | 'folder';
}

export type ClientMessage =
  | PromptMessage
  | ApprovalMessage
  | CancelMessage
  | SessionStartMessage
  | SessionAttachMessage
  | AgentMessageMessage
  | WorkspaceTreeMessage
  | ContextAddMessage;

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
  | AgentSpawnMessage
  | AgentWorkingMessage
  | AgentIdleMessage
  | AgentCompleteMessage
  | AgentDismissedMessage
  | ConnectionStatusMessage
  | SessionInfoMessage
  | WorkspaceTreeResponseMessage
  | ErrorMessage;

// ── Utilities ───────────────────────────────────────────────

export type MessageType = ClientMessage['type'] | ServerMessage['type'];

export function newRequestId(): string {
  return randomUUID();
}
