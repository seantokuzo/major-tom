<script lang="ts">
  import { onMount } from 'svelte';
  import { initPushNotifications, unsubscribeFromPush } from '../push/push-manager';
  import { relay } from '../stores/relay.svelte';
  import { toasts } from '../stores/toast.svelte';

  let permission = $state<NotificationPermission | 'unsupported'>(
    typeof Notification !== 'undefined' ? Notification.permission : 'unsupported',
  );
  let loading = $state(false);
  let subscribed = $state(false);

  // Check for existing subscription on mount (once only)
  onMount(() => {
    checkExistingSubscription();
  });

  async function checkExistingSubscription(): Promise<void> {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      permission = 'unsupported';
      return;
    }
    try {
      const registration = await navigator.serviceWorker.getRegistration();
      if (!registration) return;
      const sub = await registration.pushManager.getSubscription();
      subscribed = sub !== null;
    } catch {
      // Silently degrade
    }
  }

  async function handleEnable(): Promise<void> {
    loading = true;
    try {
      const status = await initPushNotifications(relay.authToken ?? undefined);
      permission = status.permission === 'unsupported' ? 'unsupported' : status.permission;
      subscribed = status.subscribed;

      if (status.permission === 'denied') {
        toasts.warning('Notifications blocked — enable in browser settings');
      } else if (status.subscribed) {
        toasts.success('Notifications enabled');
      } else if (status.error) {
        toasts.error(status.error);
      }
    } catch {
      toasts.error('Failed to enable notifications');
    } finally {
      loading = false;
    }
  }

  async function handleDisable(): Promise<void> {
    loading = true;
    try {
      const registration = await navigator.serviceWorker.getRegistration();
      if (!registration) {
        toasts.error('No service worker registered');
        return;
      }
      const sub = await registration.pushManager.getSubscription();
      if (sub) {
        await unsubscribeFromPush(sub, relay.authToken ?? undefined);
      }
      subscribed = false;
      toasts.info('Notifications disabled');
    } catch {
      toasts.error('Failed to disable notifications');
    } finally {
      loading = false;
    }
  }
</script>

<div class="notification-toggle">
  {#if permission === 'unsupported'}
    <span class="status-text muted">Notifications not supported</span>
  {:else if permission === 'denied'}
    <span class="status-text blocked">Notifications blocked</span>
    <span class="hint">Enable in browser settings</span>
  {:else if permission === 'granted' && subscribed}
    <span class="status-text enabled">Notifications on</span>
    <button class="btn btn-disable" onclick={handleDisable} disabled={loading}>
      {loading ? '...' : 'Disable'}
    </button>
  {:else}
    <button class="btn btn-enable" onclick={handleEnable} disabled={loading}>
      {loading ? 'Enabling...' : 'Enable Notifications'}
    </button>
  {/if}
</div>

<style>
  .notification-toggle {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .status-text {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 500;
  }

  .status-text.enabled {
    color: var(--allow);
  }

  .status-text.blocked {
    color: var(--deny);
  }

  .status-text.muted {
    color: var(--text-tertiary);
  }

  .hint {
    font-size: 0.65rem;
    color: var(--text-tertiary);
  }

  .btn {
    padding: var(--sp-xs) var(--sp-md);
    border: none;
    border-radius: var(--r-sm);
    font-size: 0.7rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s;
  }
  .btn:hover { opacity: 0.85; }
  .btn:disabled { opacity: 0.5; cursor: not-allowed; }

  .btn-enable {
    background: var(--accent);
    color: #000;
  }

  .btn-disable {
    background: var(--surface-hover);
    color: var(--text-secondary);
    border: 1px solid var(--border);
  }
</style>
