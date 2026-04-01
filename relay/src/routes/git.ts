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
import type {
  GitStatusEntry,
  GitLogEntry,
  GitBranchEntry,
  GitStatusMessage,
  GitDiffMessage,
  GitLogMessage,
  GitBranchesMessage,
  GitShowMessage,
  GitStatusResponseMessage,
  GitDiffResponseMessage,
  GitLogResponseMessage,
  GitBranchesResponseMessage,
  GitShowResponseMessage,
  GitErrorResponseMessage,
} from '../protocol/messages.js';

const execFileAsync = promisify(execFile);

// Re-export protocol types for consumers
export type { GitStatusEntry, GitLogEntry, GitBranchEntry } from '../protocol/messages.js';

export type GitServerMessage =
  | GitStatusResponseMessage
  | GitDiffResponseMessage
  | GitLogResponseMessage
  | GitBranchesResponseMessage
  | GitShowResponseMessage
  | GitErrorResponseMessage;

// ── Constants ────────────────────────────────────────────────

const MAX_DIFF_SIZE = 512 * 1024; // 512 KB
const MAX_BUFFER = 5 * 1024 * 1024; // 5 MB — large enough to capture output before truncation
const GIT_TIMEOUT = 10_000; // 10s
// Unambiguous delimiter for git show format parsing (ASCII record separator)
const SHOW_DELIMITER = '\x1e';

// ── Helpers ──────────────────────────────────────────────────

async function runGit(args: string[], cwd: string): Promise<string> {
  const { stdout } = await execFileAsync('git', args, {
    cwd,
    timeout: GIT_TIMEOUT,
    maxBuffer: MAX_BUFFER,
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

      // Use ASCII record separator as delimiter between format fields and body
      const d = SHOW_DELIMITER;
      const format = `%H${d}%h${d}%an${d}%ae${d}%aI${d}%B${d}`;
      const raw = await runGit(['show', `--format=${format}`, '--stat', '--patch', message.commitHash], workingDir);

      // Split on delimiter — last field (%B) is followed by delimiter then the stat/diff output
      const parts = raw.split(d);
      const hash = parts[0]?.trim() ?? '';
      const shortHash = parts[1]?.trim() ?? '';
      const author = parts[2]?.trim() ?? '';
      const authorEmail = parts[3]?.trim() ?? '';
      const date = parts[4]?.trim() ?? '';
      const commitMessage = parts[5]?.trim() ?? '';
      // Everything after the last delimiter is the stat + diff portion
      const remainder = parts.slice(6).join(d);

      let diff = remainder.trim();
      if (diff.length > MAX_DIFF_SIZE) {
        diff = diff.slice(0, MAX_DIFF_SIZE) + '\n... (truncated)';
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
        diff,
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
