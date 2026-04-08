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
  import { keybarModifiers } from '../shell/modifiers.svelte';
  import { shellStore } from '../stores/shell.svelte';

  const TMUX_ENTER_COPY_MODE = '\x02['; // Ctrl-B, [
  const TMUX_EXIT_COPY_MODE = 'q';

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
  // State lives in `keybarModifiers` (shared singleton) so XtermPane can
  // intercept iOS soft-keyboard input and apply armed modifiers too. We
  // surface the reactive fields as $derived locals so the rendered
  // children (KeybarAccessory/KeybarSpecialty) don't have to import the
  // store themselves — the prop-drilling shape from Wave 1 is preserved.
  const ctrlArmed = $derived(keybarModifiers.ctrlArmed);
  const ctrlLocked = $derived(keybarModifiers.ctrlLocked);
  const altArmed = $derived(keybarModifiers.altArmed);
  const altLocked = $derived(keybarModifiers.altLocked);

  /**
   * Reactive "is the active tab currently in tmux copy mode". Drives the
   * highlighted state of the `tmux-scroll` button on both the accessory
   * row and the specialty grid. Read from shellStore so a tab switch
   * immediately re-derives the correct visual — different tabs can each
   * be in their own copy-mode state independently.
   */
  const copyModeActive = $derived(shellStore.isInCopyMode(shellStore.activeTabId));

  /**
   * Main dispatch: sticky keys toggle the shared latch; the tmux-scroll
   * key toggles per-tab copy mode (entering sends `^B[`, exiting sends
   * `q`); every other key injects its raw bytes.
   *
   * The ctrl/alt transform + clearArmed() happens inside XtermPane.onData
   * — that's the single chokepoint that normally EVERY input flows through
   * (iOS keyboard, physical keyboard, and keybar injections, since
   * term.input(..., true) fires onData synchronously). The tmux-scroll
   * branch is the ONE exception: see inline comment for why.
   */
  function dispatch(spec: KeySpec): void {
    if (spec.sticky) {
      if (spec.id === 'ctrl' || spec.id === 'alt') keybarModifiers.toggleSticky(spec.id);
      return;
    }
    if (spec.id === 'tmux-scroll') {
      // Toggle semantics so the button's "selected" highlight actually
      // reflects whether we're in copy mode. Client-side tracking is
      // best-effort — see shellStore.copyModeByTab comment for drift
      // behavior. No active tab = no-op (keybar shouldn't be visible
      // with zero tabs anyway, but defensive).
      const tabId = shellStore.activeTabId;
      if (!tabId) return;
      const wasActive = shellStore.isInCopyMode(tabId);
      shellStore.toggleCopyMode(tabId);
      // Send the copy-mode control sequence DIRECTLY via shellStore.send,
      // bypassing XtermPane.onData + keybarModifiers.transform. If the
      // user had Ctrl or Alt armed when they tapped the button, letting
      // the bytes flow through the normal transform chain would corrupt
      // the sequence — Alt would prefix `\x1b` (so `^B[` becomes ESC ^B[
      // and copy-mode entry fails silently); Ctrl would mangle the byte.
      // Still call clearArmed() manually so the user's next keystroke
      // doesn't inherit a one-shot latch they thought they "spent" on
      // this press. Caught by Copilot review on PR #95.
      shellStore.send(tabId, wasActive ? TMUX_EXIT_COPY_MODE : TMUX_ENTER_COPY_MODE);
      keybarModifiers.clearArmed();
      return;
    }
    inject(spec.bytes);
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
      {ctrlArmed}
      {ctrlLocked}
      {altArmed}
      {altLocked}
      {copyModeActive}
    />
  {:else if keyboardMode === 'specialty'}
    <KeybarSpecialty
      onPress={dispatch}
      onDismiss={toggleSpecialty}
      onOpenCustomize={openCustomize}
      onHeightChange={handleSpecialtyHeight}
      {ctrlArmed}
      {ctrlLocked}
      {altArmed}
      {altLocked}
      {copyModeActive}
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
