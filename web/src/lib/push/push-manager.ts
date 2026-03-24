// Push notification manager — handles SW registration, permission, and subscription lifecycle

export interface PushStatus {
  supported: boolean;
  permission: NotificationPermission | 'unsupported';
  subscribed: boolean;
  error?: string;
}

/**
 * Convert a URL-safe base64 string to a Uint8Array for applicationServerKey.
 */
function urlBase64ToUint8Array(base64String: string): Uint8Array<ArrayBuffer> {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; i++) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

/**
 * Register the service worker from /sw.js.
 * Returns the registration, or null if unsupported.
 */
export async function registerServiceWorker(): Promise<ServiceWorkerRegistration | null> {
  if (!('serviceWorker' in navigator)) return null;

  try {
    const registration = await navigator.serviceWorker.register('/sw.js');
    return registration;
  } catch (err) {
    console.warn('[push] Service worker registration failed:', err);
    return null;
  }
}

/**
 * Request notification permission from the user.
 * Returns the resulting permission state.
 */
export async function requestNotificationPermission(): Promise<NotificationPermission> {
  if (!('Notification' in window)) return 'denied';
  return Notification.requestPermission();
}

/**
 * Subscribe to push notifications using the VAPID public key from the relay server.
 */
export async function subscribeToPush(
  registration: ServiceWorkerRegistration,
): Promise<PushSubscription | null> {
  try {
    // Check for existing subscription first
    const existing = await registration.pushManager.getSubscription();
    if (existing) return existing;

    // Fetch VAPID public key from relay
    const response = await fetch('/push/vapid-key', { credentials: 'include' });
    if (!response.ok) {
      console.warn('[push] Failed to fetch VAPID key:', response.status);
      return null;
    }

    const { publicKey } = (await response.json()) as { publicKey: string };
    if (!publicKey) {
      console.warn('[push] No VAPID public key returned from server');
      return null;
    }

    const applicationServerKey = urlBase64ToUint8Array(publicKey);
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey,
    });

    return subscription;
  } catch (err) {
    console.warn('[push] Push subscription failed:', err);
    return null;
  }
}

/**
 * Send the push subscription to the relay server so it can send us notifications.
 * Authenticates via session cookie (credentials: 'include').
 */
export async function sendSubscriptionToServer(
  subscription: PushSubscription,
): Promise<boolean> {
  try {
    const response = await fetch('/push/subscribe', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify(subscription.toJSON()),
    });
    return response.ok;
  } catch (err) {
    console.warn('[push] Failed to send subscription to server:', err);
    return false;
  }
}

/**
 * Unsubscribe from push notifications — both locally and on the server.
 */
export async function unsubscribeFromPush(
  subscription: PushSubscription,
): Promise<boolean> {
  try {
    // Notify server
    await fetch('/push/unsubscribe', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify(subscription.toJSON()),
    }).catch(() => {
      // Server might be down — still unsubscribe locally
    });

    // Unsubscribe locally
    return await subscription.unsubscribe();
  } catch (err) {
    console.warn('[push] Failed to unsubscribe:', err);
    return false;
  }
}

/**
 * Full initialization flow: register SW → check permission → subscribe → send to server.
 * Call this when the user explicitly enables notifications.
 */
export async function initPushNotifications(): Promise<PushStatus> {
  // Check support
  if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
    return { supported: false, permission: 'unsupported', subscribed: false };
  }

  // Register SW
  const registration = await registerServiceWorker();
  if (!registration) {
    return { supported: true, permission: Notification.permission, subscribed: false, error: 'Service worker registration failed' };
  }

  // Request permission
  const permission = await requestNotificationPermission();
  if (permission !== 'granted') {
    return { supported: true, permission, subscribed: false };
  }

  // Subscribe to push
  const subscription = await subscribeToPush(registration);
  if (!subscription) {
    return { supported: true, permission, subscribed: false, error: 'Push subscription failed' };
  }

  // Send to server
  const sent = await sendSubscriptionToServer(subscription);
  if (!sent) {
    return { supported: true, permission, subscribed: false, error: 'Failed to register with server' };
  }

  return { supported: true, permission, subscribed: true };
}

/**
 * Re-send the existing push subscription to the relay server.
 * Useful after WebSocket reconnect when the relay may have restarted.
 */
export async function resendPushSubscription(): Promise<void> {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) return;

  try {
    const registration = await navigator.serviceWorker.getRegistration();
    if (!registration) return;
    const subscription = await registration.pushManager.getSubscription();
    if (subscription) {
      await sendSubscriptionToServer(subscription);
    }
  } catch (err) {
    console.warn('[push] Failed to re-send push subscription:', err);
  }
}
