/**
 * Thin shell-out wrapper for tmux commands targeting Major Tom's
 * dedicated tmux server socket (`-L major-tom`).
 *
 * Wave 1 scope: version probe, server bootstrap, window lifecycle.
 * Wave 2 added `sendKeys` for hybrid-mode phone-decided approvals.
 *
 * All tmux interactions are async (`execFile` Promise-wrapped) so the
 * Node event loop is not blocked while tmux executes — important when
 * many WebSockets are alive at once. Caught by Copilot review on PR #89.
 */
import { execFile } from 'node:child_process';
import { homedir } from 'node:os';
import { promisify } from 'node:util';
import { logger } from './logger.js';

const execFileAsync = promisify(execFile);

/** Named socket all Major Tom tmux calls use — isolates us from the user's tmux. */
export const MAJOR_TOM_SOCKET = 'major-tom';
/** Canonical session name inside the dedicated socket. */
export const MAJOR_TOM_SESSION = 'major-tom';

/**
 * Working directory for new tmux sessions/windows. Falls back to $HOME so
 * users don't get dropped into wherever the relay process happened to be
 * launched from. Caught by Phase 13 Wave 1 smoke test.
 *
 * Trailing slashes are stripped because bash inherits PWD literally on
 * startup (no normalization), and the basename-via-parameter-expansion
 * that `\W` in PS1 uses would render empty for paths like `/foo/bar/`.
 * Single `/` is preserved.
 */
function getShellCwd(): string {
  // Trim CLAUDE_WORK_DIR before USING it (not just before checking it),
  // so leading/trailing whitespace from copy/paste doesn't poison the
  // tmux `-c` argument. Caught by Copilot review on PR #90.
  const trimmedClaudeWorkDir = process.env['CLAUDE_WORK_DIR']?.trim();
  const raw = trimmedClaudeWorkDir
    ? trimmedClaudeWorkDir
    : (process.env['HOME'] ?? homedir());
  return raw.length > 1 ? raw.replace(/\/+$/, '') : raw;
}

/**
 * The shell command tmux runs in every new pane. We force `-l` (login)
 * so the user's `.bash_profile` / `.zprofile` is sourced — that's where
 * PATH, nvm, brew shellenv, aliases, and prompt config live. Without `-l`
 * tmux only sources `.bashrc` / `.zshrc`, which most users leave nearly
 * empty on macOS. Caught by Phase 13 Wave 1 smoke test (user's prompt
 * styling and PATH bits were not propagating into the PWA shell).
 *
 * Honors `$SHELL` so zsh users get zsh, etc. The single-quote escape on
 * the shell path is paranoia for unusual install dirs (e.g. paths with
 * spaces) — tmux runs `shell-command` through `/bin/sh -c`, so it must
 * be safe under sh-quoting rules.
 */
function getLoginShellCommand(): string {
  // Trim before USING (not just before checking) — same reason as
  // getShellCwd. A trailing newline from a misconfigured env would
  // otherwise sneak into the quoted shell-command and tmux would fail
  // to spawn the pane. Caught by Copilot review on PR #90.
  const trimmedShell = process.env['SHELL']?.trim();
  const shell = trimmedShell ? trimmedShell : '/bin/bash';
  const escaped = shell.replace(/'/g, `'\\''`);
  return `'${escaped}' -l`;
}

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
 *
 * We short-circuit with `has-session` first because on tmux 3.6 (macOS) the
 * `new-session -A -d` form fails with `open terminal failed: not a terminal`
 * when the session already exists — `-A` apparently still triggers a tty
 * open even with `-d`, despite the man page implying otherwise. So we only
 * call `new-session` when we know we need to actually create the session.
 * Caught by Phase 13 Wave 1 smoke test (relay restart against live tmux).
 */
export async function ensureMajorTomSession(): Promise<void> {
  if (await hasMajorTomSession()) return;
  const res = await run([
    '-L', MAJOR_TOM_SOCKET,
    'new-session',
    '-d',                    // detached — no tty required
    '-s', MAJOR_TOM_SESSION,
    '-c', getShellCwd(),     // start the bootstrap window in the user's work dir
    '-x', '200',             // default canvas; each attach resizes
    '-y', '50',
    getLoginShellCommand(),  // run as login shell so PATH/aliases load
  ]);
  if (res.status !== 0) {
    throw new Error(`tmux new-session failed: ${res.stderr || res.stdout || 'unknown error'}`);
  }
}

/**
 * Create a named tmux window inside the Major Tom session. Idempotent by
 * name — if the window already exists we no-op (so multi-device attach
 * doesn't recreate).
 *
 * `env` keys are injected into the window's initial shell via `new-window
 * -e KEY=VAL` (tmux ≥ 2.3). This is the ONLY reliable way to get env vars
 * into the inner bash — env vars on the `pty.spawn()` call only reach the
 * tmux *client* process (the WebSocket relay's attach-session), not the
 * shell running inside the tmux *server*. Wave 2's CLAUDE_CONFIG_DIR /
 * MAJOR_TOM_APPROVAL plumbing depends on this same path. Caught by Phase
 * 13 Wave 1 smoke test ($MAJOR_TOM_TAB_ID was empty inside the shell).
 */
export async function createWindow(
  tabId: string,
  env: Record<string, string> = {},
): Promise<void> {
  // We want idempotent create but NOT destroy existing state, so we
  // guard first with list-windows rather than passing tmux's `-k` flag.
  if (await hasWindow(tabId)) return;
  const args = [
    '-L', MAJOR_TOM_SOCKET,
    'new-window',
    '-d',
    '-t', `${MAJOR_TOM_SESSION}:`,
    '-n', tabId,
    '-c', getShellCwd(),
  ];
  for (const [key, value] of Object.entries(env)) {
    args.push('-e', `${key}=${value}`);
  }
  // Login-shell command must be the LAST positional arg per tmux's
  // `new-window [...] [shell-command]` grammar.
  args.push(getLoginShellCommand());
  const res = await run(args);
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

/**
 * Kill a named window. No-op if it doesn't exist (idempotent under concurrent
 * closes), throws if `tmux kill-window` returns non-zero for any reason other
 * than "already gone".
 *
 * The throw-on-failure behavior matters: callers in `pty-adapter.ts` and
 * `routes/shell.ts` wrap this call in `.catch(...)` / `try/catch` and log
 * the failure — without a throw path those error handlers would be
 * unreachable, meaning real tmux failures would be silently swallowed
 * while the UI assumed the tab was killed. Caught by Copilot PR #94
 * review round 3.
 *
 * Round 4 race fix: between the `hasWindow()` guard and the `kill-window`
 * call, another actor (natural shell exit, external kill, a second REST
 * fallback) can remove the window — `kill-window` then fails and Round 3's
 * throw would surface a false 500 to the REST client even though the window
 * is genuinely gone. So on non-zero exit we re-check `hasWindow()` and treat
 * "gone now" as success; anything else re-throws with the original tmux
 * error message. Caught by Copilot PR #94 review round 4.
 */
export async function killWindow(tabId: string): Promise<void> {
  if (!(await hasWindow(tabId))) return;
  const res = await run([
    '-L', MAJOR_TOM_SOCKET,
    'kill-window',
    '-t', `${MAJOR_TOM_SESSION}:${tabId}`,
  ]);
  if (res.status !== 0) {
    // Race window: something else killed it between hasWindow() and here.
    // If the window is gone now, that's the desired end state — success.
    if (!(await hasWindow(tabId))) return;
    throw new Error(
      `tmux kill-window(${tabId}) failed: ${res.stderr || res.stdout || 'unknown error'}`,
    );
  }
}

/**
 * Create a grouped "view" session that shares the master session's window set
 * but has its OWN current-window slot, then point it at `tabId`.
 *
 * This is the fix for the Phase 13 Wave 2.5 session-handling bug: when two
 * WebSocket clients both attached directly to the master `major-tom` session
 * via `attach-session -t major-tom:<tabId>`, they were sharing the single
 * "current window" slot of the master session — so client B attaching with
 * `-t major-tom:t2` forcibly switched client A's view from t1 to t2. Grouped
 * sessions sidestep this: per the tmux man page, "the current and previous
 * window and any session options remain independent and may be switched
 * between without affecting other sessions in the group".
 *
 * Usage: call this BEFORE `pty.spawn('tmux', ['attach-session', '-t', viewId])`.
 * Each WS attach should get a UNIQUE viewId so multi-device concurrent views
 * of the same tabId don't cross-contaminate either.
 */
export async function createViewSession(viewId: string, tabId: string): Promise<void> {
  // tmux 3.6a on macOS rejects `new-session -t … -A` the same way `new-session
  // -A` fails when the session already exists (open-terminal error), so guard
  // with has-session first and treat the existing-session path as a no-op.
  // Because each attach generates a fresh viewId this should effectively
  // never hit — it's pure defense against accidental reuse.
  const exists = await run([
    '-L', MAJOR_TOM_SOCKET,
    'has-session',
    '-t', viewId,
  ]);
  if (exists.status !== 0) {
    const createRes = await run([
      '-L', MAJOR_TOM_SOCKET,
      'new-session',
      '-d',                   // detached — no tty required
      '-t', MAJOR_TOM_SESSION, // grouped with master, shares windows
      '-s', viewId,            // new grouped session's name
    ]);
    if (createRes.status !== 0) {
      throw new Error(
        `tmux new-session (grouped ${viewId}) failed: ${createRes.stderr || createRes.stdout}`,
      );
    }
  }
  // Point the grouped session at the requested window. This changes ONLY
  // `view-…`'s current-window slot, not the master session's slot. If the
  // select fails (e.g. window was just killed), we log and bail so the
  // caller can surface a real error instead of silently attaching to the
  // wrong window.
  const selectRes = await run([
    '-L', MAJOR_TOM_SOCKET,
    'select-window',
    '-t', `${viewId}:${tabId}`,
  ]);
  if (selectRes.status !== 0) {
    throw new Error(
      `tmux select-window (${viewId}:${tabId}) failed: ${selectRes.stderr || selectRes.stdout}`,
    );
  }
}

/**
 * Kill an entire tmux session. Idempotent — no-op if the session is gone.
 *
 * Used to tear down per-WS grouped view sessions on dispose. Killing a
 * grouped session does NOT kill the shared windows — those belong to the
 * master `major-tom` session and survive until explicitly `killWindow`'d.
 *
 * Round 4: logs a warn on non-zero exit. Previously the result was fully
 * ignored so a real `tmux kill-session` failure (tmux server error, grouped
 * session in a weird state) would silently leak a `view-*` session with no
 * log signal at all. dispose() is best-effort cleanup so we don't throw —
 * the log line is enough to correlate leaks with tmux errors after the fact.
 * Caught by Copilot PR #94 review round 4.
 */
export async function killSession(sessionName: string): Promise<void> {
  const exists = await run([
    '-L', MAJOR_TOM_SOCKET,
    'has-session',
    '-t', sessionName,
  ]);
  if (exists.status !== 0) return;
  const res = await run([
    '-L', MAJOR_TOM_SOCKET,
    'kill-session',
    '-t', sessionName,
  ]);
  if (res.status !== 0) {
    logger.warn(
      { sessionName, stderr: res.stderr.trim() || res.stdout.trim() },
      'tmux kill-session failed',
    );
  }
}

/**
 * Inject keystrokes into a tmux window. Variadic — pass each key as a
 * SEPARATE arg. tmux's send-keys treats `'a' 'Enter'` as the literal letter
 * followed by the Enter key, NOT as a 5-char string. Mixing them into one
 * concatenated string breaks on some shells and the `Enter` key name is the
 * portable way to do newlines.
 *
 * Used by hybrid-mode approval routing in Wave 2: when the phone resolves
 * an approval, the relay injects `a` `Enter` (allow) or `d` `Enter` (deny)
 * into the tmux window where `claude` is prompting.
 *
 * Best-effort: failures are logged but not thrown — caller is responsible
 * for the higher-level race resolution. Returns true on success.
 *
 * @param windowTarget e.g. `major-tom:t1`
 * @param keys e.g. `'a', 'Enter'` or `'d', 'Enter'`
 */
export async function sendKeys(windowTarget: string, ...keys: string[]): Promise<boolean> {
  if (keys.length === 0) return false;
  const res = await run([
    '-L', MAJOR_TOM_SOCKET,
    'send-keys',
    '-t', windowTarget,
    ...keys,
  ]);
  if (res.status !== 0) {
    logger.warn(
      { windowTarget, keys, stderr: res.stderr.trim() || res.stdout.trim() },
      'tmux send-keys failed',
    );
    return false;
  }
  return true;
}

/**
 * Capture the current visible content of a tmux window pane. Used by smoke
 * tests / debug tooling to verify state without needing the user to look at
 * the terminal. Returns the captured text or null on failure.
 */
export async function capturePane(windowTarget: string): Promise<string | null> {
  const res = await run([
    '-L', MAJOR_TOM_SOCKET,
    'capture-pane',
    '-p',
    '-t', windowTarget,
  ]);
  if (res.status !== 0) return null;
  return res.stdout;
}
