<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import ActivityFeed from './ActivityFeed.svelte';

  let open = $state(false);
</script>

{#if relay.isConnected}
  <button
    class="activity-btn"
    onclick={() => (open = !open)}
    title="Team Activity"
    aria-label="Toggle team activity feed"
  >
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path d="M8 2C4.69 2 2 4.69 2 8s2.69 6 6 6 6-2.69 6-6-2.69-6-6-6zm0 11c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm.5-8H7v4l3.5 2.1.5-.82-3-1.78V5z" fill="currentColor"/>
    </svg>
  </button>

  <ActivityFeed {open} onClose={() => (open = false)} />
{/if}

<style>
  .activity-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text-secondary);
    cursor: pointer;
    padding: 3px 8px;
    border-radius: var(--r-sm);
    transition: all 0.15s;
    line-height: 1;
  }

  .activity-btn:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
    border-color: var(--accent);
  }
</style>
