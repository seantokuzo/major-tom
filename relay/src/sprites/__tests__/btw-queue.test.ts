import { describe, it, expect, vi } from 'vitest';
import { BtwQueue, buildConstrainedText } from '../btw-queue.js';

describe('buildConstrainedText', () => {
  it('wraps user text in the locked constraint framing', () => {
    const out = buildConstrainedText({
      role: 'frontend',
      task: 'build a form',
      userText: 'any progress on that form?',
    });
    expect(out).toContain('non-blocking observation');
    expect(out).toContain('subagent "frontend"');
    expect(out).toContain('task: "build a form"');
    expect(out).toContain("'any progress on that form?'");
    expect(out).toContain('1-2 sentences');
    expect(out).toContain('Do NOT change the subagent');
  });

  it('escapes quotes in user text, role, and task', () => {
    const out = buildConstrainedText({
      role: "it's fine",
      task: "don't worry",
      userText: "don't panic",
    });
    // Single quotes are escaped so the outer framing stays parseable.
    expect(out).toContain("\\'");
  });
});

describe('BtwQueue', () => {
  const baseInput = () => ({
    sessionId: 'sess-1',
    subagentId: 'agent-1',
    spriteHandle: 'sprite-abc',
    messageId: 'msg-1',
    userText: 'hi there',
    role: 'backend',
    task: 'wire the queue',
  });

  it('enqueues a message and marks it queued', () => {
    const q = new BtwQueue();
    const entry = q.enqueue(baseInput());
    expect(entry.status).toBe('queued');
    expect(entry.constrainedText).toContain('non-blocking observation');
    expect(q.size).toBe(1);
    expect(q.sizeFor('agent-1')).toBe(1);
  });

  it('emits "injected" when takeNextForSubagent is called', () => {
    const q = new BtwQueue();
    q.enqueue(baseInput());
    const injected = vi.fn();
    q.on('injected', injected);
    const taken = q.takeNextForSubagent('agent-1');
    expect(taken?.status).toBe('injected');
    expect(injected).toHaveBeenCalledWith({
      sessionId: 'sess-1',
      subagentId: 'agent-1',
      spriteHandle: 'sprite-abc',
      messageId: 'msg-1',
    });
  });

  it('FIFO per subagent (M1 — multiple queued)', () => {
    const q = new BtwQueue();
    q.enqueue({ ...baseInput(), messageId: 'msg-1' });
    q.enqueue({ ...baseInput(), messageId: 'msg-2' });
    q.enqueue({ ...baseInput(), messageId: 'msg-3' });
    expect(q.sizeFor('agent-1')).toBe(3);
    const first = q.takeNextForSubagent('agent-1');
    expect(first?.messageId).toBe('msg-1');
    const second = q.takeNextForSubagent('agent-1');
    expect(second?.messageId).toBe('msg-2');
    const third = q.takeNextForSubagent('agent-1');
    expect(third?.messageId).toBe('msg-3');
  });

  it('peekQueuedForSession returns only queued entries for that session', () => {
    const q = new BtwQueue();
    q.enqueue({ ...baseInput(), messageId: 'msg-1', subagentId: 'a1' });
    q.enqueue({ ...baseInput(), messageId: 'msg-2', subagentId: 'a2' });
    q.enqueue({ ...baseInput(), messageId: 'msg-3', sessionId: 'sess-other' });

    const forSess1 = q.peekQueuedForSession('sess-1');
    expect(forSess1).toHaveLength(2);
    expect(forSess1.map(e => e.messageId)).toEqual(['msg-1', 'msg-2']);
  });

  it('peekQueuedForSession ignores already-injected entries', () => {
    const q = new BtwQueue();
    q.enqueue({ ...baseInput(), messageId: 'msg-1' });
    q.enqueue({ ...baseInput(), messageId: 'msg-2' });
    q.takeNextForSubagent('agent-1'); // injects msg-1
    const forSess1 = q.peekQueuedForSession('sess-1');
    expect(forSess1).toHaveLength(1);
    expect(forSess1[0]!.messageId).toBe('msg-2');
  });

  it('markAwaitingResponse transitions injected entries correctly', () => {
    const q = new BtwQueue();
    q.enqueue(baseInput());
    q.takeNextForSubagent('agent-1');
    const marked = q.markAwaitingResponse('msg-1');
    expect(marked?.status).toBe('awaiting_response');
  });

  it('findAwaitingForSession returns the in-flight entry', () => {
    const q = new BtwQueue();
    q.enqueue(baseInput());
    q.takeNextForSubagent('agent-1');
    q.markAwaitingResponse('msg-1');
    const found = q.findAwaitingForSession('sess-1');
    expect(found?.messageId).toBe('msg-1');
    expect(found?.status).toBe('awaiting_response');
  });

  it('markResponded removes entry and emits "responded"', () => {
    const q = new BtwQueue();
    q.enqueue(baseInput());
    q.takeNextForSubagent('agent-1');
    q.markAwaitingResponse('msg-1');
    const responded = vi.fn();
    q.on('responded', responded);
    const removed = q.markResponded('msg-1', 'Making good progress on the wiring!');
    expect(removed?.messageId).toBe('msg-1');
    expect(q.size).toBe(0);
    expect(responded).toHaveBeenCalledWith({
      sessionId: 'sess-1',
      subagentId: 'agent-1',
      spriteHandle: 'sprite-abc',
      messageId: 'msg-1',
      text: 'Making good progress on the wiring!',
    });
  });

  it('dropForSubagent fires "dropped" for each entry (scenario #4)', () => {
    const q = new BtwQueue();
    q.enqueue({ ...baseInput(), messageId: 'msg-1' });
    q.enqueue({ ...baseInput(), messageId: 'msg-2' });
    const dropped = vi.fn();
    q.on('dropped', dropped);
    const count = q.dropForSubagent('agent-1', 'Subagent completed before delivery');
    expect(count).toBe(2);
    expect(dropped).toHaveBeenCalledTimes(2);
    expect(dropped).toHaveBeenNthCalledWith(1, expect.objectContaining({
      messageId: 'msg-1',
      reason: 'Subagent completed before delivery',
    }));
    expect(dropped).toHaveBeenNthCalledWith(2, expect.objectContaining({
      messageId: 'msg-2',
      reason: 'Subagent completed before delivery',
    }));
    expect(q.size).toBe(0);
  });

  it('dropForSubagent drops both queued AND injected/awaiting entries', () => {
    const q = new BtwQueue();
    q.enqueue({ ...baseInput(), messageId: 'msg-1' });
    q.enqueue({ ...baseInput(), messageId: 'msg-2' });
    q.takeNextForSubagent('agent-1'); // msg-1 → injected
    q.markAwaitingResponse('msg-1');  // msg-1 → awaiting_response
    const dropped = vi.fn();
    q.on('dropped', dropped);
    const count = q.dropForSubagent('agent-1', 'Session ended');
    expect(count).toBe(2);
    expect(dropped).toHaveBeenCalledTimes(2);
  });

  it('dropForSession drops entries across multiple subagents', () => {
    const q = new BtwQueue();
    q.enqueue({ ...baseInput(), subagentId: 'a1', messageId: 'msg-1' });
    q.enqueue({ ...baseInput(), subagentId: 'a2', messageId: 'msg-2' });
    q.enqueue({ ...baseInput(), subagentId: 'a3', messageId: 'msg-3', sessionId: 'sess-2' });
    const dropped = vi.fn();
    q.on('dropped', dropped);
    const count = q.dropForSession('sess-1', 'Session ended');
    expect(count).toBe(2);
    expect(dropped).toHaveBeenCalledTimes(2);
    expect(q.sizeFor('a3')).toBe(1); // different session, not dropped
  });

  it('dropForSubagent on empty queue returns 0, emits nothing', () => {
    const q = new BtwQueue();
    const dropped = vi.fn();
    q.on('dropped', dropped);
    const count = q.dropForSubagent('ghost-agent', 'Nonexistent');
    expect(count).toBe(0);
    expect(dropped).not.toHaveBeenCalled();
  });

  it('takeNextForSubagent on empty queue returns undefined', () => {
    const q = new BtwQueue();
    expect(q.takeNextForSubagent('nobody')).toBeUndefined();
  });

  it('markResponded for unknown messageId returns undefined', () => {
    const q = new BtwQueue();
    expect(q.markResponded('ghost-msg', 'irrelevant')).toBeUndefined();
  });

  it('multiple subagents, independent queues', () => {
    const q = new BtwQueue();
    q.enqueue({ ...baseInput(), subagentId: 'a1', messageId: 'msg-a1-1' });
    q.enqueue({ ...baseInput(), subagentId: 'a1', messageId: 'msg-a1-2' });
    q.enqueue({ ...baseInput(), subagentId: 'a2', messageId: 'msg-a2-1' });

    expect(q.sizeFor('a1')).toBe(2);
    expect(q.sizeFor('a2')).toBe(1);
    expect(q.size).toBe(3);

    // Dropping a1 doesn't touch a2
    q.dropForSubagent('a1', 'gone');
    expect(q.sizeFor('a1')).toBe(0);
    expect(q.sizeFor('a2')).toBe(1);
  });
});
