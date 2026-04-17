// Wave 5 — compile-time + runtime shape tests for the new optional
// fields on tool.* and agent.* messages. The interfaces are
// discriminated unions so a purely structural test here also serves as
// a compile-gate: if the field isn't declared, the test stops
// compiling.

import { describe, it, expect } from 'vitest';
import type {
  ToolStartMessage,
  ToolCompleteMessage,
  AgentWorkingMessage,
  AgentIdleMessage,
} from '../messages.js';

describe('Wave 5 protocol shapes — ToolStartMessage', () => {
  it('accepts a minimal (backward-compatible) payload with only required fields', () => {
    const msg: ToolStartMessage = {
      type: 'tool.start',
      sessionId: 'sess-1',
      tool: 'Read',
      input: { path: '/tmp/foo' },
    };
    expect(msg.subagentId).toBeUndefined();
    expect(msg.spriteHandle).toBeUndefined();
    expect(msg.toolUseId).toBeUndefined();
  });

  it('accepts all optional Wave 5 fields populated', () => {
    const msg: ToolStartMessage = {
      type: 'tool.start',
      sessionId: 'sess-1',
      tool: 'Read',
      input: { path: '/tmp/foo' },
      subagentId: 'agent-1',
      spriteHandle: 'sprite-abc',
      toolUseId: 'toolu_01ABC',
    };
    expect(msg.subagentId).toBe('agent-1');
    expect(msg.spriteHandle).toBe('sprite-abc');
    expect(msg.toolUseId).toBe('toolu_01ABC');
  });
});

describe('Wave 5 protocol shapes — ToolCompleteMessage', () => {
  it('accepts a minimal payload (no Wave 5 fields set)', () => {
    const msg: ToolCompleteMessage = {
      type: 'tool.complete',
      sessionId: 'sess-1',
      tool: 'Read',
      output: 'file contents',
      success: true,
    };
    expect(msg.subagentId).toBeUndefined();
    expect(msg.spriteHandle).toBeUndefined();
    expect(msg.toolUseId).toBeUndefined();
  });

  it('accepts all optional fields populated', () => {
    const msg: ToolCompleteMessage = {
      type: 'tool.complete',
      sessionId: 'sess-1',
      tool: 'Read',
      output: 'contents',
      success: true,
      subagentId: 'agent-1',
      spriteHandle: 'sprite-abc',
      toolUseId: 'toolu_01ABC',
    };
    expect(msg.subagentId).toBe('agent-1');
    expect(msg.spriteHandle).toBe('sprite-abc');
  });
});

describe('Wave 5 protocol shapes — AgentWorkingMessage', () => {
  it('accepts a minimal payload (no metrics)', () => {
    const msg: AgentWorkingMessage = {
      type: 'agent.working',
      sessionId: 'sess-1',
      agentId: 'agent-1',
      task: 'explore the codebase',
    };
    expect(msg.toolCount).toBeUndefined();
    expect(msg.tokenCount).toBeUndefined();
  });

  it('accepts toolCount + tokenCount optional fields', () => {
    const msg: AgentWorkingMessage = {
      type: 'agent.working',
      sessionId: 'sess-1',
      agentId: 'agent-1',
      task: 'explore the codebase',
      toolCount: 5,
      tokenCount: 1234,
    };
    expect(msg.toolCount).toBe(5);
    expect(msg.tokenCount).toBe(1234);
  });

  it('accepts toolCount without tokenCount (partial metrics)', () => {
    // Spec: tokenCount is allowed to be undefined when attribution is
    // impossible, while toolCount is always countable.
    const msg: AgentWorkingMessage = {
      type: 'agent.working',
      sessionId: 'sess-1',
      agentId: 'agent-1',
      task: 'build a form',
      toolCount: 3,
    };
    expect(msg.toolCount).toBe(3);
    expect(msg.tokenCount).toBeUndefined();
  });
});

describe('Wave 5 protocol shapes — AgentIdleMessage', () => {
  it('accepts a minimal payload', () => {
    const msg: AgentIdleMessage = {
      type: 'agent.idle',
      sessionId: 'sess-1',
      agentId: 'agent-1',
    };
    expect(msg.toolCount).toBeUndefined();
    expect(msg.tokenCount).toBeUndefined();
  });

  it('accepts metrics on idle events too', () => {
    const msg: AgentIdleMessage = {
      type: 'agent.idle',
      sessionId: 'sess-1',
      agentId: 'agent-1',
      toolCount: 7,
      tokenCount: 2048,
    };
    expect(msg.toolCount).toBe(7);
    expect(msg.tokenCount).toBe(2048);
  });
});
