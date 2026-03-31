<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { sessionStateManager } from '../stores/session-state.svelte';
  import { presenceStore } from '../stores/presence.svelte';
  import PresenceAvatars from './PresenceAvatars.svelte';

  const showPresence = $derived(relay.multiUserEnabled);

  // Request session list whenever panel opens
  $effect(() => {
    if (sessionStateManager.panelOpen) {
      relay.requestSessionList();
    }
  });

  // Close on Escape key
  $effect(() => {
    if (!sessionStateManager.panelOpen) return;
    function onKeydown(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        sessionStateManager.closePanel();
      }
    }
    window.addEventListener('keydown', onKeydown);
    return () => window.removeEventListener('keydown', onKeydown);
  });

  function formatCost(cost: number): string {
    if (cost === 0) return '$0';
    return `$${cost.toFixed(4)}`;
  }

  function truncateDir(dir: string, maxLen = 30): string {
    if (!dir) return '';
    if (dir.length <= maxLen) return dir;
    return '...' + dir.slice(-maxLen + 3);
  }

  function handleSessionClick(sessionId: string) {
    if (sessionId === relay.sessionId) {
      // Already on this session — just close panel
      sessionStateManager.closePanel();
      return;
    }
    relay.switchSession(sessionId);
    sessionStateManager.closePanel();
  }

  function handleNewSession() {
    relay.newSession();
    sessionStateManager.closePanel();
  }

  // Editable name state
  let editingId = $state<string | null>(null);
  let editValue = $state('');

  function startRename(sessionId: string, currentName: string, e: Event) {
    e.stopPropagation();
    editingId = sessionId;
    editValue = currentName;
  }

  function commitRename() {
    if (editingId && editValue.trim()) {
      sessionStateManager.renameSession(editingId, editValue.trim());
    }
    editingId = null;
    editValue = '';
  }

  function cancelRename() {
    editingId = null;
    editValue = '';
  }
</script>

{#if sessionStateManager.panelOpen}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="panel-backdrop" onclick={() => sessionStateManager.closePanel()}>
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="panel" onclick={(e) => e.stopPropagation()}>
      <div class="panel-header">
        <span class="panel-title">Sessions</span>
        <button class="panel-close" onclick={() => sessionStateManager.closePanel()} aria-label="Close">&times;</button>
      </div>

      <!-- New Session button -->
      <button class="new-session-btn" onclick={handleNewSession} disabled={!relay.isConnected}>
        <span class="new-icon">+</span>
        New Session
      </button>

      <!-- Session list -->
      <div class="panel-body">
        {#if sessionStateManager.sessionList.length === 0}
          <div class="panel-empty">No sessions yet</div>
        {:else}
          {#each sessionStateManager.sessionList as entry (entry.sessionId)}
            <button
              class="session-item"
              class:current={entry.sessionId === relay.sessionId}
              onclick={() => handleSessionClick(entry.sessionId)}
            >
              <div class="session-row-top">
                <span
                  class="status-dot"
                  class:dot-active={entry.status === 'active'}
                  class:dot-idle={entry.status === 'idle'}
                  class:dot-closed={entry.status === 'closed'}
                  title={entry.status}
                ></span>
                {#if editingId === entry.sessionId}
                  <!-- svelte-ignore a11y_autofocus -->
                  <input
                    class="rename-input"
                    bind:value={editValue}
                    onkeydown={(e) => { if (e.key === 'Enter') commitRename(); if (e.key === 'Escape') cancelRename(); }}
                    onblur={commitRename}
                    onclick={(e) => e.stopPropagation()}
                    autofocus
                  />
                {:else}
                  <!-- svelte-ignore a11y_click_events_have_key_events -->
                  <!-- svelte-ignore a11y_no_static_element_interactions -->
                  <span
                    class="session-name"
                    ondblclick={(e) => startRename(entry.sessionId, entry.name, e)}
                    title="Double-click to rename"
                  >
                    {entry.name}
                  </span>
                {/if}
                {#if entry.sessionId === relay.sessionId}
                  <span class="current-badge">current</span>
                {/if}
                {#if showPresence}
                  {@const watchers = presenceStore.watchersFor(entry.sessionId)}
                  {#if watchers.length > 0}
                    <PresenceAvatars users={watchers} maxShow={2} size="sm" />
                  {/if}
                {/if}
              </div>
              <div class="session-row-meta">
                {#if entry.workingDir}
                  <span class="meta-dir" title={entry.workingDir}>{truncateDir(entry.workingDir)}</span>
                {/if}
                <span class="meta-cost">{formatCost(entry.totalCost)}</span>
                {#if entry.agentCount > 0}
                  <span class="meta-agents">{entry.agentCount} agent{entry.agentCount !== 1 ? 's' : ''}</span>
                {/if}
              </div>
            </button>
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
    width: min(320px, 85vw);
    background: var(--bg);
    border-left: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    box-shadow: -4px 0 24px rgba(0, 0, 0, 0.4);
    animation: slide-in 0.2s ease-out;
  }

  @keyframes slide-in {
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

  .new-session-btn {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    margin: var(--sp-sm) var(--sp-md);
    padding: var(--sp-sm) var(--sp-md);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--bg);
    background: var(--accent);
    border: none;
    border-radius: var(--r-sm);
    cursor: pointer;
    transition: all 0.15s;
    flex-shrink: 0;
  }

  .new-session-btn:hover:not(:disabled) {
    background: var(--accent-dim);
  }

  .new-session-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .new-icon {
    font-size: 1rem;
    font-weight: 700;
    line-height: 1;
  }

  .panel-body {
    flex: 1;
    overflow-y: auto;
    padding: var(--sp-xs) var(--sp-md);
  }

  .panel-empty {
    padding: var(--sp-xl);
    text-align: center;
    font-family: var(--font-mono);
    font-size: 0.8rem;
    color: var(--text-tertiary);
  }

  .session-item {
    display: block;
    width: 100%;
    padding: var(--sp-sm) var(--sp-md);
    margin-bottom: var(--sp-xs);
    background: transparent;
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    cursor: pointer;
    text-align: left;
    color: var(--text-primary);
    transition: background 0.15s, border-color 0.15s;
  }

  .session-item:hover {
    background: var(--surface-hover);
  }

  .session-item.current {
    border-color: var(--accent);
    background: rgba(77, 217, 115, 0.06);
  }

  .session-row-top {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    margin-bottom: 4px;
  }

  .status-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
    background: var(--text-tertiary);
  }

  .dot-active {
    background: var(--allow);
    box-shadow: 0 0 4px var(--allow);
  }

  .dot-idle {
    background: #eab308;
  }

  .dot-closed {
    background: var(--text-tertiary);
  }

  .session-name {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex: 1;
    min-width: 0;
    cursor: text;
  }

  .rename-input {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--text-primary);
    background: var(--surface);
    border: 1px solid var(--accent);
    border-radius: 3px;
    padding: 1px 6px;
    flex: 1;
    min-width: 0;
    outline: none;
  }

  .current-badge {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    font-weight: 700;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    flex-shrink: 0;
  }

  .session-row-meta {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-tertiary);
    flex-wrap: wrap;
    padding-left: calc(8px + var(--sp-sm));
  }

  .meta-dir {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 160px;
  }

  .meta-cost {
    color: var(--text-secondary);
  }

  .meta-agents {
    color: var(--accent-dim);
  }
</style>
