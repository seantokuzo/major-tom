/**
 * SandboxGuard — enforces per-user directory access restrictions.
 *
 * When multi-user mode is active, each non-admin user can be restricted
 * to specific directories. Admins with no explicit restrictions have
 * unrestricted access. Non-admins with no configured paths are denied.
 *
 * State is persisted to ~/.major-tom/sandbox-config.json with debounced writes.
 */
import { resolve, relative, sep } from 'node:path';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { realpath } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { logger } from '../utils/logger.js';
import type { UserRole } from '../users/types.js';

const CONFIG_DIR = join(homedir(), '.major-tom');
const CONFIG_FILE = join(CONFIG_DIR, 'sandbox-config.json');
const DEBOUNCE_MS = 2000;

export interface SandboxConfig {
  /** Per-user allowed paths — empty array means unrestricted (admin default) */
  allowedPaths: Map<string, string[]>;
}

export class SandboxGuard {
  private allowedPaths = new Map<string, string[]>();
  private saveTimer: ReturnType<typeof setTimeout> | null = null;

  /** Set allowed paths for a user */
  setUserPaths(userId: string, paths: string[]): void {
    this.allowedPaths.set(userId, paths);
    this.scheduleSave();
  }

  /** Get allowed paths for a user */
  getUserPaths(userId: string): string[] {
    return this.allowedPaths.get(userId) ?? [];
  }

  /** Remove all path restrictions for a user */
  clearUserPaths(userId: string): void {
    this.allowedPaths.delete(userId);
    this.scheduleSave();
  }

  /**
   * Check if a user can access a given path.
   * Admin users with empty allowedPaths = unrestricted.
   * Returns true if the path is within any of the user's allowed paths.
   */
  async canAccess(userId: string, role: UserRole, targetPath: string): Promise<boolean> {
    // Admins with no restrictions have full access
    const paths = this.allowedPaths.get(userId);
    if (!paths || paths.length === 0) {
      if (role === 'admin') return true;
      // Non-admins with no paths configured = no access
      return false;
    }

    // Resolve real path (follow symlinks)
    let realTarget: string;
    try {
      realTarget = await realpath(resolve(targetPath));
    } catch {
      // Path doesn't exist — check parent directory
      const parent = resolve(targetPath, '..');
      try {
        realTarget = await realpath(parent);
      } catch {
        return false;
      }
    }

    // Check if target is within any allowed path
    for (const allowedPath of paths) {
      let realAllowed: string;
      try {
        realAllowed = await realpath(resolve(allowedPath));
      } catch {
        continue; // Skip paths that don't exist
      }
      const rel = relative(realAllowed, realTarget);
      const isWithin =
        rel === '' || (rel !== '..' && !rel.startsWith('..' + sep));
      if (isWithin) {
        return true;
      }
    }
    return false;
  }

  /**
   * Filter a directory listing to only show entries the user can see.
   * For directories outside the user's scope: only show structural paths
   * that lead to allowed directories (ancestor directories shown as structural-only).
   */
  async filterEntries(
    userId: string,
    role: UserRole,
    dirPath: string,
    entries: Array<{ name: string; isDirectory: boolean }>
  ): Promise<Array<{ name: string; isDirectory: boolean; restricted?: boolean }>> {
    const paths = this.allowedPaths.get(userId);
    if (!paths || paths.length === 0) {
      if (role === 'admin') return entries;
      return []; // Non-admins with no paths = see nothing
    }

    const result: Array<{ name: string; isDirectory: boolean; restricted?: boolean }> = [];
    for (const entry of entries) {
      const fullPath = resolve(dirPath, entry.name);
      if (await this.canAccess(userId, role, fullPath)) {
        result.push(entry);
      } else if (entry.isDirectory && await this.isAncestorOfAllowed(fullPath, paths)) {
        // Show structural directory (leads to an allowed path) but mark as restricted
        result.push({ ...entry, restricted: true });
      }
    }
    return result;
  }

  /**
   * Check if a directory is an ancestor of any allowed path.
   * Used to show structural directories in filtered tree views.
   */
  private async isAncestorOfAllowed(dirPath: string, allowedPaths: string[]): Promise<boolean> {
    let realDir: string;
    try {
      realDir = await realpath(resolve(dirPath));
    } catch {
      return false;
    }
    for (const allowed of allowedPaths) {
      let realAllowed: string;
      try {
        realAllowed = await realpath(resolve(allowed));
      } catch {
        continue;
      }
      const rel = relative(realDir, realAllowed);
      if (rel === '' || (rel !== '..' && !rel.startsWith('..' + sep))) {
        return true;
      }
    }
    return false;
  }

  /**
   * Get the deepest common ancestor of a user's allowed paths.
   * Useful for determining the effective root for a user.
   */
  getAllowedRoot(userId: string): string | null {
    const paths = this.allowedPaths.get(userId);
    if (!paths || paths.length === 0) return null;
    if (paths.length === 1) return paths[0]!;

    const segments = paths.map(p => resolve(p).split(sep));
    const minLen = Math.min(...segments.map(s => s.length));
    const common: string[] = [];
    for (let i = 0; i < minLen; i++) {
      if (segments.every(s => s[i] === segments[0]![i])) {
        common.push(segments[0]![i]!);
      } else {
        break;
      }
    }
    return common.join(sep) || sep;
  }

  /** Serialize state for persistence */
  toJSON(): Record<string, string[]> {
    const result: Record<string, string[]> = {};
    for (const [userId, paths] of this.allowedPaths) {
      result[userId] = paths;
    }
    return result;
  }

  /** Restore from persisted state */
  fromJSON(data: Record<string, string[]>): void {
    this.allowedPaths.clear();
    for (const [userId, paths] of Object.entries(data)) {
      this.allowedPaths.set(userId, paths);
    }
  }

  /** Load config from disk */
  async load(): Promise<void> {
    try {
      const data = await readFile(CONFIG_FILE, 'utf-8');
      this.fromJSON(JSON.parse(data) as Record<string, string[]>);
      logger.info({ userCount: this.allowedPaths.size }, 'SandboxGuard config loaded');
    } catch {
      // No config yet — start empty
      logger.debug('No sandbox config found, starting with empty restrictions');
    }
  }

  /** Schedule a debounced save */
  private scheduleSave(): void {
    if (this.saveTimer) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      void this.flush();
    }, DEBOUNCE_MS);
  }

  /** Flush pending writes to disk immediately */
  async flush(): Promise<void> {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
      this.saveTimer = null;
    }
    try {
      await mkdir(CONFIG_DIR, { recursive: true });
      await writeFile(CONFIG_FILE, JSON.stringify(this.toJSON(), null, 2), 'utf-8');
      logger.debug('SandboxGuard config saved');
    } catch (err) {
      logger.error({ err }, 'Failed to save SandboxGuard config');
    }
  }

  /** Cancel pending writes */
  dispose(): void {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
      this.saveTimer = null;
    }
  }
}
