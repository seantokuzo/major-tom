<script lang="ts">
  /**
   * Shell tab strip — new / close / switch.
   *
   * Each tab represents one tmux window inside the Major Tom session.
   * Tabs are persistent on the relay side, so closing the strip entry
   * does NOT kill the underlying claude process unless you explicitly
   * `tmux kill-window`. Wave 1 keeps the close button as a "detach"
   * (closes the WS, leaves the tmux window) — true window destruction
   * is a Wave 2/3 affordance.
   */
  import { shellStore } from '../stores/shell.svelte';

  interface Props {
    onNew: () => void;
    onClose: (tabId: string) => void;
  }

  let { onNew, onClose }: Props = $props();
</script>

<div class="tabs">
  {#each shellStore.tabs as tab (tab.id)}
    <div
      class="tab"
      class:active={shellStore.activeTabId === tab.id}
      role="tab"
      tabindex="0"
      aria-selected={shellStore.activeTabId === tab.id}
      onclick={() => shellStore.setActive(tab.id)}
      onkeydown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          shellStore.setActive(tab.id);
        }
      }}
    >
      <span class="dot" class:on={tab.connected}></span>
      <span class="label">{tab.label}</span>
      <button
        type="button"
        class="close"
        title="Detach tab (tmux window stays alive)"
        aria-label="Detach tab"
        onclick={(e) => { e.stopPropagation(); onClose(tab.id); }}
      >×</button>
    </div>
  {/each}
  <button type="button" class="new" onclick={onNew} aria-label="New tab">+</button>
</div>

<style>
  .tabs {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 4px 6px;
    background: #0d0d11;
    border-bottom: 1px solid #1f1f26;
    overflow-x: auto;
    flex-shrink: 0;
  }

  .tab {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 4px 8px;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 6px;
    color: #b0b0bc;
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
    font-size: 0.72rem;
    cursor: pointer;
    flex-shrink: 0;
  }

  .tab.active {
    background: #16161d;
    border-color: #2a2a35;
    color: #e8e8f0;
  }

  .dot {
    display: inline-block;
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #555560;
  }

  .dot.on {
    background: #4dd973;
  }

  .label {
    max-width: 120px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .close {
    background: transparent;
    border: none;
    color: #777783;
    font-size: 0.95rem;
    line-height: 1;
    padding: 0 2px;
    cursor: pointer;
    border-radius: 3px;
  }

  .close:hover {
    color: #e8e8f0;
    background: #25252e;
  }

  .new {
    flex-shrink: 0;
    padding: 4px 10px;
    background: transparent;
    border: 1px dashed #2a2a35;
    border-radius: 6px;
    color: #888893;
    font-size: 0.85rem;
    cursor: pointer;
  }

  .new:hover {
    color: #e8e8f0;
    border-color: #4dd973;
  }
</style>
