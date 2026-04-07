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
        // Phase 13 Wave 2 — `tag` lets the SW dedup notifications across
        // devices: when one device resolves the approval, every other
        // device's SW closes the matching notification by tag. Without
        // this, dismissed approvals would linger on lockscreens.
        data: { url: '/', requestId: item.requestId, tag: item.requestId },
      };
    } else {
      payload = {
        type: 'approval',
        title: 'Major Tom',
        body: `\u{1F527} ${batch.length} tools waiting for approval`,
        // For batches we tag with a sentinel so the SW knows it's a
        // batch grouping, not tied to a single requestId.
        data: { url: '/', tag: 'major-tom-approval-batch' },
      };
    }

    logger.info(
      { batchSize: batch.length, tools: batch.map((b) => b.tool) },
      'Sending batched push notification',
    );

    try {
      // urgency:'high' so APNS wakes the device immediately for approvals.
      // topic mirrors `tag` so push services replace the previous in-flight
      // approval push instead of stacking — only one approval card at a time.
      const topic =
        batch.length === 1
          ? `mt-approval-${batch[0]!.requestId}`
          : 'mt-approval-batch';
      await this.pushManager.notifyAll(payload, { urgency: 'high', topic });
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
