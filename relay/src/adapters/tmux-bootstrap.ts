/**
 * tmux server bootstrap — guarantees Major Tom's dedicated tmux session
 * is alive before any `/shell/:tabId` WebSocket handler spawns a PTY.
 *
 * The bootstrap is idempotent and re-runnable: if someone runs
 * `tmux kill-server` from another terminal, the next WS connection will
 * trigger `ensure()` again and rebuild the session.
 */
import { logger } from '../utils/logger.js';
import {
  ensureMajorTomSession,
  getTmuxVersion,
  hasMajorTomSession,
  isTmuxVersionSupported,
} from '../utils/tmux-cli.js';

export class TmuxMissingError extends Error {
  constructor() {
    super('tmux is not installed or not on PATH — install tmux ≥ 3.2');
    this.name = 'TmuxMissingError';
  }
}

export class TmuxVersionError extends Error {
  constructor(public readonly raw: string) {
    super(`tmux version too old (${raw}) — Major Tom requires ≥ 3.2`);
    this.name = 'TmuxVersionError';
  }
}

/**
 * Lazy, memoised bootstrap. Awaiting the promise guarantees:
 *   1. tmux ≥ 3.2 exists on PATH.
 *   2. The dedicated `-L major-tom` socket is running.
 *   3. The canonical `major-tom` session exists.
 *
 * Repeated calls reuse the cached promise while it is fulfilled. If the
 * underlying tmux server dies externally, call `reset()` to force a fresh
 * bootstrap on next `ensure()`.
 */
export class TmuxBootstrap {
  private promise: Promise<void> | null = null;
  /**
   * False until the in-flight `run()` resolves successfully. Without
   * this flag, a concurrent `ensure()` would call `hasMajorTomSession()`
   * before the first `run()` had created the session, see `false`,
   * null the in-flight promise, and start a duplicate bootstrap. The
   * flag means we only do "session went missing" revalidation AFTER
   * the cached promise has resolved (Copilot review on PR #89).
   */
  private ready = false;

  async ensure(): Promise<void> {
    const cached = this.promise;
    if (cached) {
      // While the first bootstrap is still in flight, every concurrent
      // caller must reuse the same promise — no revalidation, no race.
      if (!this.ready) return cached;

      // Bootstrap finished. Now it's safe to check whether tmux was
      // killed externally between the resolve and this call.
      if (await hasMajorTomSession()) return cached;

      // Another caller may have already nulled/replaced the promise
      // while we were awaiting hasMajorTomSession.
      if (this.promise !== cached) {
        return this.promise ?? cached;
      }

      logger.warn('tmux session went missing — re-bootstrapping');
      this.promise = null;
      this.ready = false;
    }

    const runPromise = this.run()
      .then(() => {
        this.ready = true;
      })
      .catch((err) => {
        // Failed bootstrap must not poison future attempts.
        this.promise = null;
        this.ready = false;
        throw err;
      });
    this.promise = runPromise;
    return runPromise;
  }

  reset(): void {
    this.promise = null;
    this.ready = false;
  }

  private async run(): Promise<void> {
    const version = await getTmuxVersion();
    if (!version) {
      throw new TmuxMissingError();
    }
    if (!isTmuxVersionSupported(version)) {
      throw new TmuxVersionError(version.raw);
    }
    logger.info({ tmuxVersion: version.raw }, 'tmux version check passed');

    await ensureMajorTomSession();
    logger.info('tmux Major Tom session ready');
  }
}

export const tmuxBootstrap = new TmuxBootstrap();
