<script lang="ts">
  /**
   * KeybarCustomizeSheet — modal drawer for editing which keys appear on
   * the accessory row and specialty grid. Lets the user:
   *   - remove keys from either layout
   *   - reorder keys left/right
   *   - add keys from the full library
   *   - reset to defaults
   *
   * All mutations go through `keybarStore` which persists to localStorage.
   */
  import { keybarStore } from '../stores/keybar.svelte';
  import { KEY_LIBRARY, type KeySpec } from '../shell/keys';

  interface Props {
    open: boolean;
    onClose: () => void;
  }

  const { open, onClose }: Props = $props();

  /** Which layout is currently being edited. */
  let activeTab = $state<'accessory' | 'specialty'>('accessory');
  /** Text filter for the "add key" picker. */
  let filter = $state('');
  /**
   * Collapsed by default so the active-keys list gets the full sheet
   * height for reorder/remove. Expanding flips it into a disclosure
   * panel and the active list goes back to sharing the space.
   * State is scoped to the sheet's lifetime — reopening the sheet
   * resets to collapsed, which is the desired behavior (the sheet
   * unmounts when `open === false`).
   */
  let addListOpen = $state(false);

  const currentIds = $derived(
    activeTab === 'accessory' ? keybarStore.accessoryIds : keybarStore.specialtyIds
  );
  const currentKeys = $derived(
    activeTab === 'accessory' ? keybarStore.accessoryKeys : keybarStore.specialtyKeys
  );

  /** Keys from the library that aren't currently on the active layout, filtered by text. */
  const availableKeys = $derived.by<KeySpec[]>(() => {
    const ids = new Set(currentIds);
    const q = filter.trim().toLowerCase();
    return KEY_LIBRARY.filter((k) => {
      if (ids.has(k.id)) return false;
      if (!q) return true;
      return (
        k.id.toLowerCase().includes(q) ||
        k.label.toLowerCase().includes(q) ||
        (k.description ?? '').toLowerCase().includes(q)
      );
    });
  });

  function addKey(id: string): void {
    if (activeTab === 'accessory') keybarStore.addAccessoryKey(id);
    else keybarStore.addSpecialtyKey(id);
  }

  function removeKey(id: string): void {
    if (activeTab === 'accessory') keybarStore.removeAccessoryKey(id);
    else keybarStore.removeSpecialtyKey(id);
  }

  function moveKey(id: string, direction: -1 | 1): void {
    if (activeTab === 'accessory') keybarStore.moveAccessoryKey(id, direction);
    else keybarStore.moveSpecialtyKey(id, direction);
  }

  function resetAll(): void {
    if (typeof window !== 'undefined') {
      const ok = window.confirm('Reset all keybar layouts to defaults?');
      if (!ok) return;
    }
    keybarStore.resetToDefaults();
  }
</script>

{#if open}
  <div
    class="kb-customize-backdrop"
    role="presentation"
    onpointerdown={(e) => {
      if (e.target === e.currentTarget) onClose();
    }}
  >
    <div
      class="kb-customize-sheet"
      role="dialog"
      aria-label="Customize keybar"
      aria-modal="true"
    >
      <header class="sheet-header">
        <div class="sheet-title">Customize keys</div>
        <button type="button" class="close-btn" onpointerdown={(e) => { e.preventDefault(); onClose(); }}>
          ✕
        </button>
      </header>

      <div class="tabs">
        <button
          type="button"
          class="tab"
          class:active={activeTab === 'accessory'}
          onpointerdown={(e) => { e.preventDefault(); activeTab = 'accessory'; }}
        >
          Accessory row
        </button>
        <button
          type="button"
          class="tab"
          class:active={activeTab === 'specialty'}
          onpointerdown={(e) => { e.preventDefault(); activeTab = 'specialty'; }}
        >
          Specialty grid
        </button>
      </div>

      <section class="active-list" class:expanded={!addListOpen}>
        <div class="section-title">Active ({currentKeys.length})</div>
        {#if currentKeys.length === 0}
          <div class="empty">No keys — add some below.</div>
        {/if}
        <ul>
          {#each currentKeys as spec, idx (spec.id)}
            <li data-active-key-id={spec.id}>
              <span class="row-label">
                <span class="label-glyph">{spec.label}</span>
                <span class="label-desc">{spec.description ?? spec.id}</span>
              </span>
              <div class="row-actions">
                <button
                  type="button"
                  class="icon-btn"
                  aria-label="Move up"
                  disabled={idx === 0}
                  onpointerdown={(e) => { e.preventDefault(); moveKey(spec.id, -1); }}
                >↑</button>
                <button
                  type="button"
                  class="icon-btn"
                  aria-label="Move down"
                  disabled={idx === currentKeys.length - 1}
                  onpointerdown={(e) => { e.preventDefault(); moveKey(spec.id, 1); }}
                >↓</button>
                <button
                  type="button"
                  class="icon-btn danger"
                  aria-label="Remove"
                  data-remove-id={spec.id}
                  onpointerdown={(e) => { e.preventDefault(); removeKey(spec.id); }}
                >−</button>
              </div>
            </li>
          {/each}
        </ul>
      </section>

      <section class="add-list" class:open={addListOpen}>
        <button
          type="button"
          class="add-toggle"
          aria-expanded={addListOpen}
          aria-controls="kb-add-list-body"
          onpointerdown={(e) => { e.preventDefault(); }}
          onclick={() => { addListOpen = !addListOpen; }}
        >
          <span class="section-title add-title">Add a key</span>
          <span class="chevron" aria-hidden="true">{addListOpen ? '▾' : '▸'}</span>
        </button>
        {#if addListOpen}
          <div id="kb-add-list-body" class="add-body">
            <input
              type="text"
              name="keybar-filter"
              class="filter-input"
              placeholder="Filter…"
              bind:value={filter}
            />
            <ul>
              {#each availableKeys as spec (spec.id)}
                <li data-available-key-id={spec.id}>
                  <span class="row-label">
                    <span class="label-glyph">{spec.label}</span>
                    <span class="label-desc">{spec.description ?? spec.id}</span>
                  </span>
                  <button
                    type="button"
                    class="icon-btn accent"
                    aria-label="Add"
                    onpointerdown={(e) => { e.preventDefault(); addKey(spec.id); }}
                  >+</button>
                </li>
              {/each}
              {#if availableKeys.length === 0}
                <li class="empty">All library keys are already active.</li>
              {/if}
            </ul>
          </div>
        {/if}
      </section>

      <footer class="sheet-footer">
        <button type="button" class="footer-btn danger" onpointerdown={(e) => { e.preventDefault(); resetAll(); }}>
          Reset to defaults
        </button>
        <button type="button" class="footer-btn primary" onpointerdown={(e) => { e.preventDefault(); onClose(); }}>
          Done
        </button>
      </footer>
    </div>
  </div>
{/if}

<style>
  .kb-customize-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    z-index: 200;
    display: flex;
    align-items: flex-end;
    justify-content: center;
  }

  .kb-customize-sheet {
    width: 100%;
    max-width: 560px;
    max-height: 85vh;
    background: #111116;
    border-top: 1px solid #25252c;
    border-radius: 12px 12px 0 0;
    display: flex;
    flex-direction: column;
    color: #e0e0e8;
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
  }

  .sheet-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 14px;
    border-bottom: 1px solid #20202a;
  }

  .sheet-title {
    font-size: 0.9rem;
    font-weight: 700;
  }

  .close-btn {
    width: 32px;
    height: 32px;
    border: 1px solid #2a2a32;
    border-radius: 6px;
    background: #16161d;
    color: #c0c0c8;
    font-size: 0.9rem;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    user-select: none;
  }

  .tabs {
    display: flex;
    gap: 6px;
    padding: 10px 14px 0;
  }

  .tab {
    flex: 1;
    height: 34px;
    border: 1px solid #2a2a32;
    border-radius: 6px;
    background: #15151d;
    color: #9a9aa8;
    font-family: inherit;
    font-size: 0.78rem;
    font-weight: 600;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    user-select: none;
  }

  .tab.active {
    background: #1d2a3d;
    border-color: #345077;
    color: #9fcdf6;
  }

  .active-list,
  .add-list {
    padding: 10px 14px;
    -webkit-overflow-scrolling: touch;
  }

  /* Default: active list takes whatever is left after the add panel. */
  .active-list {
    overflow-y: auto;
    flex: 1;
    min-height: 0;
    border-bottom: 1px solid #20202a;
  }

  /* When the add panel is collapsed, the active list gets the full sheet. */
  .active-list.expanded {
    flex: 1 1 auto;
  }

  /* The add panel is a disclosure — header only when collapsed, full
     scrollable picker when open. Collapsed it's a 1-line header, so no
     flex:1 (that would squeeze the active list for no reason). */
  .add-list {
    flex: 0 0 auto;
    display: flex;
    flex-direction: column;
    min-height: 0;
  }

  .add-list.open {
    flex: 1 1 auto;
    min-height: 0;
    overflow: hidden;
  }

  .add-toggle {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    padding: 6px 0;
    background: transparent;
    border: none;
    color: inherit;
    font-family: inherit;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
  }

  .add-toggle .add-title {
    margin-bottom: 0;
  }

  .chevron {
    color: #6a6a78;
    font-size: 0.8rem;
    line-height: 1;
  }

  .add-body {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    margin-top: 8px;
  }

  .section-title {
    font-size: 0.7rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: #6a6a78;
    margin-bottom: 6px;
  }

  .filter-input {
    width: 100%;
    height: 32px;
    padding: 0 10px;
    margin-bottom: 8px;
    border: 1px solid #2a2a32;
    border-radius: 6px;
    background: #16161d;
    color: #e0e0e8;
    font-family: inherit;
    font-size: 0.8rem;
    outline: none;
  }

  .filter-input:focus {
    border-color: #345077;
  }

  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  li {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    padding: 6px 8px;
    background: #15151d;
    border: 1px solid #20202a;
    border-radius: 6px;
  }

  li.empty {
    justify-content: center;
    color: #6a6a78;
    font-size: 0.78rem;
    padding: 12px;
    background: transparent;
    border: none;
  }

  .row-label {
    display: flex;
    align-items: baseline;
    gap: 10px;
    min-width: 0;
    flex: 1;
  }

  .label-glyph {
    font-weight: 700;
    color: #e0e0e8;
    min-width: 32px;
  }

  .label-desc {
    font-size: 0.72rem;
    color: #7a7a88;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .row-actions {
    display: flex;
    gap: 4px;
    flex-shrink: 0;
  }

  .icon-btn {
    width: 30px;
    height: 30px;
    border: 1px solid #2a2a32;
    border-radius: 6px;
    background: #1a1a22;
    color: #c0c0c8;
    font-family: inherit;
    font-size: 0.85rem;
    font-weight: 700;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    user-select: none;
  }

  .icon-btn[disabled] {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .icon-btn.danger {
    color: #f89a9a;
    border-color: #4a2428;
  }

  .icon-btn.accent {
    color: #9fcdf6;
    border-color: #345077;
    background: #1d2a3d;
  }

  .sheet-footer {
    display: flex;
    gap: 8px;
    padding: 10px 14px 14px;
    border-top: 1px solid #20202a;
  }

  .footer-btn {
    flex: 1;
    height: 40px;
    border: 1px solid #2a2a32;
    border-radius: 6px;
    background: #15151d;
    color: #c0c0c8;
    font-family: inherit;
    font-size: 0.82rem;
    font-weight: 600;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    user-select: none;
  }

  .footer-btn.primary {
    background: #1d2a3d;
    border-color: #345077;
    color: #9fcdf6;
  }

  .footer-btn.danger {
    color: #f89a9a;
    border-color: #4a2428;
  }
</style>
