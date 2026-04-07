/**
 * Thin shell-out wrapper for tmux commands targeting Major Tom's
 * dedicated tmux server socket (`-L major-tom`).
 *
 * Wave 1 scope: version probe, server bootstrap, window lifecycle.
 * Wave 2 will add `sendKeys` for hybrid-mode phone decisions.
 */
import { spawnSync, type SpawnSyncReturns } from 'node:child_process';

/** Named socket all Major Tom tmux calls use — isolates us from the user's tmux. */
export const MAJOR_TOM_SOCKET = 'major-tom';
/** Canonical session name inside the dedicated socket. */
export const MAJOR_TOM_SESSION = 'major-tom';

function run(args: string[], input?: string): SpawnSyncReturns<string> {
  return spawnSync('tmux', args, {
    encoding: 'utf-8',
    ...(input !== undefined ? { input } : {}),
  });
}

/**
 * Return tmux version triple or null if tmux is missing / output is unparseable.
 * `tmux -V` prints e.g. `tmux 3.6a` — we coerce letter suffixes into a dot-number.
 */
export function getTmuxVersion(): { major: number; minor: number; raw: string } | null {
  const res = spawnSync('tmux', ['-V'], { encoding: 'utf-8' });
  if (res.status !== 0 || !res.stdout) return null;
  const raw = res.stdout.trim();
  const match = /tmux\s+(\d+)\.(\d+)/.exec(raw);
  if (!match || !match[1] || !match[2]) return null;
  return { major: Number(match[1]), minor: Number(match[2]), raw };
}

/** tmux ≥ 3.2 is required for `new-session -A` and stable `send-keys -X` semantics. */
export function isTmuxVersionSupported(version: { major: number; minor: number }): boolean {
  if (version.major > 3) return true;
  if (version.major === 3 && version.minor >= 2) return true;
  return false;
}

/** Returns true if the dedicated Major Tom tmux server has our session. */
export function hasMajorTomSession(): boolean {
  const res = run(['-L', MAJOR_TOM_SOCKET, 'has-session', '-t', MAJOR_TOM_SESSION]);
  return res.status === 0;
}

/**
 * Idempotently ensure the Major Tom tmux session exists on the dedicated socket.
 * `new-session -A` attaches if it already exists, creates if not. `-d` keeps it detached.
 */
export function ensureMajorTomSession(): void {
  const res = run([
    '-L', MAJOR_TOM_SOCKET,
    'new-session',
    '-A',            // attach if exists
    '-d',            // detached
    '-s', MAJOR_TOM_SESSION,
    '-x', '200',     // default canvas; each attach resizes
    '-y', '50',
  ]);
  if (res.status !== 0) {
    throw new Error(`tmux new-session failed: ${res.stderr || res.stdout || 'unknown error'}`);
  }
}

/** Create a named tmux window inside the Major Tom session. Idempotent by name. */
export function createWindow(tabId: string): void {
  // `-k` kills an existing window with the same name — we want idempotent create
  // but NOT destroy existing state, so we guard first with list-windows.
  if (hasWindow(tabId)) return;
  const res = run([
    '-L', MAJOR_TOM_SOCKET,
    'new-window',
    '-d',
    '-t', `${MAJOR_TOM_SESSION}:`,
    '-n', tabId,
  ]);
  if (res.status !== 0) {
    throw new Error(`tmux new-window(${tabId}) failed: ${res.stderr || res.stdout}`);
  }
}

/** Check whether a window with the given name exists. */
export function hasWindow(tabId: string): boolean {
  const res = run([
    '-L', MAJOR_TOM_SOCKET,
    'list-windows',
    '-t', MAJOR_TOM_SESSION,
    '-F', '#{window_name}',
  ]);
  if (res.status !== 0) return false;
  return res.stdout.split('\n').some((line) => line.trim() === tabId);
}

/** List all window names for the Major Tom session. */
export function listWindows(): string[] {
  const res = run([
    '-L', MAJOR_TOM_SOCKET,
    'list-windows',
    '-t', MAJOR_TOM_SESSION,
    '-F', '#{window_name}',
  ]);
  if (res.status !== 0) return [];
  return res.stdout.split('\n').map((l) => l.trim()).filter(Boolean);
}

/** Kill a named window. No-op if it doesn't exist. */
export function killWindow(tabId: string): void {
  if (!hasWindow(tabId)) return;
  run([
    '-L', MAJOR_TOM_SOCKET,
    'kill-window',
    '-t', `${MAJOR_TOM_SESSION}:${tabId}`,
  ]);
}
