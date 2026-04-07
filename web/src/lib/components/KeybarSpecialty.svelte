<script lang="ts">
  /**
   * KeybarSpecialty — full-replacement soft keyboard that takes over the
   * iOS keyboard area when the user taps the specialty toggle. Renders
   * a dense wrap-grid of specialty keys. F-keys (the last 12 in the
   * default config) are given their own bottom row per Termius convention.
   *
   * Emits `onHeightChange` whenever its rendered height changes so that
   * Shell.svelte can publish it into `--vv-h` for the prompt-line lock.
   */
  import { onDestroy, onMount } from 'svelte';
  import { keybarStore } from '../stores/keybar.svelte';
  import type { KeySpec } from '../shell/keys';

  interface Props {
    onPress: (spec: KeySpec) => void;
    onDismiss: () => void;
    onOpenCustomize: () => void;
    onHeightChange: (h: number) => void;
    armedMod: 'ctrl' | 'alt' | null;
    lockedMod: 'ctrl' | 'alt' | null;
  }

  const {
    onPress,
    onDismiss,
    onOpenCustomize,
    onHeightChange,
    armedMod,
    lockedMod,
  }: Props = $props();

  let rootEl: HTMLDivElement | undefined = $state();
  let resizeObserver: ResizeObserver | undefined;

  // Partition keys into function row vs rest so we can render the F-row
  // at the bottom of the grid, even when the user customized the order.
  let mainKeys = $derived<KeySpec[]>(
    keybarStore.specialtyKeys.filter((k) => k.group !== 'function')
  );
  let functionKeys = $derived<KeySpec[]>(
    keybarStore.specialtyKeys.filter((k) => k.group === 'function')
  );

  onMount(() => {
    if (rootEl && typeof ResizeObserver !== 'undefined') {
      resizeObserver = new ResizeObserver(() => {
        if (rootEl) onHeightChange(rootEl.getBoundingClientRect().height);
      });
      resizeObserver.observe(rootEl);
    }
    // Emit an initial height so the parent's lock sizing is correct on mount.
    if (rootEl) onHeightChange(rootEl.getBoundingClientRect().height);
  });

  onDestroy(() => {
    resizeObserver?.disconnect();
    // Release the parent's height clamp when we unmount.
    onHeightChange(0);
  });

  function handleKey(spec: KeySpec, e: Event): void {
    e.preventDefault();
    onPress(spec);
  }

  function isArmed(spec: KeySpec): boolean {
    return !!spec.sticky && armedMod === spec.id && lockedMod !== spec.id;
  }

  function isLocked(spec: KeySpec): boolean {
    return !!spec.sticky && lockedMod === spec.id;
  }
</script>

<div class="kb-specialty" bind:this={rootEl} aria-label="Specialty keyboard">
  <div class="kb-specialty-header">
    <button
      type="button"
      class="header-btn"
      onpointerdown={(e) => {
        e.preventDefault();
        onDismiss();
      }}
    >
      ABC
    </button>
    <div class="header-title">Specialty</div>
    <button
      type="button"
      class="header-btn"
      onpointerdown={(e) => {
        e.preventDefault();
        onOpenCustomize();
      }}
    >
      ⚙
    </button>
  </div>

  <div class="kb-specialty-grid">
    {#each mainKeys as spec (spec.id)}
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

  {#if functionKeys.length > 0}
    <div class="kb-specialty-frow">
      {#each functionKeys as spec (spec.id)}
        <button
          type="button"
          class="key fkey"
          data-key-id={spec.id}
          aria-label={spec.description ?? spec.label}
          title={spec.description ?? spec.label}
          onpointerdown={(e) => handleKey(spec, e)}
        >
          {spec.label}
        </button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .kb-specialty {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 6px 6px 8px;
    background: #0e0e13;
    border-top: 1px solid #25252c;
    flex-shrink: 0;
    max-height: 50vh;
    overflow-y: auto;
    -webkit-overflow-scrolling: touch;
  }

  .kb-specialty-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 2px 4px;
  }

  .header-btn {
    min-width: 44px;
    height: 28px;
    padding: 0 10px;
    border: 1px solid #2a2a32;
    border-radius: 6px;
    background: #16161d;
    color: #c0c0c8;
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
    font-size: 0.78rem;
    font-weight: 600;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    user-select: none;
    touch-action: manipulation;
  }

  .header-title {
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
    font-size: 0.72rem;
    color: #6a6a78;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .kb-specialty-grid {
    display: grid;
    grid-template-columns: repeat(8, minmax(0, 1fr));
    gap: 4px;
  }

  .kb-specialty-frow {
    display: grid;
    grid-template-columns: repeat(12, minmax(0, 1fr));
    gap: 3px;
    padding-top: 4px;
    border-top: 1px solid #20202a;
  }

  .key {
    min-width: 0;
    height: 36px;
    padding: 0 4px;
    border: 1px solid #2a2a32;
    border-radius: 6px;
    background: #1a1a22;
    color: #e0e0e8;
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
    font-size: 0.78rem;
    font-weight: 600;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    user-select: none;
    touch-action: manipulation;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .key:active {
    background: #25252e;
  }

  .key.fkey {
    height: 30px;
    font-size: 0.7rem;
    background: #15151c;
    color: #b0b0bc;
  }

  .key.primary {
    background: #1d2a3d;
    border-color: #345077;
    color: #9fcdf6;
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
</style>
