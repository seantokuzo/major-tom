<script lang="ts">
  /**
   * Shell — top-level container for the Phase 13 terminal experience.
   *
   * Layout:
   *   ┌────────────────┐
   *   │ ShellTabs      │  ← new / close / switch tmux windows
   *   ├────────────────┤
   *   │ XtermPane      │  ← actual xterm.js renderer + WS plumbing
   *   ├────────────────┤
   *   │ MobileKeybar   │  ← visible only when iOS keyboard is up
   *   └────────────────┘
   *
   * Wave 1 ships behind a localStorage feature flag (`mt-shell-enabled`)
   * so the legacy chat layer keeps working until Wave 3 demolition.
   */
  import { onDestroy, onMount } from 'svelte';
  import XtermPane from './XtermPane.svelte';
  import ShellTabs from './ShellTabs.svelte';
  import MobileKeybar from './MobileKeybar.svelte';
  import { shellStore } from '../stores/shell.svelte';
  import { relay } from '../stores/relay.svelte';

  let keyboardVisible = $state(false);
  let cleanupVv: (() => void) | null = null;

  // Ensure at least one tab on mount.
  onMount(() => {
    if (shellStore.tabs.length === 0) {
      shellStore.openTab({
        id: 't1',
        label: 't1',
        cols: 80,
        rows: 24,
        token: relay.authToken,
      });
    }

    // Detect mobile keyboard visibility from visualViewport. The same event
    // fires on rotation and address-bar collapse, so we derive from the
    // height delta rather than treat the event as a flag.
    if (typeof window !== 'undefined' && window.visualViewport) {
      const vv = window.visualViewport;
      let raf = 0;
      const recompute = () => {
        if (raf) cancelAnimationFrame(raf);
        raf = requestAnimationFrame(() => {
          const delta = window.innerHeight - vv.height;
          keyboardVisible = delta > 100;
        });
      };
      vv.addEventListener('resize', recompute);
      vv.addEventListener('scroll', recompute);
      recompute();
      cleanupVv = () => {
        vv.removeEventListener('resize', recompute);
        vv.removeEventListener('scroll', recompute);
        if (raf) cancelAnimationFrame(raf);
      };
    }
  });

  onDestroy(() => {
    cleanupVv?.();
  });

  function handleNewTab(): void {
    shellStore.openTab({
      cols: 80,
      rows: 24,
      token: relay.authToken,
    });
  }

  function handleCloseTab(id: string): void {
    shellStore.closeTab(id);
  }

  function injectFromKeybar(data: string): void {
    shellStore.injectIntoActive(data);
  }
</script>

<div class="shell">
  <ShellTabs onNew={handleNewTab} onClose={handleCloseTab} />
  <div class="panes">
    {#each shellStore.tabs as tab (tab.id)}
      <div class="pane-wrap" class:active={shellStore.activeTabId === tab.id}>
        <XtermPane tabId={tab.id} />
      </div>
    {/each}
    {#if shellStore.tabs.length === 0}
      <div class="empty">No shell session. Tap + above to start one.</div>
    {/if}
  </div>
  <MobileKeybar inject={injectFromKeybar} {keyboardVisible} />
</div>

<style>
  .shell {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0;
    background: #0a0a0a;
    color: #e8e8e8;
  }

  .panes {
    flex: 1;
    position: relative;
    display: flex;
    min-height: 0;
  }

  .pane-wrap {
    flex: 1;
    display: none;
    flex-direction: column;
    min-height: 0;
  }

  .pane-wrap.active {
    display: flex;
  }

  .empty {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #666672;
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
    font-size: 0.8rem;
  }
</style>
