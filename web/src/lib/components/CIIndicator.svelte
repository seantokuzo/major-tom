<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  function toggle() {
    relay.toggleCIPanel();
  }

  let badgeCount = $derived(
    relay.ciRuns.filter(
      (r) =>
        r.status === 'in_progress' ||
        r.status === 'queued' ||
        (r.conclusion !== '' && r.conclusion !== 'success')
    ).length
  );

  let badgeColor = $derived.by(() => {
    const runs = relay.ciRuns;
    if (runs.length === 0) return 'none';
    const hasFailed = runs.some(r => r.conclusion !== '' && r.conclusion !== 'success');
    if (hasFailed) return 'failure';
    const hasInProgress = runs.some(r => r.status === 'in_progress' || r.status === 'queued');
    if (hasInProgress) return 'in-progress';
    const allSucceeded = runs.every(r => r.conclusion === 'success');
    if (allSucceeded) return 'success';
    return 'none';
  });
</script>

{#if relay.isConnected && relay.hasSession}
  <button
    class="ci-indicator"
    onclick={toggle}
    title="CI Runs"
  >
    <span class="ci-icon">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
        <path d="M8 0a8 8 0 110 16A8 8 0 018 0zm0 1.5a6.5 6.5 0 100 13 6.5 6.5 0 000-13zM6.5 5a1 1 0 011.04.037l4 2.75a1 1 0 010 1.652l-4 2.75A1 1 0 016 11.25v-5.5A1 1 0 016.5 5z"/>
      </svg>
    </span>
    {#if badgeCount > 0}
      <span class="ci-count {badgeColor}">{badgeCount}</span>
    {:else}
      <span class="ci-label">CI</span>
    {/if}
  </button>
{/if}

<style>
  .ci-indicator {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text-secondary);
    padding: 3px 8px;
    border-radius: 4px;
    cursor: pointer;
    font-family: var(--font-mono, monospace);
    font-size: 0.65rem;
    line-height: 1;
    transition: all 0.15s;
    white-space: nowrap;
  }
  .ci-indicator:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
    border-color: var(--accent);
  }
  .ci-icon {
    display: flex;
    align-items: center;
  }
  .ci-label {
    font-size: 0.65rem;
  }
  .ci-count {
    font-size: 0.6rem;
    font-weight: 700;
    padding: 0 5px;
    border-radius: 8px;
    line-height: 1.4;
  }
  .ci-count.success {
    background: rgba(35, 134, 54, 0.2);
    color: #238636;
  }
  .ci-count.failure {
    background: rgba(218, 54, 51, 0.2);
    color: #da3633;
  }
  .ci-count.in-progress {
    background: rgba(210, 153, 34, 0.2);
    color: #d29922;
  }
  .ci-count.none {
    background: var(--surface-hover);
  }
</style>
