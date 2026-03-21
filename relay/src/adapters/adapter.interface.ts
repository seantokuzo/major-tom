import type { Session } from '../sessions/session.js';

// ── Types used by adapters ──────────────────────────────────

export interface ApprovalRequest {
  requestId: string;
  tool: string;
  description: string;
  details: Record<string, unknown>;
}

export interface ToolInfo {
  tool: string;
  input: Record<string, unknown>;
  sessionId: string;
}

export interface ToolResult {
  tool: string;
  output: string;
  success: boolean;
  sessionId: string;
}

export interface AgentEvent {
  agentId: string;
  event: 'spawn' | 'working' | 'idle' | 'complete' | 'dismissed';
  task?: string;
  role?: string;
  parentId?: string;
  result?: string;
}

export interface SessionResult {
  sessionId: string;
  costUsd: number;
  numTurns: number;
  durationMs: number;
  inputTokens?: number;
  outputTokens?: number;
}

// ── Adapter interface ───────────────────────────────────────

export interface IAdapter {
  readonly type: 'cli' | 'vscode';

  start(workingDir: string): Promise<Session>;
  attach(sessionId: string): Promise<Session>;
  sendPrompt(sessionId: string, text: string, context?: string[]): Promise<void>;
  sendAgentMessage(sessionId: string, agentId: string, text: string): Promise<void>;
  cancelOperation(sessionId: string): Promise<void>;

  on(event: 'output', handler: (sessionId: string, chunk: string) => void): void;
  on(event: 'approval-request', handler: (request: ApprovalRequest) => void): void;
  on(event: 'tool-start', handler: (info: ToolInfo) => void): void;
  on(event: 'tool-complete', handler: (result: ToolResult) => void): void;
  on(event: 'agent-lifecycle', handler: (event: AgentEvent) => void): void;
  on(event: 'session-result', handler: (result: SessionResult) => void): void;

  dispose(): Promise<void>;
}
