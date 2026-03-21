<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  let tokenInput = $state(relay.authToken ?? '');
  let showToken = $state(false);
  let dirty = $derived(tokenInput !== (relay.authToken ?? ''));

  function handleSave() {
    const trimmed = tokenInput.trim();
    tokenInput = trimmed;
    relay.setAuthToken(trimmed || null);
  }

  function handleClear() {
    tokenInput = '';
    relay.setAuthToken(null);
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') handleSave();
  }
</script>

<div class="auth-settings">
  <div class="token-row">
    <input
      class="token-input"
      type={showToken ? 'text' : 'password'}
      placeholder="Auth token"
      aria-label="Authentication token"
      autocomplete="off"
      bind:value={tokenInput}
      onkeydown={handleKeydown}
    />
    <button
      class="btn btn-toggle"
      onclick={() => (showToken = !showToken)}
      title={showToken ? 'Hide token' : 'Show token'}
    >
      {showToken ? 'Hide' : 'Show'}
    </button>
    {#if dirty}
      <button class="btn btn-save" onclick={handleSave}>Save</button>
    {/if}
    {#if relay.authToken}
      <button class="btn btn-clear" onclick={handleClear}>Clear</button>
    {/if}
  </div>
  {#if relay.authToken}
    <span class="status-text authenticated">Token set</span>
    <button class="btn btn-repaid" onclick={handleClear} title="Clear token and re-pair device">
      Re-pair
    </button>
  {:else}
    <span class="status-text unauthenticated">No token</span>
  {/if}
</div>

<style>
  .auth-settings {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .token-row {
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .token-input {
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    padding: 3px 8px;
    outline: none;
    width: 140px;
  }

  .token-input:focus {
    border-color: var(--accent);
  }

  .token-input::placeholder {
    color: var(--text-tertiary);
  }

  .status-text {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 500;
    white-space: nowrap;
  }

  .status-text.authenticated {
    color: var(--allow);
  }

  .status-text.unauthenticated {
    color: var(--text-tertiary);
  }

  .btn {
    padding: 3px 8px;
    border: none;
    border-radius: var(--r-sm);
    font-size: 0.65rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s;
    white-space: nowrap;
  }
  .btn:hover { opacity: 0.85; }

  .btn-toggle {
    background: var(--surface-hover);
    color: var(--text-secondary);
    border: 1px solid var(--border);
  }

  .btn-save {
    background: var(--accent);
    color: #000;
  }

  .btn-clear {
    background: var(--surface-hover);
    color: var(--text-secondary);
    border: 1px solid var(--border);
  }

  .btn-repaid {
    background: var(--surface-hover);
    color: var(--text-secondary);
    border: 1px solid var(--border);
  }
</style>
