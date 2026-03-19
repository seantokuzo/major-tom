<script lang="ts">
  import { relay } from '../stores/relay.svelte';
</script>

{#if relay.isWaitingForResponse || relay.activeToolName}
  <div class="indicator">
    {#if relay.activeToolName}
      <span class="tool-indicator">
        <span class="tool-spinner"></span>
        Using {relay.activeToolName}...
      </span>
    {:else}
      <span class="thinking">
        <span class="dot"></span>
        <span class="dot"></span>
        <span class="dot"></span>
        Claude is thinking
      </span>
    {/if}
  </div>
{/if}

<style>
  .indicator {
    padding: var(--sp-xs) var(--sp-lg);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    color: var(--text-tertiary);
  }

  .thinking {
    display: inline-flex;
    align-items: center;
    gap: 2px;
  }

  .dot {
    display: inline-block;
    width: 4px;
    height: 4px;
    border-radius: 50%;
    background: var(--accent);
    animation: pulse 1.4s ease-in-out infinite;
    margin-right: 1px;
  }
  .dot:nth-child(2) { animation-delay: 0.2s; }
  .dot:nth-child(3) { animation-delay: 0.4s; margin-right: var(--sp-sm); }

  @keyframes pulse {
    0%, 80%, 100% { opacity: 0.3; transform: scale(0.8); }
    40% { opacity: 1; transform: scale(1.2); }
  }

  .tool-indicator {
    display: inline-flex;
    align-items: center;
    gap: var(--sp-sm);
    color: var(--text-secondary);
  }

  .tool-spinner {
    display: inline-block;
    width: 10px;
    height: 10px;
    border: 2px solid var(--border);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }
</style>
