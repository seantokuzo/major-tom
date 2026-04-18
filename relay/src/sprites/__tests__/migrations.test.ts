/**
 * Tab-Keyed Offices — Wave 5 migration tests (Gate B).
 *
 * Covers `runSpriteMappingMigration` from `../migrations.ts`:
 *   - Sweeps legacy mapping files on first run, writes the sentinel,
 *     logs a single info line with the cleared count.
 *   - Idempotent: second run on the same dir is a no-op (files preserved,
 *     no log line, no side effects).
 *   - Fresh install (missing dir) is a silent no-op.
 *   - Empty dir still stamps the sentinel and logs `cleared 0`.
 *   - Per-file delete failure is logged but doesn't block the sweep or
 *     sentinel write.
 *   - Dotfiles (user-placed markers, including the sentinel itself) are
 *     preserved.
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { mkdtemp, rm, readdir, readFile, writeFile, stat, mkdir, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import {
  runSpriteMappingMigration,
  SPRITE_MIGRATION_SENTINEL,
  type MigrationFsOps,
} from '../migrations.js';
import { logger } from '../../utils/logger.js';

async function writeJson(dir: string, name: string, body: unknown): Promise<void> {
  await writeFile(join(dir, name), JSON.stringify(body), 'utf-8');
}

describe('runSpriteMappingMigration', () => {
  let baseDir: string;
  let infoSpy: ReturnType<typeof vi.spyOn>;
  let debugSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'sprite-migration-'));
    infoSpy = vi.spyOn(logger, 'info').mockImplementation(() => logger);
    debugSpy = vi.spyOn(logger, 'debug').mockImplementation(() => logger);
  });

  afterEach(async () => {
    infoSpy.mockRestore();
    debugSpy.mockRestore();
    await rm(baseDir, { recursive: true, force: true });
  });

  it('sweeps legacy files, writes the sentinel, and logs the cleared count', async () => {
    await writeJson(baseDir, 'sess-aaa.json', { version: 1, sessionId: 'sess-aaa' });
    await writeJson(baseDir, 'sess-bbb.json', { version: 1, sessionId: 'sess-bbb' });
    await writeJson(baseDir, 'sess-ccc.json', { version: 1, sessionId: 'sess-ccc' });

    await runSpriteMappingMigration({ baseDir });

    const remaining = await readdir(baseDir);
    expect(remaining).toEqual([SPRITE_MIGRATION_SENTINEL]);

    // Sentinel carries an ISO timestamp so operators can audit when the
    // migration ran.
    const stamp = await readFile(join(baseDir, SPRITE_MIGRATION_SENTINEL), 'utf-8');
    expect(stamp).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/);

    // Exactly one info log mentioning the 3-file count.
    expect(infoSpy).toHaveBeenCalledTimes(1);
    const [, msg] = infoSpy.mock.calls[0]!;
    expect(msg).toContain('cleared 3 legacy sprite mappings');
    expect(msg).toContain('Wave 5 migration');
  });

  it('is idempotent — second run preserves files and emits no info log', async () => {
    // First run stamps the sentinel.
    await runSpriteMappingMigration({ baseDir });
    expect(infoSpy).toHaveBeenCalledTimes(1);
    infoSpy.mockClear();
    debugSpy.mockClear();

    // Drop a "new" mapping file that belongs to the post-migration era.
    // This must survive the second run — the sentinel is the whole gate.
    await writeJson(baseDir, 'sess-new-era.json', { version: 1, sessionId: 'sess-new-era' });

    await runSpriteMappingMigration({ baseDir });

    const remaining = (await readdir(baseDir)).sort();
    expect(remaining).toEqual([SPRITE_MIGRATION_SENTINEL, 'sess-new-era.json'].sort());

    // No info log on the idempotent path. Debug-level only.
    expect(infoSpy).not.toHaveBeenCalled();
  });

  it('no-ops silently on a missing directory (fresh install)', async () => {
    const ghost = join(baseDir, 'never-created');
    await runSpriteMappingMigration({ baseDir: ghost });

    // Migration should not create the directory on its own.
    await expect(stat(ghost)).rejects.toMatchObject({ code: 'ENOENT' });
    expect(infoSpy).not.toHaveBeenCalled();
  });

  it('empty directory still stamps the sentinel and logs cleared 0', async () => {
    await runSpriteMappingMigration({ baseDir });

    const remaining = await readdir(baseDir);
    expect(remaining).toEqual([SPRITE_MIGRATION_SENTINEL]);
    expect(infoSpy).toHaveBeenCalledTimes(1);
    const [, msg] = infoSpy.mock.calls[0]!;
    expect(msg).toContain('cleared 0 legacy sprite mappings');
  });

  it('logs a warning and continues when a per-file delete fails', async () => {
    await writeJson(baseDir, 'good-1.json', { v: 1 });
    await writeJson(baseDir, 'corrupt.json', { v: 1 });
    await writeJson(baseDir, 'good-2.json', { v: 1 });

    const warnSpy = vi.spyOn(logger, 'warn').mockImplementation(() => logger);
    const realUnlink = unlink;
    const brokenUnlink: MigrationFsOps['unlink'] = async (path, ...rest) => {
      if (String(path).endsWith('corrupt.json')) {
        const err = Object.assign(new Error('EACCES'), { code: 'EACCES' });
        throw err;
      }
      return realUnlink(path, ...rest);
    };

    try {
      await runSpriteMappingMigration({
        baseDir,
        fs: { unlink: brokenUnlink },
      });

      // Sentinel still lands — one bad file does not block startup.
      const remaining = (await readdir(baseDir)).sort();
      expect(remaining).toContain(SPRITE_MIGRATION_SENTINEL);
      // Only the 2 good files got deleted; the corrupt one is still there.
      expect(remaining).toContain('corrupt.json');
      expect(remaining).not.toContain('good-1.json');
      expect(remaining).not.toContain('good-2.json');

      expect(warnSpy).toHaveBeenCalledTimes(1);
      expect(infoSpy).toHaveBeenCalledTimes(1);
      // The cleared count should reflect successful deletions only.
      const [, infoMsg] = infoSpy.mock.calls[0]!;
      expect(infoMsg).toContain('cleared 2 legacy sprite mappings');
    } finally {
      warnSpy.mockRestore();
    }
  });

  it('preserves dotfiles (operator markers + the sentinel itself) during sweep', async () => {
    await writeJson(baseDir, 'sess-x.json', { v: 1 });
    await writeFile(join(baseDir, '.keep-me'), 'operator marker', 'utf-8');

    await runSpriteMappingMigration({ baseDir });

    const remaining = (await readdir(baseDir)).sort();
    expect(remaining).toEqual(['.keep-me', SPRITE_MIGRATION_SENTINEL].sort());
  });

  it('exposes SPRITE_MIGRATION_SENTINEL as a stable filename', () => {
    // Guards against accidental rename — the whole migration gate depends
    // on this exact dotfile name.
    expect(SPRITE_MIGRATION_SENTINEL).toBe('.migrated-v4');
  });
});

describe('runSpriteMappingMigration — FS injection surface', () => {
  it('accepts partial fs overrides and falls back to real node:fs ops', async () => {
    // Smoke test that MigrationFsOps is honored — the broken-unlink test
    // above exercises the positive path; this asserts the type surface
    // compiles with a stubbed subset (stat-only here).
    const baseDir = await mkdtemp(join(tmpdir(), 'sprite-migration-fs-'));
    try {
      const statCalls: string[] = [];
      const wrappedStat: MigrationFsOps['stat'] = async (p, ...rest) => {
        statCalls.push(String(p));
        return stat(p, ...rest);
      };
      await runSpriteMappingMigration({
        baseDir,
        fs: { stat: wrappedStat },
      });
      // stat should have been hit at least twice: baseDir + sentinel probe.
      expect(statCalls.length).toBeGreaterThanOrEqual(2);
    } finally {
      await rm(baseDir, { recursive: true, force: true });
    }
  });
});

// Ensure `mkdir` re-export compiles (unused-import guard).
void mkdir;
