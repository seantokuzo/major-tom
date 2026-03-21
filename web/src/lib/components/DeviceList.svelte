<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import type { DeviceInfo } from '../protocol/messages';

  let loading = $state(true);
  let confirmingId = $state<string | null>(null);
  let initialDevices: DeviceInfo[] | null = null;

  // Request device list on mount
  $effect(() => {
    initialDevices = relay.devices;
    relay.requestDeviceList();
    // Fallback timeout in case response never arrives
    const timeout = setTimeout(() => { loading = false; }, 5000);
    return () => clearTimeout(timeout);
  });

  // Clear loading when devices array reference changes (response arrived)
  $effect(() => {
    if (loading && initialDevices !== null && relay.devices !== initialDevices) {
      loading = false;
    }
  });

  function formatDate(iso: string): string {
    try {
      return new Date(iso).toLocaleDateString(undefined, {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
      });
    } catch {
      return iso;
    }
  }

  function formatRelativeTime(iso: string): string {
    try {
      const diff = Date.now() - new Date(iso).getTime();
      const seconds = Math.floor(diff / 1000);
      if (seconds < 60) return 'just now';
      const minutes = Math.floor(seconds / 60);
      if (minutes < 60) return `${minutes}m ago`;
      const hours = Math.floor(minutes / 60);
      if (hours < 24) return `${hours}h ago`;
      const days = Math.floor(hours / 24);
      if (days < 30) return `${days}d ago`;
      return formatDate(iso);
    } catch {
      return iso;
    }
  }

  function handleRevoke(device: DeviceInfo) {
    if (confirmingId === device.id) {
      relay.revokeDevice(device.id);
      confirmingId = null;
    } else {
      confirmingId = device.id;
    }
  }

  function handleCancelConfirm() {
    confirmingId = null;
  }
</script>

<div class="device-list">
  <div class="device-list-header">
    <h3 class="device-list-title">Paired Devices</h3>
  </div>

  {#if loading}
    <div class="device-list-loading">Loading devices...</div>
  {:else if relay.devices.length === 0}
    <div class="device-list-empty">No paired devices</div>
  {:else}
    <div class="device-items">
      {#each relay.devices as device (device.id)}
        <div class="device-item">
          <div class="device-info">
            <span class="device-name">{device.name}</span>
            <span class="device-meta">
              Paired on {formatDate(device.createdAt)}
            </span>
            <span class="device-meta">
              Last seen {formatRelativeTime(device.lastSeenAt)}
            </span>
          </div>
          <div class="device-actions">
            {#if confirmingId === device.id}
              <button
                class="btn btn-confirm-revoke"
                onclick={() => handleRevoke(device)}
              >
                Confirm?
              </button>
              <button
                class="btn btn-cancel"
                onclick={handleCancelConfirm}
              >
                Cancel
              </button>
            {:else}
              <button
                class="btn btn-revoke"
                onclick={() => handleRevoke(device)}
              >
                Revoke
              </button>
            {/if}
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .device-list {
    display: flex;
    flex-direction: column;
    gap: var(--sp-md);
    padding: var(--sp-lg);
    max-width: 500px;
    width: 100%;
  }

  .device-list-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .device-list-title {
    font-family: var(--font-mono);
    font-size: 0.95rem;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .device-list-loading,
  .device-list-empty {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    color: var(--text-tertiary);
    text-align: center;
    padding: var(--sp-lg) 0;
  }

  .device-items {
    display: flex;
    flex-direction: column;
    gap: var(--sp-sm);
  }

  .device-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-md);
    padding: var(--sp-sm) var(--sp-md);
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
  }

  .device-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .device-name {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--text-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .device-meta {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
  }

  .device-actions {
    display: flex;
    gap: 4px;
    flex-shrink: 0;
  }

  .btn {
    padding: 4px 10px;
    border: none;
    border-radius: var(--r-sm);
    font-size: 0.7rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s;
    white-space: nowrap;
    font-family: var(--font-mono);
  }
  .btn:hover { opacity: 0.85; }

  .btn-revoke {
    background: var(--deny);
    color: #fff;
  }

  .btn-confirm-revoke {
    background: var(--deny);
    color: #fff;
    animation: pulse 0.6s ease-in-out;
  }

  .btn-cancel {
    background: var(--surface-hover);
    color: var(--text-secondary);
    border: 1px solid var(--border);
  }

  @keyframes pulse {
    0% { transform: scale(1); }
    50% { transform: scale(1.05); }
    100% { transform: scale(1); }
  }
</style>
