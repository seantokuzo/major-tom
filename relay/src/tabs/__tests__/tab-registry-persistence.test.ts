import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, rm, readdir, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { TabRegistry } from '../tab-registry.js';
import { TabRegistryPersistence } from '../tab-registry-persistence.js';

describe('TabRegistryPersistence', () => {
  let baseDir: string;
  let persistence: TabRegistryPersistence;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'tab-registry-'));
    persistence = new TabRegistryPersistence({ baseDir });
  });

  afterEach(async () => {
    await rm(baseDir, { recursive: true, force: true });
  });

  describe('save + load roundtrip', () => {
    it('persists a TabMeta and reads it back identically', async () => {
      const registry = new TabRegistry(persistence);
      registry.registerSessionStart('sess-1', 'tab-A', '/home/u/proj', 'user-1');
      await new Promise((r) => setTimeout(r, 20));

      const loaded = await persistence.load('tab-A');
      expect(loaded).not.toBeNull();
      expect(loaded!.tabId).toBe('tab-A');
      expect(loaded!.userId).toBe('user-1');
      expect(loaded!.workingDir).toBe('/home/u/proj');
      expect(loaded!.sessionIds).toEqual(['sess-1']);
      expect(loaded!.status).toBe('active');
    });

    it('returns null for a missing file (ENOENT is silent)', async () => {
      const loaded = await persistence.load('ghost');
      expect(loaded).toBeNull();
    });

    it('returns null for a corrupt file', async () => {
      await writeFile(join(baseDir, 'tab-X.json'), 'not json at all', 'utf-8');
      const loaded = await persistence.load('tab-X');
      expect(loaded).toBeNull();
    });

    it('returns null for a file with wrong schema', async () => {
      await writeFile(
        join(baseDir, 'tab-Y.json'),
        JSON.stringify({ version: 99, random: 'garbage' }),
        'utf-8',
      );
      const loaded = await persistence.load('tab-Y');
      expect(loaded).toBeNull();
    });

    it('rejects invalid tabId characters at write time', async () => {
      await expect(
        persistence.save({
          tabId: '../etc/passwd',
          userId: undefined,
          workingDir: undefined,
          createdAt: new Date().toISOString(),
          lastSeenAt: new Date().toISOString(),
          sessionIds: new Set(),
          status: 'idle',
        }),
      ).rejects.toThrow(/Invalid tabId/);
    });
  });

  describe('loadAll', () => {
    it('returns every valid tab file', async () => {
      const registry = new TabRegistry(persistence);
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      registry.registerSessionStart('sess-2', 'tab-B', '/other', 'user-2');
      await new Promise((r) => setTimeout(r, 20));

      const all = await persistence.loadAll();
      expect(all).toHaveLength(2);
      const ids = all.map((t) => t.tabId).sort();
      expect(ids).toEqual(['tab-A', 'tab-B']);
    });

    it('skips non-json files', async () => {
      await writeFile(join(baseDir, 'README.txt'), 'hi', 'utf-8');
      const all = await persistence.loadAll();
      expect(all).toHaveLength(0);
    });

    it('skips corrupt files gracefully', async () => {
      const registry = new TabRegistry(persistence);
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      await new Promise((r) => setTimeout(r, 20));
      await writeFile(join(baseDir, 'tab-bad.json'), '{{{', 'utf-8');

      const all = await persistence.loadAll();
      expect(all.map((t) => t.tabId).sort()).toEqual(['tab-A']);
    });

    it('returns [] when the directory is empty', async () => {
      const all = await persistence.loadAll();
      expect(all).toEqual([]);
    });
  });

  describe('delete', () => {
    it('removes the persisted file', async () => {
      const registry = new TabRegistry(persistence);
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      await new Promise((r) => setTimeout(r, 20));
      expect(await persistence.load('tab-A')).not.toBeNull();

      await persistence.delete('tab-A');
      expect(await persistence.load('tab-A')).toBeNull();
    });

    it('is a no-op for an unknown tabId', async () => {
      await expect(persistence.delete('ghost')).resolves.toBeUndefined();
    });
  });

  describe('TabRegistry integration (fire-and-forget saves)', () => {
    it('writes one file on registerSessionStart', async () => {
      const registry = new TabRegistry(persistence);
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      await new Promise((r) => setTimeout(r, 20));
      const files = await readdir(baseDir);
      expect(files.filter((f) => f.endsWith('.json'))).toEqual(['tab-A.json']);
    });

    it('updates the file on registerSessionEnd', async () => {
      const registry = new TabRegistry(persistence);
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      await new Promise((r) => setTimeout(r, 20));
      registry.registerSessionEnd('sess-1');
      await new Promise((r) => setTimeout(r, 20));

      const raw = await readFile(join(baseDir, 'tab-A.json'), 'utf-8');
      const parsed = JSON.parse(raw);
      expect(parsed.sessionIds).toEqual([]);
      expect(parsed.status).toBe('idle');
    });

    it('deletes the file on tabClosed', async () => {
      const registry = new TabRegistry(persistence);
      registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
      await new Promise((r) => setTimeout(r, 20));
      expect(await persistence.load('tab-A')).not.toBeNull();

      registry.tabClosed('tab-A');
      await new Promise((r) => setTimeout(r, 20));
      expect(await persistence.load('tab-A')).toBeNull();
    });
  });

  describe('restoreFromDisk', () => {
    it('rehydrates tabs from disk', async () => {
      {
        const firstRegistry = new TabRegistry(persistence);
        firstRegistry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
        firstRegistry.registerSessionStart('sess-2', 'tab-B', '/other', 'user-2');
        await new Promise((r) => setTimeout(r, 20));
      }

      const fresh = new TabRegistry(persistence);
      await fresh.restoreFromDisk();
      expect(fresh.listTabs()).toHaveLength(2);
      expect(fresh.getTab('tab-A')?.userId).toBe('user-1');
      expect(fresh.getTab('tab-B')?.userId).toBe('user-2');
    });

    it('resets sessionIds to empty and forces idle status on rehydrate', async () => {
      {
        const firstRegistry = new TabRegistry(persistence);
        firstRegistry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1');
        await new Promise((r) => setTimeout(r, 20));
      }

      const fresh = new TabRegistry(persistence);
      await fresh.restoreFromDisk();
      const tab = fresh.getTab('tab-A')!;
      expect(tab.sessionIds.size).toBe(0);
      expect(tab.status).toBe('idle');
      expect(fresh.getTabForSession('sess-1')).toBeUndefined();
    });

    it('is a no-op when no persistence is configured', async () => {
      const ghost = new TabRegistry();
      await expect(ghost.restoreFromDisk()).resolves.toBeUndefined();
      expect(ghost.listTabs()).toEqual([]);
    });

    it('starts empty when the directory does not exist', async () => {
      await rm(baseDir, { recursive: true, force: true });
      const fresh = new TabRegistry(persistence);
      await fresh.restoreFromDisk();
      expect(fresh.listTabs()).toEqual([]);
    });
  });

  describe('save failure modes', () => {
    it('does not throw when writeFile rejects (ENOSPC)', async () => {
      const failingFs = {
        writeFile: async () => {
          const err = new Error('no space') as NodeJS.ErrnoException;
          err.code = 'ENOSPC';
          throw err;
        },
      };
      const flaky = new TabRegistryPersistence({ baseDir, fs: failingFs });
      const registry = new TabRegistry(flaky);
      expect(() => registry.registerSessionStart('sess-1', 'tab-A', '/proj', 'user-1')).not.toThrow();
      // Give the fire-and-forget a tick to resolve without bubbling.
      await new Promise((r) => setTimeout(r, 20));
    });
  });
});
