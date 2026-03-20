<script lang="ts">
  import CostDisplay from './CostDisplay.svelte';
</script>

<div class="session-bar">
  <CostDisplay />
</div>

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
