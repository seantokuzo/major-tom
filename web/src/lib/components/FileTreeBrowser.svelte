<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { contextStore } from '../stores/context.svelte';
  import type { FileNode } from '../protocol/messages';

  let { open = $bindable(false), onclose }: { open: boolean; onclose: () => void } = $props();

  let expandedDirs = $state<Set<string>>(new Set());
  let selectedFiles = $state<Set<string>>(new Set());

  // Request tree when opened
  $effect(() => {
    if (open) {
      relay.requestWorkspaceTree();
      selectedFiles = new Set();
      expandedDirs = new Set();
    }
  });

  function toggleDir(path: string) {
    const next = new Set(expandedDirs);
    if (next.has(path)) {
      next.delete(path);
    } else {
      next.add(path);
    }
    expandedDirs = next;
  }

  function toggleFile(path: string) {
    const next = new Set(selectedFiles);
    if (next.has(path)) {
      next.delete(path);
    } else {
      next.add(path);
    }
    selectedFiles = next;
  }

  function addSelected() {
    for (const path of selectedFiles) {
      if (!contextStore.isFileAttached(path)) {
        relay.addContext(path);
      }
    }
    close();
  }

  function close() {
    open = false;
    onclose();
  }

  function handleBackdropKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      close();
    }
  }
</script>

{#snippet treeNode(node: FileNode, depth: number)}
  {#if node.isDirectory}
    <button
      class="tree-item tree-dir"
      style="padding-left: {12 + depth * 16}px"
      onclick={() => toggleDir(node.path)}
    >
      <span class="tree-icon">{expandedDirs.has(node.path) ? '\u25BE' : '\u25B8'}</span>
      <span class="tree-name">{node.name}/</span>
    </button>
    {#if expandedDirs.has(node.path) && node.children}
      {#each node.children as child (child.path)}
        {@render treeNode(child, depth + 1)}
      {/each}
    {/if}
  {:else}
    <button
      class="tree-item tree-file"
      class:tree-selected={selectedFiles.has(node.path)}
      class:tree-attached={contextStore.isFileAttached(node.path)}
      style="padding-left: {12 + depth * 16}px"
      onclick={() => toggleFile(node.path)}
      disabled={contextStore.isFileAttached(node.path)}
    >
      <span class="tree-checkbox">
        {#if contextStore.isFileAttached(node.path)}
          &#x2713;
        {:else if selectedFiles.has(node.path)}
          &#x25A0;
        {:else}
          &#x25A1;
        {/if}
      </span>
      <span class="tree-name">{node.name}</span>
    </button>
  {/if}
{/snippet}

{#if open}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="tree-backdrop" onclick={close} onkeydown={handleBackdropKeydown} role="presentation">
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <!-- svelte-ignore a11y_interactive_supports_focus -->
    <div class="tree-panel" onclick={(e) => e.stopPropagation()} onkeydown={handleBackdropKeydown} role="dialog" aria-label="File browser" aria-modal="true">
      <div class="tree-header">
        <span class="tree-title">Workspace Files</span>
        <button class="tree-close" onclick={close} aria-label="Close">&times;</button>
      </div>

      <div class="tree-body">
        {#if contextStore.isLoadingTree}
          <div class="tree-loading">
            <span class="spinner"></span>
            Loading file tree...
          </div>
        {:else if contextStore.treeCache.length === 0}
          <div class="tree-empty">No files found</div>
        {:else}
          {#each contextStore.treeCache as node (node.path)}
            {@render treeNode(node, 0)}
          {/each}
        {/if}
      </div>

      <div class="tree-footer">
        <span class="tree-context-size">
          {contextStore.formattedSize} / {contextStore.maxSizeFormatted}
        </span>
        <button
          class="tree-add-btn"
          onclick={addSelected}
          disabled={selectedFiles.size === 0}
        >
          Add {selectedFiles.size} file{selectedFiles.size !== 1 ? 's' : ''} to context
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .tree-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding-top: 10vh;
    z-index: 100;
  }

  .tree-panel {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    width: 90%;
    max-width: 500px;
    max-height: 70vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
  }

  .tree-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--sp-md) var(--sp-lg);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .tree-title {
    font-family: var(--font-mono);
    font-size: 0.9rem;
    font-weight: 600;
    color: var(--text-primary);
  }

  .tree-close {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    font-size: 1.2rem;
    cursor: pointer;
    padding: 0 4px;
  }
  .tree-close:hover {
    color: var(--text-primary);
  }

  .tree-body {
    flex: 1;
    overflow-y: auto;
    min-height: 0;
  }

  .tree-loading,
  .tree-empty {
    padding: var(--sp-xl);
    text-align: center;
    color: var(--text-tertiary);
    font-size: 0.85rem;
  }

  .tree-loading {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--sp-sm);
  }

  .spinner {
    display: inline-block;
    width: 14px;
    height: 14px;
    border: 2px solid var(--border);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .tree-item {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    width: 100%;
    padding: 4px var(--sp-md);
    background: transparent;
    border: none;
    cursor: pointer;
    text-align: left;
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    transition: background 0.1s;
  }

  .tree-item:hover:not(:disabled) {
    background: var(--surface-hover);
  }

  .tree-dir {
    color: var(--accent);
    font-weight: 500;
  }

  .tree-icon {
    font-size: 0.7rem;
    width: 10px;
    text-align: center;
    flex-shrink: 0;
  }

  .tree-checkbox {
    font-size: 0.75rem;
    width: 14px;
    text-align: center;
    flex-shrink: 0;
    color: var(--text-secondary);
  }

  .tree-selected .tree-checkbox {
    color: var(--accent);
  }

  .tree-attached {
    opacity: 0.5;
  }

  .tree-attached .tree-checkbox {
    color: var(--text-success, #4ade80);
  }

  .tree-name {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .tree-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--sp-sm) var(--sp-lg);
    border-top: 1px solid var(--border);
    flex-shrink: 0;
  }

  .tree-context-size {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-tertiary);
  }

  .tree-add-btn {
    padding: 6px 12px;
    border-radius: var(--r-sm);
    border: 1px solid var(--accent);
    background: transparent;
    color: var(--accent);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.15s;
  }

  .tree-add-btn:hover:not(:disabled) {
    background: var(--accent);
    color: #000;
  }

  .tree-add-btn:disabled {
    opacity: 0.4;
    cursor: default;
    border-color: var(--border);
    color: var(--text-tertiary);
  }
</style>
