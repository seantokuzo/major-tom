// Relay-side runtime config — persists across restart in
// `~/.major-tom/relay-config.json`. Today only `defaultSpawnCwd` lives
// here; future fields (PTY input limit overrides, default permission
// mode, etc.) can layer on without changing the file shape since
// missing fields are treated as unset.
//
// Mutations come from the REST surface in `routes/relay-config.ts`
// (driven by iOS Settings → Developer → Default Working Directory and,
// later, Ground Control's config UI — closes QA-FIXES #19).
//
// Failure modes:
//   - Missing file → silent default (fresh-install, expected).
//   - Corrupt / bad schema → logged at WARN, ignored (treat as fresh).
//   - I/O failures on save → logged at WARN, NOT thrown. The in-memory
//     cache stays advanced; next save attempt will retry.

import { existsSync, statSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { logger } from '../utils/logger.js';

export interface RelayConfig {
  /**
   * Default cwd for new PTY spawns when there is no fresh per-tab
   * workingDir to honor. iOS Settings → Developer writes this; the env
   * var `MAJORTOM_DEFAULT_CWD` takes precedence at read time.
   *
   * Validated on save: must be a non-empty string, must exist, must be
   * a directory. Invalid values are rejected with `RelayConfigError`.
   */
  defaultSpawnCwd?: string;
}

export const DEFAULT_RELAY_CONFIG_FILE = join(
  homedir(),
  '.major-tom',
  'relay-config.json',
);

/**
 * Distinguishes user-input errors (`validation`) from disk-write failures
 * (`io`) so the REST layer can pick the right HTTP status. Validation
 * errors = 400; IO errors = 500. Without the kind, a misconfigured path
 * and an out-of-disk would look the same to the client.
 */
export class RelayConfigError extends Error {
  constructor(
    message: string,
    public readonly kind: 'validation' | 'io' = 'validation',
  ) {
    super(message);
    this.name = 'RelayConfigError';
  }
}

/**
 * In-process holder for the persisted relay config. Loads at app boot
 * and stays in memory; PATCH writes both update the cache and persist
 * to disk. Constructed once and shared across the resolver + REST route.
 */
export class RelayConfigStore {
  private cached: RelayConfig = {};

  constructor(private readonly path: string = DEFAULT_RELAY_CONFIG_FILE) {}

  /** Path the store reads/writes — exposed for tests + diagnostics. */
  get filePath(): string {
    return this.path;
  }

  /**
   * Read the config file once at startup. ENOENT is a silent noop —
   * fresh installs have no file. Corrupt / bad-schema files log at
   * WARN and reset the in-memory cache to empty.
   */
  async load(): Promise<RelayConfig> {
    let raw: string;
    try {
      raw = await readFile(this.path, 'utf-8');
    } catch (err) {
      const code = errnoCode(err);
      if (code !== 'ENOENT') {
        logger.warn({ err, path: this.path, code }, 'Relay config read failed');
      }
      this.cached = {};
      return this.cached;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch (err) {
      logger.warn({ err, path: this.path }, 'Relay config is invalid JSON — ignoring');
      this.cached = {};
      return this.cached;
    }
    if (!isRelayConfig(parsed)) {
      logger.warn({ path: this.path }, 'Relay config has invalid schema — ignoring');
      this.cached = {};
      return this.cached;
    }
    this.cached = parsed;
    return this.cached;
  }

  /** Snapshot of the current in-memory config. */
  get(): RelayConfig {
    return { ...this.cached };
  }

  /**
   * Persist a new config. Validation runs first — bad values throw
   * `RelayConfigError(kind='validation')` and never touch disk or the
   * in-memory cache. After a successful write, the cache advances so
   * memory always matches what is persisted. I/O failures throw
   * `RelayConfigError(kind='io')` so the REST route can return 500
   * instead of misleading the client into thinking the value persisted.
   */
  async save(next: RelayConfig): Promise<void> {
    if (next.defaultSpawnCwd !== undefined) {
      const v = next.defaultSpawnCwd;
      if (typeof v !== 'string') {
        throw new RelayConfigError('defaultSpawnCwd must be a string');
      }
      if (v.length === 0) {
        throw new RelayConfigError('defaultSpawnCwd must not be empty');
      }
      // Stat upfront so the user gets a clear rejection instead of the
      // failure showing up later as a silent fall-through inside
      // resolveDefaultSpawnCwd.
      try {
        if (!statSync(v).isDirectory()) {
          throw new RelayConfigError(`defaultSpawnCwd is not a directory: ${v}`);
        }
      } catch (err) {
        if (err instanceof RelayConfigError) throw err;
        throw new RelayConfigError(`defaultSpawnCwd does not exist: ${v}`);
      }
    }
    try {
      await mkdir(dirname(this.path), { recursive: true });
      await writeFile(this.path, JSON.stringify(next, null, 2), 'utf-8');
    } catch (err) {
      logger.warn(
        { err, path: this.path },
        'Relay config save failed — cache NOT advanced; client receives 500',
      );
      throw new RelayConfigError(
        `Failed to persist relay config: ${(err as Error).message}`,
        'io',
      );
    }
    // Disk holds the new value — safe to advance memory.
    this.cached = { ...next };
  }
}

/**
 * Resolve the cwd a fresh PTY should spawn into when no fresh per-tab
 * workingDir is available. Cascade order:
 *   1. `$MAJORTOM_DEFAULT_CWD` env var (must point at an existing dir)
 *   2. Persisted `defaultSpawnCwd` from the relay config file
 *   3. `$HOME/Documents/code/dev` if it exists
 *   4. `$HOME`
 *
 * Each non-final stop is path-validated; any miss falls through. We never
 * spawn into an empty / non-existent dir — node-pty would reject that.
 */
export function resolveDefaultSpawnCwd(
  store: RelayConfigStore,
  env: NodeJS.ProcessEnv = process.env,
): string {
  const fromEnv = env['MAJORTOM_DEFAULT_CWD'];
  if (fromEnv && isExistingDir(fromEnv)) return fromEnv;

  const fromFile = store.get().defaultSpawnCwd;
  if (fromFile && isExistingDir(fromFile)) return fromFile;

  const home = env['HOME'] ?? homedir();
  const devGuess = join(home, 'Documents', 'code', 'dev');
  if (isExistingDir(devGuess)) return devGuess;

  return home;
}

function isExistingDir(path: string): boolean {
  if (!path || path.length === 0) return false;
  try {
    return existsSync(path) && statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function isRelayConfig(v: unknown): v is RelayConfig {
  if (typeof v !== 'object' || v === null) return false;
  const o = v as Record<string, unknown>;
  if (
    o['defaultSpawnCwd'] !== undefined &&
    typeof o['defaultSpawnCwd'] !== 'string'
  ) return false;
  return true;
}

function errnoCode(err: unknown): string | undefined {
  if (typeof err === 'object' && err !== null && 'code' in err) {
    const code = (err as { code: unknown }).code;
    if (typeof code === 'string') return code;
  }
  return undefined;
}
