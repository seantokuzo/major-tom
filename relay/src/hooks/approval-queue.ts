import { EventEmitter } from 'node:events';
import { logger } from '../utils/logger.js';
import { sendKeys, MAJOR_TOM_SESSION } from '../utils/tmux-cli.js';

export type ApprovalDecision = 'allow' | 'deny' | 'skip' | 'allow_always';
/** Queue-level mode: manual blocks, auto resolves immediately, delay resolves after timer */
export type ApprovalQueueMode = 'manual' | 'auto' | 'delay';

/**
 * Wave 2: ORTHOGONAL routing dimension. Independent of `manual`/`auto`/`delay`.
 * - `local`  — TUI owns the decision; phone gets a passive notification
 * - `remote` — phone owns the decision; TUI is bypassed (hook blocks)
 * - `hybrid` — both prompt; first to resolve wins; phone-wins uses tmux send-keys
 */
export type ApprovalRoutingMode = 'local' | 'remote' | 'hybrid';

/** Where the request originated. Used to decide enqueue behavior + dedup. */
export type ApprovalSource = 'sdk' | 'hook';

interface PendingApproval {
  requestId: string;
  tool: string;
  description: string;
  details: Record<string, unknown>;
  resolve: (decision: ApprovalDecision) => void;
  timer: ReturnType<typeof setTimeout>;
  /** Optional delay timer for 'delay' mode auto-approval */
  delayTimer?: ReturnType<typeof setTimeout>;
  createdAt: number;
  // ── Wave 2 routing fields (optional for backwards compat) ──
  /** Canonical Claude tool_use_id — populated when source==='sdk' or source==='hook' */
  toolUseId?: string;
  /** Routing dimension — local/remote/hybrid. Defaults to 'local' for legacy callers. */
  routingMode?: ApprovalRoutingMode;
  /** Origin path: sdk callback or shell hook script */
  source?: ApprovalSource;
  /** tmux window name for hybrid send-keys target */
  tabId?: string;
}

interface EnqueueOptions {
  /** Canonical dedup key — typically Claude's tool_use_id */
  dedupKey: string;
  source: ApprovalSource;
  routingMode: ApprovalRoutingMode;
  tool: string;
  description?: string;
  details?: Record<string, unknown>;
  /** Required for hybrid mode so the relay knows where to inject keystrokes */
  tabId?: string;
  /** Optional abort signal that resolves the approval as 'deny' if aborted */
  signal?: AbortSignal;
}

// ── Approval Queue ──────────────────────────────────────────
// Hook scripts AND the SDK callback path both flow through this queue.
// Wave 2 added orthogonal routing-mode dimension and tool_use_id dedup.
//
// Emits the following events for the WebSocket layer to broadcast:
//   - 'enqueue'  → { requestId, tool, description, details, source, routingMode }
//   - 'resolve'  → { requestId, decision }
//   - 'expired'  → { requestId }
//
// The events are additive; existing waitForDecision() callsites that don't
// pass routing options keep working untouched.

export class ApprovalQueue extends EventEmitter {
  private pending = new Map<string, PendingApproval>();
  private timeoutMs: number;
  private mode: ApprovalQueueMode = 'manual';
  private delaySeconds = 10;
  /** Recently resolved tool_use_ids — short TTL, used to short-circuit hybrid races. */
  private resolved = new Map<string, ApprovalDecision>();
  private RESOLVED_TTL_MS = 60_000;

  constructor(timeoutMs = 5 * 60 * 1000) {
    super();
    this.timeoutMs = timeoutMs;
    // Match listener cap to FleetManager scale (50)
    this.setMaxListeners(50);
  }

  /**
   * Set the approval mode.
   * - 'manual': block until the client responds (default)
   * - 'auto': immediately allow all requests (ClaudeGod mode)
   * - 'delay': auto-allow after delaySeconds unless client responds first
   */
  setMode(mode: ApprovalQueueMode, delaySeconds?: number): void {
    const prevMode = this.mode;
    this.mode = mode;

    // Validate and clamp delaySeconds to safe range [1, 300]
    if (delaySeconds !== undefined) {
      const parsed = typeof delaySeconds === 'number' ? delaySeconds : NaN;
      this.delaySeconds = Number.isFinite(parsed)
        ? Math.max(1, Math.min(300, Math.floor(parsed)))
        : this.delaySeconds;
    }

    // Cancel existing delay timers when switching away from delay mode,
    // or when re-entering delay mode (timers will be re-created with new delay)
    if (prevMode === 'delay') {
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

  /** Get current queue mode */
  getMode(): ApprovalQueueMode {
    return this.mode;
  }

  /** Flush all pending approvals by auto-allowing them (used when switching to god mode) */
  flushPending(): void {
    for (const requestId of [...this.pending.keys()]) {
      logger.info({ requestId, reason: 'god-mode-flush' }, 'Flushing pending approval');
      this.resolve(requestId, 'allow');
    }
  }

  /** Flush pending approvals that match a predicate (used when switching to smart mode) */
  flushMatching(predicate: (tool: string, details: Record<string, unknown>) => boolean): void {
    for (const [requestId, entry] of [...this.pending.entries()]) {
      if (predicate(entry.tool, entry.details)) {
        logger.info({ requestId, tool: entry.tool, reason: 'smart-mode-flush' }, 'Flushing matching pending approval');
        this.resolve(requestId, 'allow');
      }
    }
  }

  /**
   * Queue an approval request and wait for a decision.
   * Returns a Promise that resolves when the iOS app responds.
   * The hook script blocks on this.
   *
   * Wave 2: optional `signal` aborts the wait and resolves as 'deny'. The
   * SDK adapter threads the canUseTool `options.signal` through this so
   * cancellations clean up properly. Existing callsites without a signal
   * remain unaffected.
   */
  waitForDecision(
    requestId: string,
    tool: string,
    description = '',
    details: Record<string, unknown> = {},
    signal?: AbortSignal,
  ): Promise<ApprovalDecision> {
    // Auto mode: immediately allow without queuing
    if (this.mode === 'auto') {
      logger.info({ requestId, tool, mode: 'auto' }, 'Auto-approving (ClaudeGod mode)');
      return Promise.resolve('allow');
    }

    // Pre-aborted signal: resolve immediately as deny.
    if (signal?.aborted) {
      logger.info({ requestId, tool }, 'Approval aborted before enqueue');
      return Promise.resolve('deny');
    }

    return new Promise<ApprovalDecision>((resolve) => {
      // Timeout: auto-deny if no response
      const timer = setTimeout(() => {
        if (this.pending.has(requestId)) {
          logger.warn({ requestId, tool }, 'Approval timed out, auto-denying');
          this.emit('expired', { requestId });
          this.resolve(requestId, 'deny');
        }
      }, this.timeoutMs);

      const entry: PendingApproval = {
        requestId,
        tool,
        description,
        details,
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

      // Wire abort signal — resolves as 'deny' and removes the entry. We
      // intentionally do NOT call this.resolve() with the public method
      // because the caller's promise handler is the same `resolve` we own.
      if (signal) {
        const onAbort = () => {
          if (this.pending.has(requestId)) {
            logger.info({ requestId, tool }, 'Approval aborted by signal');
            this.resolve(requestId, 'deny');
          }
        };
        signal.addEventListener('abort', onAbort, { once: true });
      }

      this.pending.set(requestId, entry);
      logger.info({ requestId, tool, mode: this.mode }, 'Approval queued, waiting for decision');
    });
  }

  /**
   * Wave 2 unified entrypoint that supports the routing-mode dimension.
   * Idempotent on dedupKey — duplicate enqueues attach to the existing
   * pending entry instead of creating a new one. Returns the same Promise
   * for both calls so dedup is cooperative.
   */
  enqueueAndWait(opts: EnqueueOptions): Promise<ApprovalDecision> {
    const {
      dedupKey,
      source,
      routingMode,
      tool,
      description = '',
      details = {},
      tabId,
      signal,
    } = opts;

    // ── Recently-resolved short-circuit (hybrid race protection) ──
    const cached = this.resolved.get(dedupKey);
    if (cached) {
      logger.info({ dedupKey, decision: cached, tool }, 'Approval already resolved (cache hit)');
      return Promise.resolve(cached);
    }

    // ── Dedup: same toolUseId already in flight → attach to it ──
    const existing = this.pending.get(dedupKey);
    if (existing) {
      logger.info({ dedupKey, tool, source }, 'Approval dedup — returning existing pending Promise');
      return new Promise<ApprovalDecision>((resolveAttach) => {
        // Wrap the existing resolve so both callers see the result.
        const originalResolve = existing.resolve;
        existing.resolve = (decision) => {
          originalResolve(decision);
          resolveAttach(decision);
        };
      });
    }

    // Auto mode escape — same as legacy waitForDecision.
    if (this.mode === 'auto') {
      logger.info({ dedupKey, tool, mode: 'auto' }, 'Auto-approving (ClaudeGod mode)');
      this.markResolved(dedupKey, 'allow');
      return Promise.resolve('allow');
    }

    if (signal?.aborted) {
      logger.info({ dedupKey, tool }, 'Approval aborted before enqueue');
      return Promise.resolve('deny');
    }

    // Build the pending entry with routing fields populated.
    return new Promise<ApprovalDecision>((resolveOuter) => {
      const timer = setTimeout(() => {
        if (this.pending.has(dedupKey)) {
          logger.warn({ dedupKey, tool, routingMode }, 'Approval timed out, auto-denying');
          this.emit('expired', { requestId: dedupKey });
          this.resolve(dedupKey, 'deny');
        }
      }, this.timeoutMs);

      const entry: PendingApproval = {
        requestId: dedupKey,
        tool,
        description,
        details,
        resolve: resolveOuter,
        timer,
        createdAt: Date.now(),
        toolUseId: dedupKey,
        routingMode,
        source,
        tabId,
      };

      if (this.mode === 'delay') {
        entry.delayTimer = setTimeout(() => {
          if (this.pending.has(dedupKey)) {
            logger.info(
              { dedupKey, tool, delaySeconds: this.delaySeconds },
              'Delay expired, auto-approving',
            );
            this.resolve(dedupKey, 'allow');
          }
        }, this.delaySeconds * 1000);
      }

      if (signal) {
        const onAbort = () => {
          if (this.pending.has(dedupKey)) {
            logger.info({ dedupKey, tool }, 'Approval aborted by signal');
            this.resolve(dedupKey, 'deny');
          }
        };
        signal.addEventListener('abort', onAbort, { once: true });
      }

      this.pending.set(dedupKey, entry);
      logger.info(
        { dedupKey, tool, mode: this.mode, routingMode, source, tabId },
        'Approval enqueued (Wave 2)',
      );

      // Tell the WS layer there's a new pending approval.
      this.emit('enqueue', {
        requestId: dedupKey,
        tool,
        description,
        details,
        source,
        routingMode,
        tabId,
      });
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
    // Cache the decision for hybrid race short-circuit (TTL-bounded).
    if (entry.toolUseId) {
      this.markResolved(entry.toolUseId, decision);
    }
    entry.resolve(decision);
    logger.info({ requestId, decision, tool: entry.tool, source: entry.source }, 'Approval resolved');
    this.emit('resolve', { requestId, decision });
    return true;
  }

  /**
   * Resolve a hybrid-mode approval coming from the phone. Marks the
   * dedupKey as resolved (short-circuiting any duplicate enqueue) and
   * injects the decision into the tmux window so the TUI's prompt
   * resolves too. Best-effort: a stray keystroke is acceptable if the
   * TUI has already moved on. The relay does NOT delay or wait — see
   * Wave 2 spec OQ#2.
   */
  async resolveHybrid(
    dedupKey: string,
    decision: 'allow' | 'deny',
    tabId: string,
  ): Promise<boolean> {
    if (this.isResolved(dedupKey)) {
      logger.info({ dedupKey, decision }, 'Hybrid resolve skipped — already resolved');
      return false;
    }
    // Short-circuit any future duplicate enqueues immediately so we never
    // double-fire even if the TUI's send-keys takes a beat to land.
    this.markResolved(dedupKey, decision);

    // Mirror into the pending map so any in-flight Promise also resolves.
    this.resolve(dedupKey, decision);

    const key = decision === 'allow' ? 'a' : 'd';
    const target = `${MAJOR_TOM_SESSION}:${tabId}`;
    const ok = await sendKeys(target, key, 'Enter');
    if (!ok) {
      logger.warn({ dedupKey, target, decision }, 'Hybrid send-keys injection failed');
    } else {
      logger.info({ dedupKey, target, decision }, 'Hybrid send-keys injected');
    }
    return ok;
  }

  /** True if this dedupKey was resolved within the TTL window. */
  isResolved(dedupKey: string): boolean {
    return this.resolved.has(dedupKey);
  }

  /** Mark a dedupKey as resolved with TTL cleanup. */
  markResolved(dedupKey: string, decision: ApprovalDecision): void {
    this.resolved.set(dedupKey, decision);
    setTimeout(() => {
      this.resolved.delete(dedupKey);
    }, this.RESOLVED_TTL_MS).unref();
  }

  /** Get all pending approval request IDs */
  getPending(): string[] {
    return [...this.pending.keys()];
  }

  /** Get all pending approvals with full details (for re-broadcasting on reconnect) */
  getPendingDetails(): Array<{
    requestId: string;
    tool: string;
    description: string;
    details: Record<string, unknown>;
    routingMode?: ApprovalRoutingMode;
    source?: ApprovalSource;
    tabId?: string;
    createdAt: number;
  }> {
    return [...this.pending.values()].map((p) => ({
      requestId: p.requestId,
      tool: p.tool,
      description: p.description,
      details: p.details,
      routingMode: p.routingMode,
      source: p.source,
      tabId: p.tabId,
      createdAt: p.createdAt,
    }));
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
