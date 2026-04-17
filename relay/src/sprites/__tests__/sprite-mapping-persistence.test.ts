// Wave 6 — persistence cascade hardening tests for SpriteMappingPersistence.
//
// Covers the three-tier resolution cascade from docs/PHASE-SPRITE-AGENT-WIRING.md:
//   1. Relay-authoritative (disk file, valid) — load() returns the file.
//   2. Client-authoritative (corrupt / unreadable file) — load() returns null +
//      logs WARN, ws.ts falls through to iOS re-sending its mappings.
//   3. Best-effort rebuild (mapping never persists) — load() returns null and
//      fresh allocation from live agent state takes over.
//
// Also covers:
//   - Disk-full (ENOSPC) on write — writeToDisk returns false, in-memory survives.
//   - Cold-boot stale-file detection via listStale().
//   - Session-end delete path.

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { mkdtemp, rm, readFile, writeFile, readdir, stat, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import {
  SpriteMappingPersistence,
  type PersistedSpriteMappingFile,
} from '../sprite-mapping-persistence.js';

// Helper — construct a minimal valid mapping file.
function sampleFile(sessionId: string, count = 1): PersistedSpriteMappingFile {
  return {
    version: 1,
    sessionId,
    updatedAt: new Date().toISOString(),
    roleBindings: { backend: 'backendEngineer' },
    mappings: Array.from({ length: count }, (_, i) => ({
      spriteHandle: `sprite-${sessionId}-${i}`,
      subagentId: `agent-${sessionId}-${i}`,
      canonicalRole: 'backend',
      characterType: 'backendEngineer',
      task: `task ${i}`,
      deskIndex: i,
      linkedAt: new Date().toISOString(),
    })),
  };
}

describe('SpriteMappingPersistence — cascade tier 1 (relay-authoritative)', () => {
  let baseDir: string;
  let persistence: SpriteMappingPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'sprite-map-persist-'));
    persistence = new SpriteMappingPersistence({ baseDir });
  });

  afterEach(async () => {
    persistence.dispose();
    await rm(baseDir, { recursive: true, force: true });
  });

  it('saveImmediate + load round-trip returns equivalent data', async () => {
    const original = sampleFile('sess-abc', 2);
    await persistence.saveImmediate(original);
    const loaded = await persistence.load('sess-abc');
    expect(loaded).not.toBeNull();
    expect(loaded!.sessionId).toBe('sess-abc');
    expect(loaded!.mappings).toHaveLength(2);
    expect(loaded!.mappings[0]!.subagentId).toBe('agent-sess-abc-0');
    expect(loaded!.roleBindings).toEqual({ backend: 'backendEngineer' });
  });

  it('load returns null for a missing file (ENOENT is not a cascade failure)', async () => {
    const loaded = await persistence.load('nonexistent-session');
    expect(loaded).toBeNull();
  });

  it('delete removes a previously-saved file without errors', async () => {
    const file = sampleFile('sess-to-delete');
    await persistence.saveImmediate(file);
    await persistence.delete('sess-to-delete');
    const after = await persistence.load('sess-to-delete');
    expect(after).toBeNull();
    // Re-deleting is a no-op (ENOENT already handled).
    await expect(persistence.delete('sess-to-delete')).resolves.toBeUndefined();
  });

  it('deleteAll clears every mapping file on shutdown', async () => {
    await persistence.saveImmediate(sampleFile('sess-1'));
    await persistence.saveImmediate(sampleFile('sess-2'));
    await persistence.saveImmediate(sampleFile('sess-3'));
    await persistence.deleteAll();
    const files = await readdir(baseDir);
    expect(files.filter((f) => f.endsWith('.json'))).toHaveLength(0);
  });
});

describe('SpriteMappingPersistence — cascade tier 2 (corrupt/unreadable → client-authoritative)', () => {
  let baseDir: string;
  let persistence: SpriteMappingPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'sprite-map-corrupt-'));
    persistence = new SpriteMappingPersistence({ baseDir });
  });

  afterEach(async () => {
    persistence.dispose();
    await rm(baseDir, { recursive: true, force: true });
  });

  it('load returns null when the file contains invalid JSON (spec: cascade falls through)', async () => {
    // Ensure the directory exists (constructor fires async).
    await stat(baseDir);
    const file = join(baseDir, 'corrupt-sess.json');
    await writeFile(file, '{{{ not json at all', 'utf-8');

    const loaded = await persistence.load('corrupt-sess');
    expect(loaded).toBeNull();
    // Sanity — file still exists (we don't delete on corrupt; next cold
    // boot cleanup reaps it or iOS overwrites it after reconnect).
    await expect(stat(file)).resolves.toBeDefined();
  });

  it('load returns null when the file is valid JSON but has the wrong schema', async () => {
    const file = join(baseDir, 'wrongschema.json');
    await writeFile(file, JSON.stringify({ version: 99, nope: true }), 'utf-8');
    expect(await persistence.load('wrongschema')).toBeNull();
  });

  it('load returns null when version is missing entirely', async () => {
    const file = join(baseDir, 'noversion.json');
    await writeFile(file, JSON.stringify({ sessionId: 'noversion', mappings: [] }), 'utf-8');
    expect(await persistence.load('noversion')).toBeNull();
  });

  it('load returns null when mappings is not an array', async () => {
    const file = join(baseDir, 'badarray.json');
    await writeFile(
      file,
      JSON.stringify({ version: 1, sessionId: 'badarray', mappings: 'nope' }),
      'utf-8',
    );
    expect(await persistence.load('badarray')).toBeNull();
  });

  it('load handles file-system read errors gracefully (simulated EACCES)', async () => {
    // Inject a readFile that throws an EACCES-style error.
    const faultyFs = {
      readFile: vi.fn().mockRejectedValue(
        Object.assign(new Error('permission denied'), { code: 'EACCES' }),
      ),
    };
    const testDir = await mkdtemp(join(tmpdir(), 'sprite-faulty-'));
    try {
      const p = new SpriteMappingPersistence({ baseDir: testDir, fs: faultyFs });
      const loaded = await p.load('some-sess');
      expect(loaded).toBeNull();
      expect(faultyFs.readFile).toHaveBeenCalled();
      p.dispose();
    } finally {
      await rm(testDir, { recursive: true, force: true });
    }
  });

  it('load preserves backward-compat migration from agentId/role → subagentId/canonicalRole', async () => {
    // Old-format file from pre-Wave-5 relay build.
    const legacy = {
      version: 1,
      sessionId: 'legacy-sess',
      updatedAt: new Date().toISOString(),
      roleBindings: {},
      mappings: [
        {
          spriteHandle: 'sprite-x',
          agentId: 'old-agent-id',       // old name
          role: 'frontend',              // old name
          characterType: 'frontendDev',
          // no `task` field (default '')
          deskIndex: 2,
          linkedAt: new Date().toISOString(),
        },
      ],
    };
    const file = join(baseDir, 'legacy-sess.json');
    await writeFile(file, JSON.stringify(legacy), 'utf-8');

    const loaded = await persistence.load('legacy-sess');
    expect(loaded).not.toBeNull();
    const m = loaded!.mappings[0]! as unknown as Record<string, unknown>;
    expect(m['subagentId']).toBe('old-agent-id');
    expect(m['canonicalRole']).toBe('frontend');
    expect(m['task']).toBe('');
  });
});

describe('SpriteMappingPersistence — disk-full (ENOSPC) survival', () => {
  let baseDir: string;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'sprite-enospc-'));
  });

  afterEach(async () => {
    await rm(baseDir, { recursive: true, force: true });
  });

  it('saveImmediate does not throw when the filesystem raises ENOSPC (scenario: disk full)', async () => {
    const enospc = Object.assign(new Error('no space left on device'), { code: 'ENOSPC' });
    const faultyFs = {
      // Allow directory creation (so ensureDir succeeds) but fail writes.
      mkdir: mkdir as unknown as typeof mkdir,
      writeFile: vi.fn().mockRejectedValue(enospc),
    };
    const p = new SpriteMappingPersistence({ baseDir, fs: faultyFs });
    // saveImmediate must not throw — the contract is "in-memory survives".
    await expect(p.saveImmediate(sampleFile('enospc-sess'))).resolves.toBeUndefined();
    expect(faultyFs.writeFile).toHaveBeenCalled();
    p.dispose();
  });

  it('saveImmediate does not throw on generic EIO errors', async () => {
    const eio = Object.assign(new Error('i/o error'), { code: 'EIO' });
    const faultyFs = {
      writeFile: vi.fn().mockRejectedValue(eio),
    };
    const p = new SpriteMappingPersistence({ baseDir, fs: faultyFs });
    await expect(p.saveImmediate(sampleFile('eio-sess'))).resolves.toBeUndefined();
    p.dispose();
  });

  it('debounced save recovers on next write once disk clears', async () => {
    // First write fails with ENOSPC; a manual `writeFile` succeeds after
    // the injected mock is restored. This is the contract Wave 6 needs:
    // transient failures do not poison the persistence instance.
    const enospc = Object.assign(new Error('no space'), { code: 'ENOSPC' });
    let failNext = true;
    const realWriteFile = writeFile;
    const flakyFs = {
      writeFile: vi.fn().mockImplementation(async (...args: Parameters<typeof writeFile>) => {
        if (failNext) throw enospc;
        return realWriteFile(...args);
      }),
    };
    const p = new SpriteMappingPersistence({ baseDir, fs: flakyFs });

    await p.saveImmediate(sampleFile('flaky-sess'));
    // First write blew up → file should not exist yet.
    const first = await persistenceReadOrNull(join(baseDir, 'flaky-sess.json'));
    expect(first).toBeNull();

    failNext = false;
    await p.saveImmediate(sampleFile('flaky-sess'));
    const second = await persistenceReadOrNull(join(baseDir, 'flaky-sess.json'));
    expect(second).not.toBeNull();
    p.dispose();
  });
});

describe('SpriteMappingPersistence — cold-boot stale-file cleanup', () => {
  let baseDir: string;
  let persistence: SpriteMappingPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'sprite-stale-'));
    persistence = new SpriteMappingPersistence({ baseDir });
  });

  afterEach(async () => {
    persistence.dispose();
    await rm(baseDir, { recursive: true, force: true });
  });

  it('listStale returns only sessionIds without a live session', async () => {
    // Drop three fake mapping files on disk.
    await persistence.saveImmediate(sampleFile('live-sess'));
    await persistence.saveImmediate(sampleFile('stale-a'));
    await persistence.saveImmediate(sampleFile('stale-b'));

    const stale = await persistence.listStale((sid) => sid === 'live-sess');
    expect(stale.sort()).toEqual(['stale-a', 'stale-b'].sort());
  });

  it('listStale tolerates an empty directory', async () => {
    const stale = await persistence.listStale(() => false);
    expect(stale).toEqual([]);
  });

  it('listStale + delete loop cleans up every stale file (end-to-end cold boot)', async () => {
    await persistence.saveImmediate(sampleFile('keep'));
    await persistence.saveImmediate(sampleFile('kill-1'));
    await persistence.saveImmediate(sampleFile('kill-2'));

    const stale = await persistence.listStale((sid) => sid === 'keep');
    for (const sid of stale) await persistence.delete(sid);

    const remaining = await readdir(baseDir);
    expect(remaining.filter((f) => f.endsWith('.json'))).toEqual(['keep.json']);
  });

  it('listStale ignores non-.json files in the directory', async () => {
    await persistence.saveImmediate(sampleFile('real'));
    // Drop a couple of stray files that a user or an old relay could have left.
    await writeFile(join(baseDir, 'README.txt'), 'hi', 'utf-8');
    await writeFile(join(baseDir, '.DS_Store'), '', 'utf-8');
    const stale = await persistence.listStale(() => false);
    expect(stale).toEqual(['real']);
  });
});

describe('SpriteMappingPersistence — filePath sanitization', () => {
  let baseDir: string;
  let persistence: SpriteMappingPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'sprite-sani-'));
    persistence = new SpriteMappingPersistence({ baseDir });
  });

  afterEach(async () => {
    persistence.dispose();
    await rm(baseDir, { recursive: true, force: true });
  });

  // Path-traversal attempts: filePath() throws internally. load() and
  // delete() catch it (the thrown Error has no `.code === 'ENOENT'`) and
  // funnel it through the non-ENOENT WARN-log branch — so the operation
  // doesn't throw, but a WARN line IS emitted. save() runs inside the
  // debounce timer so its internal catch swallows the throw silently.
  // We tolerate the WARN: it helps operators spot suspect sessionIds
  // without leaking "which sessionIds are valid" to the caller.

  it('delete on an invalid session ID silently no-ops', async () => {
    await expect(persistence.delete('../../../etc/passwd')).resolves.toBeUndefined();
    // Confirm we didn't accidentally write or delete anything in the base dir.
    const after = await readdir(baseDir);
    expect(after.filter((f) => f.endsWith('.json'))).toHaveLength(0);
  });

  it('load on an invalid session ID returns null (client-authoritative fallback)', async () => {
    await expect(persistence.load('../escape-attempt')).resolves.toBeNull();
  });

  it('save on an invalid session ID silently no-ops via the debounce timer', async () => {
    // save() itself is synchronous; the internal timer catches the throw.
    expect(() => persistence.save(sampleFile('../bad-id'))).not.toThrow();
    // Nothing lands on disk.
    await new Promise((r) => setTimeout(r, 20));
    const after = await readdir(baseDir);
    expect(after.filter((f) => f.endsWith('.json'))).toHaveLength(0);
  });
});

// Small helper: return file contents or null on ENOENT.
async function persistenceReadOrNull(path: string): Promise<string | null> {
  try {
    return await readFile(path, 'utf-8');
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') return null;
    throw err;
  }
}

