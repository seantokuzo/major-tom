<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  let costDisplay = $derived(
    relay.sessionStats.totalCost > 0
      ? `$${relay.sessionStats.totalCost.toFixed(2)}`
      : '$0.00'
  );

  let turnDisplay = $derived(
    relay.sessionStats.turnCount > 0
      ? `${relay.sessionStats.turnCount} turn${relay.sessionStats.turnCount !== 1 ? 's' : ''}`
      : '0 turns'
  );
</script>

{#if relay.hasSession}
  <div class="session-info">
    <span class="info-item cost">{costDisplay}</span>
    <span class="separator">|</span>
    <span class="info-item turns">{turnDisplay}</span>
  </div>
{/if}

<style>
  .session-info {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: 2px var(--sp-lg);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
    background: rgba(10, 10, 15, 0.5);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .separator {
    color: var(--border);
  }

  .cost {
    color: var(--accent);
  }

  .turns {
    color: var(--text-tertiary);
  }
</style>
