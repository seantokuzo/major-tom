import { describe, it, expect, beforeEach } from 'vitest';
import { SessionManager } from '../session-manager.js';
import type { SessionPersistence } from '../session-persistence.js';

/**
 * registerExternal does not touch persistence, so a bare stub satisfies the
 * constructor without spinning up ~/.major-tom/ directories during tests.
 */
const stubPersistence = {} as SessionPersistence;

describe('SessionManager.registerExternal', () => {
  let manager: SessionManager;

  beforeEach(() => {
    manager = new SessionManager(stubPersistence);
  });

  it('creates a Session using the caller-supplied id', () => {
    const session = manager.registerExternal('claude-abc-123', '/home/u/proj');
    expect(session.id).toBe('claude-abc-123');
    expect(session.adapter).toBe('cli-external');
    expect(session.workingDir).toBe('/home/u/proj');
    expect(session.status).toBe('active');
  });

  it('is retrievable via get()', () => {
    manager.registerExternal('sess-X', '/tmp');
    expect(manager.get('sess-X').id).toBe('sess-X');
  });

  it('appears in list()', () => {
    manager.registerExternal('sess-Y', '/tmp');
    const ids = manager.list().map((s) => s.id);
    expect(ids).toContain('sess-Y');
  });

  it('is idempotent — a duplicate registration returns the existing Session', () => {
    const first = manager.registerExternal('sess-dup', '/a');
    const second = manager.registerExternal('sess-dup', '/b');
    expect(second).toBe(first);
    expect(manager.list().filter((s) => s.id === 'sess-dup')).toHaveLength(1);
    // The first workingDir wins (idempotence — not a re-registration).
    expect(second.workingDir).toBe('/a');
  });

  it('does not collide with UUID-generated create() ids', () => {
    const external = manager.registerExternal('custom-id', '/a');
    const created = manager.create('cli', '/b');
    expect(external.id).toBe('custom-id');
    expect(created.id).not.toBe('custom-id');
    expect(manager.list()).toHaveLength(2);
  });
});
