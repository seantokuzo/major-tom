<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { Terminal } from '@xterm/xterm';
  import { FitAddon } from '@xterm/addon-fit';
  import { WebglAddon } from '@xterm/addon-webgl';
  import { WebLinksAddon } from '@xterm/addon-web-links';
  import '@xterm/xterm/css/xterm.css';
  import { shellStore } from '../stores/shell.svelte';
  import { relay } from '../stores/relay.svelte';
  import { keybarModifiers } from '../shell/modifiers.svelte';

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

  // ── Drag-to-scroll (tmux copy mode) ────────────────────────────────
  // When the active tab is in tmux copy mode (user tapped the tmux-scroll
  // button on the keybar, flipping shellStore.copyModeByTab[tabId] = true),
  // we hijack vertical touch drags on this pane and translate them into
  // synthetic Up/Down arrow keys into the PTY. tmux copy mode moves the
  // selection cursor one line per Up/Down, which in turn scrolls the
  // viewport when the cursor hits the top/bottom edge — exactly the
  // "tap-and-drag to scroll through scrollback" UX from Termius.
  //
  // Direction mapping: a finger moving DOWN wants to reveal OLDER content
  // (scroll up toward the top of scrollback), which is Up arrow in copy
  // mode. A finger moving UP wants newer content = Down arrow. Matches
  // natural iOS scroll intuition.
  //
  // The accumulator pattern means fast swipes emit multiple arrow keys in
  // a single pointermove event (batched into one shellStore.send() call
  // so we don't flood the WS), and sub-threshold movement across event
  // boundaries isn't lost. 18px per line feels about right on a normal
  // iPhone — snappy but not twitchy.
  const DRAG_LINE_PX = 18;
  const ARROW_UP = '\x1b[A';
  const ARROW_DOWN = '\x1b[B';

  let dragging = false;
  let dragPointerId = -1;
  let dragLastY = 0;
  let dragAccumulator = 0;
  const copyModeActive = $derived(shellStore.isInCopyMode(tabId));

  function handleDragDown(e: PointerEvent): void {
    if (!copyModeActive) return;
    // Touch-only gesture. iPadOS users with a trackpad or mouse still
    // send PointerEvents, but for them a drag means "select text" or
    // "drag the cursor", not "scroll tmux scrollback" — they have a
    // real scroll wheel for that. Filtering on pointerType keeps mouse
    // drags doing their native thing even when copy mode is toggled on.
    // Caught by Copilot review on PR #95.
    if (e.pointerType !== 'touch') return;
    // Primary pointer only — ignore multi-touch / right-click / stylus
    // secondary buttons so we don't fight a pinch gesture.
    if (!e.isPrimary) return;
    e.preventDefault();
    dragging = true;
    dragPointerId = e.pointerId;
    dragLastY = e.clientY;
    dragAccumulator = 0;
    // Capture so moves outside this element still reach us — without
    // this, a finger sliding off the top of the xterm pane onto the
    // tab bar would silently end the gesture.
    containerEl?.setPointerCapture(e.pointerId);
  }

  function handleDragMove(e: PointerEvent): void {
    if (!dragging || e.pointerId !== dragPointerId) return;
    // NOT gating on copyModeActive here — once a drag has started, finish
    // it with the original semantics even if the user happens to tap the
    // scroll button mid-gesture. Releasing the finger cleans up; until
    // then we honor the drag that was in flight.
    e.preventDefault();
    const curY = e.clientY;
    dragAccumulator += curY - dragLastY;
    dragLastY = curY;
    // Drain the accumulator into whole-line counts. Finger DOWN (positive
    // delta) → UP arrows (older content). Finger UP (negative delta) →
    // DOWN arrows (newer content).
    let linesUp = 0;
    let linesDown = 0;
    while (dragAccumulator >= DRAG_LINE_PX) {
      linesUp++;
      dragAccumulator -= DRAG_LINE_PX;
    }
    while (dragAccumulator <= -DRAG_LINE_PX) {
      linesDown++;
      dragAccumulator += DRAG_LINE_PX;
    }
    // Only one of linesUp/linesDown can be non-zero in a single event
    // (the accumulator is strictly signed after the loop runs), but the
    // code is trivially safe either way.
    if (linesUp > 0) shellStore.send(tabId, ARROW_UP.repeat(linesUp));
    if (linesDown > 0) shellStore.send(tabId, ARROW_DOWN.repeat(linesDown));
  }

  function handleDragEnd(e: PointerEvent): void {
    if (!dragging || e.pointerId !== dragPointerId) return;
    dragging = false;
    dragAccumulator = 0;
    if (containerEl?.hasPointerCapture(e.pointerId)) {
      containerEl.releasePointerCapture(e.pointerId);
    }
    dragPointerId = -1;
  }

  // iOS Safari aggressively drops WebGL contexts when the PWA backgrounds.
  // Skip the addon entirely on iOS — fall back to the canvas/DOM renderer.
  // (Phase 13 spec, "iOS WebGL context loss" reality check.)
  function isIOS(): boolean {
    if (typeof navigator === 'undefined') return false;
    return /iP(hone|od|ad)/.test(navigator.userAgent);
  }

  // When the user taps into the terminal, iOS pops up the software keyboard
  // plus a "QuickType" assist bar above it (password / credit card / contact
  // suggestions on the left, a collapse checkmark on the right). The web
  // platform can't remove that bar entirely — Termius manages it because it
  // is a native app using UITextField.inputAssistantItem, an API that is
  // unreachable from a PWA. But we CAN suppress most of the left-side junk
  // by telling iOS this input is not a form field, not a password, not a
  // credit card, and has no autocomplete use.
  //
  // xterm.js maintains a hidden `.xterm-helper-textarea` inside its root
  // that receives keyboard input — we apply the attribute soup directly to
  // that element. The right-side collapse checkmark stays; that's baked
  // into iOS and not removable from a web context.
  function suppressIOSInputAssistance(container: HTMLDivElement): void {
    const helper = container.querySelector(
      '.xterm-helper-textarea'
    ) as HTMLTextAreaElement | null;
    if (!helper) return;
    helper.setAttribute('autocomplete', 'off');
    helper.setAttribute('autocorrect', 'off');
    helper.setAttribute('autocapitalize', 'off');
    helper.setAttribute('spellcheck', 'false');
    helper.setAttribute('enterkeyhint', 'send');
    // 1Password / LastPass / Bitwarden hints — stops them from injecting a
    // "fill with password" button into the assist bar on iOS.
    helper.setAttribute('data-1p-ignore', 'true');
    helper.setAttribute('data-lpignore', 'true');
    helper.setAttribute('data-form-type', 'other');
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
    suppressIOSInputAssistance(containerEl);

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

    // Terminal → PTY (handles keyboard, paste, AND keybar via term.input()).
    //
    // Bug 5 fix: apply any currently-armed keybar modifier to the bytes
    // before they leave the browser. Without this, the user can tap
    // Ctrl on the soft keybar and then type 'c' on the iOS keyboard —
    // and the literal 'c' lands at the prompt because iOS input never
    // touches the keybar's dispatch function. keybarModifiers.transform
    // is a no-op when nothing is armed, so desktop-only users who never
    // interact with the keybar pay zero cost.
    term.onData((data) => {
      // Transform contract says empty input is a no-op (no transform,
      // no clear). Gate BOTH the send and the clearArmed behind a
      // non-empty check so an empty onData event (possible in some
      // xterm.js edge cases) does not silently release the user's
      // armed Ctrl/Alt latch. Caught by Copilot PR #93 round 4 review.
      if (data.length === 0) return;
      const transformed = keybarModifiers.transform(data);
      shellStore.send(tabId, transformed);
      keybarModifiers.clearArmed();
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

  // When this tab becomes active, refit xterm (the container may have
  // resized while hidden under `display: none`) and steal focus so the
  // iOS soft-keyboard pops straight up without a second tap. Local-only
  // work — no wire traffic. The v2 relay streams PTY output live, so no
  // server-side redraw nudge is needed.
  $effect(() => {
    const seq = shellStore.activationSeq[tabId];
    if (!seq) return;
    if (shellStore.activeTabId !== tabId) return;
    if (!opened) return;
    requestAnimationFrame(() => {
      queueFit();
      term?.focus();
    });
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

<div
  class="xterm-pane"
  class:copy-mode={copyModeActive}
  bind:this={containerEl}
  onpointerdown={handleDragDown}
  onpointermove={handleDragMove}
  onpointerup={handleDragEnd}
  onpointercancel={handleDragEnd}
></div>

<style>
  .xterm-pane {
    flex: 1;
    min-height: 0;
    width: 100%;
    background: #0a0a0a;
    /* xterm needs a positioned container for some addons. */
    position: relative;
    overflow: hidden;
    /* Always prevent browser scroll gestures — xterm handles its own
       scrollback internally via .xterm-viewport overflow-y: auto. */
    touch-action: none;
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
