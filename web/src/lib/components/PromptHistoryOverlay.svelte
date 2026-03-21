<script lang="ts">
  import { promptHistory, type HistoryEntry } from '../stores/prompt-history.svelte';

  let {
    open = $bindable(false),
    onClose,
    onSelectEntry,
  }: {
    open: boolean;
    onClose: () => void;
    onSelectEntry: (text: string) => void;
  } = $props();

  let searchText = $state('');
  let selectedIndex = $state(0);
  let inputEl = $state<HTMLInputElement | undefined>(undefined);

  let filteredEntries = $derived.by(() => {
    return promptHistory.search(searchText);
  });

  function selectEntry(entry: HistoryEntry) {
    onSelectEntry(entry.text);
    close();
  }

  function close() {
    searchText = '';
    selectedIndex = 0;
    open = false;
    onClose();
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      close();
      return;
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (filteredEntries.length > 0) {
        selectedIndex = Math.min(selectedIndex + 1, filteredEntries.length - 1);
      }
      return;
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (filteredEntries.length > 0) {
        selectedIndex = Math.max(selectedIndex - 1, 0);
      }
      return;
    }
    if (e.key === 'Enter') {
      e.preventDefault();
      const entry = filteredEntries[selectedIndex];
      if (entry) selectEntry(entry);
      return;
    }
  }

  function handleOverlayKeydown(e: KeyboardEvent) {
    if (['ArrowDown', 'ArrowUp', 'Enter'].includes(e.key)) {
      e.stopPropagation();
    }
  }

  function formatTimestamp(iso: string): string {
    try {
      const date = new Date(iso);
      const now = new Date();
      const diffMs = now.getTime() - date.getTime();
      const diffMins = Math.floor(diffMs / 60000);
      if (diffMins < 1) return 'just now';
      if (diffMins < 60) return `${diffMins}m ago`;
      const diffHours = Math.floor(diffMins / 60);
      if (diffHours < 24) return `${diffHours}h ago`;
      const diffDays = Math.floor(diffHours / 24);
      if (diffDays < 7) return `${diffDays}d ago`;
      return date.toLocaleDateString();
    } catch {
      return '';
    }
  }

  function truncateText(text: string, maxLen = 80): string {
    if (text.length <= maxLen) return text;
    return text.slice(0, maxLen) + '...';
  }

  // Reset selection when filter changes
  $effect(() => {
    filteredEntries.length;
    selectedIndex = 0;
  });

  // Focus input when opened
  $effect(() => {
    if (open) {
      queueMicrotask(() => inputEl?.focus());
    }
  });
</script>

{#if open}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="history-backdrop" onclick={close} onkeydown={handleKeydown} role="presentation">
    <div class="history-panel" onclick={(e) => e.stopPropagation()} onkeydown={handleOverlayKeydown} role="dialog" aria-label="Prompt history" aria-modal="true">
      <div class="history-header">
        <input
          bind:this={inputEl}
          bind:value={searchText}
          class="history-search"
          placeholder="Search history..."
          onkeydown={handleKeydown}
        />
      </div>
      <div class="history-list">
        {#each filteredEntries as entry, i (entry.text)}
          <button
            class="history-item"
            class:selected={i === selectedIndex}
            onclick={() => selectEntry(entry)}
            onmouseenter={() => selectedIndex = i}
          >
            <span class="entry-text">{truncateText(entry.text)}</span>
            <span class="entry-meta">
              <span class="entry-time">{formatTimestamp(entry.timestamp)}</span>
              {#if entry.count > 1}
                <span class="entry-count">{entry.count}x</span>
              {/if}
            </span>
          </button>
        {/each}
        {#if filteredEntries.length === 0}
          <div class="history-empty">
            {#if searchText}
              No matching history
            {:else}
              No prompt history yet
            {/if}
          </div>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .history-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: flex-end;
    justify-content: center;
    padding-bottom: 60px;
    z-index: 100;
  }

  .history-panel {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    width: 90%;
    max-width: 420px;
    max-height: 50vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
  }

  .history-header {
    padding: var(--sp-md) var(--sp-lg);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .history-search {
    width: 100%;
    background: transparent;
    border: none;
    outline: none;
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.9rem;
  }
  .history-search::placeholder {
    color: var(--text-tertiary);
  }

  .history-list {
    overflow-y: auto;
    flex: 1;
    min-height: 0;
  }

  .history-item {
    display: flex;
    flex-direction: column;
    gap: 2px;
    width: 100%;
    padding: var(--sp-sm) var(--sp-lg);
    background: transparent;
    border: none;
    cursor: pointer;
    text-align: left;
    color: var(--text-primary);
    transition: background 0.1s;
  }

  .history-item.selected,
  .history-item:hover {
    background: var(--surface-hover);
  }

  .entry-text {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    line-height: 1.4;
    word-break: break-word;
  }

  .entry-meta {
    display: flex;
    gap: var(--sp-sm);
    align-items: center;
  }

  .entry-time {
    font-size: 0.7rem;
    color: var(--text-tertiary);
  }

  .entry-count {
    font-size: 0.7rem;
    color: var(--accent);
    font-weight: 600;
  }

  .history-empty {
    padding: var(--sp-lg);
    text-align: center;
    font-size: 0.8rem;
    color: var(--text-tertiary);
  }
</style>
