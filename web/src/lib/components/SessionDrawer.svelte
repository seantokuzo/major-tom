<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { sessionsStore } from '../stores/sessions.svelte';

  let { open = $bindable(false), onclose }: { open: boolean; onclose: () => void } = $props();

  // Request session list whenever drawer opens
  $effect(() => {
    if (open) {
      relay.requestSessionList();
    }
  });

  function formatDuration(ms: number): string {
    if (ms < 1000) return `${ms}ms`;
    const secs = Math.floor(ms / 1000);
    if (secs < 60) return `${secs}s`;
    const mins = Math.floor(secs / 60);
    const remSecs = secs % 60;
    return remSecs > 0 ? `${mins}m ${remSecs}s` : `${mins}m`;
  }

  function formatCost(cost: number): string {
    return `$${cost.toFixed(4)}`;
  }

  function formatTokens(count: number): string {
    if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(1)}M`;
    if (count >= 1_000) return `${(count / 1_000).toFixed(1)}k`;
    return `${count}`;
  }

  function formatTime(iso: string): string {
    const d = new Date(iso);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  function handleSwitch(sessionId: string) {
    relay.switchSession(sessionId);
    onclose();
  }

  function close() {
    open = false;
    onclose();
  }
</script>

{#if open}
  <div class="drawer-backdrop" onclick={close} onkeydown={(e) => { if (e.key === 'Escape' || e.key === 'Enter' || e.key === ' ') close(); }} role="presentation">
    <div class="drawer" onclick={(e) => e.stopPropagation()} role="dialog" aria-label="Sessions" aria-modal="true">
      <div class="drawer-header">
        <span class="drawer-title">Sessions</span>
        <button class="drawer-close" onclick={close} aria-label="Close">&times;</button>
      </div>

      <div class="drawer-body">
        {#if sessionsStore.isLoading}
          <div class="drawer-empty">Loading sessions...</div>
        {:else if sessionsStore.sessions.length === 0}
          <div class="drawer-empty">No sessions</div>
        {:else}
          {#each sessionsStore.sessions as session (session.id)}
            <button
              class="session-card"
              class:current={session.id === relay.sessionId}
              onclick={() => handleSwitch(session.id)}
            >
              <div class="session-top">
                <span class="session-status" class:active={session.status === 'active'} class:idle={session.status === 'idle'} class:closed={session.status === 'closed'}>
                  {session.status}
                </span>
                <span class="session-dir" title={session.workingDirName}>{session.workingDirName}</span>
                {#if session.id === relay.sessionId}
                  <span class="session-current-badge">current</span>
                {/if}
              </div>
              <div class="session-stats">
                <span class="stat">{formatCost(session.totalCost)}</span>
                <span class="stat-sep">|</span>
                <span class="stat">{formatTokens(session.inputTokens + session.outputTokens)} tok</span>
                <span class="stat-sep">|</span>
                <span class="stat">{formatDuration(session.totalDuration)}</span>
                <span class="stat-sep">|</span>
                <span class="stat">{formatTime(session.startedAt)}</span>
              </div>
            </button>
          {/each}
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .drawer-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: flex-end;
    justify-content: center;
    z-index: 100;
  }

  .drawer {
    background: var(--surface);
    border: 1px solid var(--border);
    border-bottom: none;
    border-radius: var(--r-md) var(--r-md) 0 0;
    width: 100%;
    max-width: 480px;
    max-height: 60vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 -4px 24px rgba(0, 0, 0, 0.4);
  }

  .drawer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--sp-md) var(--sp-lg);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .drawer-title {
    font-family: var(--font-mono);
    font-size: 0.9rem;
    font-weight: 600;
    color: var(--text-primary);
  }

  .drawer-close {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    font-size: 1.2rem;
    cursor: pointer;
    padding: 0 var(--sp-xs);
    line-height: 1;
  }
  .drawer-close:hover {
    color: var(--text-primary);
  }

  .drawer-body {
    flex: 1;
    overflow-y: auto;
    padding: var(--sp-sm);
  }

  .drawer-empty {
    padding: var(--sp-xl);
    text-align: center;
    font-size: 0.85rem;
    color: var(--text-tertiary);
  }

  .session-card {
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

  .session-card:hover {
    background: var(--surface-hover);
  }

  .session-card.current {
    border-color: var(--accent);
    background: rgba(99, 102, 241, 0.08);
  }

  .session-top {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    margin-bottom: var(--sp-xs);
  }

  .session-status {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    padding: 1px 6px;
    border-radius: 3px;
  }
  .session-status.active {
    background: rgba(34, 197, 94, 0.15);
    color: #22c55e;
  }
  .session-status.idle {
    background: rgba(234, 179, 8, 0.15);
    color: #eab308;
  }
  .session-status.closed {
    background: rgba(148, 163, 184, 0.15);
    color: #94a3b8;
  }

  .session-dir {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    color: var(--text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex: 1;
    min-width: 0;
  }

  .session-current-badge {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    flex-shrink: 0;
  }

  .session-stats {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-secondary);
    flex-wrap: wrap;
  }

  .stat-sep {
    color: var(--border);
  }
</style>
