<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  interface Props {
    open: boolean;
    onClose: () => void;
  }

  let { open, onClose }: Props = $props();

  // Fetch activity feed when panel opens
  $effect(() => {
    if (open && relay.isConnected) {
      relay.requestActivityFeed();
    }
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
</script>

{#if open}
  <div
    class="panel-backdrop"
    role="button"
    tabindex="0"
    aria-label="Close activity feed"
    onclick={onClose}
    onkeydown={handleBackdropKeydown}
  >
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="panel" onclick={(e) => e.stopPropagation()}>
      <div class="panel-header">
        <span class="panel-title">Team Activity</span>
        <button class="panel-close" onclick={onClose} aria-label="Close">&times;</button>
      </div>

      <div class="panel-body">
        {#if relay.activityEntries.length === 0}
          <div class="panel-empty">
            <div class="empty-title">No team activity yet</div>
            <div class="empty-hint">Activity from team members will appear here</div>
          </div>
        {:else}
          {#each relay.activityEntries as entry (entry.id)}
            <div class="entry">
              <div class="entry-main">
                <span class="entry-user">{entry.userName}</span>
                <span class="entry-action">{entry.action}</span>
              </div>
              <div class="entry-meta">
                {#if entry.sessionId}
                  <span class="entry-session" title={entry.sessionId}>{entry.sessionId.slice(0, 8)}</span>
                {/if}
                <span class="entry-time">{formatTime(entry.timestamp)}</span>
              </div>
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
    width: min(360px, 90vw);
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
    padding: var(--sp-sm) var(--sp-sm);
    border-bottom: 1px solid var(--border);
    transition: background 0.15s;
  }

  .entry:hover {
    background: var(--surface-hover);
  }

  .entry-main {
    display: flex;
    align-items: baseline;
    gap: var(--sp-xs);
    margin-bottom: 2px;
  }

  .entry-user {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 700;
    color: var(--accent);
    flex-shrink: 0;
  }

  .entry-action {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-secondary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .entry-meta {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .entry-session {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--text-tertiary);
    background: var(--surface);
    padding: 1px 5px;
    border-radius: var(--r-sm);
  }

  .entry-time {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--text-tertiary);
  }
</style>
