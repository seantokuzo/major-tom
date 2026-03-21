<script lang="ts">
  import { templates } from '../stores/templates.svelte';
  import { toasts } from '../stores/toast.svelte';

  let {
    open = $bindable(false),
    onclose,
    initialContent = '',
  }: {
    open: boolean;
    onclose: () => void;
    initialContent: string;
  } = $props();

  let name = $state('');
  let category = $state('');
  let content = $state('');
  let showCategorySuggestions = $state(false);
  let nameInputEl = $state<HTMLInputElement | undefined>(undefined);

  let filteredCategories = $derived.by(() => {
    const q = category.toLowerCase().trim();
    if (!q) return templates.categories;
    return templates.categories.filter((c) => c.toLowerCase().includes(q));
  });

  // Reset form when opened
  $effect(() => {
    if (open) {
      name = '';
      category = '';
      content = initialContent;
      showCategorySuggestions = false;
      queueMicrotask(() => nameInputEl?.focus());
    }
  });

  function handleSave() {
    const trimmedName = name.trim();
    if (!trimmedName) return;
    if (!content.trim()) return;

    if (templates.atLimit) {
      toasts.warning(`Template limit reached (${templates.count}/100). Delete some to add more.`);
      return;
    }

    const result = templates.add(trimmedName, content, category || undefined);
    if (result) {
      toasts.success(`Template "${trimmedName}" saved`);
      close();
    } else {
      toasts.error('Failed to save template');
    }
  }

  function close() {
    open = false;
    onclose();
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      close();
    }
  }

  function selectCategory(cat: string) {
    category = cat;
    showCategorySuggestions = false;
  }
</script>

{#if open}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="dialog-backdrop" onclick={close} onkeydown={handleKeydown} role="presentation">
    <div class="dialog" onclick={(e) => e.stopPropagation()} role="dialog" aria-label="Save template" aria-modal="true">
      <div class="dialog-header">
        <h3 class="dialog-title">Save Template</h3>
        <button class="dialog-close" onclick={close} aria-label="Close">&times;</button>
      </div>

      <div class="dialog-body">
        <label class="field">
          <span class="field-label">Name *</span>
          <input
            bind:this={nameInputEl}
            bind:value={name}
            class="field-input"
            placeholder="e.g. Code Review"
            onkeydown={(e) => { if (e.key === 'Enter') handleSave(); }}
          />
        </label>

        <label class="field">
          <span class="field-label">Category</span>
          <div class="category-wrap">
            <input
              bind:value={category}
              class="field-input"
              placeholder="e.g. review, debug, refactor"
              onfocus={() => showCategorySuggestions = true}
              onblur={() => setTimeout(() => showCategorySuggestions = false, 150)}
            />
            {#if showCategorySuggestions && filteredCategories.length > 0}
              <div class="category-suggestions">
                {#each filteredCategories as cat (cat)}
                  <button
                    class="category-suggestion"
                    onmousedown|preventDefault={() => selectCategory(cat)}
                  >
                    {cat}
                  </button>
                {/each}
              </div>
            {/if}
          </div>
        </label>

        <label class="field">
          <span class="field-label">Content</span>
          <textarea
            bind:value={content}
            class="field-textarea"
            rows="4"
            placeholder="Prompt content..."
          ></textarea>
        </label>
      </div>

      <div class="dialog-footer">
        <button class="btn btn-cancel" onclick={close}>Cancel</button>
        <button
          class="btn btn-save"
          onclick={handleSave}
          disabled={!name.trim() || !content.trim()}
        >
          Save
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .dialog-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 110;
    padding: var(--sp-lg);
  }

  .dialog {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    width: 100%;
    max-width: 400px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
    overflow: hidden;
  }

  .dialog-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--sp-md) var(--sp-lg);
    border-bottom: 1px solid var(--border);
  }

  .dialog-title {
    font-family: var(--font-mono);
    font-size: 0.9rem;
    font-weight: 600;
    color: var(--accent);
  }

  .dialog-close {
    background: none;
    border: none;
    color: var(--text-tertiary);
    font-size: 1.2rem;
    cursor: pointer;
    padding: 0 2px;
    line-height: 1;
  }
  .dialog-close:hover {
    color: var(--text-primary);
  }

  .dialog-body {
    padding: var(--sp-lg);
    display: flex;
    flex-direction: column;
    gap: var(--sp-md);
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: var(--sp-xs);
  }

  .field-label {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .field-input,
  .field-textarea {
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
  .field-input:focus,
  .field-textarea:focus {
    border-color: var(--accent);
  }
  .field-input::placeholder,
  .field-textarea::placeholder {
    color: var(--text-tertiary);
  }

  .field-textarea {
    resize: vertical;
    min-height: 80px;
    line-height: 1.5;
  }

  .category-wrap {
    position: relative;
  }

  .category-suggestions {
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    margin-top: 2px;
    z-index: 10;
    max-height: 120px;
    overflow-y: auto;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
  }

  .category-suggestion {
    display: block;
    width: 100%;
    padding: var(--sp-sm) var(--sp-md);
    background: transparent;
    border: none;
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    text-align: left;
    cursor: pointer;
  }
  .category-suggestion:hover {
    background: var(--surface-hover);
  }

  .dialog-footer {
    display: flex;
    justify-content: flex-end;
    gap: var(--sp-sm);
    padding: var(--sp-md) var(--sp-lg);
    border-top: 1px solid var(--border);
  }

  .btn {
    padding: var(--sp-sm) var(--sp-lg);
    border-radius: var(--r-sm);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    cursor: pointer;
    border: 1px solid var(--border);
    transition: all 0.15s;
  }

  .btn-cancel {
    background: transparent;
    color: var(--text-secondary);
  }
  .btn-cancel:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
  }

  .btn-save {
    background: var(--accent);
    color: #000;
    border-color: var(--accent);
  }
  .btn-save:hover:not(:disabled) {
    background: var(--accent-dim);
  }
  .btn-save:disabled {
    opacity: 0.4;
    cursor: default;
  }
</style>
