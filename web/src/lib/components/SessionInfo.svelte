<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import CostDisplay from './CostDisplay.svelte';
</script>

{#if relay.hasSession}
  <div class="session-bar">
    <CostDisplay />
  </div>
{/if}

<style>
  .session-bar {
    display: flex;
    align-items: center;
    padding: 0 var(--sp-sm);
    background: rgba(10, 10, 15, 0.5);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
    min-height: 22px;
  }
</style>
