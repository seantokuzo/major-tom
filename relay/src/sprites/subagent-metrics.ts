// Wave 5 — Per-subagent tool + token counters.
//
// Attribution model:
//   - Tool counts: every `tool_use` block in an assistant message whose
//     `parent_tool_use_id` maps to a known subagent increments the subagent's
//     counter by 1. Always attributable when the parent Task is known.
//   - Token counts: when a subagent's assistant message includes a `usage`
//     block, its input+output tokens are added to the subagent's counter.
//     This is best-effort — the SDK doesn't surface every boundary as a
//     subagent-tagged assistant message, so `hasTokens` guards the wire
//     field so iOS can distinguish "no data" (undefined) from
//     "attributed zero" (0).
//
// Used by both `claude-cli.adapter.ts` (single-worker) and `fleet/worker.ts`
// (fleet mode). Both paths share identical semantics.

export interface SubagentMetrics {
  toolCount: number;
  tokenCount: number;
  hasTokens: boolean;
  task: string;
}

export interface SubagentMetricsSnapshot {
  toolCount: number;
  /** `undefined` when no tokens have been attributed yet (different from 0). */
  tokenCount: number | undefined;
}

/**
 * Per-session store for subagent metrics. One instance per SDK session.
 * Subagent lifetime: created on `SubagentStart`, removed on `SubagentStop`.
 */
export class SubagentMetricsStore {
  private readonly metrics = new Map<string, SubagentMetrics>();

  /** Register a new subagent with a task label. */
  create(subagentId: string, task: string): void {
    this.metrics.set(subagentId, {
      toolCount: 0,
      tokenCount: 0,
      hasTokens: false,
      task,
    });
  }

  /** Tick the tool counter for a subagent. No-op if unknown. */
  tickTool(subagentId: string): void {
    const m = this.metrics.get(subagentId);
    if (m) m.toolCount++;
  }

  /**
   * Add `amount` tokens to a subagent's counter. `amount` ≤ 0 is ignored
   * so we don't falsely flip `hasTokens` with a noop `0`. Unknown subagent
   * is a no-op.
   */
  addTokens(subagentId: string, amount: number): void {
    if (!Number.isFinite(amount) || amount <= 0) return;
    const m = this.metrics.get(subagentId);
    if (!m) return;
    m.tokenCount += amount;
    m.hasTokens = true;
  }

  /**
   * Snapshot the live counters. `tokenCount` is `undefined` when no tokens
   * have been attributed — iOS treats `undefined` as "no data available"
   * which is different from an attributed zero.
   */
  snapshot(subagentId: string): SubagentMetricsSnapshot | undefined {
    const m = this.metrics.get(subagentId);
    if (!m) return undefined;
    return {
      toolCount: m.toolCount,
      tokenCount: m.hasTokens ? m.tokenCount : undefined,
    };
  }

  /** Look up the task label cached at `create` time. */
  getTask(subagentId: string): string | undefined {
    return this.metrics.get(subagentId)?.task;
  }

  /** Remove all state for a subagent. Returns the final snapshot. */
  remove(subagentId: string): SubagentMetricsSnapshot | undefined {
    const snap = this.snapshot(subagentId);
    this.metrics.delete(subagentId);
    return snap;
  }

  has(subagentId: string): boolean {
    return this.metrics.has(subagentId);
  }

  get size(): number {
    return this.metrics.size;
  }
}
