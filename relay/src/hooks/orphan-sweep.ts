/**
 * Orphan-subagent sweep. QA-FIXES.md #7b.
 *
 * When a claude session ends cleanly (Stop hook fires) or a tab's PTY
 * goes away (grace-expire / REST kill / natural exit), any subagent
 * whose `SubagentStop` hook never fired would otherwise stay `working`
 * in the iOS Office forever. This helper finds those orphans in the
 * singleton `agentTracker` and injects synthetic
 * `agent-lifecycle: dismissed` events through the same fanout the
 * worker/SDK paths use, so clients see the sprite dismiss with no
 * special-casing.
 *
 * Reproducer from L5 QA (2026-04-19): user typed `/exit` with a custom
 * subagent (`claude-code-guide`) still active. 4 of 5 Explore subagents
 * dismissed cleanly; the custom one never fired SubagentStop, and the
 * parent session's Stop hook never fired either. With this sweep wired
 * to both `/hooks/stop` and PTY-exit, closing the tab sweeps the orphan.
 */
import type { AgentEvent } from '../adapters/adapter.interface.js';
import { agentTracker } from '../events/agent-tracker.js';
import { logger } from '../utils/logger.js';

export type SweepReason = 'session-stop' | 'pty-exit';

/**
 * Dismiss every subagent still linked to `sessionId`. Returns the count
 * of orphans swept. No-op (returns 0) when the tracker has no live
 * subagents for the session.
 *
 * The caller supplies `reportAgentLifecycle` — the same function the
 * PTY hook and SDK paths use to inject events. This keeps the sweep
 * pure (no direct coupling to FleetManager) and testable.
 */
export function sweepOrphanedSubagentsForSession(
  sessionId: string,
  reportAgentLifecycle: (event: AgentEvent) => void,
  reason: SweepReason,
): number {
  const orphans = agentTracker.getBySession(sessionId);
  if (orphans.length === 0) return 0;

  logger.info(
    {
      sessionId,
      count: orphans.length,
      agentIds: orphans.map((o) => o.agentId),
      reason,
    },
    'Sweeping orphaned subagents',
  );

  for (const orphan of orphans) {
    reportAgentLifecycle({
      sessionId,
      agentId: orphan.agentId,
      event: 'dismissed',
    });
  }

  return orphans.length;
}
