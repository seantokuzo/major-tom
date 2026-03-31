<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  interface Props {
    open: boolean;
    onClose: () => void;
  }

  let { open, onClose }: Props = $props();

  type TimeRange = 'hour' | 'day' | 'week' | 'all';
  let timeRange = $state<TimeRange>('day');
  let actionFilter = $state('');
  let userFilter = $state('');

  // Fetch audit entries when panel opens or filters change
  $effect(() => {
    if (!open || !relay.isConnected) return;

    const now = new Date();
    let startTime: string | undefined;
    if (timeRange === 'hour') {
      startTime = new Date(now.getTime() - 60 * 60 * 1000).toISOString();
    } else if (timeRange === 'day') {
      startTime = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
    } else if (timeRange === 'week') {
      startTime = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
    }

    relay.queryAudit({
      startTime,
      userId: userFilter || undefined,
      action: actionFilter || undefined,
      limit: 200,
    });
  });

  // Close on Escape
  $effect(() => {
    if (!open) return;
    function onKeydown(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKeydown);
    return () => window.removeEventListener('keydown', onKeydown);
  });

  function handleBackdropKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onClose();
    }
  }

  function formatTime(iso: string): string {
    const date = new Date(iso);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMin = Math.floor(diffMs / 60_000);
    if (diffMin < 1) return 'just now';
    if (diffMin < 60) return `${diffMin}m ago`;
    const diffHr = Math.floor(diffMin / 60);
    if (diffHr < 24) return `${diffHr}h ago`;
    const diffDay = Math.floor(diffHr / 24);
    return `${diffDay}d ago`;
  }

  function actionColor(action: string): string {
    if (action.includes('approve') || action.includes('allow')) return 'var(--allow)';
    if (action.includes('deny') || action.includes('revoke')) return 'var(--deny)';
    if (action.includes('prompt')) return 'var(--accent)';
    if (action.includes('login') || action.includes('auth')) return '#a78bfa';
    if (action.includes('session')) return '#60a5fa';
    return 'var(--text-secondary)';
  }

  // Unique actions for filter dropdown
  const uniqueActions = $derived(
    [...new Set(relay.auditEntries.map(e => e.action))].sort()
  );

  // Unique users for filter dropdown
  const uniqueUsers = $derived(
    [...new Set(relay.auditEntries.map(e => e.email))].sort()
  );
</script>

{#if open}
  <div
    class="panel-backdrop"
    role="button"
    tabindex="0"
    aria-label="Close audit viewer"
    onclick={onClose}
    onkeydown={handleBackdropKeydown}
  >
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="panel" onclick={(e) => e.stopPropagation()}>
      <div class="panel-header">
        <span class="panel-title">Audit Log</span>
        <button class="panel-close" onclick={onClose} aria-label="Close">&times;</button>
      </div>

      <div class="filters">
        <div class="filter-row">
          <select class="filter-select" bind:value={timeRange}>
            <option value="hour">Last Hour</option>
            <option value="day">Last 24h</option>
            <option value="week">Last 7 Days</option>
            <option value="all">All Time</option>
          </select>
          <select class="filter-select" bind:value={actionFilter}>
            <option value="">All Actions</option>
            {#each uniqueActions as action}
              <option value={action}>{action}</option>
            {/each}
          </select>
        </div>
        <div class="filter-row">
          <select class="filter-select wide" bind:value={userFilter}>
            <option value="">All Users</option>
            {#each uniqueUsers as email}
              <option value={email}>{email}</option>
            {/each}
          </select>
          <button class="refresh-btn" onclick={() => relay.queryAudit({ limit: 200 })} title="Refresh">
            <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
              <path d="M13.65 2.35A8 8 0 1 0 16 8h-2a6 6 0 1 1-1.76-4.24L10 6h6V0l-2.35 2.35z" fill="currentColor"/>
            </svg>
          </button>
        </div>
      </div>

      <div class="panel-body">
        {#if relay.auditEntries.length === 0}
          <div class="panel-empty">
            <div class="empty-title">No audit entries</div>
            <div class="empty-hint">Actions will be recorded here</div>
          </div>
        {:else}
          {#each relay.auditEntries as entry, i (i)}
            <div class="entry">
              <div class="entry-header">
                <span class="entry-action" style="color: {actionColor(entry.action)}">{entry.action}</span>
                <span class="entry-time">{formatTime(entry.timestamp)}</span>
              </div>
              <div class="entry-details">
                <span class="entry-user">{entry.email}</span>
                <span class="entry-role">{entry.role}</span>
              </div>
              {#if entry.sessionId || entry.path}
                <div class="entry-meta">
                  {#if entry.sessionId}
                    <span class="meta-tag" title={entry.sessionId}>{entry.sessionId.slice(0, 8)}</span>
                  {/if}
                  {#if entry.path}
                    <span class="meta-tag path" title={entry.path}>{entry.path}</span>
                  {/if}
                </div>
              {/if}
              {#if entry.details}
                <div class="entry-extra">{entry.details}</div>
              {/if}
            </div>
          {/each}
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .panel-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.45);
    z-index: 200;
  }

  .panel {
    position: fixed;
    top: 0;
    right: 0;
    bottom: 0;
    width: min(440px, 95vw);
    background: var(--bg);
    border-left: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    box-shadow: -4px 0 24px rgba(0, 0, 0, 0.4);
    animation: slide-in-right 0.2s ease-out;
  }

  @keyframes slide-in-right {
    from { transform: translateX(100%); }
    to { transform: translateX(0); }
  }

  .panel-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--sp-md) var(--sp-lg);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .panel-title {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--text-primary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .panel-close {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    font-size: 1.3rem;
    cursor: pointer;
    padding: 0 var(--sp-xs);
    line-height: 1;
  }
  .panel-close:hover {
    color: var(--text-primary);
  }

  .filters {
    padding: var(--sp-sm) var(--sp-md);
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: var(--sp-xs);
    flex-shrink: 0;
  }

  .filter-row {
    display: flex;
    gap: var(--sp-xs);
    align-items: center;
  }

  .filter-select {
    flex: 1;
    font-family: var(--font-mono);
    font-size: 0.65rem;
    padding: 4px 6px;
    background: var(--surface);
    color: var(--text-secondary);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    cursor: pointer;
    min-width: 0;
  }
  .filter-select:focus {
    border-color: var(--accent);
    outline: none;
  }
  .filter-select.wide {
    flex: 3;
  }

  .refresh-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text-secondary);
    cursor: pointer;
    padding: 4px 8px;
    border-radius: var(--r-sm);
    transition: all 0.15s;
    flex-shrink: 0;
  }
  .refresh-btn:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
    border-color: var(--accent);
  }

  .panel-body {
    flex: 1;
    overflow-y: auto;
    padding: var(--sp-xs) var(--sp-md);
  }

  .panel-empty {
    padding: var(--sp-xl);
    text-align: center;
  }

  .empty-title {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--text-secondary);
    margin-bottom: var(--sp-xs);
  }

  .empty-hint {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
  }

  .entry {
    padding: var(--sp-sm);
    border-bottom: 1px solid var(--border);
    transition: background 0.15s;
  }
  .entry:hover {
    background: var(--surface-hover);
  }

  .entry-header {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: var(--sp-sm);
    margin-bottom: 2px;
  }

  .entry-action {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 700;
  }

  .entry-time {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--text-tertiary);
    flex-shrink: 0;
  }

  .entry-details {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    margin-bottom: 2px;
  }

  .entry-user {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .entry-role {
    font-family: var(--font-mono);
    font-size: 0.55rem;
    font-weight: 600;
    color: var(--text-tertiary);
    background: var(--surface);
    padding: 0 5px;
    border-radius: var(--r-full);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    flex-shrink: 0;
  }

  .entry-meta {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    margin-top: 2px;
  }

  .meta-tag {
    font-family: var(--font-mono);
    font-size: 0.55rem;
    color: var(--text-tertiary);
    background: var(--surface);
    padding: 1px 5px;
    border-radius: var(--r-sm);
    max-width: 100px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .meta-tag.path {
    max-width: 200px;
  }

  .entry-extra {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--text-tertiary);
    margin-top: 2px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>
