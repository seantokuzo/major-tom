<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { contextStore } from '../stores/context.svelte';

  function fileName(path: string): string {
    const parts = path.split('/');
    return parts[parts.length - 1] ?? path;
  }

  function removeFile(path: string) {
    relay.removeContext(path);
  }
</script>

{#if contextStore.contextFiles.length > 0}
  <div class="context-chips">
    <div class="chips-row">
      {#each contextStore.contextFiles as file (file.path)}
        <span class="chip" title={file.path}>
          <span class="chip-name">{fileName(file.path)}</span>
          <button class="chip-remove" onclick={() => removeFile(file.path)} aria-label="Remove {fileName(file.path)}">&times;</button>
        </span>
      {/each}
    </div>
    <span class="context-size-label">
      {contextStore.formattedSize} / {contextStore.maxSizeFormatted}
    </span>
  </div>
{/if}

<style>
  .context-chips {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: 4px var(--sp-md);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
    overflow: hidden;
  }

  .chips-row {
    display: flex;
    gap: 4px;
    flex: 1;
    overflow-x: auto;
    min-width: 0;
  }

  .chip {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    padding: 2px 6px;
    border-radius: var(--r-sm);
    background: rgba(100, 100, 255, 0.12);
    border: 1px solid rgba(100, 100, 255, 0.25);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--accent);
    white-space: nowrap;
    flex-shrink: 0;
  }

  .chip-name {
    max-width: 120px;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .chip-remove {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    font-size: 0.85rem;
    cursor: pointer;
    padding: 0 2px;
    line-height: 1;
  }
  .chip-remove:hover {
    color: var(--text-primary);
  }

  .context-size-label {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-tertiary);
    white-space: nowrap;
    flex-shrink: 0;
  }
</style>
