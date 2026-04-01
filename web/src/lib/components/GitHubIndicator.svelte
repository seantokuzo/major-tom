<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  function toggle() {
    relay.toggleGitHubPanel();
  }

  let prCount = $derived(relay.githubPullRequests.length);
</script>

{#if relay.isConnected && relay.hasSession}
  <button
    class="github-indicator"
    onclick={toggle}
    title="GitHub PRs & Issues"
  >
    <span class="github-icon">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
        <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/>
      </svg>
    </span>
    {#if prCount > 0}
      <span class="pr-count">{prCount}</span>
    {:else}
      <span class="pr-label">PRs</span>
    {/if}
  </button>
{/if}

<style>
  .github-indicator {
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
  .github-indicator:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
    border-color: var(--accent);
  }
  .github-icon {
    display: flex;
    align-items: center;
  }
  .pr-label {
    font-size: 0.65rem;
  }
  .pr-count {
    font-size: 0.6rem;
    font-weight: 700;
    background: var(--surface-hover);
    padding: 0 5px;
    border-radius: 8px;
    line-height: 1.4;
  }
</style>
