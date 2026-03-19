import { logger } from '../utils/logger.js';

export type ApprovalDecision = 'allow' | 'deny' | 'skip' | 'allow_always';
export type ApprovalMode = 'manual' | 'auto' | 'delay';

interface PendingApproval {
  requestId: string;
  tool: string;
  resolve: (decision: ApprovalDecision) => void;
  timer: ReturnType<typeof setTimeout>;
  /** Optional delay timer for 'delay' mode auto-approval */
  delayTimer?: ReturnType<typeof setTimeout>;
  createdAt: number;
}

// ── Approval Queue ──────────────────────────────────────────
// Hook scripts POST approval requests here and block until
// the iOS app sends a decision back through the WebSocket.

export class ApprovalQueue {
  private pending = new Map<string, PendingApproval>();
  private timeoutMs: number;
  private mode: ApprovalMode = 'manual';
  private delaySeconds = 10;

  constructor(timeoutMs = 5 * 60 * 1000) {
    this.timeoutMs = timeoutMs;
  }

  /**
   * Set the approval mode.
   * - 'manual': block until the client responds (default)
   * - 'auto': immediately allow all requests (ClaudeGod mode)
   * - 'delay': auto-allow after delaySeconds unless client responds first
   */
  setMode(mode: ApprovalMode, delaySeconds?: number): void {
    const prevMode = this.mode;
    this.mode = mode;

    // Validate and clamp delaySeconds to safe range [1, 300]
    if (delaySeconds !== undefined) {
      this.delaySeconds = Math.max(1, Math.min(300, Math.floor(delaySeconds || 10)));
    }

    // Cancel existing delay timers when switching away from delay mode
    if (prevMode === 'delay' && mode !== 'delay') {
      for (const entry of this.pending.values()) {
        if (entry.delayTimer) {
          clearTimeout(entry.delayTimer);
          entry.delayTimer = undefined;
        }
      }
    }

    // Apply new mode to already-pending approvals
    if (mode === 'auto') {
      // Resolve all pending as 'allow'
      for (const requestId of [...this.pending.keys()]) {
        logger.info({ requestId, mode: 'auto' }, 'Mode switch: auto-approving pending request');
        this.resolve(requestId, 'allow');
      }
    } else if (mode === 'delay') {
      // Attach delay timers to pending entries that don't already have one
      for (const entry of this.pending.values()) {
        if (!entry.delayTimer) {
          entry.delayTimer = setTimeout(() => {
            if (this.pending.has(entry.requestId)) {
              logger.info(
                { requestId: entry.requestId, tool: entry.tool, delaySeconds: this.delaySeconds },
                'Delay expired, auto-approving',
              );
              this.resolve(entry.requestId, 'allow');
            }
          }, this.delaySeconds * 1000);
        }
      }
    }

    logger.info({ mode, prevMode, delaySeconds: this.delaySeconds }, 'Approval mode updated');
  }

  /** Get current approval mode */
  getMode(): ApprovalMode {
    return this.mode;
  }

  /**
   * Queue an approval request and wait for a decision.
   * Returns a Promise that resolves when the iOS app responds.
   * The hook script blocks on this.
   */
  waitForDecision(requestId: string, tool: string): Promise<ApprovalDecision> {
    // Auto mode: immediately allow without queuing
    if (this.mode === 'auto') {
      logger.info({ requestId, tool, mode: 'auto' }, 'Auto-approving (ClaudeGod mode)');
      return Promise.resolve('allow');
    }

    return new Promise<ApprovalDecision>((resolve) => {
      // Timeout: auto-deny if no response
      const timer = setTimeout(() => {
        if (this.pending.has(requestId)) {
          logger.warn({ requestId, tool }, 'Approval timed out, auto-denying');
          this.resolve(requestId, 'deny');
        }
      }, this.timeoutMs);

      const entry: PendingApproval = {
        requestId,
        tool,
        resolve,
        timer,
        createdAt: Date.now(),
      };

      // Delay mode: set a timer to auto-allow after delaySeconds
      if (this.mode === 'delay') {
        entry.delayTimer = setTimeout(() => {
          if (this.pending.has(requestId)) {
            logger.info(
              { requestId, tool, delaySeconds: this.delaySeconds },
              'Delay expired, auto-approving',
            );
            this.resolve(requestId, 'allow');
          }
        }, this.delaySeconds * 1000);
      }

      this.pending.set(requestId, entry);
      logger.info({ requestId, tool, mode: this.mode }, 'Approval queued, waiting for decision');
    });
  }

  /**
   * Resolve a pending approval with a decision from the iOS app.
   */
  resolve(requestId: string, decision: ApprovalDecision): boolean {
    const entry = this.pending.get(requestId);
    if (!entry) {
      logger.warn({ requestId }, 'Approval resolve: no pending request found');
      return false;
    }
    this.pending.delete(requestId);
    clearTimeout(entry.timer);
    if (entry.delayTimer) {
      clearTimeout(entry.delayTimer);
    }
    entry.resolve(decision);
    logger.info({ requestId, decision, tool: entry.tool }, 'Approval resolved');
    return true;
  }

  /** Get all pending approval request IDs */
  getPending(): string[] {
    return [...this.pending.keys()];
  }

  /** Check if a specific request is pending */
  isPending(requestId: string): boolean {
    return this.pending.has(requestId);
  }

  /** Number of pending approvals */
  get size(): number {
    return this.pending.size;
  }
}
