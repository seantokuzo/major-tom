<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import type { PermissionMode, GodSubMode } from '../stores/relay.svelte';

  let delayDropdownOpen = $state(false);
  let godDropdownOpen = $state(false);
  let godConfirmPending = $state(false);

  const DELAY_OPTIONS = [3, 5, 10, 15, 30];

  const mode = $derived(relay.permissionMode.mode);
  const delaySeconds = $derived(relay.permissionMode.delaySeconds);
  const godSubMode = $derived(relay.permissionMode.godSubMode);

  function setMode(newMode: PermissionMode) {
    // Close dropdowns
    delayDropdownOpen = false;
    godDropdownOpen = false;

    if (newMode === 'god' && mode !== 'god') {
      // Require confirmation when first activating God mode
      godConfirmPending = true;
      return;
    }

    relay.setPermissionMode(newMode);
  }

  function confirmGodMode() {
    godConfirmPending = false;
    relay.setPermissionMode('god', undefined, 'normal');
  }

  function cancelGodConfirm() {
    godConfirmPending = false;
  }

  function setDelay(seconds: number) {
    delayDropdownOpen = false;
    relay.setPermissionMode('delay', seconds);
  }

  function setGodSubMode(sub: GodSubMode) {
    godDropdownOpen = false;
    relay.setPermissionMode('god', undefined, sub);
  }

  function toggleDelayDropdown(e: MouseEvent) {
    e.stopPropagation();
    godDropdownOpen = false;
    if (mode !== 'delay') {
      relay.setPermissionMode('delay');
    } else {
      delayDropdownOpen = !delayDropdownOpen;
    }
  }

  function toggleGodDropdown(e: MouseEvent) {
    e.stopPropagation();
    delayDropdownOpen = false;
    if (mode !== 'god') {
      setMode('god');
    } else {
      godDropdownOpen = !godDropdownOpen;
    }
  }

  // Close dropdowns on outside click
  function handleGlobalClick() {
    delayDropdownOpen = false;
    godDropdownOpen = false;
  }

  $effect(() => {
    if (delayDropdownOpen || godDropdownOpen) {
      window.addEventListener('click', handleGlobalClick);
      return () => window.removeEventListener('click', handleGlobalClick);
    }
  });
</script>

<div class="switcher">
  <button
    class="pill"
    class:active={mode === 'manual'}
    onclick={() => setMode('manual')}
  >
    Manual
  </button>

  <button
    class="pill"
    class:active={mode === 'smart'}
    onclick={() => setMode('smart')}
  >
    Smart
  </button>

  <div class="pill-wrap">
    <button
      class="pill"
      class:active={mode === 'delay'}
      onclick={toggleDelayDropdown}
    >
      Delay{#if mode === 'delay'} {delaySeconds}s{/if}
      <span class="caret">&#x25BE;</span>
    </button>
    {#if delayDropdownOpen}
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div class="dropdown" onclick={(e) => e.stopPropagation()}>
        {#each DELAY_OPTIONS as sec}
          <button
            class="dropdown-item"
            class:selected={delaySeconds === sec}
            onclick={() => setDelay(sec)}
          >
            {sec}s
          </button>
        {/each}
      </div>
    {/if}
  </div>

  <div class="pill-wrap">
    <button
      class="pill pill-god"
      class:active={mode === 'god'}
      class:yolo={mode === 'god' && godSubMode === 'yolo'}
      onclick={toggleGodDropdown}
    >
      God{#if mode === 'god'}: {godSubMode === 'yolo' ? 'YOLO' : 'Normal'}{/if}
      <span class="caret">&#x25BE;</span>
    </button>
    {#if godDropdownOpen}
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div class="dropdown" onclick={(e) => e.stopPropagation()}>
        <button
          class="dropdown-item"
          class:selected={godSubMode === 'normal'}
          onclick={() => setGodSubMode('normal')}
        >
          Normal
          <span class="dropdown-hint">Blocks destructive</span>
        </button>
        <button
          class="dropdown-item dropdown-yolo"
          class:selected={godSubMode === 'yolo'}
          onclick={() => setGodSubMode('yolo')}
        >
          YOLO
          <span class="dropdown-hint">Allows EVERYTHING</span>
        </button>
      </div>
    {/if}
  </div>
</div>

{#if godConfirmPending}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="confirm-overlay" onclick={cancelGodConfirm}>
    <div class="confirm-card" onclick={(e) => e.stopPropagation()}>
      <div class="confirm-title">Enable God Mode?</div>
      <div class="confirm-text">
        All tool calls will be auto-approved. Destructive commands are still blocked in Normal mode.
      </div>
      <div class="confirm-actions">
        <button class="confirm-btn confirm-cancel" onclick={cancelGodConfirm}>Cancel</button>
        <button class="confirm-btn confirm-ok" onclick={confirmGodMode}>Enable</button>
      </div>
    </div>
  </div>
{/if}

<style>
  .switcher {
    display: flex;
    gap: 2px;
    background: var(--surface);
    border-radius: var(--r-sm);
    padding: 2px;
    flex-shrink: 0;
  }

  .pill-wrap {
    position: relative;
  }

  .pill {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 500;
    color: var(--text-tertiary);
    background: transparent;
    border: none;
    padding: 4px 8px;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.15s;
    white-space: nowrap;
    display: flex;
    align-items: center;
    gap: 2px;
  }

  .pill:hover {
    color: var(--text-secondary);
    background: rgba(255, 255, 255, 0.03);
  }

  .pill.active {
    color: var(--text-primary);
    background: var(--surface-hover);
  }

  .pill-god.active {
    color: #fbbf24;
    background: rgba(251, 191, 36, 0.12);
  }

  .pill-god.yolo {
    color: #f87171;
    background: rgba(248, 113, 113, 0.12);
    animation: yolo-pulse 1.5s ease-in-out infinite alternate;
  }

  @keyframes yolo-pulse {
    from { box-shadow: inset 0 0 4px rgba(248, 113, 113, 0.15); }
    to { box-shadow: inset 0 0 8px rgba(248, 113, 113, 0.3); }
  }

  .caret {
    font-size: 0.55rem;
    opacity: 0.6;
  }

  .dropdown {
    position: absolute;
    top: 100%;
    left: 0;
    margin-top: 4px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: 4px;
    z-index: 50;
    min-width: 80px;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
  }

  .dropdown-item {
    display: flex;
    flex-direction: column;
    width: 100%;
    padding: 5px 8px;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    cursor: pointer;
    border-radius: 3px;
    text-align: left;
    transition: all 0.1s;
  }

  .dropdown-item:hover {
    background: var(--surface-hover);
    color: var(--text-primary);
  }

  .dropdown-item.selected {
    color: var(--accent);
    font-weight: 600;
  }

  .dropdown-yolo {
    color: var(--deny);
  }
  .dropdown-yolo:hover {
    background: rgba(248, 113, 113, 0.1);
    color: var(--deny);
  }

  .dropdown-hint {
    font-size: 0.55rem;
    color: var(--text-tertiary);
    font-weight: 400;
  }

  /* Confirmation dialog */
  .confirm-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 200;
  }

  .confirm-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    padding: var(--sp-lg);
    max-width: 300px;
    width: 90%;
  }

  .confirm-title {
    font-family: var(--font-mono);
    font-size: 0.9rem;
    font-weight: 700;
    color: #fbbf24;
    margin-bottom: var(--sp-sm);
  }

  .confirm-text {
    font-size: 0.8rem;
    color: var(--text-secondary);
    line-height: 1.4;
    margin-bottom: var(--sp-md);
  }

  .confirm-actions {
    display: flex;
    gap: var(--sp-sm);
    justify-content: flex-end;
  }

  .confirm-btn {
    padding: 6px 14px;
    border-radius: var(--r-sm);
    border: none;
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 600;
    cursor: pointer;
  }

  .confirm-cancel {
    background: transparent;
    color: var(--text-secondary);
    border: 1px solid var(--border);
  }

  .confirm-ok {
    background: #fbbf24;
    color: #000;
  }
</style>
