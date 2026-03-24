<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import type { PermissionMode, GodSubMode } from '../stores/relay.svelte';

  let openDropdown = $state<'delay' | 'god' | null>(null);
  let godConfirmPending = $state(false);
  let switcherEl: HTMLDivElement | undefined;

  const DELAY_OPTIONS = [3, 5, 10, 15, 30];

  const mode = $derived(relay.permissionMode.mode);
  const delaySeconds = $derived(relay.permissionMode.delaySeconds);
  const godSubMode = $derived(relay.permissionMode.godSubMode);

  // ── Mode switching ─────────────────────────────────────────

  function switchTo(newMode: PermissionMode) {
    openDropdown = null;

    if (newMode === 'god' && mode !== 'god') {
      godConfirmPending = true;
      return;
    }

    relay.setPermissionMode(newMode);
  }

  function handleDelayClick() {
    if (mode !== 'delay') {
      // First click: switch to delay mode
      openDropdown = null;
      relay.setPermissionMode('delay');
    } else {
      // Already in delay: toggle dropdown
      openDropdown = openDropdown === 'delay' ? null : 'delay';
    }
  }

  function handleGodClick() {
    if (mode !== 'god') {
      openDropdown = null;
      switchTo('god');
    } else {
      openDropdown = openDropdown === 'god' ? null : 'god';
    }
  }

  function setDelay(seconds: number) {
    openDropdown = null;
    relay.setPermissionMode('delay', seconds);
  }

  function setGodSub(sub: GodSubMode) {
    openDropdown = null;
    relay.setPermissionMode('god', undefined, sub);
  }

  function confirmGodMode() {
    godConfirmPending = false;
    relay.setPermissionMode('god', undefined, 'normal');
  }

  function cancelGodConfirm() {
    godConfirmPending = false;
  }

  // ── Outside click detection (no stopPropagation needed) ────

  $effect(() => {
    if (openDropdown === null) return;

    function onPointerDown(e: PointerEvent) {
      if (switcherEl && !switcherEl.contains(e.target as Node)) {
        openDropdown = null;
      }
    }

    // Use pointerdown — fires before click, avoids race conditions
    document.addEventListener('pointerdown', onPointerDown);
    return () => document.removeEventListener('pointerdown', onPointerDown);
  });
</script>

<div class="switcher" bind:this={switcherEl}>
  <button
    class="pill"
    class:active={mode === 'manual'}
    onclick={() => switchTo('manual')}
  >
    Manual
  </button>

  <button
    class="pill"
    class:active={mode === 'smart'}
    onclick={() => switchTo('smart')}
  >
    Smart
  </button>

  <div class="pill-wrap">
    <button
      class="pill"
      class:active={mode === 'delay'}
      onclick={handleDelayClick}
    >
      Delay{#if mode === 'delay'}<span class="pill-detail">{delaySeconds}s</span>{/if}
      <span class="caret">&#x25BE;</span>
    </button>
    {#if openDropdown === 'delay'}
      <div class="dropdown">
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
      onclick={handleGodClick}
    >
      God{#if mode === 'god'}<span class="pill-detail">{godSubMode === 'yolo' ? 'YOLO' : 'Nrml'}</span>{/if}
      <span class="caret">&#x25BE;</span>
    </button>
    {#if openDropdown === 'god'}
      <div class="dropdown dropdown-right">
        <button
          class="dropdown-item"
          class:selected={godSubMode === 'normal'}
          onclick={() => setGodSub('normal')}
        >
          Normal
          <span class="dropdown-hint">Blocks destructive</span>
        </button>
        <button
          class="dropdown-item dropdown-yolo"
          class:selected={godSubMode === 'yolo'}
          onclick={() => setGodSub('yolo')}
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
    <!-- svelte-ignore a11y_no_static_element_interactions -->
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
    background: rgba(20, 20, 31, 0.6);
    border-radius: var(--r-sm);
    padding: 2px;
    width: 100%;
  }

  .pill-wrap {
    position: relative;
    flex: 1;
    display: flex;
  }

  .pill {
    flex: 1;
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 500;
    color: var(--text-tertiary);
    background: transparent;
    border: none;
    padding: 6px 4px;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.15s;
    white-space: nowrap;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 3px;
    min-height: 30px;
  }

  .pill:hover {
    color: var(--text-secondary);
    background: rgba(255, 255, 255, 0.04);
  }

  .pill.active {
    color: var(--text-primary);
    background: var(--surface-hover);
    font-weight: 600;
  }

  .pill-detail {
    font-size: 0.6rem;
    opacity: 0.7;
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
    font-size: 0.5rem;
    opacity: 0.5;
  }

  /* Dropdowns */
  .dropdown {
    position: absolute;
    top: calc(100% + 4px);
    left: 0;
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: 4px;
    z-index: 50;
    min-width: 90px;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.5);
  }

  .dropdown-right {
    left: auto;
    right: 0;
  }

  .dropdown-item {
    display: flex;
    flex-direction: column;
    width: 100%;
    padding: 6px 10px;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    font-family: var(--font-mono);
    font-size: 0.72rem;
    cursor: pointer;
    border-radius: 4px;
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
