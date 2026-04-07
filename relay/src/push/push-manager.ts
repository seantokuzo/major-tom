import webpush from 'web-push';
import { logger } from '../utils/logger.js';
import { PushPersistence } from './push-persistence.js';

// ── Types ────────────────────────────────────────────────────

export interface PushSubscriptionData {
  endpoint: string;
  keys: {
    p256dh: string;
    auth: string;
  };
}

export interface NotificationPayload {
  type: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

/**
 * Per-call options that map onto web-push's `RequestOptions` (the third
 * argument to `webpush.sendNotification`). Phase 13 Wave 2 uses
 * `urgency: 'high'` for approval prompts so iOS APNS doesn't coalesce
 * them with low-priority traffic, and `topic` so multiple in-flight
 * approvals replace each other on the lockscreen instead of stacking.
 *
 * `tag` is a SW-side dedup key that goes inside the payload data, NOT a
 * web-push field — included here for symmetry but actually applied via
 * `payload.data.tag` in the SW notification handler.
 */
export interface NotifyAllOptions {
  /** APNS / VAPID urgency. 'high' = wake immediately. */
  urgency?: 'very-low' | 'low' | 'normal' | 'high';
  /** Time-to-live in seconds. Push services drop the message after this. */
  TTL?: number;
  /** Push service "topic" header — replaces an outstanding push with same topic. */
  topic?: string;
}

// ── Push Manager ─────────────────────────────────────────────
// Manages VAPID keys and push subscriptions.
// Subscriptions are persisted to disk and restored on startup.

export class PushManager {
  private subscriptions = new Map<string, PushSubscriptionData>();
  private vapidPublicKey: string;
  private vapidPrivateKey: string;
  private initialized = false;
  private persistence = new PushPersistence();

  constructor() {
    const envPublic = process.env['VAPID_PUBLIC_KEY'];
    const envPrivate = process.env['VAPID_PRIVATE_KEY'];
    const envSubject = process.env['VAPID_SUBJECT'] ?? 'mailto:major-tom@example.com';

    if (envPublic && envPrivate) {
      this.vapidPublicKey = envPublic;
      this.vapidPrivateKey = envPrivate;
      logger.info('VAPID keys loaded from environment variables');
    } else {
      const keys = webpush.generateVAPIDKeys();
      this.vapidPublicKey = keys.publicKey;
      this.vapidPrivateKey = keys.privateKey;
      logger.warn(
        { publicKey: keys.publicKey },
        'VAPID keys auto-generated. Set these in your .env file (private key printed to stdout).',
      );
      console.log('\n  VAPID_PUBLIC_KEY=' + keys.publicKey);
      if (process.stdout.isTTY) {
        console.log(`\n  VAPID_PRIVATE_KEY=${keys.privateKey}\n`);
      } else {
        logger.warn('VAPID private key generated but not logged (non-interactive). Run relay interactively to see the key, or set VAPID_PRIVATE_KEY env var.');
      }
    }

    webpush.setVapidDetails(envSubject, this.vapidPublicKey, this.vapidPrivateKey);
    this.initialized = true;
    logger.info({ subscriptionCount: 0 }, 'PushManager initialized');
  }

  /** Load persisted subscriptions from disk. Call during startup.
   *  Clears stale subscriptions if the VAPID key changed since last save. */
  async restoreFromDisk(): Promise<void> {
    const restored = await this.persistence.load(this.vapidPublicKey);
    for (const sub of restored) {
      this.subscriptions.set(sub.endpoint, sub);
    }
    if (restored.length > 0) {
      logger.info(
        { count: restored.length },
        'Push subscriptions restored from disk',
      );
    }
  }

  /** Returns the VAPID public key for clients to use when subscribing */
  getVapidPublicKey(): string {
    return this.vapidPublicKey;
  }

  /**
   * Store a push subscription.
   * Dedup: if same endpoint re-subscribes, update keys rather than duplicate.
   */
  subscribe(subscription: PushSubscriptionData): void {
    const isUpdate = this.subscriptions.has(subscription.endpoint);
    this.subscriptions.set(subscription.endpoint, subscription);
    this.persistSubscriptions();

    logger.info(
      {
        endpoint: subscription.endpoint,
        total: this.subscriptions.size,
        updated: isUpdate,
      },
      isUpdate ? 'Push subscription updated (dedup)' : 'Push subscription added',
    );
  }

  /** Remove a push subscription by endpoint */
  unsubscribe(endpoint: string): boolean {
    const removed = this.subscriptions.delete(endpoint);
    if (removed) {
      this.persistSubscriptions();
      logger.info({ endpoint, total: this.subscriptions.size }, 'Push subscription removed');
    }
    return removed;
  }

  /**
   * Send a push notification to all stored subscriptions.
   *
   * The optional `options` arg threads through to web-push's third
   * `RequestOptions` parameter — used by Phase 13 Wave 2 to send
   * approval requests with `urgency: 'high'` so they don't get
   * coalesced into a low-priority drip on iOS. Existing callers that
   * don't pass options keep their previous default behavior.
   */
  async notifyAll(payload: NotificationPayload, options?: NotifyAllOptions): Promise<void> {
    if (!this.initialized || this.subscriptions.size === 0) {
      return;
    }

    const payloadStr = JSON.stringify(payload);
    const expiredEndpoints: string[] = [];
    let successCount = 0;

    // Build the web-push RequestOptions only if any options were passed.
    // Avoids sending an empty object that could trigger a header on
    // services that interpret an empty Topic field as a real topic.
    const requestOptions: Record<string, unknown> | undefined =
      options && (options.urgency || options.TTL !== undefined || options.topic)
        ? {
            ...(options.urgency && { urgency: options.urgency }),
            ...(options.TTL !== undefined && { TTL: options.TTL }),
            ...(options.topic && { topic: options.topic }),
          }
        : undefined;

    await Promise.allSettled(
      [...this.subscriptions.values()].map(async (sub) => {
        try {
          await webpush.sendNotification(
            {
              endpoint: sub.endpoint,
              keys: sub.keys,
            },
            payloadStr,
            requestOptions as never,
          );
          successCount++;
        } catch (err: unknown) {
          const statusCode = (err as { statusCode?: number }).statusCode;
          if (statusCode === 410) {
            // 410 Gone — subscription expired, mark for removal
            expiredEndpoints.push(sub.endpoint);
            logger.info({ endpoint: sub.endpoint }, 'Push subscription expired (410 Gone), removing');
          } else {
            logger.error(
              { err, endpoint: sub.endpoint, statusCode },
              'Failed to send push notification',
            );
          }
        }
      }),
    );

    // Clean up expired subscriptions and persist if any were pruned
    if (expiredEndpoints.length > 0) {
      for (const endpoint of expiredEndpoints) {
        this.subscriptions.delete(endpoint);
      }
      this.persistSubscriptions();
    }

    logger.debug(
      { sent: successCount, expired: expiredEndpoints.length, total: this.subscriptions.size },
      'Push notification batch complete',
    );
  }

  /** Number of active subscriptions */
  get size(): number {
    return this.subscriptions.size;
  }

  /** Get all subscriptions as an array (for persistence) */
  private getSubscriptionsArray(): PushSubscriptionData[] {
    return [...this.subscriptions.values()];
  }

  /** Trigger a debounced save to disk (includes VAPID key for stale-sub detection) */
  private persistSubscriptions(): void {
    this.persistence.save(this.getSubscriptionsArray(), this.vapidPublicKey);
  }

  /** Flush pending writes and clean up (call on shutdown) */
  async dispose(): Promise<void> {
    await this.persistence.saveImmediate(this.getSubscriptionsArray(), this.vapidPublicKey);
    this.persistence.dispose();
  }
}
