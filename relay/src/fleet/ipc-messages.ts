/**
 * IPC Message Types — Typed protocol between parent relay process and child workers.
 *
 * All messages are discriminated unions keyed by the `type` field.
 * Parent → Child messages start with `ipc:` prefix.
 * Child → Parent messages also use `ipc:` prefix.
 */

import type { ApprovalDecision } from '../hooks/approval-queue.js';
import type { PermissionMode, GodSubMode, AutoAllowReason } from '../permissions/permission-filter.js';

// ── Parent → Child Messages ────────────────────────────────

export interface IpcSessionStart {
  type: 'ipc:session.start';
  sessionId: string;
  workingDir: string;
}

export interface IpcSessionDestroy {
  type: 'ipc:session.destroy';
  sessionId: string;
}

export interface IpcPrompt {
  type: 'ipc:prompt';
  sessionId: string;
  text: string;
  context?: string[];
}

export interface IpcApproval {
  type: 'ipc:approval';
  sessionId: string;
  requestId: string;
  decision: ApprovalDecision;
}

export interface IpcCancel {
  type: 'ipc:cancel';
  sessionId: string;
}

export interface IpcAgentMessage {
  type: 'ipc:agent.message';
  sessionId: string;
  agentId: string;
  text: string;
}

export interface IpcContextAdd {
  type: 'ipc:context.add';
  sessionId: string;
  path: string;
  content: string;
}

export interface IpcContextRemove {
  type: 'ipc:context.remove';
  sessionId: string;
  path: string;
}

export interface IpcPermissionMode {
  type: 'ipc:permission.mode';
  mode: PermissionMode;
  delaySeconds?: number;
  godSubMode?: GodSubMode;
}

export interface IpcSpriteMessage {
  type: 'ipc:sprite.message';
  sessionId: string;
  spriteHandle: string;
  agentId: string;
  text: string;
  messageId: string;
}

export type ParentToChildMessage =
  | IpcSessionStart
  | IpcSessionDestroy
  | IpcPrompt
  | IpcApproval
  | IpcCancel
  | IpcAgentMessage
  | IpcContextAdd
  | IpcContextRemove
  | IpcPermissionMode;

// ── Child → Parent Messages ────────────────────────────────

export interface IpcSessionStarted {
  type: 'ipc:session.started';
  sessionId: string;
  workingDir: string;
}

export interface IpcSessionError {
  type: 'ipc:session.error';
  sessionId: string;
  error: string;
}

export interface IpcOutput {
  type: 'ipc:output';
  sessionId: string;
  chunk: string;
}

export interface IpcApprovalRequest {
  type: 'ipc:approval.request';
  sessionId: string;
  requestId: string;
  tool: string;
  description: string;
  details: Record<string, unknown>;
}

export interface IpcApprovalAuto {
  type: 'ipc:approval.auto';
  tool: string;
  description: string;
  reason: AutoAllowReason;
  toolUseId: string;
}

export interface IpcToolStart {
  type: 'ipc:tool.start';
  sessionId: string;
  tool: string;
  input: Record<string, unknown>;
}

export interface IpcToolComplete {
  type: 'ipc:tool.complete';
  sessionId: string;
  tool: string;
  output: string;
  success: boolean;
}

export interface IpcAgentLifecycle {
  type: 'ipc:agent.lifecycle';
  sessionId: string;
  agentId: string;
  event: 'spawn' | 'working' | 'idle' | 'complete' | 'dismissed';
  task?: string;
  role?: string;
  parentId?: string;
  result?: string;
}

export interface IpcSessionResult {
  type: 'ipc:session.result';
  sessionId: string;
  costUsd: number;
  numTurns: number;
  durationMs: number;
  inputTokens?: number;
  outputTokens?: number;
}

export interface IpcWorkerReady {
  type: 'ipc:worker.ready';
  workerId: string;
  workingDir: string;
}

export interface IpcWorkerError {
  type: 'ipc:worker.error';
  workerId: string;
  error: string;
}

export type ChildToParentMessage =
  | IpcSessionStarted
  | IpcSessionError
  | IpcOutput
  | IpcApprovalRequest
  | IpcApprovalAuto
  | IpcToolStart
  | IpcToolComplete
  | IpcAgentLifecycle
  | IpcSessionResult
  | IpcWorkerReady
  | IpcWorkerError;

// ── Union of all IPC messages ──────────────────────────────

export type IpcMessage = ParentToChildMessage | ChildToParentMessage;

// ── Type guards ────────────────────────────────────────────

export function isChildToParentMessage(msg: unknown): msg is ChildToParentMessage {
  if (typeof msg !== 'object' || msg === null) return false;
  const typed = msg as { type?: string };
  if (typeof typed.type !== 'string') return false;
  return typed.type.startsWith('ipc:') && [
    'ipc:session.started',
    'ipc:session.error',
    'ipc:output',
    'ipc:approval.request',
    'ipc:approval.auto',
    'ipc:tool.start',
    'ipc:tool.complete',
    'ipc:agent.lifecycle',
    'ipc:session.result',
    'ipc:worker.ready',
    'ipc:worker.error',
  ].includes(typed.type);
}

export function isParentToChildMessage(msg: unknown): msg is ParentToChildMessage {
  if (typeof msg !== 'object' || msg === null) return false;
  const typed = msg as { type?: string };
  if (typeof typed.type !== 'string') return false;
  return typed.type.startsWith('ipc:') && [
    'ipc:session.start',
    'ipc:session.destroy',
    'ipc:prompt',
    'ipc:approval',
    'ipc:cancel',
    'ipc:agent.message',
    'ipc:context.add',
    'ipc:context.remove',
    'ipc:permission.mode',
  ].includes(typed.type);
}
