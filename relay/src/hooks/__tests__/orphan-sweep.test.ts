/**
 * QA-FIXES.md #7b — orphan-subagent sweep.
 *
 * Covers the pure-helper contract. Wired call sites
 * (`hook-server.ts:/hooks/stop` and `app.ts` `onTabClosed`) are
 * exercised end-to-end by `hook-server-tab.test.ts` and the L-matrix
 * live QA — we don't duplicate integration coverage here.
 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { agentTracker } from '../../events/agent-tracker.js';
import { sweepOrphanedSubagentsForSession } from '../orphan-sweep.js';
import type { AgentEvent } from '../../adapters/adapter.interface.js';

// agentTracker is a module-level singleton; dismiss any leftovers between
// tests so one case can't poison the next.
function resetTracker(): void {
  for (const agent of agentTracker.getAll()) {
    agentTracker.dismiss(agent.agentId);
  }
}

describe('sweepOrphanedSubagentsForSession', () => {
  beforeEach(resetTracker);
  afterEach(resetTracker);

  it('returns 0 and emits nothing when no agents are linked', () => {
    const events: AgentEvent[] = [];
    const count = sweepOrphanedSubagentsForSession(
      'sess-empty',
      (ev) => events.push(ev),
      'session-stop',
    );
    expect(count).toBe(0);
    expect(events).toEqual([]);
  });

  it('emits one dismissed event per linked subagent for the given session', () => {
    agentTracker.spawn('agent-1', 'researcher', 'Explore A', 'sess-A');
    agentTracker.spawn('agent-2', 'researcher', 'Explore B', 'sess-A');
    agentTracker.spawn('agent-3', 'engineer', 'Write', 'sess-A');

    const events: AgentEvent[] = [];
    const count = sweepOrphanedSubagentsForSession(
      'sess-A',
      (ev) => events.push(ev),
      'pty-exit',
    );

    expect(count).toBe(3);
    expect(events.every((e) => e.event === 'dismissed')).toBe(true);
    expect(events.every((e) => e.sessionId === 'sess-A')).toBe(true);
    expect(events.map((e) => e.agentId).sort()).toEqual([
      'agent-1',
      'agent-2',
      'agent-3',
    ]);
  });

  it('does not sweep subagents belonging to a different session', () => {
    agentTracker.spawn('agent-A1', 'researcher', 'Explore', 'sess-A');
    agentTracker.spawn('agent-B1', 'engineer', 'Write', 'sess-B');

    const events: AgentEvent[] = [];
    const count = sweepOrphanedSubagentsForSession(
      'sess-A',
      (ev) => events.push(ev),
      'session-stop',
    );

    expect(count).toBe(1);
    expect(events).toHaveLength(1);
    expect(events[0]?.agentId).toBe('agent-A1');
    // sess-B's agent is untouched — the tracker still has it.
    expect(agentTracker.get('agent-B1')).toBeDefined();
  });

  it('ignores subagents already dismissed before the sweep', () => {
    agentTracker.spawn('agent-stopped', 'researcher', 'Explore', 'sess-A');
    agentTracker.spawn('agent-orphan', 'engineer', 'Write', 'sess-A');
    // One fires SubagentStop cleanly — the other doesn't.
    agentTracker.dismiss('agent-stopped');

    const events: AgentEvent[] = [];
    const count = sweepOrphanedSubagentsForSession(
      'sess-A',
      (ev) => events.push(ev),
      'pty-exit',
    );

    expect(count).toBe(1);
    expect(events[0]?.agentId).toBe('agent-orphan');
  });
});
