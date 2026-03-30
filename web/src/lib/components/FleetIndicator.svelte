<script lang="ts">
  import { fleetStore } from '../stores/fleet.svelte';
  import { relay } from '../stores/relay.svelte';

  // Request fleet status whenever we're connected (for the indicator badge)
  // Poll at a slow rate (30s) just for the indicator; FleetPanel polls at 5s when open
  let indicatorTimer: ReturnType<typeof setInterval> | null = null;

  $effect(() => {
    if (relay.isConnected && !fleetStore.panelOpen) {
      // Initial fetch
      relay.requestFleetStatus();
      // Slow poll for indicator only
      indicatorTimer = setInterval(() => {
        if (relay.isConnected && !fleetStore.panelOpen) {
          relay.requestFleetStatus();
        }
      }, 30_000);
      return () => {
        if (indicatorTimer) {
          clearInterval(indicatorTimer);
          indicatorTimer = null;
        }
      };
    }
  });

  const healthColor = $derived(
    fleetStore.health === 'healthy' ? 'var(--allow)' :
    fleetStore.health === 'degraded' ? '#eab308' :
    fleetStore.health === 'critical' ? 'var(--deny)' :
    'var(--text-tertiary)'
  );
</script>

{#if relay.isConnected}
  <button
    class="fleet-indicator"
    class:has-workers={fleetStore.totalWorkers > 0}
    onclick={() => fleetStore.togglePanel()}
    title="Fleet: {fleetStore.totalWorkers} worker{fleetStore.totalWorkers !== 1 ? 's' : ''}"
    aria-label="Toggle fleet panel"
  >
    <span class="fleet-dot" style:background={healthColor}></span>
    {#if fleetStore.totalWorkers > 0}
      <span class="fleet-count">{fleetStore.totalWorkers}</span>
    {/if}
  </button>
{/if}

<style>
  .fleet-indicator {
    display: flex;
    align-items: center;
    gap: 4px;
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text-secondary);
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 600;
    cursor: pointer;
    padding: 3px 8px;
    border-radius: var(--r-sm);
    transition: all 0.15s;
    line-height: 1;
  }

  .fleet-indicator:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
    border-color: var(--accent);
  }

  .fleet-indicator.has-workers {
    border-color: rgba(77, 217, 115, 0.3);
  }

  .fleet-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .fleet-count {
    min-width: 8px;
    text-align: center;
  }
</style>
