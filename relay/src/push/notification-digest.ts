/**
 * Notification Digest — collects low-priority notifications and sends
 * periodic summary pushes instead of individual notifications.
 *
 * High and medium priority always fire immediately (via PushManager).
 * Low priority is collected and batched into a digest every N minutes.
 */

import { logger } from '../utils/logger.js';
import type { PushManager, NotificationPayload } from './push-manager.js';
import type { NotificationConfigManager } from './notification-config.js';
import type { PriorityLevel } from './priority-scorer.js';

// ── Types ────────────────────────────────────────────────────

export interface DigestItem {
  toolName: string;
  target: string;
  priority: PriorityLevel;
  timestamp: string;
  requestId: string;
}

// ── Notification Digest ─────────────────────────────────────

export class NotificationDigest {
  private pushManager: PushManager;
  private configManager: NotificationConfigManager;
  private digestItems: DigestItem[] = [];
  private digestTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(pushManager: PushManager, configManager: NotificationConfigManager) {
    this.pushManager = pushManager;
    this.configManager = configManager;
  }

  /**
   * Process an approval request notification. Depending on priority and config:
   * - High/medium: fire immediately (respecting quiet hours)
   * - Low: collect into digest
   */
  async processNotification(
    tool: string,
    target: string,
    priority: PriorityLevel,
    requestId: string,
  ): Promise<void> {
    const config = await this.configManager.getConfig();
    const shouldNotify = await this.configManager.shouldNotify(priority);

    if (!shouldNotify) {
      // Distinguish between below-threshold (drop entirely) and quiet-hours-suppressed (digest).
      // shouldNotify returns false for both cases. Check quiet hours to determine which:
      const isQuiet = await this.configManager.isQuietHours();
      if (isQuiet && config.digest.enabled) {
        // Quiet-hours suppressed — collect into digest for later
        this.addToDigest(tool, target, priority, requestId);
      }
      // Below-threshold items are dropped entirely (not digested)
      return;
    }

    // High and medium priority fire immediately
    if (priority === 'high' || priority === 'medium') {
      await this.fireImmediateNotification(tool, target, priority, requestId);
      return;
    }

    // Low priority: collect into digest if enabled, otherwise fire immediately
    if (config.digest.enabled) {
      this.addToDigest(tool, target, priority, requestId);
    } else {
      await this.fireImmediateNotification(tool, target, priority, requestId);
    }
  }

  /**
   * Get all items currently collected in the digest (for client expansion).
   */
  getDigestItems(): DigestItem[] {
    return [...this.digestItems];
  }

  /**
   * Flush the digest immediately (e.g., on shutdown).
   */
  async flushDigest(): Promise<void> {
    if (this.digestItems.length === 0) return;
    await this.sendDigestNotification();
  }

  /**
   * Clean up timers on shutdown.
   */
  dispose(): void {
    if (this.digestTimer !== null) {
      clearTimeout(this.digestTimer);
      this.digestTimer = null;
    }
    this.digestItems = [];
  }

  // ── Private helpers ──────────────────────────────────────

  private addToDigest(
    tool: string,
    target: string,
    priority: PriorityLevel,
    requestId: string,
  ): void {
    this.digestItems.push({
      toolName: tool,
      target,
      priority,
      timestamp: new Date().toISOString(),
      requestId,
    });

    logger.debug(
      { tool, priority, digestSize: this.digestItems.length },
      'Added to notification digest',
    );

    // Start digest timer if not already running
    if (this.digestTimer === null) {
      void this.startDigestTimer();
    }
  }

  private async startDigestTimer(): Promise<void> {
    const config = await this.configManager.getConfig();
    const intervalMs = config.digest.intervalMinutes * 60 * 1000;

    this.digestTimer = setTimeout(() => {
      this.digestTimer = null;
      void this.sendDigestNotification();
    }, intervalMs);

    logger.debug(
      { intervalMs, intervalMinutes: config.digest.intervalMinutes },
      'Digest timer started',
    );
  }

  private async sendDigestNotification(): Promise<void> {
    if (this.digestTimer !== null) {
      clearTimeout(this.digestTimer);
      this.digestTimer = null;
    }

    const items = this.digestItems.splice(0);
    if (items.length === 0) return;

    // Build summary body
    const toolCounts = new Map<string, number>();
    for (const item of items) {
      const key = item.toolName.toLowerCase();
      toolCounts.set(key, (toolCounts.get(key) ?? 0) + 1);
    }

    const summaryParts: string[] = [];
    for (const [tool, count] of toolCounts) {
      summaryParts.push(`${count} ${tool}${count > 1 ? 's' : ''}`);
    }

    const body = summaryParts.join(', ');

    const payload: NotificationPayload = {
      type: 'digest',
      title: `Major Tom — ${items.length} pending approval${items.length > 1 ? 's' : ''}`,
      body,
      data: {
        url: '/',
        digest: true,
        items: items.map((i) => ({
          toolName: i.toolName,
          target: i.target,
          priority: i.priority,
          timestamp: i.timestamp,
        })),
      },
    };

    logger.info(
      { itemCount: items.length, summary: body },
      'Sending digest notification',
    );

    try {
      await this.pushManager.notifyAll(payload);
    } catch (err: unknown) {
      logger.error({ err }, 'Failed to send digest notification');
    }
  }

  private async fireImmediateNotification(
    tool: string,
    target: string,
    priority: PriorityLevel,
    requestId: string,
  ): Promise<void> {
    const priorityLabel = priority === 'high' ? '🔴' : priority === 'medium' ? '🟡' : '🟢';

    const payload: NotificationPayload = {
      type: 'approval',
      title: 'Major Tom',
      body: `${priorityLabel} Tool approval needed: ${tool}`,
      data: {
        url: '/',
        requestId,
        priority,
        tool,
        target,
      },
    };

    logger.info(
      { tool, priority, requestId },
      'Sending immediate priority notification',
    );

    try {
      await this.pushManager.notifyAll(payload);
    } catch (err: unknown) {
      logger.error({ err }, 'Failed to send immediate notification');
    }
  }
}
