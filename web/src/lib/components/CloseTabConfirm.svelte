<script lang="ts">
  /**
   * CloseTabConfirm — destructive confirmation modal for closing a CLI tab.
   *
   * Phase 13 Wave 2.6: closing a tab now sends a `{type:'kill'}` control
   * frame to the relay which runs `tmux kill-window` server-side (or hits
   * `POST /shell/:tabId/kill` as a REST fallback when the WS isn't OPEN).
   * That is an irreversible action — the shell process (claude, pnpm dev,
   * anything running in the window) dies immediately. This dialog is the
   * fat-finger safety net between the × button and that destructive path.
   *
   * Implementation: native HTML `<dialog>` element with `.showModal()`.
   * That's what gives us, for free:
   *   - Proper focus trap (Tab/Shift-Tab cycles only inside the dialog —
   *     focus can't leak onto the underlying tab strip or xterm)
   *   - Escape closes the dialog (via the `cancel` event, which we hook
   *     to route through `onCancel` so the parent can clear pending state)
   *   - Inert-ing of the rest of the page so screen readers and pointer
   *     events don't leak past the modal
   *   - Browser-native `::backdrop` pseudo-element for the dim overlay
   *
   * The previous div+role="dialog" version tried to DIY this and users
   * could Tab out onto underlying focusable controls — caught by Copilot
   * PR #94 review round 2.
   *
   * Focus lands on the Cancel button (the SAFE action) via an explicit
   * `.focus()` in onMount — showModal()'s own autofocus logic picks the
   * first tabbable element, which would be Cancel anyway, but we make it
   * explicit so rage-tapping Enter hits Cancel on every browser.
   *
   * Backdrop click → cancel: native `<dialog>` clicks bubble up with
   * `event.target === dialogEl` for backdrop-area hits (the backdrop is
   * technically part of the dialog element itself), while clicks on
   * inner content have event.target set to the inner element. We use
   * that distinction instead of a separate backdrop div.
   */
  import { onMount } from 'svelte';

  interface Props {
    tabId: string;
    onCancel: () => void;
    onConfirm: () => void;
  }

  let { tabId, onCancel, onConfirm }: Props = $props();

  let dialogEl = $state<HTMLDialogElement | undefined>(undefined);
  let cancelBtnEl = $state<HTMLButtonElement | undefined>(undefined);

  onMount(() => {
    const dialog = dialogEl;
    if (!dialog) return;
    // showModal() gets us the focus trap + native backdrop + inert-ing
    // for free. Without this call, the <dialog> element renders but
    // behaves like a regular block and none of the modal semantics apply.
    dialog.showModal();
    // Override showModal's default autofocus — queueMicrotask lets the
    // browser finish its own initial focus resolution before we grab it,
    // otherwise on some engines our .focus() would be clobbered.
    queueMicrotask(() => cancelBtnEl?.focus());
    return () => {
      // Component unmounting (parent cleared pendingCloseTabId) — make
      // sure we release the dialog's modal state too. Safe if already
      // closed (no-op).
      if (dialog.open) dialog.close();
    };
  });

  /**
   * Escape triggers the native `cancel` event on `<dialog>`. We hook it
   * and route through the parent's `onCancel` prop so the parent clears
   * `pendingCloseTabId` (which unmounts this component). Preventing the
   * default avoids a double-close race between the native dialog.close()
   * path and our own unmount path.
   */
  function handleCancel(e: Event): void {
    e.preventDefault();
    onCancel();
  }

  /**
   * Backdrop click detection. With native `<dialog>` the backdrop is the
   * ::backdrop pseudo-element attached to the dialog element itself, so
   * a click on the dim area bubbles with `event.target === dialogEl`.
   * Clicks on inner content have event.target set to the inner element
   * (the h3, a p, a button, etc.) so they don't match.
   */
  function handleDialogClick(e: MouseEvent): void {
    if (e.target === dialogEl) {
      onCancel();
    }
  }
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<dialog
  bind:this={dialogEl}
  class="close-dialog"
  aria-labelledby="close-tab-title"
  aria-describedby="close-tab-desc"
  oncancel={handleCancel}
  onclick={handleDialogClick}
>
  <div class="close-inner">
    <div class="close-header">
      <h3 id="close-tab-title" class="close-title">Close CLI tab?</h3>
    </div>

    <div class="close-body">
      <p id="close-tab-desc" class="close-desc">
        This will kill the <code>{tabId}</code> tmux window. Any process running
        inside it — <code>claude</code>, shell, <code>pnpm dev</code>, anything —
        dies with it.
      </p>
      <p class="close-warn">There's no undo.</p>
    </div>

    <div class="close-footer">
      <button
        type="button"
        class="btn btn-cancel"
        bind:this={cancelBtnEl}
        onclick={onCancel}
      >
        Cancel
      </button>
      <button
        type="button"
        class="btn btn-destroy"
        onclick={onConfirm}
      >
        Close &amp; kill
      </button>
    </div>
  </div>
</dialog>

<style>
  .close-dialog {
    /* Native <dialog> carries default padding/border/margin we don't want —
       reset so our own .close-inner owns the layout. */
    padding: 0;
    margin: auto;
    background: var(--surface, #16161d);
    border: 1px solid var(--border, #2a2a35);
    border-radius: var(--r-md, 8px);
    width: calc(100% - 32px);
    max-width: 380px;
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.55);
    color: var(--text-primary, #e8e8f0);
    overflow: hidden;
    /*
     * The destructive nature of this dialog warrants a subtle red tint on
     * the top border so the user's eye registers "warning" before reading.
     */
    border-top: 2px solid #e05252;
  }

  /* Native browser backdrop — replaces the old .close-backdrop div. */
  .close-dialog::backdrop {
    background: rgba(0, 0, 0, 0.65);
  }

  .close-header {
    padding: var(--sp-md, 12px) var(--sp-lg, 16px) 0;
  }

  .close-title {
    margin: 0;
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
    font-size: 0.95rem;
    font-weight: 700;
    color: var(--text-primary, #e8e8f0);
  }

  .close-body {
    padding: var(--sp-md, 12px) var(--sp-lg, 16px);
    display: flex;
    flex-direction: column;
    gap: var(--sp-sm, 8px);
  }

  .close-desc {
    margin: 0;
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
    font-size: 0.8rem;
    line-height: 1.55;
    color: var(--text-secondary, #b0b0bc);
  }

  .close-desc code {
    background: var(--bg, #0a0a0a);
    border: 1px solid var(--border, #2a2a35);
    border-radius: 3px;
    padding: 1px 5px;
    font-size: 0.78rem;
    color: var(--accent, #4dd973);
  }

  .close-warn {
    margin: 0;
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
    font-size: 0.78rem;
    color: #e05252;
    font-weight: 600;
    letter-spacing: 0.02em;
  }

  .close-footer {
    display: flex;
    justify-content: flex-end;
    gap: var(--sp-sm, 8px);
    padding: var(--sp-md, 12px) var(--sp-lg, 16px);
    border-top: 1px solid var(--border, #2a2a35);
    background: rgba(0, 0, 0, 0.2);
  }

  .btn {
    padding: var(--sp-sm, 8px) var(--sp-lg, 16px);
    border-radius: var(--r-sm, 6px);
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
    font-size: 0.8rem;
    font-weight: 600;
    cursor: pointer;
    border: 1px solid var(--border, #2a2a35);
    transition: all 0.15s;
    /*
     * Larger touch target on mobile — the whole point of this dialog is
     * finger-precision, so don't skimp on hit area. 44px is the iOS HIG
     * minimum for touch targets.
     */
    min-height: 44px;
    min-width: 96px;
  }

  .btn-cancel {
    background: transparent;
    color: var(--text-secondary, #b0b0bc);
  }
  .btn-cancel:hover,
  .btn-cancel:focus-visible {
    color: var(--text-primary, #e8e8f0);
    background: var(--surface-hover, #1f1f27);
    outline: none;
    border-color: var(--text-secondary, #b0b0bc);
  }

  .btn-destroy {
    background: transparent;
    color: #ff6a6a;
    border-color: #7a2323;
  }
  .btn-destroy:hover,
  .btn-destroy:focus-visible {
    color: #fff;
    background: #7a2323;
    border-color: #e05252;
    outline: none;
  }

  @media (max-width: 480px) {
    .close-dialog {
      max-width: 100%;
    }
    .btn {
      flex: 1;
      min-width: 0;
    }
  }
</style>
