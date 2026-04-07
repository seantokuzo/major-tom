<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import type { PermissionMode, GodSubMode, ApprovalRoutingMode } from '../stores/relay.svelte';

  let openDropdown = $state<'delay' | 'god' | null>(null);
  let godConfirmPending = $state(false);
  let switcherEl: HTMLDivElement | undefined;

  // ── Phase 13 Wave 2 — approval routing dimension ──────────
  // This is orthogonal to the permission mode above. The mode
  // (manual/smart/delay/god) decides HOW each approval is answered;
  // the routing decides WHO answers it (TUI, phone, or both racing).
  // The shell hook script in MAJOR_TOM_CONFIG_DIR reads this value
  // from approval-mode.json on every invocation, so we don't need to
  // restart the relay when the user flips a pill.
  const routingMode = $derived<ApprovalRoutingMode>(relay.approvalRoutingMode);
  function setRouting(mode: ApprovalRoutingMode) {
    void relay.setApprovalRoutingMode(mode);
  }

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

  // Window-level Escape to dismiss God Mode confirm dialog
  $effect(() => {
    if (!godConfirmPending) return;
    function onKeydown(e: KeyboardEvent) {
      if (e.key === 'Escape') cancelGodConfirm();
    }
    window.addEventListener('keydown', onKeydown);
    return () => window.removeEventListener('keydown', onKeydown);
  });
</script>

<div
  class="switcher"
  class:yolo-active={mode === 'god' && godSubMode === 'yolo'}
  bind:this={switcherEl}
>
  <button
    class="pill pill-manual"
    class:active={mode === 'manual'}
    onclick={() => switchTo('manual')}
  >
    <span class="label-full">Manual</span><span class="label-short">Man</span>
  </button>

  <button
    class="pill pill-smart"
    class:active={mode === 'smart'}
    onclick={() => switchTo('smart')}
  >
    <span class="label-full">Smart</span><span class="label-short">Smt</span>
  </button>

  <div class="pill-wrap">
    <button
      class="pill pill-delay"
      class:active={mode === 'delay'}
      onclick={handleDelayClick}
    >
      <span class="label-full">Delay</span><span class="label-short">Dly</span>{#if mode === 'delay'}<span class="pill-detail">{delaySeconds}s</span>{/if}
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
      <span class="label-full">God</span><span class="label-short">God</span>{#if mode === 'god'}<span class="pill-detail">{godSubMode === 'yolo' ? 'YOLO' : 'Nrml'}</span>{/if}
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

<!-- Phase 13 Wave 2 — Approval routing (shell hook intercept path) -->
<div class="routing-row" role="group" aria-label="Approval routing">
  <span class="routing-label">Route</span>
  <div class="routing-pills">
    <button
      type="button"
      class="route-pill"
      class:active={routingMode === 'local'}
      data-mode="local"
      onclick={() => setRouting('local')}
      title="TUI owns approvals — phone gets a quiet notification"
    >
      Local
    </button>
    <button
      type="button"
      class="route-pill"
      class:active={routingMode === 'remote'}
      data-mode="remote"
      onclick={() => setRouting('remote')}
      title="Phone owns approvals — TUI blocks until you decide here"
    >
      Remote
    </button>
    <button
      type="button"
      class="route-pill"
      class:active={routingMode === 'hybrid'}
      data-mode="hybrid"
      onclick={() => setRouting('hybrid')}
      title="Both can decide — first answer wins"
    >
      Hybrid
    </button>
  </div>
</div>

{#if godConfirmPending}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="confirm-overlay"
    role="dialog"
    aria-modal="true"
    aria-label="Enable God Mode confirmation"
    onclick={cancelGodConfirm}
  >
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
  /* ── Segmented control container ─────────────────────────── */
  .switcher {
    display: flex;
    gap: 0;
    background: rgba(10, 10, 15, 0.7);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: 2px;
    width: 100%;
    position: relative;
  }

  .switcher.yolo-active {
    border-color: rgba(248, 113, 113, 0.5);
    animation: switcher-yolo-pulse 2s ease-in-out infinite alternate;
    background: rgba(248, 113, 113, 0.06);
  }

  @keyframes switcher-yolo-pulse {
    from { box-shadow: 0 0 6px rgba(248, 113, 113, 0.15), inset 0 0 8px rgba(248, 113, 113, 0.05); }
    to { box-shadow: 0 0 12px rgba(248, 113, 113, 0.3), inset 0 0 12px rgba(248, 113, 113, 0.1); }
  }

  .pill-wrap {
    position: relative;
    flex: 1;
    display: flex;
  }

  /* ── Pill buttons (segmented control segments) ───────────── */
  .pill {
    flex: 1;
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 500;
    color: var(--text-tertiary);
    background: transparent;
    border: none;
    padding: 5px 4px;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.2s ease;
    white-space: nowrap;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 3px;
    min-height: 28px;
    position: relative;
    z-index: 1;
  }

  .pill:hover:not(.active) {
    color: var(--text-secondary);
    background: rgba(255, 255, 255, 0.04);
  }

  /* ── Active pill states (per-mode colors) ────────────────── */
  .pill.active {
    color: var(--text-primary);
    font-weight: 600;
    border-radius: 4px;
  }

  /* Manual — default accent */
  .pill-manual.active {
    color: var(--text-primary);
    background: var(--surface-hover);
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
  }

  /* Smart — gold accent (default mode) */
  .pill-smart.active {
    color: var(--accent);
    background: rgba(212, 168, 83, 0.15);
    box-shadow: 0 1px 4px rgba(212, 168, 83, 0.2);
  }

  /* Delay — blue accent */
  .pill-delay.active {
    color: var(--skip);
    background: rgba(96, 165, 250, 0.12);
    box-shadow: 0 1px 4px rgba(96, 165, 250, 0.2);
  }

  /* God normal — amber */
  .pill-god.active {
    color: #fbbf24;
    background: rgba(251, 191, 36, 0.14);
    box-shadow: 0 1px 4px rgba(251, 191, 36, 0.2);
  }

  /* God YOLO — pulsing red danger */
  .pill-god.yolo {
    color: #f87171;
    background: rgba(248, 113, 113, 0.18);
    box-shadow: 0 0 6px rgba(248, 113, 113, 0.3);
    animation: yolo-pill-pulse 1.5s ease-in-out infinite alternate;
  }

  @keyframes yolo-pill-pulse {
    from {
      background: rgba(248, 113, 113, 0.14);
      box-shadow: 0 0 4px rgba(248, 113, 113, 0.2);
    }
    to {
      background: rgba(248, 113, 113, 0.22);
      box-shadow: 0 0 10px rgba(248, 113, 113, 0.4);
    }
  }

  .pill-detail {
    font-size: 0.58rem;
    opacity: 0.7;
    font-weight: 400;
  }

  .caret {
    font-size: 0.5rem;
    opacity: 0.4;
    transition: opacity 0.15s;
  }

  .pill:hover .caret,
  .pill.active .caret {
    opacity: 0.7;
  }

  /* ── Dropdowns ───────────────────────────────────────────── */
  .dropdown {
    position: absolute;
    top: calc(100% + 6px);
    left: 50%;
    transform: translateX(-50%);
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: 4px;
    z-index: 50;
    min-width: 90px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6);
    /* Entry animation */
    animation: dropdown-enter 0.15s ease-out;
  }

  .dropdown-right {
    left: auto;
    right: 0;
    transform: none;
  }

  @keyframes dropdown-enter {
    from {
      opacity: 0;
      transform: translateX(-50%) translateY(-4px);
    }
    to {
      opacity: 1;
      transform: translateX(-50%) translateY(0);
    }
  }

  .dropdown-right {
    animation-name: dropdown-enter-right;
  }

  @keyframes dropdown-enter-right {
    from {
      opacity: 0;
      transform: translateY(-4px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  /* Arrow nub pointing to parent pill */
  .dropdown::before {
    content: '';
    position: absolute;
    top: -5px;
    left: 50%;
    transform: translateX(-50%) rotate(45deg);
    width: 8px;
    height: 8px;
    background: var(--bg);
    border-top: 1px solid var(--border);
    border-left: 1px solid var(--border);
  }

  .dropdown-right::before {
    left: auto;
    right: 12px;
    transform: rotate(45deg);
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

  /* ── Mobile: abbreviate pill labels ──────────────────────── */
  .pill .label-full { display: inline; }
  .pill .label-short { display: none; }

  @media (max-width: 400px) {
    .pill {
      font-size: 0.62rem;
      padding: 5px 2px;
      gap: 2px;
    }
    .pill .label-full { display: none; }
    .pill .label-short { display: inline; }
    .pill-detail {
      font-size: 0.52rem;
    }
    .caret {
      font-size: 0.45rem;
    }
  }

  /* ── Confirmation dialog ─────────────────────────────────── */
  .confirm-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 200;
    animation: overlay-enter 0.15s ease-out;
  }

  @keyframes overlay-enter {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .confirm-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    padding: var(--sp-lg);
    max-width: 300px;
    width: 90%;
    animation: card-enter 0.2s ease-out;
  }

  @keyframes card-enter {
    from {
      opacity: 0;
      transform: scale(0.95) translateY(8px);
    }
    to {
      opacity: 1;
      transform: scale(1) translateY(0);
    }
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
    transition: all 0.15s;
  }

  .confirm-btn:hover {
    transform: translateY(-1px);
  }

  .confirm-cancel {
    background: transparent;
    color: var(--text-secondary);
    border: 1px solid var(--border);
  }

  .confirm-cancel:hover {
    background: var(--surface-hover);
  }

  .confirm-ok {
    background: #fbbf24;
    color: #000;
  }

  .confirm-ok:hover {
    background: #f5c842;
  }

  /* ── Phase 13 Wave 2 — approval routing row ─────────────── */
  .routing-row {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 6px;
    padding: 0 2px;
  }

  .routing-label {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: var(--text-tertiary);
  }

  .routing-pills {
    display: flex;
    flex: 1;
    background: rgba(10, 10, 15, 0.7);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: 2px;
    gap: 0;
  }

  .route-pill {
    flex: 1;
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 500;
    color: var(--text-tertiary);
    background: transparent;
    border: none;
    padding: 4px 4px;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.15s ease;
    min-height: 24px;
  }

  .route-pill:hover:not(.active) {
    color: var(--text-secondary);
    background: rgba(255, 255, 255, 0.04);
  }

  .route-pill.active {
    color: var(--text-primary);
    font-weight: 600;
  }

  .route-pill.active[data-mode='local'] {
    background: var(--surface-hover);
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
  }

  .route-pill.active[data-mode='remote'] {
    color: #a8d0ff;
    background: rgba(80, 160, 255, 0.18);
    box-shadow: 0 1px 4px rgba(80, 160, 255, 0.25);
  }

  .route-pill.active[data-mode='hybrid'] {
    color: #d4b3ff;
    background: rgba(180, 120, 255, 0.18);
    box-shadow: 0 1px 4px rgba(180, 120, 255, 0.25);
  }
</style>
