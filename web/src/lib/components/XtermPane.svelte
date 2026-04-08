<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { Terminal } from '@xterm/xterm';
  import { FitAddon } from '@xterm/addon-fit';
  import { WebglAddon } from '@xterm/addon-webgl';
  import { WebLinksAddon } from '@xterm/addon-web-links';
  import '@xterm/xterm/css/xterm.css';
  import { shellStore } from '../stores/shell.svelte';
  import { relay } from '../stores/relay.svelte';

  interface Props {
    tabId: string;
  }

  let { tabId }: Props = $props();

  let containerEl: HTMLDivElement | undefined = $state();
  let term: Terminal | undefined;
  let fit: FitAddon | undefined;
  let webgl: WebglAddon | undefined;
  let resizeObserver: ResizeObserver | undefined;
  let unsubData: (() => void) | undefined;
  let unsubStatus: (() => void) | undefined;
  let lastDims = { cols: 80, rows: 24 };
  let opened = false;

  // iOS Safari aggressively drops WebGL contexts when the PWA backgrounds.
  // Skip the addon entirely on iOS — fall back to the canvas/DOM renderer.
  // (Phase 13 spec, "iOS WebGL context loss" reality check.)
  function isIOS(): boolean {
    if (typeof navigator === 'undefined') return false;
    return /iP(hone|od|ad)/.test(navigator.userAgent);
  }

  onMount(() => {
    if (!containerEl) return;

    term = new Terminal({
      fontFamily: 'Berkeley Mono, ui-monospace, Menlo, monospace',
      // Initial size from the shared store so zoom preference persists
      // across refreshes and new tabs. Reactive updates are handled via
      // the $effect below that watches shellStore.fontSize.
      fontSize: shellStore.fontSize,
      cursorBlink: true,
      allowProposedApi: true,
      scrollback: 5000,
      theme: {
        background: '#0a0a0a',
        foreground: '#e8e8e8',
        cursor: '#e8e8e8',
      },
    });

    fit = new FitAddon();
    term.loadAddon(fit);
    term.loadAddon(new WebLinksAddon());

    if (!isIOS()) {
      try {
        webgl = new WebglAddon();
        webgl.onContextLoss(() => {
          // Drop the addon and let xterm fall back to canvas. Re-init on
          // next mount cycle if the user navigates away and back.
          webgl?.dispose();
          webgl = undefined;
        });
        term.loadAddon(webgl);
      } catch {
        // Some browsers refuse WebGL — silent fallback to canvas renderer.
        webgl = undefined;
      }
    }

    term.open(containerEl);
    opened = true;
    queueFit();

    // Register listeners BEFORE openTab so the WebSocket connection (and
    // any data tmux emits immediately on attach) cannot fire before we're
    // subscribed. shellStore.onData/onStatus accept tab ids that don't
    // exist yet — the listener Set is created lazily. Caught by Copilot
    // review on PR #89; without this, the very first prompt redraw could
    // be silently dropped on a fast-LAN attach.

    // PTY → terminal
    unsubData = shellStore.onData(tabId, (chunk) => {
      term?.write(chunk);
    });

    unsubStatus = shellStore.onStatus(tabId, (status, detail) => {
      if (!term) return;
      if (status === 'connecting') {
        term.write('\r\n\x1b[2;37m[cli] connecting…\x1b[0m\r\n');
      } else if (status === 'open') {
        term.write('\r\n\x1b[2;32m[cli] connected\x1b[0m\r\n');
        // Resync size to the relay on (re)open
        if (lastDims.cols && lastDims.rows) {
          shellStore.sendControl(tabId, { type: 'resize', cols: lastDims.cols, rows: lastDims.rows });
        }
      } else if (status === 'closed') {
        term.write(`\r\n\x1b[2;33m[cli] disconnected${detail ? ` (${detail})` : ''}\x1b[0m\r\n`);
      } else if (status === 'error') {
        term.write(`\r\n\x1b[2;31m[cli] error${detail ? `: ${detail}` : ''}\x1b[0m\r\n`);
      }
    });

    // Now that data + status listeners are wired, kick off the WS attach.
    // Order matters: openTab() constructs the WebSocket synchronously and
    // any first-frame data must land in our onData listener above.
    const existing = shellStore.tabs.find((t) => t.id === tabId);
    if (!existing) {
      shellStore.openTab({
        id: tabId,
        label: tabId,
        cols: lastDims.cols,
        rows: lastDims.rows,
        token: relay.authToken,
      });
    }

    // Terminal → PTY (handles keyboard, paste, AND keybar via term.input())
    term.onData((data) => {
      shellStore.send(tabId, data);
    });

    term.onResize(({ cols, rows }) => {
      lastDims = { cols, rows };
      shellStore.sendControl(tabId, { type: 'resize', cols, rows });
    });

    // Refit on container changes
    if (typeof ResizeObserver !== 'undefined') {
      resizeObserver = new ResizeObserver(() => queueFit());
      resizeObserver.observe(containerEl);
    }

    // Refit on visualViewport changes (mobile keyboard show/hide,
    // address-bar collapse, rotation). visualViewport is the right
    // signal here because it accounts for the keyboard.
    if (typeof window !== 'undefined' && window.visualViewport) {
      window.visualViewport.addEventListener('resize', queueFit);
      window.visualViewport.addEventListener('scroll', queueFit);
    }

    term.focus();

    // Let the keybar inject keystrokes into THIS pane's terminal.
    shellStore.registerInjector(tabId, (data) => {
      term?.input(data, true);
    });
    // Let the keybar restore focus to this terminal (e.g. after dismissing
    // the specialty grid so the iOS keyboard comes back up).
    shellStore.registerFocuser(tabId, () => {
      term?.focus();
    });
  });

  let pendingFit = false;
  function queueFit(): void {
    if (pendingFit) return;
    pendingFit = true;
    requestAnimationFrame(() => {
      pendingFit = false;
      if (!opened || !fit || !term || !containerEl) return;
      try {
        fit.fit();
      } catch {
        // fit() can throw if the container has zero height (e.g. tab hidden)
      }
    });
  }

  // Reactively sync the xterm font size with the shared store. Bumping the
  // font size invalidates the cached cell dimensions, so we also have to
  // refit — otherwise the terminal keeps rendering at the previous grid
  // size and half the prompt falls off the right edge.
  $effect(() => {
    const size = shellStore.fontSize;
    if (!term) return;
    if (term.options.fontSize === size) return;
    term.options.fontSize = size;
    queueFit();
  });

  onDestroy(() => {
    shellStore.unregisterInjector(tabId);
    shellStore.unregisterFocuser(tabId);
    unsubData?.();
    unsubStatus?.();
    if (typeof window !== 'undefined' && window.visualViewport) {
      window.visualViewport.removeEventListener('resize', queueFit);
      window.visualViewport.removeEventListener('scroll', queueFit);
    }
    resizeObserver?.disconnect();
    webgl?.dispose();
    term?.dispose();
  });
</script>

<div class="xterm-pane" bind:this={containerEl}></div>

<style>
  .xterm-pane {
    flex: 1;
    min-height: 0;
    width: 100%;
    background: #0a0a0a;
    /* xterm needs a positioned container for some addons. */
    position: relative;
    overflow: hidden;
  }

  /* xterm.css ships its own .xterm rules; this just lets it fill the pane. */
  .xterm-pane :global(.xterm) {
    height: 100%;
    width: 100%;
    padding: 6px 8px;
    box-sizing: border-box;
  }

  /* Mobile: shave padding so the prompt line gets every last column. */
  @media (max-width: 480px) {
    .xterm-pane :global(.xterm) {
      padding: 2px 4px;
    }
  }

  .xterm-pane :global(.xterm-viewport) {
    overflow-y: auto;
  }
</style>
