/**
 * Git message handlers — sandboxed git operations scoped to session workingDir.
 *
 * Handles git.status, git.diff, git.log, git.branches, git.show messages.
 * All operations run in the session's working directory, validated against SandboxGuard.
 */
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { WebSocket } from 'ws';
import { logger } from '../utils/logger.js';

const execFileAsync = promisify(execFile);

// ── Types ────────────────────────────────────────────────────

export interface GitStatusEntry {
  path: string;
  status: 'added' | 'modified' | 'deleted' | 'renamed' | 'copied' | 'untracked';
  staged: boolean;
  oldPath?: string; // for renames
}

export interface GitLogEntry {
  hash: string;
  shortHash: string;
  author: string;
  authorEmail: string;
  date: string; // ISO 8601
  message: string;
}

export interface GitBranchEntry {
  name: string;
  current: boolean;
  remote: boolean;
  upstream?: string;
  ahead?: number;
  behind?: number;
}

// ── Client messages ──────────────────────────────────────────

export interface GitStatusMessage {
  type: 'git.status';
  sessionId: string;
}

export interface GitDiffMessage {
  type: 'git.diff';
  sessionId: string;
  path?: string;    // specific file, or all if omitted
  staged?: boolean;  // staged diff vs unstaged (default: unstaged)
}

export interface GitLogMessage {
  type: 'git.log';
  sessionId: string;
  count?: number; // default 20
}

export interface GitBranchesMessage {
  type: 'git.branches';
  sessionId: string;
}

export interface GitShowMessage {
  type: 'git.show';
  sessionId: string;
  commitHash: string;
}

export type GitClientMessage =
  | GitStatusMessage
  | GitDiffMessage
  | GitLogMessage
  | GitBranchesMessage
  | GitShowMessage;

// ── Server response messages ─────────────────────────────────

export interface GitStatusResponseMessage {
  type: 'git.status.response';
  sessionId: string;
  branch: string;
  entries: GitStatusEntry[];
}

export interface GitDiffResponseMessage {
  type: 'git.diff.response';
  sessionId: string;
  diff: string;
  path?: string;
  staged: boolean;
}

export interface GitLogResponseMessage {
  type: 'git.log.response';
  sessionId: string;
  entries: GitLogEntry[];
}

export interface GitBranchesResponseMessage {
  type: 'git.branches.response';
  sessionId: string;
  branches: GitBranchEntry[];
}

export interface GitShowResponseMessage {
  type: 'git.show.response';
  sessionId: string;
  hash: string;
  shortHash: string;
  author: string;
  authorEmail: string;
  date: string;
  message: string;
  diff: string;
}

export interface GitErrorResponseMessage {
  type: 'git.error';
  sessionId: string;
  message: string;
}

export type GitServerMessage =
  | GitStatusResponseMessage
  | GitDiffResponseMessage
  | GitLogResponseMessage
  | GitBranchesResponseMessage
  | GitShowResponseMessage
  | GitErrorResponseMessage;

// ── Constants ────────────────────────────────────────────────

const MAX_DIFF_SIZE = 512 * 1024; // 512 KB
const GIT_TIMEOUT = 10_000; // 10s

// ── Helpers ──────────────────────────────────────────────────

async function runGit(args: string[], cwd: string): Promise<string> {
  const { stdout } = await execFileAsync('git', args, {
    cwd,
    timeout: GIT_TIMEOUT,
    maxBuffer: MAX_DIFF_SIZE * 2,
    env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
  });
  return stdout;
}

function parseStatusCode(x: string, y: string): { status: GitStatusEntry['status']; staged: boolean } {
  // X = index (staged), Y = worktree (unstaged)
  if (x === '?' && y === '?') return { status: 'untracked', staged: false };
  if (x === 'A') return { status: 'added', staged: true };
  if (x === 'D') return { status: 'deleted', staged: true };
  if (x === 'R') return { status: 'renamed', staged: true };
  if (x === 'C') return { status: 'copied', staged: true };
  if (x === 'M') return { status: 'modified', staged: true };

  // Unstaged changes
  if (y === 'M') return { status: 'modified', staged: false };
  if (y === 'D') return { status: 'deleted', staged: false };
  if (y === 'A') return { status: 'added', staged: false };

  return { status: 'modified', staged: x !== ' ' };
}

// ── Handler factory ──────────────────────────────────────────

export function createGitHandlers(
  sendToClient: (ws: WebSocket, msg: GitServerMessage) => void,
) {
  function sendError(ws: WebSocket, sessionId: string, message: string): void {
    sendToClient(ws, { type: 'git.error', sessionId, message });
  }

  async function handleGitStatus(ws: WebSocket, message: GitStatusMessage, workingDir: string): Promise<void> {
    try {
      // Get current branch
      let branch = 'HEAD';
      try {
        branch = (await runGit(['rev-parse', '--abbrev-ref', 'HEAD'], workingDir)).trim();
      } catch {
        // detached HEAD or not a git repo — will be caught below
      }

      // Get porcelain status
      const raw = await runGit(['status', '--porcelain=v1', '-uall'], workingDir);
      const entries: GitStatusEntry[] = [];

      for (const line of raw.split('\n')) {
        if (!line) continue;
        const x = line[0]!;
        const y = line[1]!;
        const rest = line.slice(3);

        const { status, staged } = parseStatusCode(x, y);

        // Handle renames: "R  old -> new"
        const arrowIdx = rest.indexOf(' -> ');
        if (arrowIdx !== -1 && (x === 'R' || x === 'C')) {
          entries.push({
            path: rest.slice(arrowIdx + 4),
            status,
            staged,
            oldPath: rest.slice(0, arrowIdx),
          });
        } else {
          entries.push({ path: rest, status, staged });
        }

        // If both staged and unstaged changes exist for a file, emit two entries
        if (x !== ' ' && x !== '?' && y !== ' ' && y !== '?') {
          const unstaged = parseStatusCode(' ', y);
          entries.push({ path: rest, status: unstaged.status, staged: false });
        }
      }

      sendToClient(ws, {
        type: 'git.status.response',
        sessionId: message.sessionId,
        branch,
        entries,
      });
    } catch (err) {
      logger.warn({ err: err instanceof Error ? err.message : String(err) }, 'git.status failed');
      sendError(ws, message.sessionId, 'Failed to get git status — is this a git repository?');
    }
  }

  async function handleGitDiff(ws: WebSocket, message: GitDiffMessage, workingDir: string): Promise<void> {
    try {
      const args = ['diff'];
      if (message.staged) args.push('--cached');
      if (message.path) args.push('--', message.path);

      const diff = await runGit(args, workingDir);

      sendToClient(ws, {
        type: 'git.diff.response',
        sessionId: message.sessionId,
        diff: diff.length > MAX_DIFF_SIZE ? diff.slice(0, MAX_DIFF_SIZE) + '\n... (truncated)' : diff,
        path: message.path,
        staged: message.staged ?? false,
      });
    } catch (err) {
      logger.warn({ err: err instanceof Error ? err.message : String(err) }, 'git.diff failed');
      sendError(ws, message.sessionId, 'Failed to get diff');
    }
  }

  async function handleGitLog(ws: WebSocket, message: GitLogMessage, workingDir: string): Promise<void> {
    try {
      const count = Math.min(message.count ?? 20, 100);
      const format = '%H%n%h%n%an%n%ae%n%aI%n%s';
      const raw = await runGit(['log', `--max-count=${count}`, `--format=${format}`], workingDir);

      const entries: GitLogEntry[] = [];
      const lines = raw.split('\n');

      for (let i = 0; i + 5 < lines.length; i += 6) {
        entries.push({
          hash: lines[i]!,
          shortHash: lines[i + 1]!,
          author: lines[i + 2]!,
          authorEmail: lines[i + 3]!,
          date: lines[i + 4]!,
          message: lines[i + 5]!,
        });
      }

      sendToClient(ws, {
        type: 'git.log.response',
        sessionId: message.sessionId,
        entries,
      });
    } catch (err) {
      logger.warn({ err: err instanceof Error ? err.message : String(err) }, 'git.log failed');
      sendError(ws, message.sessionId, 'Failed to get git log');
    }
  }

  async function handleGitBranches(ws: WebSocket, message: GitBranchesMessage, workingDir: string): Promise<void> {
    try {
      // Get branches with upstream info
      const format = '%(refname:short)%09%(HEAD)%09%(upstream:short)%09%(upstream:track,nobracket)';
      const raw = await runGit(['for-each-ref', '--format', format, 'refs/heads/'], workingDir);

      const branches: GitBranchEntry[] = [];

      for (const line of raw.split('\n')) {
        if (!line) continue;
        const [name, head, upstream, track] = line.split('\t');
        if (!name) continue;

        let ahead: number | undefined;
        let behind: number | undefined;
        if (track) {
          const aheadMatch = track.match(/ahead (\d+)/);
          const behindMatch = track.match(/behind (\d+)/);
          if (aheadMatch) ahead = parseInt(aheadMatch[1]!, 10);
          if (behindMatch) behind = parseInt(behindMatch[1]!, 10);
        }

        branches.push({
          name,
          current: head === '*',
          remote: false,
          upstream: upstream || undefined,
          ahead,
          behind,
        });
      }

      // Add remote branches
      try {
        const remoteRaw = await runGit(['for-each-ref', '--format', '%(refname:short)', 'refs/remotes/'], workingDir);
        for (const line of remoteRaw.split('\n')) {
          if (!line || line.endsWith('/HEAD')) continue;
          branches.push({ name: line, current: false, remote: true });
        }
      } catch {
        // No remotes configured — that's fine
      }

      sendToClient(ws, {
        type: 'git.branches.response',
        sessionId: message.sessionId,
        branches,
      });
    } catch (err) {
      logger.warn({ err: err instanceof Error ? err.message : String(err) }, 'git.branches failed');
      sendError(ws, message.sessionId, 'Failed to list branches');
    }
  }

  async function handleGitShow(ws: WebSocket, message: GitShowMessage, workingDir: string): Promise<void> {
    try {
      // Validate commit hash to prevent command injection
      if (!/^[a-f0-9]{4,40}$/i.test(message.commitHash)) {
        sendError(ws, message.sessionId, 'Invalid commit hash');
        return;
      }

      const format = '%H%n%h%n%an%n%ae%n%aI%n%B';
      const raw = await runGit(['show', `--format=${format}`, '--stat', '--patch', message.commitHash], workingDir);

      // The format output ends before the diff starts — split on the first empty line after the format fields
      const lines = raw.split('\n');
      const hash = lines[0]!;
      const shortHash = lines[1]!;
      const author = lines[2]!;
      const authorEmail = lines[3]!;
      const date = lines[4]!;

      // Commit body: everything from line 5 until we hit the diff separator (starts with "diff --git")
      let bodyEnd = 5;
      while (bodyEnd < lines.length && !lines[bodyEnd]!.startsWith('diff --git') && !lines[bodyEnd]!.match(/^ \S/)) {
        bodyEnd++;
      }
      const commitMessage = lines.slice(5, bodyEnd).join('\n').trim();

      // Diff: everything from first "diff --git" onwards
      const diffStart = lines.findIndex((l, i) => i >= 5 && l.startsWith('diff --git'));
      let diff = '';
      if (diffStart >= 0) {
        diff = lines.slice(diffStart).join('\n');
        if (diff.length > MAX_DIFF_SIZE) {
          diff = diff.slice(0, MAX_DIFF_SIZE) + '\n... (truncated)';
        }
      }

      // Stat section: between body and diff
      const statLines: string[] = [];
      for (let i = bodyEnd; i < lines.length && (diffStart < 0 || i < diffStart); i++) {
        if (lines[i]!.trim()) statLines.push(lines[i]!);
      }

      sendToClient(ws, {
        type: 'git.show.response',
        sessionId: message.sessionId,
        hash,
        shortHash,
        author,
        authorEmail,
        date,
        message: commitMessage,
        diff: (statLines.length ? statLines.join('\n') + '\n\n' : '') + diff,
      });
    } catch (err) {
      logger.warn({ err: err instanceof Error ? err.message : String(err) }, 'git.show failed');
      sendError(ws, message.sessionId, 'Failed to show commit');
    }
  }

  return {
    handleGitStatus,
    handleGitDiff,
    handleGitLog,
    handleGitBranches,
    handleGitShow,
  };
}
