<script lang="ts">
  /**
   * CloseTabConfirm — destructive confirmation modal for closing a CLI tab.
   *
   * Phase 13 Wave 2.6: closing a tab now sends a `{type:'kill'}` control
   * frame to the relay which runs `tmux kill-window` server-side. That is
   * an irreversible action — the shell process (claude, pnpm dev, anything
   * running in the window) dies immediately. This dialog is the fat-finger
   * safety net between the × button and that destructive path.
   *
   * Accessibility:
   *   - role="dialog" + aria-modal="true" + aria-labelledby for the title
   *   - Default focus lands on the Cancel button (the SAFE action), so a
   *     user spamming Enter or rage-tapping the × can't accidentally kill
   *     a session — they'd have to Tab over to the destructive button or
   *     explicitly click it.
   *   - Escape → cancel (native dialog convention)
   *   - Backdrop click → cancel
   *   - Tab/Shift-Tab cycles between Cancel and Close
   */
  import { onMount } from 'svelte';

  interface Props {
    tabId: string;
    onCancel: () => void;
    onConfirm: () => void;
  }

  let { tabId, onCancel, onConfirm }: Props = $props();

  let cancelBtnEl = $state<HTMLButtonElement | undefined>(undefined);

  onMount(() => {
    // Land focus on the safe action, not the destructive one. queueMicrotask
    // lets Svelte finish mounting before we grab focus — without the delay
    // the button may not be in the DOM yet on first mount.
    queueMicrotask(() => cancelBtnEl?.focus());
  });

  function handleKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') {
      e.preventDefault();
      onCancel();
    }
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
  class="close-backdrop"
  onclick={onCancel}
  onkeydown={handleKeydown}
  role="presentation"
>
  <div
    class="close-dialog"
    onclick={(e) => e.stopPropagation()}
    role="dialog"
    aria-modal="true"
    aria-labelledby="close-tab-title"
    aria-describedby="close-tab-desc"
  >
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
</div>

<style>
  .close-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.65);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 200;
    padding: var(--sp-lg, 16px);
  }

  .close-dialog {
    background: var(--surface, #16161d);
    border: 1px solid var(--border, #2a2a35);
    border-radius: var(--r-md, 8px);
    width: 100%;
    max-width: 380px;
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.55);
    overflow: hidden;
    /*
     * The destructive nature of this dialog warrants a subtle red tint on
     * the top border so the user's eye registers "warning" before reading.
     */
    border-top: 2px solid #e05252;
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
