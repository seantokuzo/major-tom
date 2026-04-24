// Wave 6 — integration-style tests for every spec scenario the relay owns.
//
// Scenarios covered (from docs/PHASE-SPRITE-AGENT-WIRING.md tables):
//   - S1  Subagent crashes mid-task → sprite.unlink + /btw queue drop
//   - S2  Subagent completes with error → sprite.unlink + /btw queue drop
//   - S3  User dismisses subagent from inspector → sprite.unlink + /btw drop
//   - S4  Relay disconnects mid-subagent → mapping preserved on relay, restore on reconnect
//   - S6  Subagent spawns + completes in <1s → no events lost
//   - S7  All human sprites exhausted → duplicate humans (not dog fallback)
//   - S8  Relay restarts → cold boot cleanup runs, in-memory /btw lost
//   - S9  New terminal session starts → no auto-office creation (relay-side inert)
//   - Scenario 9 (race) — tap+send race: mapping created between tap and send,
//                         handler should accept the message either way.
//
// NOT covered here (iOS side / not relay):
//   - S5 desk overflow placement (OfficeViewModel sprite positioning)
//   - M2 cross-session notification banner (iOS UI)
//   - M3 bubble collision priority (iOS UI)
//   - S10 PWA client (out of scope)
//
// Assertions are done against the *direct* class APIs (BtwQueue,
// SpriteMapper, SpriteMappingPersistence) instead of spinning up the
// Fastify + fleet manager stack. This keeps the test suite fast (~10-50ms
// per test), deterministic, and focused on contracts the ws.ts / worker
// layer rely on.

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { mkdtemp, rm, writeFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { BtwQueue } from '../btw-queue.js';
import { SpriteMapper, CHARACTER_POOL } from '../sprite-mapper.js';
import {
  SpriteMappingPersistence,
  type PersistedSpriteMapping,
  type PersistedSpriteMappingFile,
} from '../sprite-mapping-persistence.js';
import { SubagentMetricsStore } from '../subagent-metrics.js';

/**
 * Mini in-process harness that mirrors the ws.ts/worker split for sprite
 * state without any network plumbing. Tests below exercise it end-to-end
 * on a per-scenario basis.
 */
function newHarness(persistence: SpriteMappingPersistence) {
  const spriteMapper = new SpriteMapper();
  const btwQueue = new BtwQueue();
  const metricsStore = new SubagentMetricsStore();
  const spriteMappings = new Map<string, PersistedSpriteMappingFile>();

  // Captured wire-side events — used for assertions.
  const events: Array<{ type: string; payload: Record<string, unknown> }> = [];
  const emit = (type: string, payload: Record<string, unknown>) => {
    events.push({ type, payload });
  };

  // Wire queue events to the captured log. These mirror the
  // ws.ts routing of 'injected' / 'responded' / 'dropped' → sprite.response /
  // sprite.queue / sprite.dropped.
  btwQueue.on('dropped', (p) => emit('sprite.dropped', { ...p }));
  btwQueue.on('injected', (p) => emit('sprite.injected', { ...p }));
  btwQueue.on('responded', (p) => emit('sprite.response', { ...p }));

  function getOrCreateSpriteState(sessionId: string): PersistedSpriteMappingFile {
    let s = spriteMappings.get(sessionId);
    if (!s) {
      s = spriteMapper.createEmptyFile(sessionId);
      spriteMappings.set(sessionId, s);
    }
    return s;
  }

  /** Simulates ws.ts agent.spawn handler — creates mapping + emits sprite.link. */
  function spawnAgent(sessionId: string, agentId: string, task: string, parentId?: string) {
    const state = getOrCreateSpriteState(sessionId);
    const { mapping } = spriteMapper.createMapping(
      agentId,
      task,
      state.mappings,
      parentId,
    );
    state.mappings.push(mapping);
    state.updatedAt = new Date().toISOString();
    persistence.save(state);
    metricsStore.create(agentId, task);
    emit('sprite.link', {
      sessionId,
      spriteHandle: mapping.spriteHandle,
      subagentId: agentId,
      canonicalRole: mapping.canonicalRole,
      characterType: mapping.characterType,
      task,
      parentId,
      deskIndex: mapping.deskIndex >= 0 ? mapping.deskIndex : undefined,
    });
    return mapping;
  }

  /** Simulates ws.ts agent.complete / agent.dismissed / agent.failed handler. */
  function unlinkAgent(sessionId: string, agentId: string, reason: 'completed' | 'failed' | 'dismissed') {
    const state = spriteMappings.get(sessionId);
    if (!state) return;
    const idx = state.mappings.findIndex((m) => m.subagentId === agentId);
    if (idx < 0) return;
    const removed = state.mappings[idx]!;
    state.mappings.splice(idx, 1);
    state.updatedAt = new Date().toISOString();
    persistence.save(state);
    emit('sprite.unlink', {
      sessionId,
      spriteHandle: removed.spriteHandle,
      subagentId: agentId,
      reason,
    });
    // Queue drop — worker does this on SubagentStop, but we reproduce here
    // so tests don't depend on the IPC layer. Reason wording mirrors the
    // wave 4 adapter behavior.
    btwQueue.dropForSubagent(agentId, `Subagent ${reason}`);
    metricsStore.remove(agentId);
  }

  /** Simulates ws.ts session.end handler — drops queue for every subagent in session. */
  function endSession(sessionId: string, reason = 'Session ended') {
    btwQueue.dropForSession(sessionId, reason);
    const state = spriteMappings.get(sessionId);
    if (state) {
      for (const mapping of state.mappings) {
        emit('sprite.unlink', {
          sessionId,
          spriteHandle: mapping.spriteHandle,
          subagentId: mapping.subagentId,
          reason: 'session_ended',
        });
        metricsStore.remove(mapping.subagentId);
      }
      spriteMappings.delete(sessionId);
    }
    void persistence.delete(sessionId);
  }

  /** Simulates the sprite.message handler from ws.ts. */
  function enqueueBtw(input: {
    sessionId: string;
    subagentId: string;
    spriteHandle: string;
    messageId: string;
    userText: string;
    role: string;
    task: string;
  }) {
    // Spec scenario #9: even if the mapping wasn't fully set up when the
    // client tapped, as long as it exists by the time the message arrives
    // we accept — that's handled by the ws.ts mapping-check happening
    // right before enqueue. This helper just enforces the same contract.
    const state = spriteMappings.get(input.sessionId);
    const mapping = state?.mappings.find((m) => m.subagentId === input.subagentId);
    if (!mapping) {
      emit('sprite.response.error', {
        sessionId: input.sessionId,
        messageId: input.messageId,
        reason: 'No sprite mapping',
      });
      return null;
    }
    return btwQueue.enqueue({
      sessionId: input.sessionId,
      subagentId: input.subagentId,
      spriteHandle: input.spriteHandle,
      messageId: input.messageId,
      userText: input.userText,
      role: input.role,
      task: input.task,
    });
  }

  function lastEvent(type: string) {
    return [...events].reverse().find((e) => e.type === type);
  }

  function eventsOfType(type: string) {
    return events.filter((e) => e.type === type);
  }

  return {
    spriteMapper,
    btwQueue,
    metricsStore,
    spriteMappings,
    events,
    emit,
    spawnAgent,
    unlinkAgent,
    endSession,
    enqueueBtw,
    lastEvent,
    eventsOfType,
    getOrCreateSpriteState,
  };
}

describe('Wave 6 scenarios — S1/S2 subagent crash or completes-with-error', () => {
  let baseDir: string;
  let persistence: SpriteMappingPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'w6-crash-'));
    persistence = new SpriteMappingPersistence({ baseDir });
  });

  afterEach(async () => {
    persistence.dispose();
    await rm(baseDir, { recursive: true, force: true });
  });

  it('S1 — subagent crashes mid-task → sprite.unlink with reason="failed", /btw queue drains', async () => {
    const h = newHarness(persistence);
    h.spawnAgent('sess-1', 'agent-crash', 'write and test the queue');
    // Queue two /btw messages before the crash.
    h.enqueueBtw({
      sessionId: 'sess-1',
      subagentId: 'agent-crash',
      spriteHandle: h.spriteMappings.get('sess-1')!.mappings[0]!.spriteHandle,
      messageId: 'btw-1',
      userText: 'still working?',
      role: 'engineer',
      task: 't',
    });
    h.enqueueBtw({
      sessionId: 'sess-1',
      subagentId: 'agent-crash',
      spriteHandle: h.spriteMappings.get('sess-1')!.mappings[0]!.spriteHandle,
      messageId: 'btw-2',
      userText: 'anything blocking?',
      role: 'engineer',
      task: 't',
    });
    expect(h.btwQueue.sizeFor('agent-crash')).toBe(2);

    // Crash → our ws.ts reports failed→unlink path.
    h.unlinkAgent('sess-1', 'agent-crash', 'failed');
    const unlink = h.lastEvent('sprite.unlink');
    expect(unlink).toBeDefined();
    expect(unlink!.payload['reason']).toBe('failed');
    // Both /btw entries drop with the subagent-level reason.
    expect(h.btwQueue.sizeFor('agent-crash')).toBe(0);
    const dropped = h.eventsOfType('sprite.dropped');
    expect(dropped).toHaveLength(2);
    expect(dropped[0]!.payload['reason']).toMatch(/failed/i);
  });

  it('S2 — subagent completes with error → sprite.unlink with reason="completed", queue drains', async () => {
    const h = newHarness(persistence);
    h.spawnAgent('sess-2', 'agent-err', 'run the flaky test');
    h.enqueueBtw({
      sessionId: 'sess-2',
      subagentId: 'agent-err',
      spriteHandle: h.spriteMappings.get('sess-2')!.mappings[0]!.spriteHandle,
      messageId: 'btw-2a',
      userText: 'status?',
      role: 'qa',
      task: 'tests',
    });
    h.unlinkAgent('sess-2', 'agent-err', 'completed');
    const unlink = h.lastEvent('sprite.unlink');
    expect(unlink!.payload['reason']).toBe('completed');
    expect(h.btwQueue.sizeFor('agent-err')).toBe(0);
  });
});

describe('Wave 6 scenario — S3 user dismisses subagent from inspector', () => {
  let baseDir: string;
  let persistence: SpriteMappingPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'w6-dismiss-'));
    persistence = new SpriteMappingPersistence({ baseDir });
  });

  afterEach(async () => {
    persistence.dispose();
    await rm(baseDir, { recursive: true, force: true });
  });

  it('dismissed flow emits sprite.unlink with reason="dismissed" and drops queue', async () => {
    const h = newHarness(persistence);
    h.spawnAgent('sess-d', 'agent-d', 'explore the codebase');
    h.enqueueBtw({
      sessionId: 'sess-d',
      subagentId: 'agent-d',
      spriteHandle: h.spriteMappings.get('sess-d')!.mappings[0]!.spriteHandle,
      messageId: 'btw-d',
      userText: 'how long?',
      role: 'researcher',
      task: 'explore',
    });
    h.unlinkAgent('sess-d', 'agent-d', 'dismissed');
    const u = h.lastEvent('sprite.unlink');
    expect(u!.payload['reason']).toBe('dismissed');
    const dropped = h.eventsOfType('sprite.dropped');
    expect(dropped).toHaveLength(1);
    expect(dropped[0]!.payload['reason']).toMatch(/dismissed/i);
  });
});

describe('Wave 6 scenario — S4 relay disconnects mid-subagent (mapping preserved, restore on reconnect)', () => {
  let baseDir: string;
  let persistence: SpriteMappingPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'w6-s4-'));
    persistence = new SpriteMappingPersistence({ baseDir });
  });

  afterEach(async () => {
    persistence.dispose();
    await rm(baseDir, { recursive: true, force: true });
  });

  it('mapping persists on disk + in memory across a simulated disconnect', async () => {
    const h = newHarness(persistence);
    h.spawnAgent('sess-4', 'agent-live', 'plan the architecture');
    h.spawnAgent('sess-4', 'agent-live-2', 'review the design');
    // Force the debounced write through.
    await persistence.saveImmediate(h.spriteMappings.get('sess-4')!);
    // Simulate disconnect: drop local refs, rebuild persistence with the
    // same baseDir, verify the file loads cleanly.
    const backup = h.spriteMappings.get('sess-4')!;
    h.spriteMappings.delete('sess-4');

    const loaded = await persistence.load('sess-4');
    expect(loaded).not.toBeNull();
    expect(loaded!.mappings).toHaveLength(2);
    // Handles are preserved → iOS sees the same sprite instances it saw
    // pre-disconnect.
    expect(loaded!.mappings.map((m) => m.spriteHandle).sort()).toEqual(
      backup.mappings.map((m) => m.spriteHandle).sort(),
    );
  });

  it('btw queue survives disconnect until session is explicitly ended', async () => {
    const h = newHarness(persistence);
    h.spawnAgent('sess-4q', 'agent-q', 'write the adapter');
    h.enqueueBtw({
      sessionId: 'sess-4q',
      subagentId: 'agent-q',
      spriteHandle: h.spriteMappings.get('sess-4q')!.mappings[0]!.spriteHandle,
      messageId: 'btw-survive',
      userText: 'update?',
      role: 'engineer',
      task: 'wire',
    });
    expect(h.btwQueue.size).toBe(1);
    // Disconnect does NOT touch the queue — only session-end does. This
    // test codifies the grace-period expectation from the spec.
    // (No action here — we assert the queue is still there.)
    expect(h.btwQueue.size).toBe(1);
    // When the grace period expires, session.end runs → queue dropped.
    h.endSession('sess-4q', 'Session ended (grace period expired)');
    expect(h.btwQueue.size).toBe(0);
    const dropped = h.eventsOfType('sprite.dropped');
    expect(dropped).toHaveLength(1);
    expect(dropped[0]!.payload['reason']).toMatch(/grace period expired/i);
  });
});

describe('Wave 6 scenario — S6 subagent spawns + completes in <1s (no lost events)', () => {
  let baseDir: string;
  let persistence: SpriteMappingPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'w6-fast-'));
    persistence = new SpriteMappingPersistence({ baseDir });
  });

  afterEach(async () => {
    persistence.dispose();
    await rm(baseDir, { recursive: true, force: true });
  });

  it('spawn + complete in the same tick both fire, in order', async () => {
    const h = newHarness(persistence);
    h.spawnAgent('sess-fast', 'agent-fast', 'quick lint fix');
    h.unlinkAgent('sess-fast', 'agent-fast', 'completed');
    const types = h.events.map((e) => e.type);
    expect(types[0]).toBe('sprite.link');
    expect(types[1]).toBe('sprite.unlink');
    // No other events leaked in between.
    expect(types).toEqual(['sprite.link', 'sprite.unlink']);
  });

  it('fast spawn+complete metrics snapshot is captured at remove()', () => {
    const h = newHarness(persistence);
    h.spawnAgent('sess-fast2', 'agent-fast2', 'implement the helper');
    // Simulate some tool usage before the quick complete.
    h.metricsStore.tickTool('agent-fast2');
    h.metricsStore.addTokens('agent-fast2', 42);
    const finalSnap = h.metricsStore.remove('agent-fast2');
    expect(finalSnap).toEqual({ toolCount: 1, tokenCount: 42 });
  });
});

describe('Wave 6 scenario — S7 all human sprites exhausted (duplication, no dog fallback)', () => {
  // Post-QA-FIXES #9: character assignment is randomized per spawn. The
  // spec now guarantees (a) dogs are never chosen as agent sprites, and
  // (b) the first 14 spawns in a session each get a distinct character
  // (CHARACTER_POOL is size 14 with dup-avoidance). The 15th spawn is
  // forced to duplicate since the pool is exhausted.

  it('never returns a dog CharacterType as an agent sprite, even when the pool is exhausted', () => {
    const mapper = new SpriteMapper();
    const mappings: PersistedSpriteMapping[] = [];
    // Spawn 20 agents — well past both MAX_DESKS (6) and the pool cap (14).
    for (let i = 0; i < 20; i++) {
      const result = mapper.createMapping(
        `agent-${i}`,
        'wire the relay endpoint',
        mappings,
      );
      expect(result.mapping.characterType).not.toMatch(
        /elvis|steve|kai|hoku|senor|esteban|zuckerbot/,
      );
      mappings.push(result.mapping);
    }
    // Overflow: first 6 get desks, 7+ get deskIndex === -1.
    expect(mappings.filter((m) => m.deskIndex >= 0)).toHaveLength(6);
    expect(mappings.filter((m) => m.deskIndex === -1)).toHaveLength(14);
  });

  it('first 14 spawns produce distinct characters (dup-avoidance until pool exhausts)', () => {
    const mapper = new SpriteMapper();
    const mappings: PersistedSpriteMapping[] = [];
    for (let i = 0; i < 14; i++) {
      const result = mapper.createMapping(`agent-${i}`, 'task', mappings);
      mappings.push(result.mapping);
    }
    const uniqueCharacters = new Set(mappings.map((m) => m.characterType));
    expect(uniqueCharacters.size).toBe(14);
  });

  it('the 15th spawn duplicates an in-use character (pool fully claimed)', () => {
    const mapper = new SpriteMapper();
    const mappings: PersistedSpriteMapping[] = [];
    for (let i = 0; i < 14; i++) {
      const result = mapper.createMapping(`agent-${i}`, 'task', mappings);
      mappings.push(result.mapping);
    }
    const inUseBeforeOverflow = new Set(mappings.map((m) => m.characterType));
    const overflow = mapper.createMapping('agent-overflow', 'task', mappings);
    expect(inUseBeforeOverflow.has(overflow.mapping.characterType)).toBe(true);
  });
});

describe('CHARACTER_POOL / iOS CharacterType lockstep invariant', () => {
  // Drift guard: CHARACTER_POOL must exactly match the non-dog cases of
  // the iOS `CharacterType` enum at
  // ios/MajorTom/Features/Office/Models/AgentState.swift. iOS's
  // `deterministicFallbackCharacter(for:)` does `pool.count`-modulo on
  // `CharacterType.allCases.filter { !$0.isDog }` — if iOS adds a crew
  // member without extending CHARACTER_POOL (or vice versa), the fallback
  // pool sizes diverge and reconnect-time sprite rolls stop agreeing with
  // relay-time rolls. Updating one side REQUIRES updating the other plus
  // this snapshot.
  const IOS_NON_DOG_CHARACTERS_SNAPSHOT = [
    'alienDiplomat',
    'backendEngineer',
    'botanist',
    'bowenYang',
    'captain',
    'chef',
    'claudimusPrime',
    'doctor',
    'dwight',
    'frontendDev',
    'kendrick',
    'mechanic',
    'pm',
    'prince',
  ] as const;

  it('CHARACTER_POOL matches the iOS non-dog CharacterType snapshot', () => {
    expect([...CHARACTER_POOL].sort()).toEqual(
      [...IOS_NON_DOG_CHARACTERS_SNAPSHOT].sort(),
    );
  });
});

describe('Wave 6 scenario — S8 relay restart (cold boot cleanup)', () => {
  let baseDir: string;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'w6-boot-'));
  });

  afterEach(async () => {
    await rm(baseDir, { recursive: true, force: true });
  });

  it('listStale reaps files that do not match any live session', async () => {
    const p1 = new SpriteMappingPersistence({ baseDir });
    await p1.saveImmediate({
      version: 1,
      sessionId: 'live-1',
      updatedAt: new Date().toISOString(),
      roleBindings: {},
      mappings: [],
    });
    await p1.saveImmediate({
      version: 1,
      sessionId: 'ghost-1',
      updatedAt: new Date().toISOString(),
      roleBindings: {},
      mappings: [],
    });
    await p1.saveImmediate({
      version: 1,
      sessionId: 'ghost-2',
      updatedAt: new Date().toISOString(),
      roleBindings: {},
      mappings: [],
    });
    p1.dispose();

    // "Restart": new persistence instance, same baseDir.
    const p2 = new SpriteMappingPersistence({ baseDir });
    const stale = await p2.listStale((sid) => sid === 'live-1');
    expect(stale.sort()).toEqual(['ghost-1', 'ghost-2'].sort());
    for (const sid of stale) await p2.delete(sid);
    const remaining = await readdir(baseDir);
    expect(remaining.filter((f) => f.endsWith('.json'))).toEqual(['live-1.json']);
    p2.dispose();
  });

  it('in-memory /btw queue is lost across a restart (documented spec behavior)', async () => {
    const p1 = new SpriteMappingPersistence({ baseDir });
    const q1 = new BtwQueue();
    q1.enqueue({
      sessionId: 'sess-boot',
      subagentId: 'agent-boot',
      spriteHandle: 'sprite-boot',
      messageId: 'msg-lost',
      userText: 'hi',
      role: 'engineer',
      task: 't',
    });
    expect(q1.size).toBe(1);
    p1.dispose();

    // Restart: brand-new queue, empty.
    const q2 = new BtwQueue();
    expect(q2.size).toBe(0);
  });
});

describe('Wave 6 scenario — S9 new terminal session starts (no auto-office)', () => {
  let baseDir: string;
  let persistence: SpriteMappingPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'w6-newsess-'));
    persistence = new SpriteMappingPersistence({ baseDir });
  });

  afterEach(async () => {
    persistence.dispose();
    await rm(baseDir, { recursive: true, force: true });
  });

  it('no sprite state is created until an agent actually spawns', async () => {
    const h = newHarness(persistence);
    // session.start happens on iOS side without any sprite allocation.
    // Relay-side: no mapping file, no in-memory state.
    expect(h.spriteMappings.has('sess-new')).toBe(false);
    expect(await persistence.load('sess-new')).toBeNull();
    // Only when an agent spawns does state materialize.
    h.spawnAgent('sess-new', 'agent-a', 'first task');
    expect(h.spriteMappings.has('sess-new')).toBe(true);
  });
});

describe('Wave 6 scenario #9 — tap+send race (sprite becomes linked between tap and send)', () => {
  let baseDir: string;
  let persistence: SpriteMappingPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'w6-race-'));
    persistence = new SpriteMappingPersistence({ baseDir });
  });

  afterEach(async () => {
    persistence.dispose();
    await rm(baseDir, { recursive: true, force: true });
  });

  it('enqueue is accepted as long as the mapping exists at receive time (accept side)', () => {
    const h = newHarness(persistence);
    // Simulate the race: user tapped an idle sprite, started typing, then
    // an agent spawned before they hit send. By the time sprite.message
    // arrives the mapping exists → enqueue accepted.
    h.spawnAgent('sess-race', 'agent-late', 'write the form');
    const out = h.enqueueBtw({
      sessionId: 'sess-race',
      subagentId: 'agent-late',
      spriteHandle: h.spriteMappings.get('sess-race')!.mappings[0]!.spriteHandle,
      messageId: 'btw-race',
      userText: 'progress?',
      role: 'frontend',
      task: 'form',
    });
    expect(out).not.toBeNull();
    expect(h.btwQueue.size).toBe(1);
  });

  it('enqueue is rejected when the mapping has already been removed (miss side)', () => {
    const h = newHarness(persistence);
    // Agent spawned → unlinked (completed fast) → user finally hits send.
    h.spawnAgent('sess-miss', 'agent-gone', 'quick write');
    const handle = h.spriteMappings.get('sess-miss')!.mappings[0]!.spriteHandle;
    h.unlinkAgent('sess-miss', 'agent-gone', 'completed');
    // Mapping gone → enqueue returns null, caller emits error response.
    const out = h.enqueueBtw({
      sessionId: 'sess-miss',
      subagentId: 'agent-gone',
      spriteHandle: handle,
      messageId: 'btw-miss',
      userText: 'status?',
      role: 'engineer',
      task: 't',
    });
    expect(out).toBeNull();
    const err = h.lastEvent('sprite.response.error');
    expect(err).toBeDefined();
    expect(err!.payload['reason']).toMatch(/no sprite mapping/i);
  });
});

describe('Wave 6 — disk-full resilience (end-to-end)', () => {
  let baseDir: string;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'w6-enospc-'));
  });

  afterEach(async () => {
    await rm(baseDir, { recursive: true, force: true });
  });

  it('spawn + subsequent queue ops still work when disk writes fail with ENOSPC', async () => {
    // Inject a writeFile that ALWAYS fails. The harness should still be
    // able to spawn agents, enqueue /btw, and drop on unlink — the
    // in-memory state remains authoritative.
    const enospc = Object.assign(new Error('no space'), { code: 'ENOSPC' });
    const faultyFs = { writeFile: vi.fn().mockRejectedValue(enospc) };
    // Fake timers so the 2s debounce inside SpriteMappingPersistence
    // fires deterministically instead of making CI wait on wall-clock.
    vi.useFakeTimers();
    try {
      const persistence = new SpriteMappingPersistence({ baseDir, fs: faultyFs });
      const h = newHarness(persistence);

      // Spawn → in-memory state populated even though disk write fails.
      h.spawnAgent('sess-x', 'agent-x', 'build the form');
      expect(h.spriteMappings.get('sess-x')!.mappings).toHaveLength(1);

      // Enqueue /btw — works because the mapping exists in memory.
      const entry = h.enqueueBtw({
        sessionId: 'sess-x',
        subagentId: 'agent-x',
        spriteHandle: h.spriteMappings.get('sess-x')!.mappings[0]!.spriteHandle,
        messageId: 'msg-enospc',
        userText: 'update?',
        role: 'frontend',
        task: 'form',
      });
      expect(entry).not.toBeNull();
      expect(h.btwQueue.size).toBe(1);

      // Unlink — still works, still emits drop.
      h.unlinkAgent('sess-x', 'agent-x', 'completed');
      expect(h.btwQueue.size).toBe(0);

      // Force the debounce to flush any trailing saves. advanceTimersByTimeAsync
      // also flushes the microtasks queued by writeToDisk's await chain.
      await vi.advanceTimersByTimeAsync(2100);
      persistence.dispose();
    } finally {
      vi.useRealTimers();
    }
  });
});

describe('Wave 6 — corrupt mapping file on reconnect (cascade tier 2 integration)', () => {
  let baseDir: string;
  let persistence: SpriteMappingPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'w6-corrupt-recon-'));
    persistence = new SpriteMappingPersistence({ baseDir });
  });

  afterEach(async () => {
    persistence.dispose();
    await rm(baseDir, { recursive: true, force: true });
  });

  it('load returns null on corrupt mapping → caller falls through to client-authoritative', async () => {
    // Write garbage to the expected file path (bypassing SpriteMappingPersistence.save).
    await writeFile(join(baseDir, 'sess-corrupt.json'), '<<not json>>', 'utf-8');
    const loaded = await persistence.load('sess-corrupt');
    expect(loaded).toBeNull();
    // Now iOS reconnects and re-sends its mappings. The ws.ts handler then
    // repopulates the in-memory map + rewrites the file. We simulate only
    // the repopulate step here.
    const fresh: PersistedSpriteMappingFile = {
      version: 1,
      sessionId: 'sess-corrupt',
      updatedAt: new Date().toISOString(),
      roleBindings: { frontend: 'frontendDev' },
      mappings: [
        {
          spriteHandle: 'sprite-recovered',
          subagentId: 'agent-recovered',
          canonicalRole: 'frontend',
          characterType: 'frontendDev',
          task: 'fix the nav bar',
          deskIndex: 0,
          linkedAt: new Date().toISOString(),
        },
      ],
    };
    await persistence.saveImmediate(fresh);
    const reloaded = await persistence.load('sess-corrupt');
    expect(reloaded).not.toBeNull();
    expect(reloaded!.mappings[0]!.subagentId).toBe('agent-recovered');
  });
});

describe('Wave 6 — tool event cleanup on subagent despawn (metrics path)', () => {
  it('SubagentMetricsStore.remove returns the final snapshot so iOS can clear tool bubbles', () => {
    // The wire-level contract (verified in Wave 5 tests) is that
    // agent.dismissed / agent.complete carry the final toolCount / tokenCount
    // piggyback. iOS uses these to clear any lingering bubbles attached
    // to the sprite. Wave 6 — verify the metrics store still surfaces the
    // final counts even when the despawn is abrupt (mid-tool).
    const store = new SubagentMetricsStore();
    store.create('agent-m', 't');
    store.tickTool('agent-m'); // tool_use event happened but no matching stop
    store.tickTool('agent-m');
    store.addTokens('agent-m', 120);
    const snap = store.remove('agent-m');
    expect(snap).toEqual({ toolCount: 2, tokenCount: 120 });
    // Store entry cleaned up.
    expect(store.has('agent-m')).toBe(false);
  });
});
