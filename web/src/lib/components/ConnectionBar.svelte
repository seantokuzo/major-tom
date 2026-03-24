<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  let editing = $state(false);
  let addressInput = $state(relay.serverAddress);

  function handleConnect() {
    if (relay.isConnected) {
      relay.disconnect();
    } else {
      relay.serverAddress = addressInput;
      relay.connect();
    }
  }

  function handleRetry() {
    relay.serverAddress = addressInput;
    relay.retry();
  }

  function handleStartSession() {
    relay.startSession();
  }

  const statusColors: Record<string, string> = {
    disconnected: 'var(--deny)',
    connecting: 'var(--accent)',
    connected: 'var(--allow)',
    reconnecting: 'var(--accent)',
  };

  let timeSinceDisconnect = $state('');
  let disconnectTimer: ReturnType<typeof setInterval> | undefined;

  function formatElapsed(ms: number): string {
    const secs = Math.floor(ms / 1000);
    if (secs < 60) return `${secs}s`;
    const mins = Math.floor(secs / 60);
    const remainSecs = secs % 60;
    return `${mins}m ${remainSecs}s`;
  }

  $effect(() => {
    if (relay.isReconnecting && relay.lastDisconnectedAt) {
      disconnectTimer = setInterval(() => {
        if (relay.lastDisconnectedAt) {
          timeSinceDisconnect = formatElapsed(Date.now() - relay.lastDisconnectedAt.getTime());
        }
      }, 1000);
      // Immediate update
      timeSinceDisconnect = formatElapsed(Date.now() - relay.lastDisconnectedAt.getTime());
    } else {
      timeSinceDisconnect = '';
    }
    return () => {
      if (disconnectTimer) clearInterval(disconnectTimer);
    };
  });

  let stateLabel = $derived.by(() => {
    const state = relay.connectionState;
    if (state === 'reconnecting') {
      const parts = [`Reconnecting (${relay.reconnectAttempt}/${relay.maxReconnectAttempts})`];
      if (timeSinceDisconnect) parts.push(timeSinceDisconnect);
      return parts.join(' \u2014 ');
    }
    if (state === 'disconnected' && relay.connectionError) {
      return relay.connectionError;
    }
    return state;
  });

  let isPulsing = $derived(
    relay.connectionState === 'connecting' || relay.connectionState === 'reconnecting'
  );
</script>

<div class="connection-bar">
  <div class="left">
    <span
      class="status-dot"
      class:pulsing={isPulsing}
      style="background: {statusColors[relay.connectionState]}"
    ></span>

    {#if editing && !relay.isConnected}
      <input
        class="address-input"
        bind:value={addressInput}
        onblur={() => editing = false}
        onkeydown={(e) => { if (e.key === 'Enter') { editing = false; handleConnect(); }}}
      />
    {:else}
      <button class="address-label" onclick={() => { if (!relay.isConnected) editing = true; }}>
        {relay.serverAddress}
      </button>
    {/if}

    <span class="state-text" class:state-error={relay.connectionError}>{stateLabel}</span>
  </div>

  <div class="right">
    {#if relay.isConnected && !relay.hasSession}
      <button class="btn btn-session" onclick={handleStartSession}>
        Start Session
      </button>
    {/if}

    {#if relay.isDisconnected && relay.connectionError}
      <button class="btn btn-retry" onclick={handleRetry}>
        Retry
      </button>
    {/if}

    <button
      class="btn {relay.isConnected ? 'btn-disconnect' : 'btn-connect'}"
      onclick={handleConnect}
    >
      {relay.isConnected ? 'Disconnect' : 'Connect'}
    </button>
  </div>
</div>

<style>
  .connection-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--sp-sm) var(--sp-sm);
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
    gap: var(--sp-sm);
    overflow: hidden;
  }

  .left {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    min-width: 0;
    overflow: hidden;
  }

  .status-dot {
    width: 8px;
    height: 8px;
    border-radius: var(--r-full);
    flex-shrink: 0;
    transition: background 0.3s;
  }

  .status-dot.pulsing {
    animation: pulse 1.5s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }

  .address-label {
    background: none;
    border: none;
    color: var(--text-secondary);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    cursor: pointer;
    padding: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 120px;
  }
  .address-label:hover { color: var(--text-primary); }

  .address-input {
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    padding: 2px 6px;
    outline: none;
    width: 160px;
  }

  .state-text {
    font-size: 0.7rem;
    color: var(--text-tertiary);
    text-transform: capitalize;
    transition: color 0.3s;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .state-text.state-error {
    color: var(--deny);
    text-transform: none;
  }

  .right {
    display: flex;
    gap: var(--sp-sm);
    flex-shrink: 0;
  }

  .btn {
    padding: var(--sp-xs) var(--sp-md);
    border: none;
    border-radius: var(--r-sm);
    font-size: 0.75rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s;
  }
  .btn:hover { opacity: 0.85; }

  .btn-connect { background: var(--accent); color: #000; }
  .btn-disconnect { background: var(--deny); color: #000; }
  .btn-session { background: var(--allow); color: #000; }
  .btn-retry { background: var(--accent); color: #000; }
</style>
