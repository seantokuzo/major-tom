import { logger } from '../utils/logger.js';

export type ApprovalDecision = 'allow' | 'deny' | 'skip' | 'allow_always';

interface PendingApproval {
  requestId: string;
  tool: string;
  resolve: (decision: ApprovalDecision) => void;
  timer: ReturnType<typeof setTimeout>;
  createdAt: number;
}

// ── Approval Queue ──────────────────────────────────────────
// Hook scripts POST approval requests here and block until
// the iOS app sends a decision back through the WebSocket.

export class ApprovalQueue {
  private pending = new Map<string, PendingApproval>();
  private timeoutMs: number;

  constructor(timeoutMs = 5 * 60 * 1000) {
    this.timeoutMs = timeoutMs;
  }

  /**
   * Queue an approval request and wait for a decision.
   * Returns a Promise that resolves when the iOS app responds.
   * The hook script blocks on this.
   */
  waitForDecision(requestId: string, tool: string): Promise<ApprovalDecision> {
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
      this.pending.set(requestId, entry);
      logger.info({ requestId, tool }, 'Approval queued, waiting for decision');
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
