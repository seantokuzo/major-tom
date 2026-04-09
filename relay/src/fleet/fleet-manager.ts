/**
 * FleetManager — Parent-side orchestrator for multi-directory Claude sessions.
 *
 * Forks child worker processes per unique working directory, routes session
 * commands through IPC, and re-emits events so ws.ts broadcast logic stays
 * unchanged. Drop-in replacement for direct ClaudeCliAdapter usage.
 *
 * Architecture:
 *   Relay Process (parent)
 *     ├── Fastify HTTP/WS server
 *     ├── FleetManager
 *     │   ├── Worker 1 (fork, cwd: /project-a)
 *     │   │   └── ClaudeCliAdapter → SDK Session(s)
 *     │   ├── Worker 2 (fork, cwd: /project-b)
 *     │   │   └── ClaudeCliAdapter → SDK Session(s)
 *     │   └── ...
 *     └── routes/ws.ts routes through FleetManager
 */

import { EventEmitter } from 'node:events';
import { fork, type ChildProcess } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { resolve, dirname, join, basename } from 'node:path';
import { realpathSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { Session } from '../sessions/session.js';
import type { SessionManager } from '../sessions/session-manager.js';
import { PermissionFilter } from '../permissions/permission-filter.js';
import type { PermissionMode, GodSubMode } from '../permissions/permission-filter.js';
import type {
  ApprovalRequest,
  ToolInfo,
  ToolResult,
  AgentEvent,
  SessionResult,
} from '../adapters/adapter.interface.js';
import type { AutoAllowEvent } from '../adapters/claude-cli.adapter.js';
import type { ApprovalDecision } from '../hooks/approval-queue.js';
import {
  isChildToParentMessage,
  type ParentToChildMessage,
  type ChildToParentMessage,
} from './ipc-messages.js';
import { logger } from '../utils/logger.js';

// ── Resolve worker script path ──────────────────────────────

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/**
 * Worker script resolution:
 * - Dev (tsx): __filename = .../src/fleet/fleet-manager.ts → worker.ts in same dir
 * - Prod (tsc, no bundle): __filename = .../dist/fleet/fleet-manager.js → worker.js in same dir
 * - Prod (esbuild bundle): __filename = .../dist/server.js → worker.js at dist/fleet/worker.js
 *
 * We detect the bundled case by checking if the sibling worker file exists.
 */
const EXT = __filename.endsWith('.ts') ? '.ts' : '.js';
const WORKER_SCRIPT = (() => {
  const siblingPath = join(__dirname, `worker${EXT}`);
  if (existsSync(siblingPath)) return siblingPath;
  // Bundled mode: __dirname is dist/, worker is at dist/fleet/worker.js
  return join(__dirname, 'fleet', `worker${EXT}`);
})();

// ── Worker tracking ─────────────────────────────────────────

interface WorkerEntry {
  workerId: string;
  process: ChildProcess;
  workingDir: string;
  /** Canonical absolute path for dedup */
  canonicalDir: string;
  sessionIds: Set<string>;
  ready: boolean;
  startedAt: number;
  restartCount: number;
  lastRestartAt: number;
  /** Queued messages waiting for worker.ready */
  pendingMessages: ParentToChildMessage[];
}

export interface WorkerStatus {
  workerId: string;
  workingDir: string;
  sessionCount: number;
  uptimeMs: number;
  restartCount: number;
  healthy: boolean;
  pid: number | undefined;
}

export interface FleetStatus {
  totalWorkers: number;
  totalSessions: number;
  workers: WorkerStatus[];
}

// ── Restart backoff config ──────────────────────────────────

const MAX_RESTART_ATTEMPTS = 5;
const RESTART_BACKOFF_BASE_MS = 1000;
const RESTART_BACKOFF_WINDOW_MS = 60_000; // Reset restart count after 60s of stability

// ── FleetManager ────────────────────────────────────────────

/** Timeout for waiting for ipc:session.started acknowledgement */
const SESSION_START_TIMEOUT_MS = 30_000;

export class FleetManager {
  private emitter = new EventEmitter();
  private workers = new Map<string, WorkerEntry>(); // canonicalDir → WorkerEntry
  private sessionWorkerMap = new Map<string, string>(); // sessionId → canonicalDir
  private approvalSessionMap = new Map<string, string>(); // requestId → sessionId
  /** Pending start() calls waiting for ipc:session.started or ipc:session.error */
  private pendingStarts = new Map<string, { resolve: () => void; reject: (err: Error) => void }>();
  /** Parent-side mirror of pending approvals for re-broadcast on client reconnect */
  private pendingApprovals = new Map<string, { requestId: string; tool: string; description: string; details: Record<string, unknown> }>();
  private sessionManager: SessionManager;
  readonly permissionFilter: PermissionFilter;
  private shuttingDown = false;

  constructor(sessionManager: SessionManager) {
    this.sessionManager = sessionManager;
    this.permissionFilter = new PermissionFilter();
    this.emitter.setMaxListeners(50);
  }

  // ── Worker lifecycle ──────────────────────────────────────

  /**
   * Get or create a worker for the given working directory.
   * Workers are keyed by canonical absolute path.
   */
  private getOrCreateWorker(workingDir: string): WorkerEntry {
    const canonicalDir = this.canonicalize(workingDir);
    const existing = this.workers.get(canonicalDir);
    if (existing && existing.process.connected) {
      return existing;
    }

    // If process exists but is disconnected, clean it up first
    if (existing && !existing.process.connected) {
      logger.warn({ canonicalDir, workerId: existing.workerId }, 'Stale worker found — cleaning up');
      this.cleanupWorker(existing);
    }

    return this.forkWorker(canonicalDir, workingDir);
  }

  private forkWorker(canonicalDir: string, workingDir: string, isRestart = false): WorkerEntry {
    const workerId = randomUUID();

    logger.info({ workerId: workerId.slice(0, 8), workingDir, canonicalDir }, 'Forking fleet worker');

    // Determine exec args for tsx in dev mode
    const execArgv: string[] = [];
    if (EXT === '.ts') {
      // Running under tsx — we need the child to also use tsx
      // tsx registers itself via --import, so we pass the same flag
      execArgv.push('--import', 'tsx');
    }

    const child = fork(WORKER_SCRIPT, [], {
      cwd: workingDir,
      env: {
        ...process.env,
        FLEET_WORKER_ID: workerId,
      },
      stdio: ['ignore', 'inherit', 'inherit', 'ipc'],
      execArgv,
    });

    const entry: WorkerEntry = {
      workerId,
      process: child,
      workingDir,
      canonicalDir,
      sessionIds: new Set(),
      ready: false,
      startedAt: Date.now(),
      restartCount: 0,
      lastRestartAt: 0,
      pendingMessages: [],
    };

    // Preserve restart count from previous worker for this dir
    const prevEntry = this.workers.get(canonicalDir);
    if (prevEntry) {
      // Reset restart count if stable for a while
      const sinceLastRestart = Date.now() - prevEntry.lastRestartAt;
      entry.restartCount = sinceLastRestart > RESTART_BACKOFF_WINDOW_MS
        ? 0
        : prevEntry.restartCount;
      entry.lastRestartAt = prevEntry.lastRestartAt;
    }

    this.workers.set(canonicalDir, entry);

    // Wire IPC
    child.on('message', (raw: unknown) => {
      if (!isChildToParentMessage(raw)) {
        logger.warn({ raw, workerId: workerId.slice(0, 8) }, 'Unknown IPC message from worker');
        return;
      }
      this.handleWorkerMessage(entry, raw);
    });

    child.on('error', (err) => {
      logger.error({ workerId: workerId.slice(0, 8), err }, 'Worker process error');
    });

    child.on('exit', (code, signal) => {
      logger.warn(
        { workerId: workerId.slice(0, 8), code, signal, canonicalDir },
        'Worker process exited',
      );
      if (!this.shuttingDown) {
        this.handleWorkerCrash(entry, code, signal);
      }
    });

    // Emit worker-spawned only for genuinely new workers (not restarts)
    if (!isRestart) {
      this.emitter.emit('worker-spawned', {
        workerId,
        workingDir,
        dirName: basename(workingDir),
      });
    }

    return entry;
  }

  private handleWorkerCrash(entry: WorkerEntry, code: number | null, signal: string | null): void {
    const { canonicalDir, workerId, sessionIds } = entry;
    entry.restartCount++;
    entry.lastRestartAt = Date.now();

    logger.warn(
      {
        workerId: workerId.slice(0, 8),
        code,
        signal,
        restartCount: entry.restartCount,
        sessionCount: sessionIds.size,
      },
      'Worker crashed — evaluating restart',
    );

    // Emit worker-crashed event for real-time fleet dashboard
    this.emitter.emit('worker-crashed', {
      workerId,
      workingDir: entry.workingDir,
      dirName: basename(entry.workingDir),
      restartCount: entry.restartCount,
    });

    // Clear pending approvals for all sessions in the crashed worker
    for (const sessionId of sessionIds) {
      this.clearApprovalsForSession(sessionId);
    }

    if (entry.restartCount > MAX_RESTART_ATTEMPTS) {
      logger.error(
        { workerId: workerId.slice(0, 8), restartCount: entry.restartCount },
        'Worker exceeded max restart attempts — not restarting',
      );
      // Emit errors for all sessions in this worker
      for (const sessionId of sessionIds) {
        this.emitter.emit('output', sessionId, '\n[Worker crashed and will not restart. Please start a new session.]\n');
        this.sessionWorkerMap.delete(sessionId);
      }
      this.workers.delete(canonicalDir);
      return;
    }

    // Exponential backoff
    const backoffMs = RESTART_BACKOFF_BASE_MS * Math.pow(2, entry.restartCount - 1);
    logger.info(
      { workerId: workerId.slice(0, 8), backoffMs },
      'Scheduling worker restart with backoff',
    );

    setTimeout(() => {
      if (this.shuttingDown) return;

      // Fork a new worker (suppress worker-spawned since we emit worker-restarted instead)
      const newEntry = this.forkWorker(canonicalDir, entry.workingDir, true);
      newEntry.restartCount = entry.restartCount;
      newEntry.lastRestartAt = entry.lastRestartAt;

      // Emit worker-restarted event for real-time fleet dashboard
      this.emitter.emit('worker-restarted', {
        workerId: newEntry.workerId,
        workingDir: entry.workingDir,
        dirName: basename(entry.workingDir),
        restartCount: entry.restartCount,
      });

      // Notify sessions about the crash (they need to be re-established by the client)
      for (const sessionId of sessionIds) {
        this.emitter.emit('output', sessionId, '\n[Worker restarted after crash. Session may need to be re-created.]\n');
        this.sessionWorkerMap.delete(sessionId);
      }
    }, backoffMs);
  }

  private cleanupWorker(entry: WorkerEntry): void {
    if (entry.process.connected) {
      entry.process.kill('SIGTERM');
    }
    for (const sessionId of entry.sessionIds) {
      this.sessionWorkerMap.delete(sessionId);
    }
    this.workers.delete(entry.canonicalDir);
  }

  private sendToWorker(entry: WorkerEntry, msg: ParentToChildMessage): void {
    if (!entry.ready) {
      // Queue until worker sends ipc:worker.ready
      entry.pendingMessages.push(msg);
      return;
    }
    if (entry.process.connected) {
      entry.process.send(msg);
    } else {
      logger.warn({ workerId: entry.workerId.slice(0, 8), type: msg.type }, 'Worker not connected — message dropped');
    }
  }

  private canonicalize(dir: string): string {
    const abs = resolve(dir);
    try {
      return realpathSync(abs);
    } catch {
      return abs;
    }
  }

  // ── Worker → Parent event handling ────────────────────────

  private handleWorkerMessage(entry: WorkerEntry, msg: ChildToParentMessage): void {
    switch (msg.type) {
      case 'ipc:worker.ready':
        entry.ready = true;
        logger.info(
          { workerId: entry.workerId.slice(0, 8), workingDir: msg.workingDir },
          'Worker ready',
        );
        // Sync current permission mode to the new worker
        if (entry.process.connected) {
          const modeState = this.permissionFilter.getMode();
          entry.process.send({
            type: 'ipc:permission.mode',
            mode: modeState.mode,
            delaySeconds: modeState.delaySeconds,
            godSubMode: modeState.godSubMode,
          } satisfies ParentToChildMessage);
        }
        // Flush any queued messages
        for (const queued of entry.pendingMessages) {
          if (entry.process.connected) {
            entry.process.send(queued);
          }
        }
        entry.pendingMessages = [];
        break;

      case 'ipc:session.started': {
        logger.info({ sessionId: msg.sessionId, workingDir: msg.workingDir }, 'Session started in worker');
        const pendingStart = this.pendingStarts.get(msg.sessionId);
        if (pendingStart) {
          this.pendingStarts.delete(msg.sessionId);
          pendingStart.resolve();
        }
        break;
      }

      case 'ipc:session.error': {
        logger.error({ sessionId: msg.sessionId, error: msg.error }, 'Session error from worker');
        const pendingStartErr = this.pendingStarts.get(msg.sessionId);
        if (pendingStartErr) {
          this.pendingStarts.delete(msg.sessionId);
          pendingStartErr.reject(new Error(msg.error));
        } else {
          // Error for an already-started session — emit to clients
          this.emitter.emit('output', msg.sessionId, `\n[Session error: ${msg.error}]\n`);
        }
        break;
      }

      case 'ipc:output':
        this.emitter.emit('output', msg.sessionId, msg.chunk);
        break;

      case 'ipc:approval.request': {
        this.approvalSessionMap.set(msg.requestId, msg.sessionId);
        const approvalReq: ApprovalRequest = {
          requestId: msg.requestId,
          tool: msg.tool,
          description: msg.description,
          details: msg.details,
        };
        this.pendingApprovals.set(msg.requestId, approvalReq);
        this.emitter.emit('approval-request', approvalReq);
        break;
      }

      case 'ipc:approval.auto':
        this.emitter.emit('auto-allow', {
          tool: msg.tool,
          description: msg.description,
          reason: msg.reason,
          toolUseId: msg.toolUseId,
        } satisfies AutoAllowEvent);
        break;

      case 'ipc:tool.start':
        this.emitter.emit('tool-start', {
          tool: msg.tool,
          input: msg.input,
          sessionId: msg.sessionId,
        } satisfies ToolInfo);
        break;

      case 'ipc:tool.complete':
        this.emitter.emit('tool-complete', {
          tool: msg.tool,
          output: msg.output,
          success: msg.success,
          sessionId: msg.sessionId,
        } satisfies ToolResult);
        break;

      case 'ipc:agent.lifecycle':
        this.emitter.emit('agent-lifecycle', {
          agentId: msg.agentId,
          event: msg.event,
          task: msg.task,
          role: msg.role,
          parentId: msg.parentId,
          result: msg.result,
        } satisfies AgentEvent);
        break;

      case 'ipc:session.result':
        this.emitter.emit('session-result', {
          sessionId: msg.sessionId,
          costUsd: msg.costUsd,
          numTurns: msg.numTurns,
          durationMs: msg.durationMs,
          inputTokens: msg.inputTokens,
          outputTokens: msg.outputTokens,
        } satisfies SessionResult);
        break;

      case 'ipc:worker.error':
        logger.error({ workerId: msg.workerId, error: msg.error }, 'Worker-level error');
        break;
    }
  }

  // ── Public API (mirrors ClaudeCliAdapter) ─────────────────

  async start(workingDir: string): Promise<Session> {
    const session = this.sessionManager.create('cli', workingDir);
    const entry = this.getOrCreateWorker(workingDir);

    entry.sessionIds.add(session.id);
    this.sessionWorkerMap.set(session.id, entry.canonicalDir);

    // Wait for worker to acknowledge session creation (or report error)
    const startPromise = new Promise<void>((resolve, reject) => {
      this.pendingStarts.set(session.id, { resolve, reject });
      setTimeout(() => {
        if (this.pendingStarts.has(session.id)) {
          this.pendingStarts.delete(session.id);
          reject(new Error(`Timeout waiting for session ${session.id} to start in worker`));
        }
      }, SESSION_START_TIMEOUT_MS);
    });

    this.sendToWorker(entry, {
      type: 'ipc:session.start',
      sessionId: session.id,
      workingDir,
    });

    try {
      await startPromise;
    } catch (err) {
      // Clean up on failure
      entry.sessionIds.delete(session.id);
      this.sessionWorkerMap.delete(session.id);
      this.sessionManager.close(session.id);
      this.sessionManager.destroy(session.id);
      throw err;
    }

    logger.info({ sessionId: session.id, workingDir, workerId: entry.workerId.slice(0, 8) }, 'Session started in worker');
    return session;
  }

  async attach(sessionId: string): Promise<Session> {
    const session = this.sessionManager.get(sessionId);
    const canonicalDir = this.sessionWorkerMap.get(sessionId);
    if (!canonicalDir) {
      throw new Error(`No worker for session ${sessionId}`);
    }
    const entry = this.workers.get(canonicalDir);
    if (!entry || !entry.process.connected) {
      throw new Error(`Worker for session ${sessionId} is not connected`);
    }
    return session;
  }

  async sendPrompt(sessionId: string, text: string, context?: string[]): Promise<void> {
    const entry = this.getWorkerForSession(sessionId);
    if (!entry) {
      throw new Error(`No worker for session ${sessionId}`);
    }
    this.sendToWorker(entry, {
      type: 'ipc:prompt',
      sessionId,
      text,
      context,
    });
  }

  async sendAgentMessage(sessionId: string, agentId: string, text: string): Promise<void> {
    const entry = this.getWorkerForSession(sessionId);
    if (!entry) {
      throw new Error(`No worker for session ${sessionId}`);
    }
    this.sendToWorker(entry, {
      type: 'ipc:agent.message',
      sessionId,
      agentId,
      text,
    });
  }

  /**
   * Resolve an approval decision. Routes to the correct worker using the
   * requestId → sessionId mapping established when the approval was requested.
   */
  resolveApproval(requestId: string, decision: ApprovalDecision): void {
    const sessionId = this.approvalSessionMap.get(requestId);
    this.approvalSessionMap.delete(requestId);
    this.pendingApprovals.delete(requestId);

    if (sessionId) {
      const entry = this.getWorkerForSession(sessionId);
      if (entry) {
        this.sendToWorker(entry, {
          type: 'ipc:approval',
          sessionId,
          requestId,
          decision,
        });
        return;
      }
    }

    // Fallback: broadcast to all workers if we can't route
    logger.warn({ requestId }, 'Could not route approval — broadcasting to all workers');
    for (const worker of this.workers.values()) {
      if (worker.process.connected) {
        this.sendToWorker(worker, {
          type: 'ipc:approval',
          sessionId: sessionId ?? '',
          requestId,
          decision,
        });
      }
    }
  }

  async cancelOperation(sessionId: string): Promise<void> {
    const entry = this.getWorkerForSession(sessionId);
    if (!entry) return;
    this.sendToWorker(entry, {
      type: 'ipc:cancel',
      sessionId,
    });
    // Mirror old ClaudeCliAdapter behavior: clean up parent-side state
    entry.sessionIds.delete(sessionId);
    this.sessionWorkerMap.delete(sessionId);
    this.sessionManager.close(sessionId);
    // Clear any pending approvals for this session
    this.clearApprovalsForSession(sessionId);
  }

  destroySession(sessionId: string): void {
    const entry = this.getWorkerForSession(sessionId);
    if (entry) {
      this.sendToWorker(entry, {
        type: 'ipc:session.destroy',
        sessionId,
      });
      entry.sessionIds.delete(sessionId);
    }
    this.sessionWorkerMap.delete(sessionId);
    this.clearApprovalsForSession(sessionId);
    logger.info({ sessionId }, 'Session destroyed in fleet');
  }

  /** Check if a session is tracked by the fleet */
  hasSession(sessionId: string): boolean {
    return this.sessionWorkerMap.has(sessionId);
  }

  /** Check if a session is alive within its worker */
  isSessionAlive(sessionId: string): boolean {
    const entry = this.getWorkerForSession(sessionId);
    if (!entry || !entry.process.connected) return false;
    // Only report alive if the session is still tracked by the worker
    return entry.sessionIds.has(sessionId);
  }

  /** Get pending approval details for re-broadcast on client reconnect */
  getPendingApprovals(): Array<{ requestId: string; tool: string; description: string; details: Record<string, unknown> }> {
    return [...this.pendingApprovals.values()];
  }

  /** Number of pending approvals across all workers */
  get pendingApprovalCount(): number {
    return this.pendingApprovals.size;
  }

  /** Clear all parent-side pending approval tracking (used when workers auto-flush on mode change) */
  clearPendingApprovals(): void {
    this.pendingApprovals.clear();
    this.approvalSessionMap.clear();
  }

  /**
   * Phase 13 Wave 3 — inject an `agent-lifecycle` event from a
   * non-worker source (the PTY shell hook server). Routes through the
   * same emitter that `ipc:agent.lifecycle` messages from workers use,
   * so `ws.ts:1662-1693` picks it up and runs the full
   * `agentTracker.spawn/dismiss` + `broadcastToAll` fan-out with no
   * special-casing. Kept minimal on purpose — the handoff spec says
   * the tracker + fanout do not change in Wave 3, only the producers.
   */
  reportAgentLifecycle(event: AgentEvent): void {
    this.emitter.emit('agent-lifecycle', event);
  }

  /** Clear pending approvals for a specific session */
  private clearApprovalsForSession(sessionId: string): void {
    const toDelete: string[] = [];
    for (const [requestId, sid] of this.approvalSessionMap) {
      if (sid === sessionId) toDelete.push(requestId);
    }
    for (const requestId of toDelete) {
      this.approvalSessionMap.delete(requestId);
      this.pendingApprovals.delete(requestId);
    }
  }

  /** Set permission mode on all workers */
  setPermissionMode(mode: PermissionMode, delaySeconds?: number, godSubMode?: GodSubMode): void {
    // Update parent-side filter
    this.permissionFilter.setMode(mode, delaySeconds, godSubMode);

    // Broadcast to all workers
    for (const entry of this.workers.values()) {
      this.sendToWorker(entry, {
        type: 'ipc:permission.mode',
        mode,
        delaySeconds,
        godSubMode,
      });
    }
  }

  /** Add a context file to a session's worker */
  addContextFile(sessionId: string, path: string, content: string): void {
    const entry = this.getWorkerForSession(sessionId);
    if (entry) {
      this.sendToWorker(entry, {
        type: 'ipc:context.add',
        sessionId,
        path,
        content,
      });
    }
  }

  /** Remove a context file from a session's worker */
  removeContextFile(sessionId: string, path: string): void {
    const entry = this.getWorkerForSession(sessionId);
    if (entry) {
      this.sendToWorker(entry, {
        type: 'ipc:context.remove',
        sessionId,
        path,
      });
    }
  }

  // ── Fleet status ──────────────────────────────────────────

  getFleetStatus(): FleetStatus {
    const now = Date.now();
    const workerStatuses: WorkerStatus[] = [];

    for (const entry of this.workers.values()) {
      workerStatuses.push({
        workerId: entry.workerId,
        workingDir: entry.workingDir,
        sessionCount: entry.sessionIds.size,
        uptimeMs: now - entry.startedAt,
        restartCount: entry.restartCount,
        healthy: entry.process.connected && entry.ready,
        pid: entry.process.pid,
      });
    }

    return {
      totalWorkers: this.workers.size,
      totalSessions: this.sessionWorkerMap.size,
      workers: workerStatuses,
    };
  }

  /** Get the session IDs belonging to a specific worker */
  getWorkerSessionIds(workerId: string): string[] {
    for (const entry of this.workers.values()) {
      if (entry.workerId === workerId) {
        return [...entry.sessionIds];
      }
    }
    return [];
  }

  getWorkerForSessionId(sessionId: string): WorkerStatus | undefined {
    const entry = this.getWorkerForSession(sessionId);
    if (!entry) return undefined;
    return {
      workerId: entry.workerId,
      workingDir: entry.workingDir,
      sessionCount: entry.sessionIds.size,
      uptimeMs: Date.now() - entry.startedAt,
      restartCount: entry.restartCount,
      healthy: entry.process.connected && entry.ready,
      pid: entry.process.pid,
    };
  }

  // ── Internal helpers ──────────────────────────────────────

  private getWorkerForSession(sessionId: string): WorkerEntry | undefined {
    const canonicalDir = this.sessionWorkerMap.get(sessionId);
    if (!canonicalDir) return undefined;
    return this.workers.get(canonicalDir);
  }

  // ── Event emitter interface (matches ClaudeCliAdapter) ────

  on(event: 'output', handler: (sessionId: string, chunk: string) => void): void;
  on(event: 'approval-request', handler: (request: ApprovalRequest) => void): void;
  on(event: 'auto-allow', handler: (event: AutoAllowEvent) => void): void;
  on(event: 'tool-start', handler: (info: ToolInfo) => void): void;
  on(event: 'tool-complete', handler: (result: ToolResult) => void): void;
  on(event: 'agent-lifecycle', handler: (event: AgentEvent) => void): void;
  on(event: 'session-result', handler: (result: SessionResult) => void): void;
  on(event: 'worker-spawned', handler: (info: { workerId: string; workingDir: string; dirName: string }) => void): void;
  on(event: 'worker-crashed', handler: (info: { workerId: string; workingDir: string; dirName: string; restartCount: number }) => void): void;
  on(event: 'worker-restarted', handler: (info: { workerId: string; workingDir: string; dirName: string; restartCount: number }) => void): void;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  on(event: string, handler: (...args: any[]) => void): void {
    this.emitter.on(event, handler);
  }

  // ── Graceful shutdown ─────────────────────────────────────

  async dispose(): Promise<void> {
    this.shuttingDown = true;
    const shutdownPromises: Promise<void>[] = [];

    for (const entry of this.workers.values()) {
      if (entry.process.connected) {
        shutdownPromises.push(
          new Promise<void>((resolve) => {
            const timeout = setTimeout(() => {
              logger.warn({ workerId: entry.workerId.slice(0, 8) }, 'Worker did not exit in time — killing');
              entry.process.kill('SIGKILL');
              resolve();
            }, 5000);

            entry.process.once('exit', () => {
              clearTimeout(timeout);
              resolve();
            });

            entry.process.kill('SIGTERM');
          }),
        );
      }
    }

    await Promise.all(shutdownPromises);

    this.workers.clear();
    this.sessionWorkerMap.clear();
    this.emitter.removeAllListeners();
    logger.info('FleetManager disposed — all workers terminated');
  }
}
