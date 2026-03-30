/**
 * Notification Config — manages quiet hours, priority threshold, and digest settings.
 *
 * Persists to ~/.major-tom/config.json. Safe for missing files, malformed JSON,
 * and concurrent access (uses atomic writes with rename).
 */

import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { randomUUID } from 'node:crypto';
import { logger } from '../utils/logger.js';
import type { PriorityLevel } from './priority-scorer.js';

// ── Types ────────────────────────────────────────────────────

export interface QuietHoursConfig {
  enabled: boolean;
  start: string; // "HH:MM" 24h format
  end: string;   // "HH:MM" 24h format
}

export interface DigestConfig {
  enabled: boolean;
  intervalMinutes: number;
}

export interface NotificationConfig {
  quietHours: QuietHoursConfig;
  priorityThreshold: PriorityLevel;
  digest: DigestConfig;
}

interface ConfigFile {
  notifications?: NotificationConfig;
  [key: string]: unknown;
}

// ── Constants ────────────────────────────────────────────────

const CONFIG_DIR = join(homedir(), '.major-tom');
const CONFIG_FILE = join(CONFIG_DIR, 'config.json');

const DEFAULT_CONFIG: NotificationConfig = {
  quietHours: {
    enabled: false,
    start: '22:00',
    end: '07:00',
  },
  priorityThreshold: 'low',
  digest: {
    enabled: true,
    intervalMinutes: 5,
  },
};

// ── Priority ordering ────────────────────────────────────────

const PRIORITY_ORDER: Record<PriorityLevel, number> = {
  high: 3,
  medium: 2,
  low: 1,
};

// ── NotificationConfigManager ────────────────────────────────

export class NotificationConfigManager {
  private cachedConfig: NotificationConfig | null = null;

  /**
   * Get the current notification config, reading from disk if not cached.
   */
  async getConfig(): Promise<NotificationConfig> {
    if (this.cachedConfig) {
      return { ...this.cachedConfig };
    }
    return this.loadFromDisk();
  }

  /**
   * Update notification config (partial merge), persist to disk.
   */
  async updateConfig(partial: Partial<NotificationConfig>): Promise<NotificationConfig> {
    const current = await this.getConfig();

    const updated: NotificationConfig = {
      quietHours: partial.quietHours
        ? { ...current.quietHours, ...partial.quietHours }
        : current.quietHours,
      priorityThreshold: partial.priorityThreshold ?? current.priorityThreshold,
      digest: partial.digest
        ? { ...current.digest, ...partial.digest }
        : current.digest,
    };

    // Validate
    this.validate(updated);

    // Persist
    await this.saveToDisk(updated);
    this.cachedConfig = updated;

    logger.info({ config: updated }, 'Notification config updated');
    return { ...updated };
  }

  /**
   * Check if we're currently in quiet hours.
   */
  async isQuietHours(): Promise<boolean> {
    const config = await this.getConfig();
    if (!config.quietHours.enabled) return false;

    const now = new Date();
    const currentMinutes = now.getHours() * 60 + now.getMinutes();
    const startMinutes = parseTimeToMinutes(config.quietHours.start);
    const endMinutes = parseTimeToMinutes(config.quietHours.end);

    // Handle overnight ranges (e.g., 22:00 - 07:00)
    if (startMinutes <= endMinutes) {
      // Same-day range (e.g., 09:00 - 17:00)
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      // Overnight range (e.g., 22:00 - 07:00)
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }

  /**
   * Check if a notification should fire based on priority, threshold, and quiet hours.
   *
   * Rules:
   * - High priority: always fires (even during quiet hours)
   * - Medium priority: fires if meets threshold, suppressed during quiet hours
   * - Low priority: fires only if threshold is 'low', suppressed during quiet hours
   */
  async shouldNotify(priority: PriorityLevel): Promise<boolean> {
    const config = await this.getConfig();

    // Check priority threshold
    if (PRIORITY_ORDER[priority] < PRIORITY_ORDER[config.priorityThreshold]) {
      return false;
    }

    // High priority always fires
    if (priority === 'high') {
      return true;
    }

    // Check quiet hours for medium and low
    const quiet = await this.isQuietHours();
    if (quiet) {
      return false;
    }

    return true;
  }

  /**
   * Invalidate cached config (for testing or external changes).
   */
  invalidateCache(): void {
    this.cachedConfig = null;
  }

  // ── Private helpers ──────────────────────────────────────

  private validate(config: NotificationConfig): void {
    // Validate time format
    if (!isValidTimeFormat(config.quietHours.start)) {
      throw new Error(`Invalid quiet hours start time: ${config.quietHours.start}`);
    }
    if (!isValidTimeFormat(config.quietHours.end)) {
      throw new Error(`Invalid quiet hours end time: ${config.quietHours.end}`);
    }

    // Validate priority threshold
    if (!['high', 'medium', 'low'].includes(config.priorityThreshold)) {
      throw new Error(`Invalid priority threshold: ${config.priorityThreshold}`);
    }

    // Validate digest interval
    if (config.digest.intervalMinutes < 1 || config.digest.intervalMinutes > 60) {
      throw new Error(`Invalid digest interval: ${config.digest.intervalMinutes} (must be 1-60)`);
    }
  }

  private async loadFromDisk(): Promise<NotificationConfig> {
    try {
      const data = await readFile(CONFIG_FILE, 'utf-8');
      const parsed = JSON.parse(data) as ConfigFile;

      if (parsed.notifications) {
        // Merge with defaults to handle partial configs from older versions
        const config: NotificationConfig = {
          quietHours: { ...DEFAULT_CONFIG.quietHours, ...parsed.notifications.quietHours },
          priorityThreshold: parsed.notifications.priorityThreshold ?? DEFAULT_CONFIG.priorityThreshold,
          digest: { ...DEFAULT_CONFIG.digest, ...parsed.notifications.digest },
        };

        // Validate merged config — fall back to defaults if corrupted
        try {
          this.validate(config);
        } catch (validationErr) {
          logger.warn({ validationErr }, 'Merged config failed validation — using defaults');
          this.cachedConfig = { ...DEFAULT_CONFIG };
          return { ...DEFAULT_CONFIG };
        }

        this.cachedConfig = config;
        logger.debug({ config }, 'Notification config loaded from disk');
        return { ...config };
      }
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code !== 'ENOENT') {
        logger.warn({ err }, 'Failed to read notification config — using defaults');
      }
    }

    // No config on disk — use defaults
    this.cachedConfig = { ...DEFAULT_CONFIG };
    return { ...DEFAULT_CONFIG };
  }

  private async saveToDisk(config: NotificationConfig): Promise<void> {
    await mkdir(CONFIG_DIR, { recursive: true });

    // Read existing config file to preserve other fields
    let existing: ConfigFile = {};
    try {
      const data = await readFile(CONFIG_FILE, 'utf-8');
      existing = JSON.parse(data) as ConfigFile;
    } catch {
      // File doesn't exist or is malformed — start fresh
    }

    existing.notifications = config;

    // Atomic write: write to temp file, then rename
    const tmpFile = join(CONFIG_DIR, `config.${randomUUID().slice(0, 8)}.tmp`);
    await writeFile(tmpFile, JSON.stringify(existing, null, 2), 'utf-8');
    await rename(tmpFile, CONFIG_FILE);

    logger.debug('Notification config saved to disk');
  }
}

// ── Utility functions ────────────────────────────────────────

function parseTimeToMinutes(time: string): number {
  const [hours, minutes] = time.split(':').map(Number);
  return (hours ?? 0) * 60 + (minutes ?? 0);
}

function isValidTimeFormat(time: string): boolean {
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(time);
}
