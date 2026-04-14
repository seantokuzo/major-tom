/**
 * Shell store — owns per-tab WebSocket connections to /shell/:tabId,
 * tracks focus, and exposes a tiny imperative API for the xterm pane.
 *
 * Terminal protocol v2: each tab is one PTY session. Reconnect logic is
 * intentionally simple — exponential backoff up to 20 attempts; the relay
 * holds the PTY through a 30-min grace so backgrounding / network drops
 * don't lose state.
 */

interface ShellTab {
  id: string;
  /** Display label in the tab strip; defaults to id. */
  label: string;
  /** Active WebSocket, if any. Recreated on reconnect. */
  socket: WebSocket | null;
  /** Reconnect attempt counter (resets on successful open). */
  reconnectAttempt: number;
  /** Reconnect timer handle. */
  reconnectTimer: number | null;
  /** True once the WS is OPEN. */
  connected: boolean;
  /**
   * Dev-mode legacy auth token (relayStore.authToken), stashed at openTab
   * time so the REST kill fallback can mirror the WS route's `?token=`
   * query-param path when the user is using legacy token auth instead of
   * the Google session cookie. Null in production / Google-auth mode.
   * Added for Copilot PR #94 review round 3.
   */
  token: string | null;
}

/** Detect the relay base from the current page origin (same logic as relay store). */
function detectRelayHost(): string {
  if (typeof window === 'undefined') return 'localhost:9090';
  const { hostname, port } = window.location;
  return port ? `${hostname}:${port}` : hostname;
}

function buildShellUrl(tabId: string, cols: number, rows: number, token: string | null): string {
  const proto = typeof window !== 'undefined' && window.location.protocol === 'https:' ? 'wss' : 'ws';
  const host = detectRelayHost();
  const params = new URLSearchParams();
  params.set('cols', String(cols));
  params.set('rows', String(rows));
  if (token) params.set('token', token);
  return `${proto}://${host}/shell/${encodeURIComponent(tabId)}?${params.toString()}`;
}

const MAX_RECONNECT_ATTEMPTS = 20;
const RECONNECT_BASE_MS = 500;
const RECONNECT_MAX_MS = 10_000;

/** Font size clamp: too small = unreadable, too large = one glyph fills the pane. */
const FONT_SIZE_MIN = 8;
const FONT_SIZE_MAX = 28;
const FONT_SIZE_STORAGE_KEY = 'mt-cli-font-size';

/** Compute the default font size for a fresh install: smaller on phones. */
function defaultFontSize(): number {
  if (typeof window === 'undefined') return 14;
  try {
    if (typeof window.matchMedia === 'function' && window.matchMedia('(max-width: 480px)').matches) {
      return 12;
    }
  } catch {
    // matchMedia can throw in some test harnesses
  }
  return 14;
}

function loadPersistedFontSize(): number {
  if (typeof window === 'undefined') return 14;
  try {
    const raw = window.localStorage.getItem(FONT_SIZE_STORAGE_KEY);
    if (raw) {
      const n = Number(raw);
      if (Number.isFinite(n) && n >= FONT_SIZE_MIN && n <= FONT_SIZE_MAX) {
        return Math.floor(n);
      }
    }
  } catch {
    // Privacy mode / quota — fall through to default
  }
  return defaultFontSize();
}

/** Listener type for binary frames coming from the relay PTY. */
export type DataListener = (chunk: Uint8Array) => void;
export type StatusListener = (status: 'connecting' | 'open' | 'closed' | 'error', detail?: string) => void;
/** Inject callback registered by an XtermPane so the keybar can drive its terminal. */
export type Injector = (data: string) => void;
/** Focus callback registered by an XtermPane so the keybar can restore focus. */
export type Focuser = () => void;

class ShellStore {
  tabs = $state<ShellTab[]>([]);
  activeTabId = $state<string | null>(null);
  /**
   * Terminal font size in pixels, persisted per-device so phone and
   * desktop can each pick their comfortable zoom level. Mutate via
   * setFontSize/bumpFontSize; XtermPane reacts via $effect.
   */
  fontSize = $state<number>(loadPersistedFontSize());
  /**
   * Monotonic per-tab activation counter. Bumped by activateInternal()
   * whenever a tab becomes active — that covers openTab (new + re-open),
   * the closeTab fallback to tabs[0], and explicit setActive() calls.
   * The XtermPane for the newly-visible tab watches its own entry via a
   * $effect and, on bump, refits its xterm instance + steals focus so
   * the soft keyboard pops back up. No wire traffic is emitted — the
   * relay streams PTY output live and no redraw nudge is needed.
   */
  activationSeq = $state<Record<string, number>>({});
  /**
   * Per-tab "is in tmux copy mode" flag. Flipped by the tmux-scroll button
   * on the keybar — first press enters copy mode (`^B[`), second press exits
   * (`q`). Used by:
   *   - KeybarAccessory / KeybarSpecialty to light up the scroll button
   *     ONLY when the flag is truthy (instead of always-highlighted).
   *   - XtermPane to flip on its drag-to-scroll touch handlers, so a
   *     tap-and-drag on the terminal body synthesizes Up/Down arrows into
   *     the PTY and navigates tmux's copy-mode cursor line-by-line —
   *     matching Termius's scroll-in-copy-mode UX.
   *
   * Drift note: the client can't observe tmux's real copy-mode state, so
   * exiting copy mode via a hardware keyboard (`q`, `Escape` in vi-mode)
   * leaves this flag stale. Recovery: the next tap on the scroll button
   * sends the wrong byte sequence (`q` at a bash prompt is harmless, a
   * bare `^B[` in actual copy mode is a no-op), and the tap after that
   * resyncs to the correct state. Two-tap recovery is an acceptable
   * trade for not needing a server round-trip to track mode.
   */
  copyModeByTab = $state<Record<string, boolean>>({});

  /** tabId → set of listeners for binary PTY data. */
  private dataListeners = new Map<string, Set<DataListener>>();
  /** tabId → set of listeners for connection status changes. */
  private statusListeners = new Map<string, Set<StatusListener>>();
  /** tabId → mounted XtermPane's `term.input()` shim (set on mount, cleared on destroy). */
  private injectors = new Map<string, Injector>();
  /** tabId → mounted XtermPane's `term.focus()` shim. Used by MobileKeybar to re-focus
   *  the terminal after dismissing the specialty grid so the iOS keyboard reopens. */
  private focusers = new Map<string, Focuser>();

  registerInjector(tabId: string, injector: Injector): void {
    this.injectors.set(tabId, injector);
  }

  unregisterInjector(tabId: string): void {
    this.injectors.delete(tabId);
  }

  registerFocuser(tabId: string, focuser: Focuser): void {
    this.focusers.set(tabId, focuser);
  }

  unregisterFocuser(tabId: string): void {
    this.focusers.delete(tabId);
  }

  /** Inject text into the active tab's terminal (used by MobileKeybar). */
  injectIntoActive(data: string): void {
    const id = this.activeTabId;
    if (!id) return;
    const fn = this.injectors.get(id);
    if (fn) fn(data);
  }

  /** Focus the active tab's terminal (used when leaving specialty keyboard). */
  focusActive(): void {
    const id = this.activeTabId;
    if (!id) return;
    const fn = this.focusers.get(id);
    if (fn) fn();
  }

  // ── Copy-mode state (drag-to-scroll) ────────────────────────────
  isInCopyMode(tabId: string | null): boolean {
    if (!tabId) return false;
    return this.copyModeByTab[tabId] === true;
  }

  /** Flip the flag for a tab and return the new state. */
  toggleCopyMode(tabId: string): boolean {
    const next = !this.isInCopyMode(tabId);
    this.copyModeByTab = { ...this.copyModeByTab, [tabId]: next };
    return next;
  }

  /** Remove the entry for a tab entirely (used on closeTab cleanup). */
  clearCopyMode(tabId: string): void {
    if (!(tabId in this.copyModeByTab)) return;
    const next = { ...this.copyModeByTab };
    delete next[tabId];
    this.copyModeByTab = next;
  }

  /** Add a new tab and connect immediately. Returns the tab id. */
  openTab(opts: { id?: string; label?: string; cols: number; rows: number; token: string | null }): string {
    const id = opts.id ?? this.generateTabId();
    if (this.tabs.find((t) => t.id === id)) {
      // Re-focusing an existing tab is just an activation — route it
      // through the shared helper so the XtermPane refresh $effect
      // fires for this path too (Copilot PR #93 review).
      this.activateInternal(id);
      return id;
    }
    const tab: ShellTab = {
      id,
      label: opts.label ?? id,
      socket: null,
      reconnectAttempt: 0,
      reconnectTimer: null,
      connected: false,
      token: opts.token,
    };
    this.tabs.push(tab);
    this.activateInternal(id);
    this.connect(id, opts.cols, opts.rows, opts.token);
    return id;
  }

  closeTab(tabId: string): void {
    const idx = this.tabs.findIndex((t) => t.id === tabId);
    if (idx === -1) return;
    const tab = this.tabs[idx]!;
    if (tab.reconnectTimer !== null) {
      clearTimeout(tab.reconnectTimer);
    }
    // Tell the relay to terminate the underlying PTY, not just detach
    // this client. Without this, closing a tab would leave the PTY
    // alive in the relay's session map until the 30-min grace timer
    // expired — a stranded process per closed tab.
    //
    // Two paths depending on WebSocket state:
    //   OPEN  → send {type:'kill'} in-band. WebSocket preserves frame
    //           ordering on the wire so the server processes kill →
    //           close in that order. Fast, stays on the existing socket.
    //   other → CONNECTING/CLOSING/CLOSED/null all mean the in-band
    //           send is a no-op, which would strand the PTY in the
    //           relay's grace window (it will eventually reap, but not
    //           promptly). Fall back to POST /shell/:tabId/kill so
    //           "close tab" is reliably destructive in every socket
    //           state. Caught by Copilot PR #94 review round 2.
    if (tab.socket && tab.socket.readyState === WebSocket.OPEN) {
      let sent = false;
      try {
        tab.socket.send(JSON.stringify({ type: 'kill' }));
        sent = true;
      } catch {
        // send threw despite readyState === OPEN (rare race) — fall
        // through to the REST fallback so the window still gets killed.
      }
      if (!sent) {
        void this.killWindowRest(tabId, tab.token);
      }
    } else {
      void this.killWindowRest(tabId, tab.token);
    }
    if (tab.socket) {
      try { tab.socket.close(1000, 'tab-closed'); } catch { /* ignore */ }
    }
    this.tabs.splice(idx, 1);
    this.dataListeners.delete(tabId);
    this.statusListeners.delete(tabId);
    // Drop the stale activation counter entry too. Reactive spread with
    // `delete` on a clone so the $state proxy observes the change.
    // Without this the record grows unbounded over the app's lifetime —
    // microscopic per-entry, but "open N tabs → close them all → repeat"
    // is a perfectly normal usage pattern and leaking keys has no upside.
    if (tabId in this.activationSeq) {
      const next = { ...this.activationSeq };
      delete next[tabId];
      this.activationSeq = next;
    }
    // Drop the copy-mode flag too so a future tab re-using the same id
    // (unlikely but possible via explicit openTab({id})) doesn't inherit
    // a stale true.
    this.clearCopyMode(tabId);
    if (this.activeTabId === tabId) {
      // Falling back to the first remaining tab (if any) — route through
      // activateInternal so the newly-visible pane gets a fresh paint.
      // Null = no tabs left, nothing to activate.
      this.activateInternal(this.tabs[0]?.id ?? null);
    }
  }

  setActive(tabId: string): void {
    if (this.tabs.find((t) => t.id === tabId)) {
      this.activateInternal(tabId);
    }
  }

  /**
   * Single chokepoint for mutating `activeTabId`. Bumping the activation
   * counter here means every path that changes the visible tab (openTab,
   * re-openTab, closeTab fallback, setActive) triggers the XtermPane
   * refresh $effect — not just the explicit user-initiated switches.
   * Caught by Copilot review on PR #93.
   */
  private activateInternal(tabId: string | null): void {
    this.activeTabId = tabId;
    if (tabId === null) return;
    const prev = this.activationSeq[tabId] ?? 0;
    this.activationSeq = { ...this.activationSeq, [tabId]: prev + 1 };
  }

  /** Font size accessors — persist to localStorage on every change. */
  setFontSize(px: number): void {
    // Guard against NaN/Infinity leaking into localStorage. Math.floor(NaN)
    // returns NaN and then the clamp Math.max/Math.min propagates it, so
    // without this early return a bad caller could poison the persisted
    // size and brick the terminal until the user manually clears storage.
    // Caught by Copilot PR #93 round 4 review.
    if (!Number.isFinite(px)) return;
    const clamped = Math.max(FONT_SIZE_MIN, Math.min(FONT_SIZE_MAX, Math.floor(px)));
    if (clamped === this.fontSize) return;
    this.fontSize = clamped;
    if (typeof window === 'undefined') return;
    try {
      window.localStorage.setItem(FONT_SIZE_STORAGE_KEY, String(clamped));
    } catch {
      // Privacy mode / quota — state-only change is fine
    }
  }

  bumpFontSize(delta: number): void {
    this.setFontSize(this.fontSize + delta);
  }

  /**
   * Push raw bytes to the PTY. String input is UTF-8 encoded so the
   * browser sends a *binary* WebSocket frame — the relay PTY route
   * treats text frames as JSON control messages, so unencoded strings
   * would be silently dropped (caught by Copilot review on PR #89).
   */
  send(tabId: string, data: string | Uint8Array): void {
    const tab = this.tabs.find((t) => t.id === tabId);
    if (!tab || !tab.socket || tab.socket.readyState !== WebSocket.OPEN) return;
    const payload = typeof data === 'string' ? new TextEncoder().encode(data) : data;
    tab.socket.send(payload);
  }

  /** Send a JSON control frame (resize, etc). */
  sendControl(tabId: string, message: Record<string, unknown>): void {
    const tab = this.tabs.find((t) => t.id === tabId);
    if (!tab || !tab.socket || tab.socket.readyState !== WebSocket.OPEN) return;
    tab.socket.send(JSON.stringify(message));
  }

  onData(tabId: string, listener: DataListener): () => void {
    let set = this.dataListeners.get(tabId);
    if (!set) {
      set = new Set();
      this.dataListeners.set(tabId, set);
    }
    set.add(listener);
    return () => set!.delete(listener);
  }

  onStatus(tabId: string, listener: StatusListener): () => void {
    let set = this.statusListeners.get(tabId);
    if (!set) {
      set = new Set();
      this.statusListeners.set(tabId, set);
    }
    set.add(listener);
    return () => set!.delete(listener);
  }

  private generateTabId(): string {
    let n = 1;
    while (this.tabs.find((t) => t.id === `t${n}`)) n++;
    return `t${n}`;
  }

  /**
   * REST fallback for killing a PTY when the shell WebSocket is not in
   * OPEN state (CONNECTING, CLOSING, CLOSED, or null). The relay
   * endpoint mirrors the shell WS auth: session cookie primary, dev-only
   * `?token=AUTH_TOKEN` legacy fallback. We pass the same token the
   * tab's WebSocket used at connect time when available so users
   * relying on legacy token auth (no Google session cookie) don't hit a
   * 401 on this fallback — which would leave the PTY stranded in the
   * relay's grace window for CONNECTING/CLOSED socket states. Caught by
   * Copilot PR #94 review round 3.
   *
   * Fire-and-forget on purpose — closeTab() continues synchronously and
   * the UI tab is removed immediately regardless of whether the kill
   * request lands. If it fails we log a warning and move on; the worst
   * case is a PTY that lingers until the grace timer reaps it, which is
   * the same outcome as before this fallback existed (so no regression).
   *
   * Added as part of Copilot PR #94 review round 2 — the in-band kill
   * frame was only sent on OPEN sockets, so closing during the initial
   * connect or a mid-reconnect left the PTY stranded.
   */
  private async killWindowRest(tabId: string, token: string | null): Promise<void> {
    if (typeof window === 'undefined') return;
    const host = detectRelayHost();
    const proto = window.location.protocol === 'https:' ? 'https' : 'http';
    const params = new URLSearchParams();
    if (token) params.set('token', token);
    const qs = params.toString();
    const url = `${proto}://${host}/shell/${encodeURIComponent(tabId)}/kill${qs ? `?${qs}` : ''}`;
    try {
      const res = await fetch(url, {
        method: 'POST',
        credentials: 'include',
      });
      if (!res.ok) {
        console.warn(
          `[shellStore] REST kill fallback returned ${res.status} for tab ${tabId}`,
        );
      }
    } catch (err) {
      console.warn(
        `[shellStore] REST kill fallback threw for tab ${tabId}:`,
        err,
      );
    }
  }

  private connect(tabId: string, cols: number, rows: number, token: string | null): void {
    const tab = this.tabs.find((t) => t.id === tabId);
    if (!tab) return;
    if (tab.socket) {
      try { tab.socket.close(); } catch { /* ignore */ }
    }
    this.emitStatus(tabId, 'connecting');
    const url = buildShellUrl(tabId, cols, rows, token);
    const ws = new WebSocket(url);
    ws.binaryType = 'arraybuffer';

    ws.addEventListener('open', () => {
      tab.connected = true;
      tab.reconnectAttempt = 0;
      this.emitStatus(tabId, 'open');
    });

    ws.addEventListener('message', (ev) => {
      if (ev.data instanceof ArrayBuffer) {
        const chunk = new Uint8Array(ev.data);
        const set = this.dataListeners.get(tabId);
        if (set) {
          for (const listener of set) listener(chunk);
        }
        return;
      }
      // Text frame: control message from server (attached, exit, error)
      if (typeof ev.data === 'string') {
        try {
          const ctrl = JSON.parse(ev.data) as Record<string, unknown>;
          const type = ctrl['type'];
          if (type === 'attached') {
            // v2 handshake frame: server confirms attach. `restored=true`
            // means we reattached to a PTY that was alive in the relay's
            // grace window (background-resume case); false means a fresh
            // PTY spawn. Log-only for now — no UI surface. Future: show
            // a subtle "resumed" indicator for analytics / UX.
            const restored = ctrl['restored'] === true;
            console.info(
              `[shellStore] attached tab=${tabId} restored=${restored}`,
            );
          } else if (type === 'exit') {
            this.emitStatus(tabId, 'closed', 'pty-exit');
          } else if (type === 'error') {
            this.emitStatus(tabId, 'error', String(ctrl['message'] ?? ''));
          }
          // Unknown `type` values are silently ignored — lets the server
          // introduce new control frames without breaking older clients.
        } catch {
          // ignore malformed control frames
        }
      }
    });

    ws.addEventListener('close', (ev) => {
      tab.connected = false;
      tab.socket = null;
      this.emitStatus(tabId, 'closed', `code=${ev.code}`);
      // Auth failures (1008) should not retry forever
      if (ev.code === 1008) return;
      this.scheduleReconnect(tabId, cols, rows, token);
    });

    ws.addEventListener('error', () => {
      this.emitStatus(tabId, 'error');
      // close handler will trigger reconnect
    });

    tab.socket = ws;
  }

  private scheduleReconnect(tabId: string, cols: number, rows: number, token: string | null): void {
    const tab = this.tabs.find((t) => t.id === tabId);
    if (!tab) return;
    if (tab.reconnectAttempt >= MAX_RECONNECT_ATTEMPTS) return;
    tab.reconnectAttempt++;
    const delay = Math.min(RECONNECT_BASE_MS * 2 ** (tab.reconnectAttempt - 1), RECONNECT_MAX_MS);
    tab.reconnectTimer = window.setTimeout(() => {
      tab.reconnectTimer = null;
      // Tab may have been closed during the wait
      if (this.tabs.find((t) => t.id === tabId)) {
        this.connect(tabId, cols, rows, token);
      }
    }, delay);
  }

  private emitStatus(tabId: string, status: 'connecting' | 'open' | 'closed' | 'error', detail?: string): void {
    const set = this.statusListeners.get(tabId);
    if (!set) return;
    for (const listener of set) listener(status, detail);
  }
}

export const shellStore = new ShellStore();
