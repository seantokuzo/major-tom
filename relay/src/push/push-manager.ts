import webpush from 'web-push';
import { logger } from '../utils/logger.js';

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

// ── Push Manager ─────────────────────────────────────────────
// Manages VAPID keys and push subscriptions.
// Subscriptions are in-memory only — clients re-subscribe on reconnect.

export class PushManager {
  private subscriptions = new Map<string, PushSubscriptionData>();
  private vapidPublicKey: string;
  private vapidPrivateKey: string;
  private initialized = false;

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

  /** Returns the VAPID public key for clients to use when subscribing */
  getVapidPublicKey(): string {
    return this.vapidPublicKey;
  }

  /** Store a push subscription */
  subscribe(subscription: PushSubscriptionData): void {
    this.subscriptions.set(subscription.endpoint, subscription);
    logger.info(
      { endpoint: subscription.endpoint, total: this.subscriptions.size },
      'Push subscription added',
    );
  }

  /** Remove a push subscription by endpoint */
  unsubscribe(endpoint: string): boolean {
    const removed = this.subscriptions.delete(endpoint);
    if (removed) {
      logger.info({ endpoint, total: this.subscriptions.size }, 'Push subscription removed');
    }
    return removed;
  }

  /** Send a push notification to all stored subscriptions */
  async notifyAll(payload: NotificationPayload): Promise<void> {
    if (!this.initialized || this.subscriptions.size === 0) {
      return;
    }

    const payloadStr = JSON.stringify(payload);
    const expiredEndpoints: string[] = [];
    let successCount = 0;

    await Promise.allSettled(
      [...this.subscriptions.values()].map(async (sub) => {
        try {
          await webpush.sendNotification(
            {
              endpoint: sub.endpoint,
              keys: sub.keys,
            },
            payloadStr,
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

    // Clean up expired subscriptions
    for (const endpoint of expiredEndpoints) {
      this.subscriptions.delete(endpoint);
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
}
