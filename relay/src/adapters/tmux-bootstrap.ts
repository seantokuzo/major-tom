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

  ensure(): Promise<void> {
    if (this.promise) {
      // If the session has since been killed externally, invalidate cache.
      if (!hasMajorTomSession()) {
        logger.warn('tmux session went missing — re-bootstrapping');
        this.promise = null;
      } else {
        return this.promise;
      }
    }
    this.promise = this.run().catch((err) => {
      // Failed bootstrap must not poison future attempts.
      this.promise = null;
      throw err;
    });
    return this.promise;
  }

  reset(): void {
    this.promise = null;
  }

  private async run(): Promise<void> {
    const version = getTmuxVersion();
    if (!version) {
      throw new TmuxMissingError();
    }
    if (!isTmuxVersionSupported(version)) {
      throw new TmuxVersionError(version.raw);
    }
    logger.info({ tmuxVersion: version.raw }, 'tmux version check passed');

    ensureMajorTomSession();
    logger.info('tmux Major Tom session ready');
  }
}

export const tmuxBootstrap = new TmuxBootstrap();
