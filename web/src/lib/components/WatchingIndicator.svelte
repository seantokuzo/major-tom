<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { presenceStore } from '../stores/presence.svelte';
  import PresenceAvatars from './PresenceAvatars.svelte';

  const watchers = $derived(
    relay.sessionId
      ? presenceStore.watchersFor(relay.sessionId).filter(u => u.userId !== relay.user?.userId)
      : []
  );
</script>

{#if watchers.length > 0}
  <div class="watching-bar">
    <PresenceAvatars users={watchers} maxShow={3} size="sm" />
    <span class="watching-text">
      {#if watchers.length === 1}
        {watchers[0].name ?? watchers[0].email.split('@')[0]} is watching
      {:else}
        {watchers.length} others watching
      {/if}
    </span>
  </div>
{/if}

<style>
  .watching-bar {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: var(--sp-xs) var(--sp-md);
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .watching-text {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-tertiary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
