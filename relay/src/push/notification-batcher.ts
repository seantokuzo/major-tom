import { logger } from '../utils/logger.js';
import type { PushManager, NotificationPayload } from './push-manager.js';

// ── Types ────────────────────────────────────────────────────

interface PendingApproval {
  tool: string;
  requestId: string;
}

// ── Notification Batcher ─────────────────────────────────────
// Batches rapid-fire approval requests so we don't spam push
// notifications. If multiple requests arrive within the batch
// window, they're combined into a single notification.

const BATCH_WINDOW_MS = 2_000;

export class NotificationBatcher {
  private pushManager: PushManager;
  private pendingBatch: PendingApproval[] = [];
  private batchTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(pushManager: PushManager) {
    this.pushManager = pushManager;
  }

  /** Queue an approval request for batched notification */
  addApprovalRequest(tool: string, requestId: string): void {
    this.pendingBatch.push({ tool, requestId });

    // Start the batch timer on first request
    if (this.batchTimer === null) {
      this.batchTimer = setTimeout(() => {
        void this.flushBatch();
      }, BATCH_WINDOW_MS);
    }
  }

  /** Flush the current batch and send a notification */
  private async flushBatch(): Promise<void> {
    this.batchTimer = null;

    const batch = this.pendingBatch.splice(0);
    if (batch.length === 0) {
      return;
    }

    let payload: NotificationPayload;

    if (batch.length === 1) {
      const item = batch[0]!;
      payload = {
        type: 'approval',
        title: 'Major Tom',
        body: `\u{1F527} Tool approval needed: ${item.tool}`,
        data: { url: '/', requestId: item.requestId },
      };
    } else {
      payload = {
        type: 'approval',
        title: 'Major Tom',
        body: `\u{1F527} ${batch.length} tools waiting for approval`,
        data: { url: '/' },
      };
    }

    logger.info(
      { batchSize: batch.length, tools: batch.map((b) => b.tool) },
      'Sending batched push notification',
    );

    try {
      await this.pushManager.notifyAll(payload);
    } catch (err: unknown) {
      logger.error({ err }, 'Failed to send batched push notification');
    }
  }

  /** Cancel any pending batch timer (for cleanup) */
  dispose(): void {
    if (this.batchTimer !== null) {
      clearTimeout(this.batchTimer);
      this.batchTimer = null;
    }
    this.pendingBatch.length = 0;
  }
}
