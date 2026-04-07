<script lang="ts">
  /**
   * MobileKeybar — orchestrator for the Termius-style soft-keyboard system.
   *
   * Three layers:
   *   1. KeybarAccessory — row above the iOS native keyboard
   *   2. KeybarSpecialty — full-replacement grid that takes over the iOS
   *      keyboard area (includes F1–F12 at the bottom)
   *   3. KeybarCustomizeSheet — modal for editing which keys appear
   *
   * Owns:
   *   - `keyboardMode` state ('main' vs 'specialty')
   *   - Sticky modifier latch state (Ctrl, Alt) — tap to arm, double-tap
   *     to lock; next non-modifier key consumes the armed mod
   *   - The dispatch function that resolves `KeySpec.bytes` with sticky
   *     modifiers and calls `inject()`
   *
   * All injection flows through the `inject` prop (parent wires it to
   * `shellStore.injectIntoActive`).
   */
  import { onDestroy } from 'svelte';
  import KeybarAccessory from './KeybarAccessory.svelte';
  import KeybarSpecialty from './KeybarSpecialty.svelte';
  import KeybarCustomizeSheet from './KeybarCustomizeSheet.svelte';
  import type { KeySpec } from '../shell/keys';

  interface Props {
    /** Inject keystrokes into the terminal. Provided by parent. */
    inject: (data: string) => void;
    /** True when the iOS keyboard is visible (parent computes from visualViewport). */
    keyboardVisible: boolean;
    /** Notify parent when our keyboardMode changes — drives the prompt-lock decision. */
    onModeChange?: (mode: 'main' | 'specialty') => void;
    /** Notify parent of the specialty grid's measured height (0 when not specialty). */
    onSpecialtyHeightChange?: (height: number) => void;
  }

  const { inject, keyboardVisible, onModeChange, onSpecialtyHeightChange }: Props = $props();

  /** Active keyboard mode — 'main' renders accessory row only, 'specialty' renders the grid. */
  let keyboardMode = $state<'main' | 'specialty'>('main');
  /** True while the customize sheet is open. */
  let customizeOpen = $state(false);

  // ── Sticky modifier state ──────────────────────────────────────────
  /** Armed (one-shot) modifier — cleared after next non-modifier key. */
  let armedMod = $state<'ctrl' | 'alt' | null>(null);
  /** Locked modifier — persistent until user taps again. */
  let lockedMod = $state<'ctrl' | 'alt' | null>(null);
  /**
   * Double-tap detector for locking a modifier. We record the id + time
   * of the most recent sticky tap; if the same sticky is tapped again
   * within DOUBLE_TAP_MS we promote the arm to a lock.
   */
  const DOUBLE_TAP_MS = 400;
  let lastStickyTap: { id: string; t: number } | null = null;

  function toggleSticky(id: 'ctrl' | 'alt'): void {
    const now = performance.now();
    const isDoubleTap =
      lastStickyTap !== null &&
      lastStickyTap.id === id &&
      now - lastStickyTap.t < DOUBLE_TAP_MS;
    lastStickyTap = { id, t: now };

    // If currently locked, any tap releases.
    if (lockedMod === id) {
      lockedMod = null;
      armedMod = null;
      return;
    }

    // Double-tap from armed → promote to locked.
    if (isDoubleTap && armedMod === id) {
      lockedMod = id;
      armedMod = id;
      return;
    }

    // Single tap toggles armed state.
    armedMod = armedMod === id ? null : id;
  }

  /** Main dispatch: applies armed/locked mods to spec.bytes and calls inject(). */
  function dispatch(spec: KeySpec): void {
    if (spec.sticky) {
      if (spec.id === 'ctrl' || spec.id === 'alt') toggleSticky(spec.id);
      return;
    }

    let bytes = spec.bytes;
    const effectiveMod = lockedMod ?? armedMod;

    if (effectiveMod === 'ctrl' && bytes.length >= 1) {
      // Ctrl + printable ASCII → control byte (bit 5 cleared). xterm/VT
      // convention: Ctrl-@ = NUL (0x00), Ctrl-A = 0x01, … Ctrl-_ = 0x1f.
      // We only transform the first byte so multi-byte sequences (Ctrl
      // shouldn't normally combine with CSI sequences anyway) stay sane.
      const first = bytes.charCodeAt(0);
      if (first >= 0x40 && first <= 0x7e) {
        bytes = String.fromCharCode(first & 0x1f) + bytes.slice(1);
      } else if (first >= 0x20 && first <= 0x3f) {
        // e.g. Ctrl-? = 0x7f (DEL). Rare but legal.
        bytes = String.fromCharCode(first ^ 0x40) + bytes.slice(1);
      }
    }
    if (effectiveMod === 'alt' && bytes.length >= 1) {
      // ESC prefix is the portable Meta encoding xterm.js expects.
      bytes = '\x1b' + bytes;
    }

    inject(bytes);
    // Single-tap armed mods auto-release; locked stays active.
    if (lockedMod === null) armedMod = null;
  }

  function toggleSpecialty(): void {
    keyboardMode = keyboardMode === 'specialty' ? 'main' : 'specialty';
    if (keyboardMode === 'specialty') {
      // Dismiss the iOS native keyboard by blurring whatever is focused.
      // The XtermPane's internal textarea holds focus while the user is
      // typing, and blurring it drops the iOS kbd so our specialty grid
      // can claim that screen space.
      if (typeof document !== 'undefined' && document.activeElement instanceof HTMLElement) {
        document.activeElement.blur();
      }
    }
    onModeChange?.(keyboardMode);
    // When leaving specialty, zero out the height so the prompt-lock
    // releases its custom clamp.
    if (keyboardMode !== 'specialty') onSpecialtyHeightChange?.(0);
  }

  function openCustomize(): void {
    customizeOpen = true;
  }

  function closeCustomize(): void {
    customizeOpen = false;
  }

  function handleSpecialtyHeight(h: number): void {
    onSpecialtyHeightChange?.(h);
  }

  onDestroy(() => {
    onSpecialtyHeightChange?.(0);
  });

  // True when we should render anything at all. Specialty mode is always
  // rendered (it's the replacement for the iOS kbd), accessory row only
  // when iOS keyboard is up.
  const visible = $derived(keyboardVisible || keyboardMode === 'specialty');
</script>

<div class="mobile-keybar" class:visible data-kb-mode={keyboardMode}>
  {#if keyboardMode === 'main' && keyboardVisible}
    <KeybarAccessory
      onPress={dispatch}
      onToggleSpecialty={toggleSpecialty}
      onOpenCustomize={openCustomize}
      {armedMod}
      {lockedMod}
    />
  {:else if keyboardMode === 'specialty'}
    <KeybarSpecialty
      onPress={dispatch}
      onDismiss={toggleSpecialty}
      onOpenCustomize={openCustomize}
      onHeightChange={handleSpecialtyHeight}
      {armedMod}
      {lockedMod}
    />
  {/if}
</div>

<KeybarCustomizeSheet open={customizeOpen} onClose={closeCustomize} />

<style>
  .mobile-keybar {
    display: none;
    flex-direction: column;
    flex-shrink: 0;
  }

  .mobile-keybar.visible {
    display: flex;
  }
</style>
