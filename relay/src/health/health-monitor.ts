/**
 * Health Monitor — Process watchdog for Claude Code SDK sessions.
 *
 * Tracks per-session health: pid (N/A for SDK), uptime, last activity,
 * restart count. Detects hangs (no output for configurable timeout) and
 * crashed streams (streamAlive === false). Logs all health events via pino.
 */

import { logger } from '../utils/logger.js';
import type { ToolInfo, ToolResult, SessionResult } from '../adapters/adapter.interface.js';
import type { SessionManager } from '../sessions/session-manager.js';

/** Subset of adapter/FleetManager interface needed by HealthMonitor */
export interface HealthMonitorTarget {
  isSessionAlive(sessionId: string): boolean;
  on(event: 'output', handler: (sessionId: string, chunk: string) => void): void;
  on(event: 'tool-start', handler: (info: ToolInfo) => void): void;
  on(event: 'tool-complete', handler: (result: ToolResult) => void): void;
  on(event: 'session-result', handler: (result: SessionResult) => void): void;
}

// ── Types ────────────────────────────────────────────────────

export interface SessionHealthStatus {
  sessionId: string;
  status: 'healthy' | 'idle' | 'unresponsive' | 'dead';
  uptimeMs: number;
  lastActivityAt: string;
  lastActivityAgoMs: number;
  restartCount: number;
  streamAlive: boolean;
}

export interface HealthMonitorConfig {
  /** How often to check session health (ms). Default: 30s */
  checkIntervalMs: number;
  /** Time with no output before marking session as unresponsive (ms). Default: 5 min */
  hangTimeoutMs: number;
}

const DEFAULT_CONFIG: HealthMonitorConfig = {
  checkIntervalMs: 30_000,
  hangTimeoutMs: 5 * 60 * 1000,
};

// ── Per-session tracking data ────────────────────────────────

interface SessionHealthEntry {
  sessionId: string;
  startedAt: number;
  lastActivityAt: number;
  restartCount: number;
  /** Previous status for detecting transitions */
  lastReportedStatus: SessionHealthStatus['status'] | null;
}

// ── Health Monitor ───────────────────────────────────────────

export class HealthMonitor {
  private entries = new Map<string, SessionHealthEntry>();
  private checkTimer: ReturnType<typeof setInterval> | null = null;
  private config: HealthMonitorConfig;
  private target: HealthMonitorTarget;
  private sessionManager: SessionManager;
  private wired = false;

  constructor(
    target: HealthMonitorTarget,
    sessionManager: SessionManager,
    config: Partial<HealthMonitorConfig> = {},
  ) {
    this.target = target;
    this.sessionManager = sessionManager;
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  /** Start the periodic health check loop */
  start(): void {
    if (this.checkTimer) return;

    this.wireAdapterEvents();

    this.checkTimer = setInterval(() => {
      this.runHealthCheck();
    }, this.config.checkIntervalMs);

    logger.info(
      {
        checkIntervalMs: this.config.checkIntervalMs,
        hangTimeoutMs: this.config.hangTimeoutMs,
      },
      'Health monitor started',
    );
  }

  /** Stop the health check loop */
  stop(): void {
    if (this.checkTimer) {
      clearInterval(this.checkTimer);
      this.checkTimer = null;
    }
    logger.info('Health monitor stopped');
  }

  /** Track a new session */
  trackSession(sessionId: string): void {
    const now = Date.now();
    const existing = this.entries.get(sessionId);
    this.entries.set(sessionId, {
      sessionId,
      startedAt: existing?.startedAt ?? now,
      lastActivityAt: now,
      restartCount: existing?.restartCount ?? 0,
      lastReportedStatus: null,
    });
    logger.debug({ sessionId }, 'Health monitor: tracking session');
  }

  /** Record activity for a session (call on output, tool events, etc.) */
  recordActivity(sessionId: string): void {
    const entry = this.entries.get(sessionId);
    if (entry) {
      entry.lastActivityAt = Date.now();
    }
  }

  /** Record that a session was restarted */
  recordRestart(sessionId: string): void {
    const entry = this.entries.get(sessionId);
    if (entry) {
      entry.restartCount++;
      entry.lastActivityAt = Date.now();
      logger.info(
        { sessionId, restartCount: entry.restartCount },
        'Health monitor: session restart recorded',
      );
    }
  }

  /** Stop tracking a session (on close/destroy) */
  untrackSession(sessionId: string): void {
    this.entries.delete(sessionId);
    logger.debug({ sessionId }, 'Health monitor: untracked session');
  }

  /** Get health status for all tracked sessions */
  getHealthStatuses(): SessionHealthStatus[] {
    const now = Date.now();
    const statuses: SessionHealthStatus[] = [];

    for (const entry of this.entries.values()) {
      statuses.push(this.buildStatus(entry, now));
    }

    return statuses;
  }

  /** Get health status for a single session */
  getSessionHealth(sessionId: string): SessionHealthStatus | undefined {
    const entry = this.entries.get(sessionId);
    if (!entry) return undefined;
    return this.buildStatus(entry, Date.now());
  }

  // ── Internal ───────────────────────────────────────────────

  private buildStatus(entry: SessionHealthEntry, now: number): SessionHealthStatus {
    const streamAlive = this.target.isSessionAlive(entry.sessionId);
    const lastActivityAgoMs = now - entry.lastActivityAt;
    const uptimeMs = now - entry.startedAt;

    let status: SessionHealthStatus['status'];
    if (!streamAlive) {
      status = 'dead';
    } else if (lastActivityAgoMs > this.config.hangTimeoutMs) {
      // Session is alive but no output for a long time — could be waiting for
      // user input (which is normal). We mark it 'unresponsive' as an FYI,
      // not an error. The session might be waiting for a prompt or approval.
      const session = this.sessionManager.tryGet(entry.sessionId);
      if (session?.status === 'active') {
        status = 'unresponsive';
      } else {
        status = 'idle';
      }
    } else {
      const session = this.sessionManager.tryGet(entry.sessionId);
      status = session?.status === 'active' ? 'healthy' : 'idle';
    }

    return {
      sessionId: entry.sessionId,
      status,
      uptimeMs,
      lastActivityAt: new Date(entry.lastActivityAt).toISOString(),
      lastActivityAgoMs,
      restartCount: entry.restartCount,
      streamAlive,
    };
  }

  private runHealthCheck(): void {
    const now = Date.now();

    for (const entry of this.entries.values()) {
      const healthStatus = this.buildStatus(entry, now);

      // Log status transitions
      if (entry.lastReportedStatus !== healthStatus.status) {
        const prev = entry.lastReportedStatus;
        entry.lastReportedStatus = healthStatus.status;

        if (healthStatus.status === 'dead') {
          logger.warn(
            {
              sessionId: entry.sessionId,
              previousStatus: prev,
              uptimeMs: healthStatus.uptimeMs,
              restartCount: entry.restartCount,
            },
            'Health check: session stream is dead',
          );
        } else if (healthStatus.status === 'unresponsive') {
          logger.warn(
            {
              sessionId: entry.sessionId,
              lastActivityAgoMs: healthStatus.lastActivityAgoMs,
              hangTimeoutMs: this.config.hangTimeoutMs,
            },
            'Health check: session appears unresponsive (no recent activity)',
          );
        } else if (prev === 'dead' || prev === 'unresponsive') {
          logger.info(
            {
              sessionId: entry.sessionId,
              status: healthStatus.status,
              previousStatus: prev,
            },
            'Health check: session recovered',
          );
        }
      }
    }
  }

  /** Wire into adapter events to auto-track activity (idempotent — only wires once) */
  private wireAdapterEvents(): void {
    if (this.wired) return;
    this.wired = true;

    this.target.on('output', (sessionId: string, _chunk: string) => {
      this.recordActivity(sessionId);
    });

    this.target.on('tool-start', (info) => {
      this.recordActivity(info.sessionId);
    });

    this.target.on('tool-complete', (result) => {
      this.recordActivity(result.sessionId);
    });

    this.target.on('session-result', (result) => {
      this.recordActivity(result.sessionId);
    });
  }

  dispose(): void {
    this.stop();
    this.entries.clear();
  }
}
