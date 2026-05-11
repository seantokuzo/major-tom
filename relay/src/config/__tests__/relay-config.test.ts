import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, mkdir, rm, readFile, writeFile } from 'node:fs/promises';
import { tmpdir, homedir } from 'node:os';
import { join } from 'node:path';

import {
  RelayConfigStore,
  RelayConfigError,
  resolveDefaultSpawnCwd,
} from '../relay-config.js';

describe('RelayConfigStore', () => {
  let baseDir: string;
  let configFile: string;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'relay-config-'));
    configFile = join(baseDir, 'relay-config.json');
  });

  afterEach(async () => {
    await rm(baseDir, { recursive: true, force: true });
  });

  describe('load', () => {
    it('returns empty config when file is missing (fresh install)', async () => {
      const store = new RelayConfigStore(configFile);
      const cfg = await store.load();
      expect(cfg).toEqual({});
    });

    it('reads a valid config from disk', async () => {
      await writeFile(
        configFile,
        JSON.stringify({ defaultSpawnCwd: '/some/path' }),
        'utf-8',
      );
      const store = new RelayConfigStore(configFile);
      const cfg = await store.load();
      expect(cfg.defaultSpawnCwd).toBe('/some/path');
    });

    it('treats invalid JSON as empty', async () => {
      await writeFile(configFile, 'not json', 'utf-8');
      const store = new RelayConfigStore(configFile);
      const cfg = await store.load();
      expect(cfg).toEqual({});
    });

    it('treats invalid schema as empty', async () => {
      await writeFile(
        configFile,
        JSON.stringify({ defaultSpawnCwd: 12345 }),
        'utf-8',
      );
      const store = new RelayConfigStore(configFile);
      const cfg = await store.load();
      expect(cfg).toEqual({});
    });

    it('accepts a config with no defaultSpawnCwd field set', async () => {
      await writeFile(configFile, JSON.stringify({}), 'utf-8');
      const store = new RelayConfigStore(configFile);
      const cfg = await store.load();
      expect(cfg).toEqual({});
    });
  });

  describe('save', () => {
    it('persists defaultSpawnCwd and reads it back', async () => {
      const store = new RelayConfigStore(configFile);
      await store.save({ defaultSpawnCwd: baseDir });

      const fresh = new RelayConfigStore(configFile);
      const loaded = await fresh.load();
      expect(loaded.defaultSpawnCwd).toBe(baseDir);
    });

    it('updates the in-memory cache so resolveDefaultSpawnCwd sees the new value immediately', async () => {
      const store = new RelayConfigStore(configFile);
      await store.load();
      expect(store.get().defaultSpawnCwd).toBeUndefined();

      await store.save({ defaultSpawnCwd: baseDir });
      expect(store.get().defaultSpawnCwd).toBe(baseDir);
    });

    it('creates the parent directory if missing', async () => {
      const nested = join(baseDir, 'a', 'b', 'relay-config.json');
      const store = new RelayConfigStore(nested);
      await store.save({ defaultSpawnCwd: baseDir });
      // If it threw, this line never runs. Re-read to confirm round-trip.
      const fresh = new RelayConfigStore(nested);
      const loaded = await fresh.load();
      expect(loaded.defaultSpawnCwd).toBe(baseDir);
    });

    it('rejects empty defaultSpawnCwd before writing', async () => {
      const store = new RelayConfigStore(configFile);
      await expect(store.save({ defaultSpawnCwd: '' })).rejects.toBeInstanceOf(
        RelayConfigError,
      );
    });

    it('rejects defaultSpawnCwd that does not exist', async () => {
      const store = new RelayConfigStore(configFile);
      await expect(
        store.save({ defaultSpawnCwd: '/nonexistent/major-tom/test' }),
      ).rejects.toBeInstanceOf(RelayConfigError);
    });

    it('rejects defaultSpawnCwd that points at a file', async () => {
      const filePath = join(baseDir, 'not-a-dir.txt');
      await writeFile(filePath, 'hi', 'utf-8');
      const store = new RelayConfigStore(configFile);
      await expect(
        store.save({ defaultSpawnCwd: filePath }),
      ).rejects.toBeInstanceOf(RelayConfigError);
    });

    it('does not persist when validation fails', async () => {
      const store = new RelayConfigStore(configFile);
      await store.load();
      try {
        await store.save({ defaultSpawnCwd: '/missing' });
      } catch {
        // expected
      }
      expect(store.get().defaultSpawnCwd).toBeUndefined();
      // File never written either.
      const fresh = new RelayConfigStore(configFile);
      const loaded = await fresh.load();
      expect(loaded.defaultSpawnCwd).toBeUndefined();
    });

    it('throws RelayConfigError(kind=io) and rolls back the cache when writeFile fails', async () => {
      // Path inside a file (not a directory) — `mkdir` succeeds because
      // `recursive: true` is a no-op when the path exists, but writing a
      // file at `<existing-file>/relay-config.json` rejects with ENOTDIR.
      // This forces the IO failure branch.
      const filePath = join(baseDir, 'sentinel.txt');
      await writeFile(filePath, 'hi', 'utf-8');
      const blockedPath = join(filePath, 'relay-config.json');
      const store = new RelayConfigStore(blockedPath);
      // Seed memory with a known prior value via a separate, working store.
      store['cached'] = { defaultSpawnCwd: '/old' };

      await expect(
        store.save({ defaultSpawnCwd: baseDir }),
      ).rejects.toMatchObject({
        name: 'RelayConfigError',
        kind: 'io',
      });
      // Cache must NOT have advanced — otherwise PATCH would silently
      // claim the value persisted while disk has the old one.
      expect(store.get().defaultSpawnCwd).toBe('/old');
    });

    it('rejects validation errors with kind=validation', async () => {
      const store = new RelayConfigStore(configFile);
      try {
        await store.save({ defaultSpawnCwd: '' });
        expect.unreachable('should have thrown');
      } catch (err) {
        expect(err).toMatchObject({
          name: 'RelayConfigError',
          kind: 'validation',
        });
      }
    });
  });
});

describe('resolveDefaultSpawnCwd', () => {
  let baseDir: string;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'relay-resolve-'));
  });

  afterEach(async () => {
    await rm(baseDir, { recursive: true, force: true });
  });

  it('returns $MAJORTOM_DEFAULT_CWD when it points to an existing dir', () => {
    const store = new RelayConfigStore(join(baseDir, 'cfg.json'));
    const path = resolveDefaultSpawnCwd(store, {
      MAJORTOM_DEFAULT_CWD: baseDir,
      HOME: '/should-not-reach',
    } as NodeJS.ProcessEnv);
    expect(path).toBe(baseDir);
  });

  it('falls through env var when the path is missing', async () => {
    const store = new RelayConfigStore(join(baseDir, 'cfg.json'));
    await store.save({ defaultSpawnCwd: baseDir });
    const path = resolveDefaultSpawnCwd(store, {
      MAJORTOM_DEFAULT_CWD: '/nonexistent/major-tom/test',
      HOME: '/should-not-reach',
    } as NodeJS.ProcessEnv);
    expect(path).toBe(baseDir);
  });

  it('returns persisted defaultSpawnCwd when the env var is unset', async () => {
    const store = new RelayConfigStore(join(baseDir, 'cfg.json'));
    await store.save({ defaultSpawnCwd: baseDir });
    const path = resolveDefaultSpawnCwd(store, {
      HOME: '/should-not-reach',
    } as NodeJS.ProcessEnv);
    expect(path).toBe(baseDir);
  });

  it('falls back to $HOME/Documents/code/dev when present', async () => {
    const fakeHome = join(baseDir, 'home');
    const devDir = join(fakeHome, 'Documents', 'code', 'dev');
    await mkdir(devDir, { recursive: true });
    const store = new RelayConfigStore(join(baseDir, 'cfg.json'));
    const path = resolveDefaultSpawnCwd(store, {
      HOME: fakeHome,
    } as NodeJS.ProcessEnv);
    expect(path).toBe(devDir);
  });

  it('falls back to $HOME when nothing else resolves', async () => {
    const fakeHome = join(baseDir, 'lonely-home');
    await mkdir(fakeHome, { recursive: true });
    const store = new RelayConfigStore(join(baseDir, 'cfg.json'));
    const path = resolveDefaultSpawnCwd(store, {
      HOME: fakeHome,
    } as NodeJS.ProcessEnv);
    expect(path).toBe(fakeHome);
  });

  it('falls back to homedir() when env.HOME is unset', () => {
    const store = new RelayConfigStore(join(baseDir, 'cfg.json'));
    const path = resolveDefaultSpawnCwd(store, {} as NodeJS.ProcessEnv);
    // We can't assert an exact value without mocking homedir, but we can
    // assert the resolver returns a non-empty string and doesn't throw.
    expect(typeof path).toBe('string');
    expect(path.length).toBeGreaterThan(0);
    // Should at minimum be the OS homedir or a real path; sanity-check by
    // matching the actual homedir for the test runner.
    expect(path === homedir() || path.startsWith(homedir())).toBe(true);
  });
});
