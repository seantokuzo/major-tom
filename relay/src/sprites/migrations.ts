/**
 * Tab-Keyed Offices — Wave 5 one-shot migration (Gate B).
 *
 * Spec:
 *   - docs/PHASE-TAB-KEYED-OFFICES.md §9 Gate B: "Scrap existing sprite-mapping
 *     files on upgrade. One-time cleanup on relay boot."
 *   - docs/PHASE-TAB-KEYED-OFFICES.md §10 Wave 5 row: "Persistence migration
 *     cleanup."
 *
 * Behavior on relay boot:
 *   1. If the sprite-mappings directory does not exist → no-op. Fresh install.
 *   2. If the directory exists and contains the sentinel file
 *      `.migrated-v4` → no-op. Migration already ran on a previous boot.
 *   3. Otherwise, enumerate top-level entries, delete every file that is NOT
 *      a hidden dotfile (so user-placed markers are preserved), then write
 *      the sentinel with an ISO timestamp so subsequent boots skip.
 *
 * Guards:
 *   - Individual per-file delete failures are logged at WARN and SWALLOWED so
 *     one corrupt file cannot block relay startup.
 *   - If the directory read itself throws, the migration is logged at ERROR
 *     and skipped — we don't want a filesystem glitch to block boot either.
 *
 * The migration is DELIBERATELY not idempotent through re-deletion: once the
 * sentinel lands, mapping files written by the current relay version must
 * NOT be swept. The sentinel is the entire gate.
 *
 * Tests: `__tests__/migrations.test.ts`.
 */
import {
  readdir,
  stat,
  unlink,
  writeFile,
  mkdir,
} from 'node:fs/promises';
import { join } from 'node:path';
import { logger } from '../utils/logger.js';
import { DEFAULT_MAPPINGS_DIR } from './sprite-mapping-persistence.js';

/** Filename of the one-shot sentinel. Dotfile so future dotfile-skip guards cover it. */
export const SPRITE_MIGRATION_SENTINEL = '.migrated-v4';

/**
 * Filesystem operations used by the migration. Broken out so tests can
 * inject failures (ENOENT, EACCES, ENOSPC, ...) without touching the real
 * home directory.
 */
export interface MigrationFsOps {
  readdir: typeof readdir;
  stat: typeof stat;
  unlink: typeof unlink;
  writeFile: typeof writeFile;
  mkdir: typeof mkdir;
}

const DEFAULT_FS: MigrationFsOps = { readdir, stat, unlink, writeFile, mkdir };

export interface SpriteMappingMigrationOptions {
  /** Override the mapping directory. Defaults to the canonical path. */
  baseDir?: string;
  /** Override filesystem operations. Tests use this to simulate failures. */
  fs?: Partial<MigrationFsOps>;
}

/** Narrow a caught error to NodeJS.ErrnoException so we can read `.code`. */
function errnoCode(err: unknown): string | undefined {
  if (typeof err === 'object' && err !== null && 'code' in err) {
    const code = (err as { code: unknown }).code;
    if (typeof code === 'string') return code;
  }
  return undefined;
}

/**
 * Run the Wave 5 sprite-mapping migration.
 *
 * Resolves once the sentinel exists (or the migration is confirmed a no-op
 * because the directory doesn't). Never throws — callers should `await`
 * this during relay bootstrap and tolerate failure the same as any other
 * persistence-layer hiccup.
 */
export async function runSpriteMappingMigration(
  opts: SpriteMappingMigrationOptions = {},
): Promise<void> {
  const baseDir = opts.baseDir ?? DEFAULT_MAPPINGS_DIR;
  const fs: MigrationFsOps = { ...DEFAULT_FS, ...opts.fs };
  const sentinelPath = join(baseDir, SPRITE_MIGRATION_SENTINEL);

  // 1. Probe the base directory. On fresh install (ENOENT) we create the
  // directory and stamp the sentinel immediately — otherwise a later boot
  // would see dir-but-no-sentinel (once SpriteMappingPersistence writes its
  // first mapping) and wipe those new files as "legacy".
  let baseDirExisted = true;
  try {
    await fs.stat(baseDir);
  } catch (err) {
    const code = errnoCode(err);
    if (code === 'ENOENT') {
      baseDirExisted = false;
    } else {
      logger.error(
        { err, baseDir, code },
        'Sprite mapping migration: unable to stat directory — skipping',
      );
      return;
    }
  }

  if (!baseDirExisted) {
    try {
      await fs.mkdir(baseDir, { recursive: true });
      await fs.writeFile(sentinelPath, new Date().toISOString(), 'utf-8');
      logger.info(
        { baseDir },
        'Sprite mapping migration: fresh install — directory seeded, sentinel stamped',
      );
    } catch (err) {
      logger.error(
        { err, baseDir, code: errnoCode(err) },
        'Sprite mapping migration: failed to seed fresh-install sentinel — migration will re-run next boot',
      );
    }
    return;
  }

  // 2. Sentinel present — migration already ran. Skip silently (debug only).
  // A non-ENOENT stat failure (EACCES, EIO, ...) means the sentinel *might*
  // exist but we can't confirm. Fail closed: skip the sweep so a transient
  // filesystem glitch can't wipe post-migration mapping files.
  try {
    await fs.stat(sentinelPath);
    logger.debug(
      { baseDir },
      'Sprite mapping migration already complete (sentinel present)',
    );
    return;
  } catch (err) {
    const code = errnoCode(err);
    if (code !== 'ENOENT') {
      logger.warn(
        { err, baseDir, code },
        'Sprite mapping migration: could not stat sentinel — skipping sweep (fail-closed)',
      );
      return;
    }
  }

  // 3. Sweep legacy files.
  let entries: string[];
  try {
    entries = await fs.readdir(baseDir);
  } catch (err) {
    logger.error(
      { err, baseDir, code: errnoCode(err) },
      'Sprite mapping migration: readdir failed — skipping (will retry next boot)',
    );
    return;
  }

  let cleared = 0;
  for (const name of entries) {
    // Preserve dotfiles — includes the sentinel (about to be written) and any
    // future-proofing markers operators may drop into the directory.
    if (name.startsWith('.')) continue;
    const full = join(baseDir, name);
    try {
      await fs.unlink(full);
      cleared += 1;
    } catch (err) {
      logger.warn(
        { err, file: full, code: errnoCode(err) },
        'Sprite mapping migration: per-file delete failed — continuing',
      );
    }
  }

  // 4. Stamp the sentinel so subsequent boots skip.
  try {
    await fs.writeFile(sentinelPath, new Date().toISOString(), 'utf-8');
  } catch (err) {
    logger.error(
      { err, sentinelPath, code: errnoCode(err) },
      'Sprite mapping migration: failed to write sentinel — migration will re-run next boot',
    );
    return;
  }

  logger.info(
    { baseDir, cleared },
    `cleared ${cleared} legacy sprite mappings (Wave 5 migration)`,
  );
}
