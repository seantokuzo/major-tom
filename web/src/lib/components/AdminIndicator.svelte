<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import AuditViewer from './AuditViewer.svelte';
  import RateLimitConfig from './RateLimitConfig.svelte';

  type AdminView = 'audit' | 'rates';
  let activeView = $state<AdminView | null>(null);

  function openView(view: AdminView) {
    activeView = view;
  }

  function closeView() {
    activeView = null;
  }

  const show = $derived(relay.isAdmin && relay.multiUserEnabled && relay.isConnected);
</script>

{#if show}
  <div class="admin-menu">
    <button
      class="admin-btn"
      onclick={() => openView('audit')}
      title="Audit Log"
      aria-label="Open audit log"
    >
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
        <path d="M3 2h10v1H3V2zm0 3h10v1H3V5zm0 3h7v1H3V8zm0 3h5v1H3v-1zm9-1.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zm0 1a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z" fill="currentColor"/>
      </svg>
    </button>
    <button
      class="admin-btn"
      onclick={() => openView('rates')}
      title="Rate Limits"
      aria-label="Open rate limit config"
    >
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
        <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm0 1a6 6 0 1 1 0 12A6 6 0 0 1 8 2zm-.5 2v4.3l3.06 1.84.5-.85L8.5 7.7V4h-1z" fill="currentColor"/>
      </svg>
    </button>
  </div>

  <AuditViewer open={activeView === 'audit'} onClose={closeView} />
  <RateLimitConfig open={activeView === 'rates'} onClose={closeView} />
{/if}

<style>
  .admin-menu {
    display: flex;
    align-items: center;
    gap: 2px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: 1px;
  }

  .admin-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    background: transparent;
    border: none;
    color: var(--text-tertiary);
    cursor: pointer;
    padding: 3px 6px;
    border-radius: 3px;
    transition: all 0.15s;
    line-height: 1;
  }

  .admin-btn:hover {
    color: var(--accent);
    background: var(--surface-hover);
  }
</style>
