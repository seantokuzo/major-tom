/**
 * Push Subscription Persistence — saves/loads push subscriptions to disk.
 *
 * Persists to ~/.major-tom/push-subscriptions.json, matching the data dir
 * pattern used by SessionPersistence (~/.major-tom/sessions/).
 *
 * Uses debounced writes to avoid thrashing disk on rapid subscribe/unsubscribe.
 */

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { logger } from '../utils/logger.js';
import type { PushSubscriptionData } from './push-manager.js';

// ── Types ────────────────────────────────────────────────────

interface PersistedSubscriptions {
  version: 1;
  updatedAt: string;
  subscriptions: PushSubscriptionData[];
}

// ── Constants ─────────��──────────────────────────────────────

const SUBSCRIPTIONS_FILE = join(homedir(), '.major-tom', 'push-subscriptions.json');
const DEBOUNCE_MS = 2000;

// ── Push Persistence ─────────────────────────────────────────

export class PushPersistence {
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;

  /** Load subscriptions from disk. Returns empty array if file doesn't exist. */
  async load(): Promise<PushSubscriptionData[]> {
    try {
      const data = await readFile(SUBSCRIPTIONS_FILE, 'utf-8');
      const parsed = JSON.parse(data) as PersistedSubscriptions;

      // Validate structure
      if (!parsed.subscriptions || !Array.isArray(parsed.subscriptions)) {
        logger.warn('Push subscriptions file has invalid format, returning empty');
        return [];
      }

      // Filter out entries with missing required fields
      const valid = parsed.subscriptions.filter(
        (sub) => sub.endpoint && sub.keys?.p256dh && sub.keys?.auth,
      );

      logger.info(
        { count: valid.length, total: parsed.subscriptions.length },
        'Push subscriptions loaded from disk',
      );
      return valid;
    } catch (err: unknown) {
      // ENOENT is expected on first run — not an error
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
        logger.debug('No push subscriptions file found (first run)');
        return [];
      }
      logger.error({ err }, 'Failed to load push subscriptions from disk');
      return [];
    }
  }

  /** Debounced save — waits DEBOUNCE_MS after last call before writing */
  save(subscriptions: PushSubscriptionData[]): void {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }

    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null;
      void this.writeToDisk(subscriptions);
    }, DEBOUNCE_MS);
  }

  /** Immediate save — bypasses debounce (for shutdown) */
  async saveImmediate(subscriptions: PushSubscriptionData[]): Promise<void> {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    await this.writeToDisk(subscriptions);
  }

  private async writeToDisk(subscriptions: PushSubscriptionData[]): Promise<void> {
    try {
      await mkdir(dirname(SUBSCRIPTIONS_FILE), { recursive: true });

      const persisted: PersistedSubscriptions = {
        version: 1,
        updatedAt: new Date().toISOString(),
        subscriptions,
      };

      await writeFile(SUBSCRIPTIONS_FILE, JSON.stringify(persisted, null, 2), 'utf-8');
      logger.debug(
        { count: subscriptions.length },
        'Push subscriptions persisted to disk',
      );
    } catch (err) {
      logger.error({ err }, 'Failed to persist push subscriptions');
    }
  }

  /** Cancel any pending debounced write */
  dispose(): void {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
  }
}
