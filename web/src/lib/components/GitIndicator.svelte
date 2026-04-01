<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  function toggle() {
    relay.toggleGitPanel();
  }
</script>

{#if relay.isConnected && relay.hasSession}
  <button
    class="git-indicator"
    onclick={toggle}
    title="Git status"
  >
    <span class="git-icon">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
        <path d="M9.5 3.25a2.25 2.25 0 1 1 3 2.122V6A2.5 2.5 0 0 1 10 8.5H6a1 1 0 0 0-1 1v1.128a2.251 2.251 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.5 0v1.836A2.493 2.493 0 0 1 6 7h4a1 1 0 0 0 1-1v-.628A2.25 2.25 0 0 1 9.5 3.25Z"/>
      </svg>
    </span>
    {#if relay.gitBranch}
      <span class="git-branch">{relay.gitBranch}</span>
    {/if}
  </button>
{/if}

<style>
  .git-indicator {
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
    max-width: 120px;
  }
  .git-indicator:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
    border-color: var(--accent);
  }
  .git-icon {
    display: flex;
    align-items: center;
  }
  .git-branch {
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
