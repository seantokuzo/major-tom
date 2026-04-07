/**
 * Thin shell-out wrapper for tmux commands targeting Major Tom's
 * dedicated tmux server socket (`-L major-tom`).
 *
 * Wave 1 scope: version probe, server bootstrap, window lifecycle.
 * Wave 2 will add `sendKeys` for hybrid-mode phone decisions.
 *
 * All tmux interactions are async (`execFile` Promise-wrapped) so the
 * Node event loop is not blocked while tmux executes — important when
 * many WebSockets are alive at once. Caught by Copilot review on PR #89.
 */
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

/** Named socket all Major Tom tmux calls use — isolates us from the user's tmux. */
export const MAJOR_TOM_SOCKET = 'major-tom';
/** Canonical session name inside the dedicated socket. */
export const MAJOR_TOM_SESSION = 'major-tom';

interface TmuxResult {
  status: number;
  stdout: string;
  stderr: string;
}

/** Run a tmux command without blocking the event loop. */
async function run(args: string[]): Promise<TmuxResult> {
  try {
    const { stdout, stderr } = await execFileAsync('tmux', args);
    return { status: 0, stdout, stderr };
  } catch (err) {
    const e = err as { code?: number; stdout?: string; stderr?: string };
    return {
      status: typeof e.code === 'number' ? e.code : 1,
      stdout: e.stdout ?? '',
      stderr: e.stderr ?? '',
    };
  }
}

/**
 * Return tmux version or null if tmux is missing / output is unparseable.
 * `tmux -V` prints values like `tmux 3.6a`; we parse the numeric `major.minor`
 * prefix and ignore any trailing suffix characters (Copilot review nit).
 */
export async function getTmuxVersion(): Promise<{ major: number; minor: number; raw: string } | null> {
  const res = await run(['-V']);
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
export async function hasMajorTomSession(): Promise<boolean> {
  const res = await run(['-L', MAJOR_TOM_SOCKET, 'has-session', '-t', MAJOR_TOM_SESSION]);
  return res.status === 0;
}

/**
 * Idempotently ensure the Major Tom tmux session exists on the dedicated socket.
 * `new-session -A` attaches if it already exists, creates if not. `-d` keeps it detached.
 */
export async function ensureMajorTomSession(): Promise<void> {
  const res = await run([
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
export async function createWindow(tabId: string): Promise<void> {
  // We want idempotent create but NOT destroy existing state, so we
  // guard first with list-windows rather than passing tmux's `-k` flag.
  if (await hasWindow(tabId)) return;
  const res = await run([
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
export async function hasWindow(tabId: string): Promise<boolean> {
  const res = await run([
    '-L', MAJOR_TOM_SOCKET,
    'list-windows',
    '-t', MAJOR_TOM_SESSION,
    '-F', '#{window_name}',
  ]);
  if (res.status !== 0) return false;
  return res.stdout.split('\n').some((line) => line.trim() === tabId);
}

/** List all window names for the Major Tom session. */
export async function listWindows(): Promise<string[]> {
  const res = await run([
    '-L', MAJOR_TOM_SOCKET,
    'list-windows',
    '-t', MAJOR_TOM_SESSION,
    '-F', '#{window_name}',
  ]);
  if (res.status !== 0) return [];
  return res.stdout.split('\n').map((l) => l.trim()).filter(Boolean);
}

/** Kill a named window. No-op if it doesn't exist. */
export async function killWindow(tabId: string): Promise<void> {
  if (!(await hasWindow(tabId))) return;
  await run([
    '-L', MAJOR_TOM_SOCKET,
    'kill-window',
    '-t', `${MAJOR_TOM_SESSION}:${tabId}`,
  ]);
}
