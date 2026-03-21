<script lang="ts">
  import { templates } from '../stores/templates.svelte';
  import { relay } from '../stores/relay.svelte';
  import { toasts } from '../stores/toast.svelte';

  let {
    open = $bindable(false),
    onClose,
  }: {
    open: boolean;
    onClose: () => void;
  } = $props();

  let searchQuery = $state('');
  let deleteConfirmId = $state<string | null>(null);
  let searchInputEl = $state<HTMLInputElement | undefined>(undefined);

  let results = $derived(templates.search(searchQuery));

  // Focus search when opened, reset state
  $effect(() => {
    if (open) {
      searchQuery = '';
      deleteConfirmId = null;
      queueMicrotask(() => searchInputEl?.focus());
    }
  });

  function selectTemplate(id: string) {
    const template = templates.use(id);
    if (template) {
      relay.inputText = template.content;
      toasts.info(`Loaded "${template.name}"`);
      close();
    }
  }

  function confirmDelete(id: string, e: Event) {
    e.stopPropagation();
    if (deleteConfirmId === id) {
      // Second tap — actually delete
      const tpl = templates.templates.find((t) => t.id === id);
      templates.delete(id);
      if (tpl) toasts.info(`Deleted "${tpl.name}"`);
      deleteConfirmId = null;
    } else {
      deleteConfirmId = id;
    }
  }

  function close() {
    open = false;
    onClose();
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      close();
    }
  }

  function truncate(text: string, max: number): string {
    if (text.length <= max) return text;
    return text.slice(0, max) + '...';
  }
</script>

{#if open}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="drawer-backdrop" onclick={close} onkeydown={handleKeydown} role="presentation">
    <div class="drawer" onclick={(e) => e.stopPropagation()} role="dialog" aria-label="Prompt templates" aria-modal="true">
      <div class="drawer-header">
        <h3 class="drawer-title">Templates</h3>
        <span class="drawer-count">{templates.count}/100</span>
        <button class="drawer-close" onclick={close} aria-label="Close">&times;</button>
      </div>

      <div class="drawer-search">
        <input
          bind:this={searchInputEl}
          bind:value={searchQuery}
          class="search-input"
          placeholder="Search templates..."
          onkeydown={handleKeydown}
        />
      </div>

      <div class="drawer-list">
        {#each results as tpl (tpl.id)}
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <div
            class="template-item"
            role="button"
            tabindex="0"
            onclick={() => selectTemplate(tpl.id)}
            onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); selectTemplate(tpl.id); } }}
          >
            <div class="template-header">
              <span class="template-name">{tpl.name}</span>
              {#if tpl.category}
                <span class="template-category">{tpl.category}</span>
              {/if}
            </div>
            <div class="template-preview">{truncate(tpl.content, 80)}</div>
            <div class="template-meta">
              <span class="template-uses">{tpl.usageCount} use{tpl.usageCount !== 1 ? 's' : ''}</span>
              <button
                class="template-delete"
                class:confirm={deleteConfirmId === tpl.id}
                onclick={(e) => confirmDelete(tpl.id, e)}
                aria-label={deleteConfirmId === tpl.id ? 'Confirm delete' : 'Delete template'}
              >
                {deleteConfirmId === tpl.id ? 'confirm?' : 'delete'}
              </button>
            </div>
          </div>
        {/each}
        {#if results.length === 0}
          <div class="drawer-empty">
            {searchQuery ? 'No matching templates' : 'No templates saved yet'}
          </div>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .drawer-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: flex-end;
    justify-content: center;
    z-index: 110;
  }

  .drawer {
    background: var(--surface);
    border: 1px solid var(--border);
    border-bottom: none;
    border-radius: var(--r-md) var(--r-md) 0 0;
    width: 100%;
    max-width: 500px;
    max-height: 70vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 -8px 32px rgba(0, 0, 0, 0.5);
    animation: drawer-slide-up 0.2s ease-out;
  }

  @keyframes drawer-slide-up {
    from {
      transform: translateY(100%);
    }
    to {
      transform: translateY(0);
    }
  }

  .drawer-header {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: var(--sp-md) var(--sp-lg);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .drawer-title {
    font-family: var(--font-mono);
    font-size: 0.9rem;
    font-weight: 600;
    color: var(--accent);
    flex: 1;
  }

  .drawer-count {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
  }

  .drawer-close {
    background: none;
    border: none;
    color: var(--text-tertiary);
    font-size: 1.2rem;
    cursor: pointer;
    padding: 0 2px;
    line-height: 1;
  }
  .drawer-close:hover {
    color: var(--text-primary);
  }

  .drawer-search {
    padding: var(--sp-sm) var(--sp-lg);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .search-input {
    width: 100%;
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: var(--sp-sm) var(--sp-md);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.85rem;
    outline: none;
    transition: border-color 0.15s;
  }
  .search-input:focus {
    border-color: var(--accent);
  }
  .search-input::placeholder {
    color: var(--text-tertiary);
  }

  .drawer-list {
    flex: 1;
    overflow-y: auto;
    padding: var(--sp-xs) 0;
  }

  .template-item {
    display: flex;
    flex-direction: column;
    gap: var(--sp-xs);
    width: 100%;
    padding: var(--sp-sm) var(--sp-lg);
    background: transparent;
    border: none;
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    text-align: left;
    color: var(--text-primary);
    transition: background 0.1s;
    outline: none;
  }
  .template-item:hover,
  .template-item:focus-visible {
    background: var(--surface-hover);
  }
  .template-item:last-child {
    border-bottom: none;
  }

  .template-header {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .template-name {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--text-primary);
  }

  .template-category {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--accent);
    background: rgba(212, 168, 83, 0.15);
    padding: 1px 6px;
    border-radius: var(--r-full);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .template-preview {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-secondary);
    line-height: 1.4;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .template-meta {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .template-uses {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-tertiary);
  }

  .template-delete {
    background: none;
    border: none;
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-tertiary);
    cursor: pointer;
    padding: 2px 4px;
  }
  .template-delete:hover {
    color: var(--deny);
  }
  .template-delete.confirm {
    color: var(--deny);
    font-weight: 600;
  }

  .drawer-empty {
    padding: var(--sp-xl);
    text-align: center;
    font-family: var(--font-mono);
    font-size: 0.8rem;
    color: var(--text-tertiary);
  }
</style>
