import { describe, it, expect } from 'vitest';
import { SubagentMetricsStore } from '../subagent-metrics.js';

describe('SubagentMetricsStore', () => {
  it('create() initialises counters at zero with hasTokens=false', () => {
    const store = new SubagentMetricsStore();
    store.create('agent-1', 'explore the codebase');
    expect(store.has('agent-1')).toBe(true);
    const snap = store.snapshot('agent-1');
    expect(snap).toEqual({ toolCount: 0, tokenCount: undefined });
  });

  it('getTask() returns the stored task label', () => {
    const store = new SubagentMetricsStore();
    store.create('agent-1', 'build a form');
    expect(store.getTask('agent-1')).toBe('build a form');
  });

  it('tickTool() increments toolCount', () => {
    const store = new SubagentMetricsStore();
    store.create('agent-1', 'task');
    store.tickTool('agent-1');
    store.tickTool('agent-1');
    store.tickTool('agent-1');
    expect(store.snapshot('agent-1')?.toolCount).toBe(3);
  });

  it('tickTool() on unknown subagent is a no-op', () => {
    const store = new SubagentMetricsStore();
    store.tickTool('ghost');
    expect(store.has('ghost')).toBe(false);
    expect(store.size).toBe(0);
  });

  it('addTokens() accumulates positive amounts and flips hasTokens', () => {
    const store = new SubagentMetricsStore();
    store.create('agent-1', 'task');
    // Before any addTokens, tokenCount is undefined (no data attributed).
    expect(store.snapshot('agent-1')?.tokenCount).toBeUndefined();
    store.addTokens('agent-1', 120);
    store.addTokens('agent-1', 45);
    expect(store.snapshot('agent-1')?.tokenCount).toBe(165);
  });

  it('addTokens() ignores zero and negative amounts (keeps tokenCount undefined)', () => {
    const store = new SubagentMetricsStore();
    store.create('agent-1', 'task');
    store.addTokens('agent-1', 0);
    store.addTokens('agent-1', -5);
    // hasTokens never flipped → snapshot reports tokenCount as undefined.
    expect(store.snapshot('agent-1')?.tokenCount).toBeUndefined();
  });

  it('addTokens() ignores NaN/Infinity safely', () => {
    const store = new SubagentMetricsStore();
    store.create('agent-1', 'task');
    store.addTokens('agent-1', NaN);
    store.addTokens('agent-1', Infinity);
    store.addTokens('agent-1', -Infinity);
    expect(store.snapshot('agent-1')?.tokenCount).toBeUndefined();
  });

  it('addTokens() on unknown subagent is a no-op', () => {
    const store = new SubagentMetricsStore();
    store.addTokens('ghost', 100);
    expect(store.has('ghost')).toBe(false);
  });

  it('snapshot() returns undefined for unknown subagent', () => {
    const store = new SubagentMetricsStore();
    expect(store.snapshot('nobody')).toBeUndefined();
  });

  it('snapshot() returns tokenCount=undefined before any attribution but defined=0 once hasTokens flips', () => {
    // Contract: iOS distinguishes "no data" (undefined) from "attributed
    // zero". Since addTokens ignores non-positive amounts, the only way
    // hasTokens ever flips is with a positive add. So an explicit 0
    // never reaches the wire — desirable for Wave 5 sprite UI rendering.
    const store = new SubagentMetricsStore();
    store.create('agent-1', 'task');
    expect(store.snapshot('agent-1')?.tokenCount).toBeUndefined();
    store.addTokens('agent-1', 1);
    // Now hasTokens is true, tokenCount reflects the real count.
    expect(store.snapshot('agent-1')?.tokenCount).toBe(1);
  });

  it('remove() returns the final snapshot and purges the entry', () => {
    const store = new SubagentMetricsStore();
    store.create('agent-1', 'task');
    store.tickTool('agent-1');
    store.tickTool('agent-1');
    store.addTokens('agent-1', 200);
    const snap = store.remove('agent-1');
    expect(snap).toEqual({ toolCount: 2, tokenCount: 200 });
    expect(store.has('agent-1')).toBe(false);
    expect(store.snapshot('agent-1')).toBeUndefined();
  });

  it('remove() on unknown subagent returns undefined', () => {
    const store = new SubagentMetricsStore();
    expect(store.remove('ghost')).toBeUndefined();
  });

  it('remove() returns tokenCount=undefined when nothing was attributed', () => {
    const store = new SubagentMetricsStore();
    store.create('agent-1', 'task');
    store.tickTool('agent-1');
    const snap = store.remove('agent-1');
    // Tool count captured, but token count stays undefined — never hit
    // the wire. Matches the SubagentStop dismissal-event contract:
    // emit `toolCount: 1, tokenCount: undefined`.
    expect(snap).toEqual({ toolCount: 1, tokenCount: undefined });
  });

  it('independent tracking across multiple subagents', () => {
    const store = new SubagentMetricsStore();
    store.create('a1', 'task-a');
    store.create('a2', 'task-b');
    store.tickTool('a1');
    store.tickTool('a1');
    store.tickTool('a2');
    store.addTokens('a1', 100);
    store.addTokens('a2', 50);

    expect(store.snapshot('a1')).toEqual({ toolCount: 2, tokenCount: 100 });
    expect(store.snapshot('a2')).toEqual({ toolCount: 1, tokenCount: 50 });
    expect(store.size).toBe(2);

    // Remove one without affecting the other.
    store.remove('a1');
    expect(store.snapshot('a1')).toBeUndefined();
    expect(store.snapshot('a2')).toEqual({ toolCount: 1, tokenCount: 50 });
    expect(store.size).toBe(1);
  });
});
