<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { toasts } from '../stores/toast.svelte';

  let loggingOut = $state(false);

  async function handleLogout() {
    loggingOut = true;
    await relay.logout();
    toasts.info('Signed out');
    loggingOut = false;
  }
</script>

<div class="auth-settings">
  {#if relay.user}
    <span class="user-email">{relay.user.email}</span>
    <button class="btn btn-logout" onclick={handleLogout} disabled={loggingOut}>
      {loggingOut ? '...' : 'Sign out'}
    </button>
  {:else}
    <span class="status-text">Not signed in</span>
  {/if}
</div>

<style>
  .auth-settings {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .user-email {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 500;
    color: var(--text-secondary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 180px;
  }

  .status-text {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 500;
    color: var(--text-tertiary);
    white-space: nowrap;
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
  .btn:disabled { opacity: 0.5; cursor: not-allowed; }

  .btn-logout {
    background: var(--surface-hover);
    color: var(--text-secondary);
    border: 1px solid var(--border);
  }
</style>
