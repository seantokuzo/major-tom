import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
import type { UserRole } from '../users/types.js';
import { logger } from '../utils/logger.js';

export interface RateLimitConfig {
  /** Prompts per minute */
  promptsPerMinute: number;
  /** Approvals per minute */
  approvalsPerMinute: number;
}

/** Use -1 to represent "unlimited" — survives JSON serialization unlike Infinity */
const UNLIMITED = -1;

const DEFAULT_LIMITS: Record<UserRole, RateLimitConfig> = {
  admin: { promptsPerMinute: UNLIMITED, approvalsPerMinute: UNLIMITED },
  operator: { promptsPerMinute: 10, approvalsPerMinute: 30 },
  viewer: { promptsPerMinute: 0, approvalsPerMinute: 0 },
};

interface BucketState {
  count: number;
  windowStart: number;  // epoch ms
}

const VALID_ROLES = new Set<string>(['admin', 'operator', 'viewer']);
const CONFIG_DIR = join(homedir(), '.major-tom');
const CONFIG_FILE = join(CONFIG_DIR, 'config.json');
const DEBOUNCE_MS = 2000;

export class RateLimiter {
  private roleLimits = new Map<UserRole, RateLimitConfig>();
  private userOverrides = new Map<string, Partial<RateLimitConfig>>();
  private buckets = new Map<string, BucketState>();  // key: `${userId}:${action}`
  private saveTimer: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    // Initialize with defaults
    for (const [role, config] of Object.entries(DEFAULT_LIMITS)) {
      this.roleLimits.set(role as UserRole, { ...config });
    }
  }

  /** Check if a string is a valid UserRole */
  static isValidRole(role: string): role is UserRole {
    return VALID_ROLES.has(role);
  }

  /** Set rate limit for a role */
  setRoleLimit(role: UserRole, config: Partial<RateLimitConfig>): void {
    const current = this.roleLimits.get(role) ?? { ...DEFAULT_LIMITS[role] };
    this.roleLimits.set(role, { ...current, ...config });
    this.scheduleSave();
  }

  /** Set per-user override */
  setUserOverride(userId: string, config: Partial<RateLimitConfig>): void {
    this.userOverrides.set(userId, config);
    this.scheduleSave();
  }

  /** Remove per-user override */
  clearUserOverride(userId: string): void {
    this.userOverrides.delete(userId);
    this.scheduleSave();
  }

  /** Get effective limits for a user (user override > role default) */
  getEffectiveLimits(userId: string, role: UserRole): RateLimitConfig {
    const roleConfig = this.roleLimits.get(role) ?? DEFAULT_LIMITS[role];
    const userOverride = this.userOverrides.get(userId);
    if (!userOverride) return roleConfig;
    return {
      promptsPerMinute: userOverride.promptsPerMinute ?? roleConfig.promptsPerMinute,
      approvalsPerMinute: userOverride.approvalsPerMinute ?? roleConfig.approvalsPerMinute,
    };
  }

  /** Get role defaults */
  getRoleLimits(): Record<string, RateLimitConfig> {
    const result: Record<string, RateLimitConfig> = {};
    for (const [role, config] of this.roleLimits) {
      result[role] = { ...config };
    }
    return result;
  }

  /** Get all user overrides */
  getUserOverrides(): Record<string, Partial<RateLimitConfig>> {
    const result: Record<string, Partial<RateLimitConfig>> = {};
    for (const [userId, config] of this.userOverrides) {
      result[userId] = { ...config };
    }
    return result;
  }

  /**
   * Check if an action is allowed under rate limits.
   * Returns { allowed: true } or { allowed: false, retryAfter: seconds }.
   */
  check(userId: string, role: UserRole, action: 'prompt' | 'approval'): { allowed: true } | { allowed: false; retryAfter: number } {
    const limits = this.getEffectiveLimits(userId, role);
    const maxPerMinute = action === 'prompt' ? limits.promptsPerMinute : limits.approvalsPerMinute;

    if (maxPerMinute === 0) return { allowed: false, retryAfter: 60 };
    if (maxPerMinute < 0) return { allowed: true }; // -1 = unlimited

    const key = `${userId}:${action}`;
    const now = Date.now();
    const windowMs = 60_000; // 1 minute window

    let bucket = this.buckets.get(key);
    if (!bucket || now - bucket.windowStart >= windowMs) {
      // New window
      bucket = { count: 0, windowStart: now };
      this.buckets.set(key, bucket);
    }

    if (bucket.count >= maxPerMinute) {
      const retryAfter = Math.ceil((bucket.windowStart + windowMs - now) / 1000);
      return { allowed: false, retryAfter: Math.max(1, retryAfter) };
    }

    bucket.count++;
    return { allowed: true };
  }

  /** Serialize config for persistence/API */
  toJSON(): { roles: Record<string, RateLimitConfig>; userOverrides: Record<string, Partial<RateLimitConfig>> } {
    return {
      roles: this.getRoleLimits(),
      userOverrides: this.getUserOverrides(),
    };
  }

  /** Restore from config */
  fromJSON(data: { roles?: Record<string, RateLimitConfig>; userOverrides?: Record<string, Partial<RateLimitConfig>> }): void {
    if (data.roles) {
      for (const [role, config] of Object.entries(data.roles)) {
        this.roleLimits.set(role as UserRole, config);
      }
    }
    if (data.userOverrides) {
      for (const [userId, config] of Object.entries(data.userOverrides)) {
        this.userOverrides.set(userId, config);
      }
    }
  }

  /** Schedule a debounced save to disk */
  private scheduleSave(): void {
    if (this.saveTimer) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      void this.flush();
    }, DEBOUNCE_MS);
  }

  /** Flush rate limit config to disk */
  async flush(): Promise<void> {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
      this.saveTimer = null;
    }
    try {
      await mkdir(CONFIG_DIR, { recursive: true });
      let existing: Record<string, unknown> = {};
      try {
        const raw = await readFile(CONFIG_FILE, 'utf-8');
        existing = JSON.parse(raw) as Record<string, unknown>;
      } catch { /* file doesn't exist yet */ }
      existing['rateLimits'] = this.toJSON();
      await writeFile(CONFIG_FILE, JSON.stringify(existing, null, 2), 'utf-8');
      logger.debug('Rate limit config saved to disk');
    } catch (err) {
      logger.error({ err }, 'Failed to save rate limit config');
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
