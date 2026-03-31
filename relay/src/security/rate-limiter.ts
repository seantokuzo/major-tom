import type { UserRole } from '../users/types.js';

export interface RateLimitConfig {
  /** Prompts per minute */
  promptsPerMinute: number;
  /** Approvals per minute */
  approvalsPerMinute: number;
}

const DEFAULT_LIMITS: Record<UserRole, RateLimitConfig> = {
  admin: { promptsPerMinute: Infinity, approvalsPerMinute: Infinity },
  operator: { promptsPerMinute: 10, approvalsPerMinute: 30 },
  viewer: { promptsPerMinute: 0, approvalsPerMinute: 0 },
};

interface BucketState {
  count: number;
  windowStart: number;  // epoch ms
}

export class RateLimiter {
  private roleLimits = new Map<UserRole, RateLimitConfig>();
  private userOverrides = new Map<string, Partial<RateLimitConfig>>();
  private buckets = new Map<string, BucketState>();  // key: `${userId}:${action}`

  constructor() {
    // Initialize with defaults
    for (const [role, config] of Object.entries(DEFAULT_LIMITS)) {
      this.roleLimits.set(role as UserRole, { ...config });
    }
  }

  /** Set rate limit for a role */
  setRoleLimit(role: UserRole, config: Partial<RateLimitConfig>): void {
    const current = this.roleLimits.get(role) ?? { ...DEFAULT_LIMITS[role] };
    this.roleLimits.set(role, { ...current, ...config });
  }

  /** Set per-user override */
  setUserOverride(userId: string, config: Partial<RateLimitConfig>): void {
    this.userOverrides.set(userId, config);
  }

  /** Remove per-user override */
  clearUserOverride(userId: string): void {
    this.userOverrides.delete(userId);
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
    if (!isFinite(maxPerMinute)) return { allowed: true };

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
}
