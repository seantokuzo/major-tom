<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  let timeSinceDisconnect = $state('');
  let timer: ReturnType<typeof setInterval> | undefined;

  function formatElapsed(ms: number): string {
    const secs = Math.floor(ms / 1000);
    if (secs < 60) return `${secs}s ago`;
    const mins = Math.floor(secs / 60);
    return `${mins}m ago`;
  }

  $effect(() => {
    if (relay.isReconnecting && relay.lastDisconnectedAt) {
      timer = setInterval(() => {
        if (relay.lastDisconnectedAt) {
          timeSinceDisconnect = formatElapsed(Date.now() - relay.lastDisconnectedAt.getTime());
        }
      }, 1000);
      timeSinceDisconnect = formatElapsed(Date.now() - relay.lastDisconnectedAt.getTime());
    } else {
      timeSinceDisconnect = '';
    }
    return () => {
      if (timer) clearInterval(timer);
    };
  });

  /** Only show the reconnecting banner when actively reconnecting */
  let showBanner = $derived(relay.isReconnecting);
</script>

{#if showBanner}
  <div class="reconnect-banner">
    <span class="banner-dot"></span>
    <span class="banner-text">
      Reconnecting... (attempt {relay.reconnectAttempt}/{relay.maxReconnectAttempts})
      {#if timeSinceDisconnect}
        &mdash; disconnected {timeSinceDisconnect}
      {/if}
    </span>
  </div>
{/if}

{#if relay.isDisconnected && relay.connectionError}
  <div class="error-banner">
    <span class="error-dot"></span>
    <span class="banner-text">{relay.connectionError}</span>
    <button class="banner-retry" onclick={() => relay.retry()}>Retry</button>
  </div>
{/if}

<style>
  .reconnect-banner {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 16px;
    background: color-mix(in srgb, var(--accent) 10%, transparent);
    border-bottom: 1px solid color-mix(in srgb, var(--accent) 20%, transparent);
    flex-shrink: 0;
  }

  .error-banner {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 16px;
    background: rgba(248, 113, 113, 0.1);
    border-bottom: 1px solid rgba(248, 113, 113, 0.2);
    flex-shrink: 0;
  }

  .banner-dot {
    width: 6px;
    height: 6px;
    border-radius: var(--r-full);
    background: var(--accent);
    animation: banner-pulse 1.5s ease-in-out infinite;
    flex-shrink: 0;
  }

  .error-dot {
    width: 6px;
    height: 6px;
    border-radius: var(--r-full);
    background: var(--deny);
    flex-shrink: 0;
  }

  @keyframes banner-pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }

  .banner-text {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-secondary);
    flex: 1;
  }

  .banner-retry {
    padding: 2px 10px;
    border: none;
    border-radius: var(--r-sm);
    background: var(--accent);
    color: #000;
    font-size: 0.7rem;
    font-weight: 600;
    cursor: pointer;
    flex-shrink: 0;
  }
  .banner-retry:hover {
    opacity: 0.85;
  }
</style>
