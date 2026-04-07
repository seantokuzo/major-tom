/**
 * Shell store — owns per-tab WebSocket connections to /shell/:tabId,
 * tracks focus, and exposes a tiny imperative API for the xterm pane.
 *
 * Phase 13 Wave 1: each tab is one tmux window. Reconnect logic is
 * intentionally simple — exponential backoff up to 20 attempts, the
 * tmux backend keeps the real `claude` session alive across drops.
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

/** Listener type for binary frames coming from the relay PTY. */
export type DataListener = (chunk: Uint8Array) => void;
export type StatusListener = (status: 'connecting' | 'open' | 'closed' | 'error', detail?: string) => void;
/** Inject callback registered by an XtermPane so the keybar can drive its terminal. */
export type Injector = (data: string) => void;

class ShellStore {
  tabs = $state<ShellTab[]>([]);
  activeTabId = $state<string | null>(null);

  /** tabId → set of listeners for binary PTY data. */
  private dataListeners = new Map<string, Set<DataListener>>();
  /** tabId → set of listeners for connection status changes. */
  private statusListeners = new Map<string, Set<StatusListener>>();
  /** tabId → mounted XtermPane's `term.input()` shim (set on mount, cleared on destroy). */
  private injectors = new Map<string, Injector>();

  registerInjector(tabId: string, injector: Injector): void {
    this.injectors.set(tabId, injector);
  }

  unregisterInjector(tabId: string): void {
    this.injectors.delete(tabId);
  }

  /** Inject text into the active tab's terminal (used by MobileKeybar). */
  injectIntoActive(data: string): void {
    const id = this.activeTabId;
    if (!id) return;
    const fn = this.injectors.get(id);
    if (fn) fn(data);
  }

  /** Add a new tab and connect immediately. Returns the tab id. */
  openTab(opts: { id?: string; label?: string; cols: number; rows: number; token: string | null }): string {
    const id = opts.id ?? this.generateTabId();
    if (this.tabs.find((t) => t.id === id)) {
      this.activeTabId = id;
      return id;
    }
    const tab: ShellTab = {
      id,
      label: opts.label ?? id,
      socket: null,
      reconnectAttempt: 0,
      reconnectTimer: null,
      connected: false,
    };
    this.tabs.push(tab);
    this.activeTabId = id;
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
    if (tab.socket) {
      try { tab.socket.close(1000, 'tab-closed'); } catch { /* ignore */ }
    }
    this.tabs.splice(idx, 1);
    this.dataListeners.delete(tabId);
    this.statusListeners.delete(tabId);
    if (this.activeTabId === tabId) {
      this.activeTabId = this.tabs[0]?.id ?? null;
    }
  }

  setActive(tabId: string): void {
    if (this.tabs.find((t) => t.id === tabId)) {
      this.activeTabId = tabId;
    }
  }

  /** Push raw bytes to the PTY. Caller owns the encoding. */
  send(tabId: string, data: string | Uint8Array): void {
    const tab = this.tabs.find((t) => t.id === tabId);
    if (!tab || !tab.socket || tab.socket.readyState !== WebSocket.OPEN) return;
    tab.socket.send(data);
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
      // Text frame: control message from server (exit, error)
      if (typeof ev.data === 'string') {
        try {
          const ctrl = JSON.parse(ev.data) as Record<string, unknown>;
          if (ctrl['type'] === 'exit') {
            this.emitStatus(tabId, 'closed', 'pty-exit');
          } else if (ctrl['type'] === 'error') {
            this.emitStatus(tabId, 'error', String(ctrl['message'] ?? ''));
          }
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
