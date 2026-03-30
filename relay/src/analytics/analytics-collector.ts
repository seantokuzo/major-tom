/**
 * AnalyticsCollector — Append-only JSONL analytics logging.
 *
 * Writes per-turn, session, and worker lifecycle events to ~/.major-tom/analytics.jsonl.
 * Hooks into FleetManager events (session-result, tool-start, tool-complete)
 * and session lifecycle to capture cost, token, duration, and tool usage data.
 *
 * In fleet mode the parent process runs the collector; workers send
 * analytics data via IPC which the FleetManager relays here.
 */

import { appendFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { homedir } from 'node:os';
import { logger } from '../utils/logger.js';

// ── JSONL event types ──────────────────────────────────────

export interface TurnCompleteEvent {
  event: 'turn_complete';
  sessionId: string;
  workerId?: string;
  model?: string;
  inputTokens: number;
  outputTokens: number;
  cacheCreationTokens: number;
  cacheReadTokens: number;
  cost: number;
  durationMs: number;
  toolsUsed: string[];
  timestamp: string;
}

export interface SessionStartEvent {
  event: 'session_start';
  sessionId: string;
  workerId?: string;
  workingDir: string;
  timestamp: string;
}

export interface SessionEndEvent {
  event: 'session_end';
  sessionId: string;
  workerId?: string;
  totalCost: number;
  totalTokens: number;
  durationMs: number;
  turnCount: number;
  timestamp: string;
}

export interface WorkerStartEvent {
  event: 'worker_start';
  workerId: string;
  workingDir: string;
  timestamp: string;
}

export interface WorkerStopEvent {
  event: 'worker_stop';
  workerId: string;
  reason: string;
  timestamp: string;
}

export type AnalyticsEvent =
  | TurnCompleteEvent
  | SessionStartEvent
  | SessionEndEvent
  | WorkerStartEvent
  | WorkerStopEvent;

// ── AnalyticsCollector ─────────────────────────────────────

const ANALYTICS_DIR = resolve(homedir(), '.major-tom');
const ANALYTICS_FILE = resolve(ANALYTICS_DIR, 'analytics.jsonl');

export class AnalyticsCollector {
  private writeQueue: Promise<void> = Promise.resolve();
  private filePath: string;
  private initialized = false;

  /** Per-session tool tracking: sessionId → tool names used in current turn */
  private turnTools = new Map<string, string[]>();

  constructor(filePath?: string) {
    this.filePath = filePath ?? ANALYTICS_FILE;
  }

  // ── Initialization ───────────────────────────────────────

  private async ensureDir(): Promise<void> {
    if (this.initialized) return;
    try {
      await mkdir(ANALYTICS_DIR, { recursive: true });
      this.initialized = true;
    } catch (err) {
      logger.error({ err }, 'Failed to create analytics directory');
    }
  }

  // ── Write (atomic line append) ───────────────────────────

  private append(event: AnalyticsEvent): void {
    this.writeQueue = this.writeQueue
      .then(() => this.ensureDir())
      .then(() => {
        const line = JSON.stringify(event) + '\n';
        return appendFile(this.filePath, line, { encoding: 'utf-8' });
      })
      .catch((err) => {
        logger.error({ err, event: event.event }, 'Failed to write analytics event');
      });
  }

  // ── Public recording methods ─────────────────────────────

  recordTurnComplete(data: {
    sessionId: string;
    workerId?: string;
    model?: string;
    inputTokens: number;
    outputTokens: number;
    cacheCreationTokens?: number;
    cacheReadTokens?: number;
    cost: number;
    durationMs: number;
    toolsUsed?: string[];
  }): void {
    // Merge tracked tools with any explicit list
    const tracked = this.turnTools.get(data.sessionId) ?? [];
    const toolsUsed = data.toolsUsed ?? tracked;
    // Clear turn tools for next turn
    this.turnTools.delete(data.sessionId);

    this.append({
      event: 'turn_complete',
      sessionId: data.sessionId,
      workerId: data.workerId,
      model: data.model,
      inputTokens: data.inputTokens,
      outputTokens: data.outputTokens,
      cacheCreationTokens: data.cacheCreationTokens ?? 0,
      cacheReadTokens: data.cacheReadTokens ?? 0,
      cost: data.cost,
      durationMs: data.durationMs,
      toolsUsed,
      timestamp: new Date().toISOString(),
    });
  }

  recordSessionStart(data: {
    sessionId: string;
    workerId?: string;
    workingDir: string;
  }): void {
    this.append({
      event: 'session_start',
      sessionId: data.sessionId,
      workerId: data.workerId,
      workingDir: data.workingDir,
      timestamp: new Date().toISOString(),
    });
  }

  recordSessionEnd(data: {
    sessionId: string;
    workerId?: string;
    totalCost: number;
    totalTokens: number;
    durationMs: number;
    turnCount: number;
  }): void {
    this.append({
      event: 'session_end',
      sessionId: data.sessionId,
      workerId: data.workerId,
      totalCost: data.totalCost,
      totalTokens: data.totalTokens,
      durationMs: data.durationMs,
      turnCount: data.turnCount,
      timestamp: new Date().toISOString(),
    });
  }

  recordWorkerStart(data: {
    workerId: string;
    workingDir: string;
  }): void {
    this.append({
      event: 'worker_start',
      workerId: data.workerId,
      workingDir: data.workingDir,
      timestamp: new Date().toISOString(),
    });
  }

  recordWorkerStop(data: {
    workerId: string;
    reason: string;
  }): void {
    this.append({
      event: 'worker_stop',
      workerId: data.workerId,
      reason: data.reason,
      timestamp: new Date().toISOString(),
    });
  }

  /** Track a tool usage within a session's current turn */
  trackToolUsage(sessionId: string, toolName: string): void {
    const existing = this.turnTools.get(sessionId) ?? [];
    if (!existing.includes(toolName)) {
      existing.push(toolName);
      this.turnTools.set(sessionId, existing);
    }
  }

  // ── File path accessor (for analytics API) ──────────────

  getFilePath(): string {
    return this.filePath;
  }

  // ── Flush outstanding writes ─────────────────────────────

  async flush(): Promise<void> {
    await this.writeQueue;
  }
}
