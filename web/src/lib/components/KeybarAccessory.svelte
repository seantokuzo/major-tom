<script lang="ts">
  /**
   * KeybarAccessory — horizontal scrollable row of specialty keys, sits
   * above the iOS native keyboard. The iOS keyboard still owns typing;
   * this row adds keys iOS can't produce (Esc, Tab, arrows, Ctrl combos,
   * tmux quick-tap, etc).
   *
   * Renders the keys currently in `keybarStore.accessoryKeys`. The
   * rightmost two buttons are FIXED controls owned by this component:
   *   1. Specialty-mode toggle (ABC/KB icon)
   *   2. Customize button (gear)
   *
   * All key presses are dispatched via the `onPress` callback — the
   * parent (MobileKeybar) is responsible for sticky modifier handling.
   */
  import { keybarStore } from '../stores/keybar.svelte';
  import type { KeySpec } from '../shell/keys';

  interface Props {
    onPress: (spec: KeySpec) => void;
    onToggleSpecialty: () => void;
    onOpenCustomize: () => void;
    /** Per-modifier armed (one-shot) + locked (persistent) state. */
    ctrlArmed: boolean;
    ctrlLocked: boolean;
    altArmed: boolean;
    altLocked: boolean;
  }

  const {
    onPress,
    onToggleSpecialty,
    onOpenCustomize,
    ctrlArmed,
    ctrlLocked,
    altArmed,
    altLocked,
  }: Props = $props();

  function handleKey(spec: KeySpec, e: Event): void {
    // Prevent mousedown from stealing focus from the hidden input iOS uses
    // to keep its keyboard open.
    e.preventDefault();
    onPress(spec);
  }

  function isArmed(spec: KeySpec): boolean {
    if (!spec.sticky) return false;
    if (spec.id === 'ctrl') return ctrlArmed && !ctrlLocked;
    if (spec.id === 'alt') return altArmed && !altLocked;
    return false;
  }

  function isLocked(spec: KeySpec): boolean {
    if (!spec.sticky) return false;
    if (spec.id === 'ctrl') return ctrlLocked;
    if (spec.id === 'alt') return altLocked;
    return false;
  }
</script>

<div class="kb-accessory" aria-label="Terminal accessory keys">
  <div class="kb-scroll">
    {#each keybarStore.accessoryKeys as spec (spec.id)}
      <button
        type="button"
        class="key"
        class:sticky={spec.sticky}
        class:armed={isArmed(spec)}
        class:locked={isLocked(spec)}
        class:primary={spec.id === 'tmux-scroll'}
        data-key-id={spec.id}
        aria-label={spec.description ?? spec.label}
        title={spec.description ?? spec.label}
        onpointerdown={(e) => handleKey(spec, e)}
      >
        {spec.label}
      </button>
    {/each}
  </div>
  <div class="kb-fixed">
    <button
      type="button"
      class="key fixed"
      aria-label="Open specialty keyboard"
      title="Show specialty keys"
      data-key-id="__toggle-specialty"
      onpointerdown={(e) => {
        e.preventDefault();
        onToggleSpecialty();
      }}
    >
      ⌨︎
    </button>
    <button
      type="button"
      class="key fixed"
      aria-label="Customize keybar"
      title="Customize keys"
      data-key-id="__customize"
      onpointerdown={(e) => {
        e.preventDefault();
        onOpenCustomize();
      }}
    >
      ⚙
    </button>
  </div>
</div>

<style>
  .kb-accessory {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 4px 6px;
    background: #111114;
    border-top: 1px solid #25252c;
    flex-shrink: 0;
  }

  .kb-scroll {
    display: flex;
    align-items: center;
    gap: 4px;
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
    flex: 1;
    min-width: 0;
    scrollbar-width: none;
  }

  .kb-scroll::-webkit-scrollbar {
    display: none;
  }

  .kb-fixed {
    display: flex;
    gap: 4px;
    flex-shrink: 0;
    padding-left: 4px;
    border-left: 1px solid #25252c;
  }

  .key {
    flex: 0 0 auto;
    min-width: 36px;
    height: 34px;
    padding: 0 10px;
    border: 1px solid #2a2a32;
    border-radius: 6px;
    background: #1a1a22;
    color: #e0e0e8;
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
    font-size: 0.82rem;
    font-weight: 600;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    user-select: none;
    touch-action: manipulation;
  }

  .key:active {
    background: #25252e;
  }

  .key.primary {
    background: #1d2a3d;
    border-color: #345077;
    color: #9fcdf6;
  }

  .key.primary:active {
    background: #243654;
  }

  .key.sticky.armed {
    background: rgba(99, 179, 237, 0.18);
    border-color: rgba(99, 179, 237, 0.6);
    color: #9fcdf6;
  }

  .key.sticky.locked {
    background: rgba(99, 179, 237, 0.32);
    border-color: rgba(99, 179, 237, 0.9);
    color: #cfe5fb;
    box-shadow: inset 0 0 0 1px rgba(99, 179, 237, 0.5);
  }

  .key.fixed {
    background: #16161d;
    color: #9a9aa8;
  }
</style>
