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

  function handleStartSession() {
    relay.startSession();
  }

  const statusColors: Record<string, string> = {
    disconnected: 'var(--deny)',
    connecting: 'var(--accent)',
    connected: 'var(--allow)',
    reconnecting: 'var(--accent)',
  };
</script>

<div class="connection-bar">
  <div class="left">
    <span
      class="status-dot"
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

    <span class="state-text">{relay.connectionState}</span>
  </div>

  <div class="right">
    {#if relay.isConnected && !relay.hasSession}
      <button class="btn btn-session" onclick={handleStartSession}>
        Start Session
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
    padding: var(--sp-sm) var(--sp-lg);
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
    gap: var(--sp-md);
  }

  .left {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    min-width: 0;
  }

  .status-dot {
    width: 8px;
    height: 8px;
    border-radius: var(--r-full);
    flex-shrink: 0;
  }

  .address-label {
    background: none;
    border: none;
    color: var(--text-secondary);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    cursor: pointer;
    padding: 0;
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
</style>
