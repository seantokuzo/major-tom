<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  let expanded = $state(false);

  let costValue = $derived(relay.sessionStats.totalCost);

  let costText = $derived(
    costValue > 0 ? `$${costValue.toFixed(2)}` : '$0.00'
  );

  let costColor = $derived(
    costValue > 2.0 ? 'cost-high' :
    costValue > 0.5 ? 'cost-mid' :
    'cost-low'
  );

  function formatTokens(count: number): string {
    if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(1)}M`;
    if (count >= 1_000) return `${(count / 1_000).toFixed(1)}K`;
    return String(count);
  }

  let inputTokensText = $derived(formatTokens(relay.sessionStats.inputTokens));
  let outputTokensText = $derived(formatTokens(relay.sessionStats.outputTokens));
  let hasTokens = $derived(relay.sessionStats.inputTokens > 0 || relay.sessionStats.outputTokens > 0);

  let turnDisplay = $derived(
    relay.sessionStats.turnCount > 0
      ? `${relay.sessionStats.turnCount} turn${relay.sessionStats.turnCount !== 1 ? 's' : ''}`
      : '0 turns'
  );
</script>

{#if relay.hasSession}
  <button
    class="cost-display {costColor}"
    type="button"
    onclick={() => expanded = !expanded}
    title="Click for token breakdown"
    aria-expanded={expanded}
    aria-controls="cost-token-breakdown"
  >
    <span class="cost-value">{costText}</span>
    <span class="separator">|</span>
    <span class="turns">{turnDisplay}</span>

    {#if relay.isWaitingForResponse || relay.activeToolName}
      <span class="live-dot"></span>
    {/if}
  </button>

  {#if expanded}
    <div class="token-breakdown" id="cost-token-breakdown">
      {#if hasTokens}
        <span class="token-item">
          <span class="token-label">In:</span>
          <span class="token-count">{inputTokensText}</span>
        </span>
        <span class="token-sep">/</span>
        <span class="token-item">
          <span class="token-label">Out:</span>
          <span class="token-count">{outputTokensText}</span>
        </span>
      {:else}
        <span class="token-item no-data">No token data yet</span>
      {/if}
    </div>
  {/if}
{/if}

<style>
  .cost-display {
    display: inline-flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: 2px var(--sp-md);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    background: none;
    border: none;
    cursor: pointer;
    transition: opacity 0.15s;
    line-height: 1;
  }
  .cost-display:hover {
    opacity: 0.8;
  }

  .cost-value {
    font-weight: 700;
    letter-spacing: 0.02em;
  }

  .cost-low .cost-value { color: var(--allow); }
  .cost-mid .cost-value { color: var(--accent); }
  .cost-high .cost-value { color: var(--deny); }

  .separator {
    color: var(--border);
  }

  .turns {
    color: var(--text-tertiary);
  }

  .live-dot {
    width: 5px;
    height: 5px;
    border-radius: 50%;
    background: var(--accent);
    animation: live-pulse 1.2s ease-in-out infinite;
    flex-shrink: 0;
  }

  @keyframes live-pulse {
    0%, 100% { opacity: 0.3; }
    50% { opacity: 1; }
  }

  .token-breakdown {
    display: inline-flex;
    align-items: center;
    gap: var(--sp-xs);
    padding: 2px var(--sp-md);
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-tertiary);
  }

  .token-item {
    display: inline-flex;
    gap: 2px;
  }

  .token-label {
    color: var(--text-tertiary);
  }

  .token-count {
    color: var(--text-secondary);
    font-weight: 600;
  }

  .token-sep {
    color: var(--border);
  }

  .no-data {
    font-style: italic;
    color: var(--text-tertiary);
  }
</style>
