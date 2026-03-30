<script lang="ts">
  import { achievementStore } from '../stores/achievements.svelte';
  import { relay } from '../stores/relay.svelte';

  // Fetch achievement count on connect, poll every 60s
  $effect(() => {
    if (!relay.isConnected) return;

    // Load cached data from IndexedDB for instant display, then fetch fresh data
    void achievementStore.loadFromCache();
    void achievementStore.fetchIndicatorCount();

    const timer = setInterval(() => {
      if (relay.isConnected && !achievementStore.panelOpen) {
        void achievementStore.fetchIndicatorCount();
      }
    }, 60_000);
    return () => clearInterval(timer);
  });
</script>

{#if relay.isConnected}
  <button
    class="achievement-indicator"
    class:has-pulse={achievementStore.recentUnlock}
    onclick={() => achievementStore.togglePanel()}
    title="Achievements: {achievementStore.unlockedCount}/{achievementStore.totalCount} unlocked"
    aria-label="Toggle achievement panel"
  >
    <span class="achievement-icon">&#127942;</span>
    <span class="achievement-count">{achievementStore.unlockedCount}</span>
  </button>
{/if}

<style>
  .achievement-indicator {
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

  .achievement-indicator:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
    border-color: var(--accent);
  }

  .achievement-indicator.has-pulse {
    animation: achievement-pulse 0.6s ease-in-out 3;
    border-color: #eab308;
  }

  .achievement-icon {
    font-size: 0.75rem;
    line-height: 1;
  }

  .achievement-count {
    min-width: 8px;
    text-align: center;
  }

  @keyframes achievement-pulse {
    0%, 100% {
      box-shadow: 0 0 0 0 rgba(234, 179, 8, 0);
    }
    50% {
      box-shadow: 0 0 8px 2px rgba(234, 179, 8, 0.4);
    }
  }
</style>
