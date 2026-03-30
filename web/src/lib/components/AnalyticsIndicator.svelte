<script lang="ts">
  import { analyticsStore } from '../stores/analytics.svelte';
  import { relay } from '../stores/relay.svelte';

  // Fetch 24h indicator cost on connect, poll every 60s
  $effect(() => {
    if (!relay.isConnected) return;

    void analyticsStore.fetchIndicatorCost();
    const timer = setInterval(() => {
      if (relay.isConnected) {
        void analyticsStore.fetchIndicatorCost();
      }
    }, 60_000);
    return () => clearInterval(timer);
  });

  function formatCost(cost: number): string {
    if (cost === 0) return '$0.00';
    if (cost < 0.01) return `$${cost.toFixed(4)}`;
    return `$${cost.toFixed(2)}`;
  }
</script>

{#if relay.isConnected}
  <button
    class="analytics-indicator"
    onclick={() => analyticsStore.togglePanel()}
    title="Analytics: {formatCost(analyticsStore.indicatorCost)} today"
    aria-label="Toggle analytics panel"
  >
    <span class="analytics-icon">$</span>
    <span class="analytics-cost">{formatCost(analyticsStore.indicatorCost)}</span>
  </button>
{/if}

<style>
  .analytics-indicator {
    display: flex;
    align-items: center;
    gap: 3px;
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

  .analytics-indicator:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
    border-color: var(--accent);
  }

  .analytics-icon {
    font-size: 0.7rem;
    color: var(--accent);
  }

  .analytics-cost {
    min-width: 20px;
    text-align: center;
  }
</style>
