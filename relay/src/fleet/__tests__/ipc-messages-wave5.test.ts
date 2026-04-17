// Wave 5 — shape tests for the new optional fields on IPC messages
// (parent↔child fleet worker protocol). Also verifies the existing
// type guards still accept messages carrying the new fields (IPC type
// guards key on `type` only — they must stay tolerant of optional
// additions or a rolling deploy of workers with mixed versions would
// fail).

import { describe, it, expect } from 'vitest';
import {
  isChildToParentMessage,
  isParentToChildMessage,
  type IpcToolStart,
  type IpcToolComplete,
  type IpcAgentLifecycle,
} from '../ipc-messages.js';

describe('Wave 5 IPC shapes — IpcToolStart', () => {
  it('accepts a minimal payload', () => {
    const msg: IpcToolStart = {
      type: 'ipc:tool.start',
      sessionId: 'sess-1',
      tool: 'Read',
      input: { path: '/tmp' },
    };
    expect(isChildToParentMessage(msg)).toBe(true);
  });

  it('accepts subagentId + toolUseId populated', () => {
    const msg: IpcToolStart = {
      type: 'ipc:tool.start',
      sessionId: 'sess-1',
      tool: 'Read',
      input: { path: '/tmp' },
      subagentId: 'agent-1',
      toolUseId: 'toolu_01ABC',
    };
    expect(msg.subagentId).toBe('agent-1');
    expect(isChildToParentMessage(msg)).toBe(true);
  });
});

describe('Wave 5 IPC shapes — IpcToolComplete', () => {
  it('accepts a minimal payload', () => {
    const msg: IpcToolComplete = {
      type: 'ipc:tool.complete',
      sessionId: 'sess-1',
      tool: 'Read',
      output: 'ok',
      success: true,
    };
    expect(isChildToParentMessage(msg)).toBe(true);
  });

  it('accepts subagent attribution fields', () => {
    const msg: IpcToolComplete = {
      type: 'ipc:tool.complete',
      sessionId: 'sess-1',
      tool: 'Read',
      output: 'ok',
      success: true,
      subagentId: 'agent-1',
      toolUseId: 'toolu_01ABC',
    };
    expect(isChildToParentMessage(msg)).toBe(true);
  });
});

describe('Wave 5 IPC shapes — IpcAgentLifecycle', () => {
  it('working event without metrics (pre-Wave-5 shape)', () => {
    const msg: IpcAgentLifecycle = {
      type: 'ipc:agent.lifecycle',
      sessionId: 'sess-1',
      agentId: 'agent-1',
      event: 'working',
      task: 'explore',
    };
    expect(isChildToParentMessage(msg)).toBe(true);
    expect(msg.toolCount).toBeUndefined();
    expect(msg.tokenCount).toBeUndefined();
  });

  it('working event with live metrics', () => {
    const msg: IpcAgentLifecycle = {
      type: 'ipc:agent.lifecycle',
      sessionId: 'sess-1',
      agentId: 'agent-1',
      event: 'working',
      task: 'explore',
      toolCount: 5,
      tokenCount: 1500,
    };
    expect(isChildToParentMessage(msg)).toBe(true);
    expect(msg.toolCount).toBe(5);
    expect(msg.tokenCount).toBe(1500);
  });

  it('dismissed event with final toolCount but no tokenCount (unattributable tokens)', () => {
    const msg: IpcAgentLifecycle = {
      type: 'ipc:agent.lifecycle',
      sessionId: 'sess-1',
      agentId: 'agent-1',
      event: 'dismissed',
      toolCount: 3,
    };
    expect(isChildToParentMessage(msg)).toBe(true);
    expect(msg.toolCount).toBe(3);
    expect(msg.tokenCount).toBeUndefined();
  });
});

describe('Wave 5 IPC guards remain lenient on unknown fields', () => {
  it('isParentToChildMessage still accepts sprite.enqueue (unrelated)', () => {
    expect(
      isParentToChildMessage({
        type: 'ipc:sprite.enqueue',
        sessionId: 's',
        subagentId: 'a',
        spriteHandle: 'h',
        messageId: 'm',
        userText: 'hi',
        role: 'frontend',
        task: 'build',
      }),
    ).toBe(true);
  });

  it('guard returns false for unknown types', () => {
    expect(
      isChildToParentMessage({
        type: 'ipc:unknown.thing',
      }),
    ).toBe(false);
  });
});
