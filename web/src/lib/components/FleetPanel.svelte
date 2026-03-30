<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { fleetStore } from '../stores/fleet.svelte';
  import type { FleetWorkerInfo } from '../protocol/messages';

  // Close on Escape key
  $effect(() => {
    if (!fleetStore.panelOpen) return;
    function onKeydown(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        fleetStore.closePanel();
      }
    }
    window.addEventListener('keydown', onKeydown);
    return () => window.removeEventListener('keydown', onKeydown);
  });

  // Track expanded workers
  let expandedWorkers = $state<Set<string>>(new Set());

  function toggleWorker(workerId: string) {
    const next = new Set(expandedWorkers);
    if (next.has(workerId)) {
      next.delete(workerId);
    } else {
      next.add(workerId);
    }
    expandedWorkers = next;
  }

  function formatCost(cost: number): string {
    if (cost === 0) return '$0.00';
    if (cost < 0.01) return `$${cost.toFixed(4)}`;
    return `$${cost.toFixed(2)}`;
  }

  function formatTokens(n: number): string {
    if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
    if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
    return String(n);
  }

  function formatUptime(ms: number): string {
    const seconds = Math.floor(ms / 1000);
    if (seconds < 60) return `${seconds}s`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m`;
    const hours = Math.floor(minutes / 60);
    const remainMinutes = minutes % 60;
    return `${hours}h ${remainMinutes}m`;
  }

  function healthLabel(health: typeof fleetStore.health): string {
    switch (health) {
      case 'healthy': return 'All Healthy';
      case 'degraded': return 'Degraded';
      case 'critical': return 'Critical';
      case 'empty': return 'No Workers';
    }
  }

  function workerCost(worker: FleetWorkerInfo): number {
    return worker.sessions.reduce((sum, s) => sum + s.totalCost, 0);
  }

  function handleSessionClick(sessionId: string) {
    relay.switchSession(sessionId);
    fleetStore.closePanel();
  }
</script>

{#if fleetStore.panelOpen}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="panel-backdrop" onclick={() => fleetStore.closePanel()}>
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="panel" onclick={(e) => e.stopPropagation()}>
      <div class="panel-header">
        <div class="panel-header-left">
          <span class="panel-title">Fleet Command</span>
          {#if fleetStore.totalWorkers > 0}
            <span class="worker-badge">{fleetStore.totalWorkers} worker{fleetStore.totalWorkers !== 1 ? 's' : ''}</span>
          {/if}
        </div>
        <div class="panel-header-right">
          {#if fleetStore.aggregateCost > 0}
            <span class="aggregate-cost">{formatCost(fleetStore.aggregateCost)}</span>
          {/if}
          <button class="panel-close" onclick={() => fleetStore.closePanel()} aria-label="Close">&times;</button>
        </div>
      </div>

      {#if fleetStore.totalWorkers > 0}
        <!-- Aggregate stats row -->
        <div class="stats-row">
          <div class="stat">
            <span class="stat-value">{fleetStore.totalSessions}</span>
            <span class="stat-label">sessions</span>
          </div>
          <div class="stat">
            <span class="stat-value">{formatCost(fleetStore.aggregateCost)}</span>
            <span class="stat-label">cost</span>
          </div>
          <div class="stat">
            <span class="stat-value">{formatTokens(fleetStore.aggregateTokens.input + fleetStore.aggregateTokens.output)}</span>
            <span class="stat-label">tokens</span>
          </div>
          <div class="stat">
            <span
              class="health-indicator"
              class:health-good={fleetStore.health === 'healthy'}
              class:health-warn={fleetStore.health === 'degraded'}
              class:health-bad={fleetStore.health === 'critical'}
              class:health-empty={fleetStore.health === 'empty'}
            >
              {healthLabel(fleetStore.health)}
            </span>
          </div>
        </div>
      {/if}

      <!-- Worker list -->
      <div class="panel-body">
        {#if fleetStore.totalWorkers === 0}
          <div class="panel-empty">
            <div class="empty-title">No workers active</div>
            <div class="empty-hint">Start a session to spawn a worker</div>
          </div>
        {:else}
          {#each fleetStore.workers as worker (worker.workerId)}
            <!-- svelte-ignore a11y_click_events_have_key_events -->
            <!-- svelte-ignore a11y_no_static_element_interactions -->
            <div class="worker-card">
              <button class="worker-header" onclick={() => toggleWorker(worker.workerId)}>
                <span class="expand-icon">{expandedWorkers.has(worker.workerId) ? '\u25BC' : '\u25B6'}</span>
                <span
                  class="health-dot"
                  class:dot-healthy={worker.healthy}
                  class:dot-unhealthy={!worker.healthy}
                  title={worker.healthy ? 'Healthy' : 'Unhealthy'}
                ></span>
                <span class="worker-name" title={worker.workingDir}>{worker.dirName}</span>
                <span class="worker-sessions">{worker.sessionCount} sess</span>
                {#if worker.restartCount > 0}
                  <span class="restart-badge" title={`${worker.restartCount} restarts`}>{worker.restartCount}x</span>
                {/if}
              </button>
              <div class="worker-meta">
                <span class="meta-uptime">{formatUptime(worker.uptimeMs)}</span>
                <span class="meta-cost">{formatCost(workerCost(worker))}</span>
              </div>

              {#if expandedWorkers.has(worker.workerId)}
                <div class="worker-sessions-list">
                  {#if worker.sessions.length === 0}
                    <div class="no-sessions">No active sessions</div>
                  {:else}
                    {#each worker.sessions as session (session.sessionId)}
                      <button
                        class="session-row"
                        class:session-active={session.sessionId === relay.sessionId}
                        onclick={() => handleSessionClick(session.sessionId)}
                      >
                        <span
                          class="session-dot"
                          class:dot-active={session.status === 'active'}
                          class:dot-idle={session.status === 'idle'}
                          class:dot-closed={session.status === 'closed'}
                        ></span>
                        <span class="session-id">{session.sessionId.slice(0, 8)}</span>
                        <span class="session-cost">{formatCost(session.totalCost)}</span>
                        <span class="session-turns">{session.turnCount} turns</span>
                      </button>
                    {/each}
                  {/if}
                </div>
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
    left: 0;
    bottom: 0;
    width: min(360px, 90vw);
    background: var(--bg);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    box-shadow: 4px 0 24px rgba(0, 0, 0, 0.4);
    animation: slide-in-left 0.2s ease-out;
  }

  @keyframes slide-in-left {
    from { transform: translateX(-100%); }
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

  .panel-header-left {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .panel-header-right {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .panel-title {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--text-primary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .worker-badge {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    font-weight: 700;
    background: var(--accent-dim);
    color: var(--bg);
    padding: 2px 6px;
    border-radius: var(--r-full);
    line-height: 1.2;
  }

  .aggregate-cost {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 600;
    color: var(--text-secondary);
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

  /* Stats row */
  .stats-row {
    display: flex;
    align-items: center;
    gap: var(--sp-md);
    padding: var(--sp-sm) var(--sp-lg);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
    flex-wrap: wrap;
  }

  .stat {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1px;
  }

  .stat-value {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 700;
    color: var(--text-primary);
  }

  .stat-label {
    font-family: var(--font-mono);
    font-size: 0.55rem;
    font-weight: 500;
    color: var(--text-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .health-indicator {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 700;
    padding: 2px 8px;
    border-radius: var(--r-sm);
  }

  .health-good {
    color: var(--allow);
    background: rgba(77, 217, 115, 0.1);
  }

  .health-warn {
    color: #eab308;
    background: rgba(234, 179, 8, 0.1);
  }

  .health-bad {
    color: var(--deny);
    background: rgba(248, 113, 113, 0.1);
  }

  .health-empty {
    color: var(--text-tertiary);
    background: rgba(200, 200, 210, 0.1);
  }

  /* Panel body */
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

  /* Worker cards */
  .worker-card {
    margin-bottom: var(--sp-sm);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    overflow: hidden;
  }

  .worker-header {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    width: 100%;
    padding: var(--sp-sm) var(--sp-md);
    background: transparent;
    border: none;
    cursor: pointer;
    text-align: left;
    color: var(--text-primary);
    transition: background 0.15s;
  }

  .worker-header:hover {
    background: var(--surface-hover);
  }

  .expand-icon {
    font-size: 0.55rem;
    color: var(--text-tertiary);
    flex-shrink: 0;
    width: 10px;
  }

  .health-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .dot-healthy {
    background: var(--allow);
    box-shadow: 0 0 4px var(--allow);
  }

  .dot-unhealthy {
    background: var(--deny);
    box-shadow: 0 0 4px var(--deny);
  }

  .worker-name {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex: 1;
    min-width: 0;
  }

  .worker-sessions {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--text-tertiary);
    flex-shrink: 0;
  }

  .restart-badge {
    font-family: var(--font-mono);
    font-size: 0.55rem;
    font-weight: 700;
    color: #eab308;
    background: rgba(234, 179, 8, 0.15);
    padding: 1px 5px;
    border-radius: var(--r-sm);
    flex-shrink: 0;
  }

  .worker-meta {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: 0 var(--sp-md) var(--sp-xs);
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--text-tertiary);
    padding-left: calc(var(--sp-md) + 10px + var(--sp-sm) + 8px + var(--sp-sm));
  }

  .meta-uptime {
    color: var(--text-tertiary);
  }

  .meta-cost {
    color: var(--text-secondary);
  }

  /* Session rows within worker */
  .worker-sessions-list {
    border-top: 1px solid var(--border);
    padding: var(--sp-xs);
  }

  .no-sessions {
    padding: var(--sp-sm);
    text-align: center;
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-tertiary);
  }

  .session-row {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    width: 100%;
    padding: var(--sp-xs) var(--sp-sm);
    background: transparent;
    border: none;
    border-radius: 3px;
    cursor: pointer;
    text-align: left;
    color: var(--text-primary);
    transition: background 0.15s;
    font-family: var(--font-mono);
    font-size: 0.7rem;
  }

  .session-row:hover {
    background: var(--surface-hover);
  }

  .session-row.session-active {
    background: rgba(77, 217, 115, 0.06);
    border: 1px solid rgba(77, 217, 115, 0.2);
  }

  .session-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    flex-shrink: 0;
    background: var(--text-tertiary);
  }

  .session-dot.dot-active {
    background: var(--allow);
  }

  .session-dot.dot-idle {
    background: #eab308;
  }

  .session-dot.dot-closed {
    background: var(--text-tertiary);
  }

  .session-id {
    font-weight: 600;
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .session-cost {
    color: var(--text-secondary);
    font-size: 0.65rem;
    flex-shrink: 0;
  }

  .session-turns {
    color: var(--text-tertiary);
    font-size: 0.6rem;
    flex-shrink: 0;
  }
</style>
