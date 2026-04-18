/**
 * Wave 3 — Tab-Keyed Offices protocol extension.
 *
 * Verifies two things:
 *   1. Compile-time: sprite.* and agent.* message types + SessionMetaMessage
 *      all accept an optional `tabId?: string` field (the extensions made
 *      in this wave). The static typing is the primary gate — if the
 *      interface drops the field, these tests stop compiling.
 *   2. Runtime: the `tabIdFor` helper pattern used inside ws.ts returns
 *      the correct tabId for sessions bound in TabRegistry, and undefined
 *      for legacy sessions with no binding. `undefined` on an optional
 *      field is dropped by JSON.stringify, so the wire payload matches
 *      the "omit when absent" back-compat contract.
 *
 * We don't stand up the full WS route here — the annotation logic is a
 * one-liner lookup that ws.ts threads through every emit call. Verifying
 * the pattern against the real TabRegistry gives high confidence without
 * the cost of a WS integration harness.
 */
import { describe, it, expect, beforeEach } from 'vitest';
import { TabRegistry } from '../../tabs/tab-registry.js';
import type {
  SpriteLinkMessage,
  SpriteUnlinkMessage,
  SpriteResponseMessage,
  SpriteStateMessage,
  AgentSpawnMessage,
  AgentWorkingMessage,
  AgentIdleMessage,
  AgentCompleteMessage,
  AgentDismissedMessage,
  SessionMetaMessage,
} from '../../protocol/messages.js';

/** Mirrors the helper inside createWsRoute — guards for undefined registry
 * and returns undefined for unbound sessions so the field is dropped on
 * the wire. */
function tabIdFor(registry: TabRegistry | undefined, sessionId: string): string | undefined {
  return registry?.getTabForSession(sessionId)?.tabId;
}

describe('tabIdFor helper (ws.ts annotation pattern)', () => {
  let registry: TabRegistry;

  beforeEach(() => {
    registry = new TabRegistry();
  });

  it('returns the bound tabId for a session registered via SessionStart', () => {
    registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
    expect(tabIdFor(registry, 'sess-1')).toBe('tab-A');
  });

  it('returns undefined for a session that has no TabRegistry binding (legacy cli/vscode)', () => {
    expect(tabIdFor(registry, 'sess-unknown')).toBeUndefined();
  });

  it('returns undefined when the registry itself is undefined (WsDeps omits tabRegistry)', () => {
    expect(tabIdFor(undefined, 'sess-1')).toBeUndefined();
  });

  it('stops resolving once the session ends even if the tab remains alive', () => {
    registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
    expect(tabIdFor(registry, 'sess-1')).toBe('tab-A');
    registry.registerSessionEnd('sess-1');
    // sessionToTab reverse-index is cleared on SessionEnd — tab persists
    // (idle) but the session no longer maps to it.
    expect(tabIdFor(registry, 'sess-1')).toBeUndefined();
    expect(registry.getTab('tab-A')).toBeDefined();
  });

  it('resolves multiple sessions sharing a tab (Gate A — multi-claude in one tab)', () => {
    registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
    registry.registerSessionStart('sess-2', 'tab-A', '/proj', 'user-1');
    expect(tabIdFor(registry, 'sess-1')).toBe('tab-A');
    expect(tabIdFor(registry, 'sess-2')).toBe('tab-A');
  });

  it('clears all sessions when tabClosed runs (PTY grace expired)', () => {
    registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
    registry.registerSessionStart('sess-2', 'tab-A', '/proj', 'user-1');
    registry.tabClosed('tab-A');
    expect(tabIdFor(registry, 'sess-1')).toBeUndefined();
    expect(tabIdFor(registry, 'sess-2')).toBeUndefined();
  });
});

describe('sprite.* protocol messages — tabId annotation', () => {
  let registry: TabRegistry;

  beforeEach(() => {
    registry = new TabRegistry();
    registry.registerSessionStart('sess-bound', 'tab-A', '/proj', 'user-1');
  });

  it('sprite.link emits tabId when the session is bound', () => {
    const msg: SpriteLinkMessage = {
      type: 'sprite.link',
      sessionId: 'sess-bound',
      spriteHandle: 'sprite-1',
      subagentId: 'agent-1',
      canonicalRole: 'coder',
      characterType: 'astronaut',
      task: 'explore',
      tabId: tabIdFor(registry, 'sess-bound'),
    };
    expect(msg.tabId).toBe('tab-A');
  });

  it('sprite.link omits tabId (undefined) for legacy unbound sessions', () => {
    const msg: SpriteLinkMessage = {
      type: 'sprite.link',
      sessionId: 'sess-legacy',
      spriteHandle: 'sprite-1',
      subagentId: 'agent-1',
      canonicalRole: 'coder',
      characterType: 'astronaut',
      task: 'explore',
      tabId: tabIdFor(registry, 'sess-legacy'),
    };
    expect(msg.tabId).toBeUndefined();
    // JSON serialization drops undefined, preserving back-compat with
    // clients that don't know about tabId.
    const serialized = JSON.parse(JSON.stringify(msg));
    expect('tabId' in serialized).toBe(false);
  });

  it('sprite.unlink emits tabId when bound', () => {
    const msg: SpriteUnlinkMessage = {
      type: 'sprite.unlink',
      sessionId: 'sess-bound',
      spriteHandle: 'sprite-1',
      subagentId: 'agent-1',
      reason: 'completed',
      tabId: tabIdFor(registry, 'sess-bound'),
    };
    expect(msg.tabId).toBe('tab-A');
  });

  it('sprite.response emits tabId when bound', () => {
    const msg: SpriteResponseMessage = {
      type: 'sprite.response',
      sessionId: 'sess-bound',
      spriteHandle: 'sprite-1',
      subagentId: 'agent-1',
      messageId: 'msg-1',
      text: 'hi',
      status: 'delivered',
      tabId: tabIdFor(registry, 'sess-bound'),
    };
    expect(msg.tabId).toBe('tab-A');
  });

  it('sprite.state emits tabId when bound', () => {
    const msg: SpriteStateMessage = {
      type: 'sprite.state',
      sessionId: 'sess-bound',
      mappings: [],
      roleBindings: {},
      tabId: tabIdFor(registry, 'sess-bound'),
    };
    expect(msg.tabId).toBe('tab-A');
  });
});

describe('agent.* protocol messages — tabId annotation', () => {
  let registry: TabRegistry;

  beforeEach(() => {
    registry = new TabRegistry();
    registry.registerSessionStart('sess-bound', 'tab-B', '/proj', 'user-1');
  });

  it('agent.spawn emits tabId when bound', () => {
    const msg: AgentSpawnMessage = {
      type: 'agent.spawn',
      sessionId: 'sess-bound',
      agentId: 'agent-1',
      task: 'research',
      role: 'subagent',
      tabId: tabIdFor(registry, 'sess-bound'),
    };
    expect(msg.tabId).toBe('tab-B');
  });

  it('agent.working emits tabId when bound', () => {
    const msg: AgentWorkingMessage = {
      type: 'agent.working',
      sessionId: 'sess-bound',
      agentId: 'agent-1',
      task: 'research',
      tabId: tabIdFor(registry, 'sess-bound'),
    };
    expect(msg.tabId).toBe('tab-B');
  });

  it('agent.idle emits tabId when bound', () => {
    const msg: AgentIdleMessage = {
      type: 'agent.idle',
      sessionId: 'sess-bound',
      agentId: 'agent-1',
      tabId: tabIdFor(registry, 'sess-bound'),
    };
    expect(msg.tabId).toBe('tab-B');
  });

  it('agent.complete emits tabId when bound', () => {
    const msg: AgentCompleteMessage = {
      type: 'agent.complete',
      sessionId: 'sess-bound',
      agentId: 'agent-1',
      result: 'done',
      tabId: tabIdFor(registry, 'sess-bound'),
    };
    expect(msg.tabId).toBe('tab-B');
  });

  it('agent.dismissed emits tabId when bound', () => {
    const msg: AgentDismissedMessage = {
      type: 'agent.dismissed',
      sessionId: 'sess-bound',
      agentId: 'agent-1',
      tabId: tabIdFor(registry, 'sess-bound'),
    };
    expect(msg.tabId).toBe('tab-B');
  });

  it('agent.spawn omits tabId for legacy unbound sessions', () => {
    const msg: AgentSpawnMessage = {
      type: 'agent.spawn',
      sessionId: 'sess-legacy',
      agentId: 'agent-1',
      task: 'research',
      role: 'subagent',
      tabId: tabIdFor(registry, 'sess-legacy'),
    };
    expect(msg.tabId).toBeUndefined();
    const serialized = JSON.parse(JSON.stringify(msg));
    expect('tabId' in serialized).toBe(false);
  });
});

describe('session.list.response — SessionMetaMessage tabId annotation', () => {
  let registry: TabRegistry;

  beforeEach(() => {
    registry = new TabRegistry();
    registry.registerSessionStart('sess-bound', 'tab-C', '/proj', 'user-1');
  });

  it('annotates bound session entries with tabId', () => {
    const baseMeta: Omit<SessionMetaMessage, 'tabId'> = {
      id: 'sess-bound',
      adapter: 'cli-external',
      workingDirName: 'proj',
      status: 'active',
      startedAt: new Date().toISOString(),
      totalCost: 0,
      inputTokens: 0,
      outputTokens: 0,
      turnCount: 0,
      totalDuration: 0,
    };
    const entry: SessionMetaMessage = {
      ...baseMeta,
      tabId: tabIdFor(registry, baseMeta.id),
    };
    expect(entry.tabId).toBe('tab-C');
  });

  it('leaves tabId undefined for legacy sessions with no binding', () => {
    const baseMeta: Omit<SessionMetaMessage, 'tabId'> = {
      id: 'sess-legacy',
      adapter: 'cli',
      workingDirName: 'proj',
      status: 'active',
      startedAt: new Date().toISOString(),
      totalCost: 0,
      inputTokens: 0,
      outputTokens: 0,
      turnCount: 0,
      totalDuration: 0,
    };
    const entry: SessionMetaMessage = {
      ...baseMeta,
      tabId: tabIdFor(registry, baseMeta.id),
    };
    expect(entry.tabId).toBeUndefined();
    // Wire-level back-compat: undefined disappears on JSON.stringify.
    const serialized = JSON.parse(JSON.stringify(entry));
    expect('tabId' in serialized).toBe(false);
  });

  it('mapping a sessions[] list annotates each entry by id', () => {
    registry.registerSessionStart('sess-1', 'tab-X', '/proj', 'user-1');
    registry.registerSessionStart('sess-2', 'tab-Y', '/proj', 'user-1');
    const rawSessions: Omit<SessionMetaMessage, 'tabId'>[] = [
      {
        id: 'sess-1',
        adapter: 'cli-external',
        workingDirName: 'a',
        status: 'active',
        startedAt: 't1',
        totalCost: 0,
        inputTokens: 0,
        outputTokens: 0,
        turnCount: 0,
        totalDuration: 0,
      },
      {
        id: 'sess-2',
        adapter: 'cli-external',
        workingDirName: 'b',
        status: 'active',
        startedAt: 't2',
        totalCost: 0,
        inputTokens: 0,
        outputTokens: 0,
        turnCount: 0,
        totalDuration: 0,
      },
      {
        id: 'sess-legacy',
        adapter: 'cli',
        workingDirName: 'c',
        status: 'active',
        startedAt: 't3',
        totalCost: 0,
        inputTokens: 0,
        outputTokens: 0,
        turnCount: 0,
        totalDuration: 0,
      },
    ];
    const annotated: SessionMetaMessage[] = rawSessions.map((meta) => ({
      ...meta,
      tabId: tabIdFor(registry, meta.id),
    }));
    expect(annotated[0].tabId).toBe('tab-X');
    expect(annotated[1].tabId).toBe('tab-Y');
    expect(annotated[2].tabId).toBeUndefined();
  });
});
