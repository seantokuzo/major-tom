/**
 * Window Reaper — prevents orphaned tmux windows from accumulating.
 *
 * Problem: every iOS app launch (or Xcode build cycle) creates a fresh
 * random tab ID (e.g. `tab-a3bf91c2`). When the app is killed without
 * explicitly closing the tab, the tmux window persists forever — no
 * client will ever reconnect to that random ID. Over time these orphans
 * pile up (26 windows observed in production from normal dev usage).
 *
 * Solution: two-tier reaping.
 *
 * **Tier 1 — Startup reaper:** after a grace period (default 60 s) for
 * clients to reconnect, kill every tmux window with no active WebSocket
 * client. Handles relay restarts and accumulated orphans.
 *
 * **Tier 2 — Disconnect reaper:** when a window's last client disconnects,
 * start a per-window grace timer. If no client reconnects before it fires,
 * kill the window. Handles app crashes, device sleep, new-tab-ID
 * generation from un-upgraded clients. The default grace (5 min) is long
 * enough for normal reconnects but short enough to prevent unbounded
 * accumulation during active development.
 *
 * The bootstrap "bash" window (tmux index 0, created by
 * `ensureMajorTomSession`) is also reaped — it's never used by any
 * client. Killing the last window kills the session, which is fine:
 * `tmuxBootstrap.ensure()` recreates it on the next client connect.
 */
import { listWindows, killWindow } from '../utils/tmux-cli.js';
import type { SessionManager } from '../sessions/session-manager.js';
import { logger } from '../utils/logger.js';

/** Default grace period (ms) after relay startup before reaping unclaimed windows. */
const STARTUP_GRACE_MS = 60_000;

/**
 * Default grace period (ms) after a window's last client disconnects
 * before reaping it. 5 minutes is generous for reconnects but prevents
 * unbounded accumulation during active dev cycles.
 */
const DISCONNECT_GRACE_MS = 5 * 60_000;

export interface WindowReaperOptions {
  /** Grace period after relay startup before the first reap (ms). */
  startupGraceMs?: number;
  /** Grace period after last-client disconnect before reaping a window (ms). */
  disconnectGraceMs?: number;
}

export class WindowReaper {
  private readonly startupGraceMs: number;
  private readonly disconnectGraceMs: number;
  private startupTimer: ReturnType<typeof setTimeout> | null = null;
  /** Per-window disconnect grace timers, keyed by tabId. */
  private disconnectTimers = new Map<string, ReturnType<typeof setTimeout>>();
  private disposed = false;

  constructor(
    private readonly sessionManager: SessionManager,
    options: WindowReaperOptions = {},
  ) {
    this.startupGraceMs = options.startupGraceMs ?? STARTUP_GRACE_MS;
    this.disconnectGraceMs = options.disconnectGraceMs ?? DISCONNECT_GRACE_MS;
  }

  /**
   * Start the startup reaper. Call once after tmux bootstrap succeeds.
   * After `startupGraceMs`, any tmux window without an active WebSocket
   * client is killed.
   */
  start(): void {
    logger.info(
      { startupGraceMs: this.startupGraceMs, disconnectGraceMs: this.disconnectGraceMs },
      'Window reaper started — startup grace period running',
    );
    this.startupTimer = setTimeout(() => {
      this.startupTimer = null;
      void this.reap('startup');
    }, this.startupGraceMs);
  }

  /**
   * Notify the reaper that a window's last client disconnected.
   * Starts a per-window grace timer. If no client reconnects before
   * the timer fires, the window is killed.
   *
   * Call from the shell route's socket-close handler when
   * `sessionManager.getTab(tabId)` returns undefined (last client gone).
   */
  onLastClientDisconnected(tabId: string): void {
    if (this.disposed) return;
    // Don't double-schedule
    if (this.disconnectTimers.has(tabId)) return;

    logger.info(
      { tabId, graceMs: this.disconnectGraceMs },
      'Window reaper: last client disconnected — grace timer started',
    );

    const timer = setTimeout(() => {
      this.disconnectTimers.delete(tabId);
      // Re-check: a client may have reconnected during the grace window
      if (this.sessionManager.getTab(tabId)) {
        logger.debug({ tabId }, 'Window reaper: client reconnected during grace — sparing window');
        return;
      }
      logger.info({ tabId }, 'Window reaper: grace expired, no reconnect — killing orphan');
      killWindow(tabId).catch((err) => {
        logger.warn({ err, tabId }, 'Window reaper: failed to kill orphaned window');
      });
    }, this.disconnectGraceMs);

    this.disconnectTimers.set(tabId, timer);
  }

  /**
   * Notify the reaper that a client connected to a window.
   * Cancels any pending disconnect grace timer for that window.
   *
   * Call from the shell route when a new PTY attaches.
   */
  onClientConnected(tabId: string): void {
    const timer = this.disconnectTimers.get(tabId);
    if (timer) {
      clearTimeout(timer);
      this.disconnectTimers.delete(tabId);
      logger.debug({ tabId }, 'Window reaper: client reconnected — grace timer cancelled');
    }
  }

  /**
   * Scan all tmux windows and kill those with no active WebSocket client.
   */
  async reap(reason: string): Promise<{ reaped: string[]; spared: string[] }> {
    const allWindows = await listWindows();
    const activeTabs = new Set(
      this.sessionManager.listTabs().map((t) => t.tabId),
    );

    const orphans = allWindows.filter((w) => !activeTabs.has(w));
    const spared = allWindows.filter((w) => activeTabs.has(w));

    if (orphans.length === 0) {
      logger.info(
        { reason, totalWindows: allWindows.length, activeClients: activeTabs.size },
        'Window reaper: no orphans found',
      );
      return { reaped: [], spared };
    }

    logger.info(
      { reason, orphanCount: orphans.length, totalWindows: allWindows.length, orphans },
      'Window reaper: killing orphaned windows',
    );

    const reaped: string[] = [];
    for (const windowName of orphans) {
      try {
        await killWindow(windowName);
        reaped.push(windowName);
        logger.info({ windowName, reason }, 'Window reaper: killed orphan');
      } catch (err) {
        logger.warn({ err, windowName, reason }, 'Window reaper: failed to kill orphan');
      }
    }

    return { reaped, spared };
  }

  /** Stop all timers. Call on graceful shutdown. */
  dispose(): void {
    this.disposed = true;
    if (this.startupTimer) {
      clearTimeout(this.startupTimer);
      this.startupTimer = null;
    }
    for (const [tabId, timer] of this.disconnectTimers) {
      clearTimeout(timer);
      logger.debug({ tabId }, 'Window reaper: cleared disconnect timer on dispose');
    }
    this.disconnectTimers.clear();
    logger.info('Window reaper disposed');
  }
}
