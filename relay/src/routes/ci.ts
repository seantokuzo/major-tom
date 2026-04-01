/**
 * CI message handlers — GitHub Actions CI operations scoped to session workingDir.
 *
 * Handles ci.runs, ci.run.detail messages via the `gh` CLI.
 * All operations run in the session's working directory.
 */
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { WebSocket } from 'ws';
import { logger } from '../utils/logger.js';
import type {
  CIRunEntry,
  CIJobEntry,
  CIRunDetailEntry,
  CIRunsMessage,
  CIRunDetailMessage,
  CIRunsResponseMessage,
  CIRunDetailResponseMessage,
  CIErrorResponseMessage,
} from '../protocol/messages.js';

const execFileAsync = promisify(execFile);

export type CIServerMessage =
  | CIRunsResponseMessage
  | CIRunDetailResponseMessage
  | CIErrorResponseMessage;

// ── Constants ────────────────────────────────────────────────

const MAX_BUFFER = 5 * 1024 * 1024; // 5 MB
const GH_TIMEOUT = 15_000; // 15s — GitHub API calls can be slower than local git

// ── Helpers ──────────────────────────────────────────────────

async function runGh(args: string[], cwd: string): Promise<string> {
  const { stdout } = await execFileAsync('gh', args, {
    cwd,
    timeout: GH_TIMEOUT,
    maxBuffer: MAX_BUFFER,
    env: { ...process.env, GH_PROMPT_DISABLED: '1' },
  });
  return stdout;
}

function isPositiveInt(n: unknown): n is number {
  return typeof n === 'number' && Number.isInteger(n) && n > 0;
}

// ── Handler factory ──────────────────────────────────────────

export function createCIHandlers(
  sendToClient: (ws: WebSocket, msg: CIServerMessage) => void,
) {
  function sendError(ws: WebSocket, sessionId: string, message: string): void {
    sendToClient(ws, { type: 'ci.error', sessionId, message });
  }

  function handleGhError(err: unknown, ws: WebSocket, sessionId: string, operation: string): void {
    const errMsg = err instanceof Error ? err.message : String(err);
    logger.warn({ err: errMsg }, `${operation} failed`);

    // Provide helpful messages for common failure modes
    if (errMsg.includes('ENOENT') || errMsg.includes('not found')) {
      sendError(ws, sessionId, 'GitHub CLI (gh) is not installed. Install it from https://cli.github.com');
    } else if (errMsg.includes('auth login') || errMsg.includes('not logged')) {
      sendError(ws, sessionId, 'GitHub CLI is not authenticated. Run `gh auth login` to authenticate.');
    } else {
      sendError(ws, sessionId, `Failed to ${operation}: ${errMsg}`);
    }
  }

  async function handleCIRuns(ws: WebSocket, message: CIRunsMessage, workingDir: string): Promise<void> {
    try {
      const args = [
        'run', 'list',
        '--json', 'databaseId,name,displayTitle,status,conclusion,headBranch,event,url,createdAt,updatedAt,actor',
        '--limit', '20',
      ];

      if (message.branch) {
        args.push('--branch', message.branch);
      }

      const raw = await runGh(args, workingDir);
      const parsed = JSON.parse(raw) as Array<Record<string, unknown>>;

      const runs: CIRunEntry[] = parsed.map((run) => ({
        id: run.databaseId as number,
        name: (run.name as string) ?? '',
        displayTitle: (run.displayTitle as string) ?? '',
        status: (run.status as string) ?? '',
        conclusion: (run.conclusion as string) ?? '',
        headBranch: (run.headBranch as string) ?? '',
        event: (run.event as string) ?? '',
        url: (run.url as string) ?? '',
        createdAt: (run.createdAt as string) ?? '',
        updatedAt: (run.updatedAt as string) ?? '',
        actor: (run.actor as Record<string, unknown>)?.login as string ?? '',
      }));

      sendToClient(ws, {
        type: 'ci.runs.response',
        sessionId: message.sessionId,
        runs,
      });
    } catch (err) {
      handleGhError(err, ws, message.sessionId, 'list CI runs');
    }
  }

  async function handleCIRunDetail(ws: WebSocket, message: CIRunDetailMessage, workingDir: string): Promise<void> {
    if (!isPositiveInt(message.runId)) {
      sendError(ws, message.sessionId, 'Invalid run ID');
      return;
    }

    try {
      const raw = await runGh([
        'run', 'view', String(message.runId),
        '--json', 'databaseId,name,displayTitle,status,conclusion,headBranch,headSha,event,url,createdAt,updatedAt,actor,jobs',
      ], workingDir);

      const data = JSON.parse(raw) as Record<string, unknown>;

      const jobs: CIJobEntry[] = Array.isArray(data.jobs)
        ? (data.jobs as Array<Record<string, unknown>>).map((j) => ({
            id: (j.databaseId as number) ?? 0,
            name: (j.name as string) ?? '',
            status: (j.status as string) ?? '',
            conclusion: (j.conclusion as string) ?? '',
            startedAt: (j.startedAt as string) ?? null,
            completedAt: (j.completedAt as string) ?? null,
          }))
        : [];

      const run: CIRunDetailEntry = {
        id: data.databaseId as number,
        name: (data.name as string) ?? '',
        displayTitle: (data.displayTitle as string) ?? '',
        status: (data.status as string) ?? '',
        conclusion: (data.conclusion as string) ?? '',
        headBranch: (data.headBranch as string) ?? '',
        headSha: (data.headSha as string) ?? '',
        event: (data.event as string) ?? '',
        url: (data.url as string) ?? '',
        createdAt: (data.createdAt as string) ?? '',
        updatedAt: (data.updatedAt as string) ?? '',
        actor: (data.actor as Record<string, unknown>)?.login as string ?? '',
        jobs,
      };

      sendToClient(ws, {
        type: 'ci.run.detail.response',
        sessionId: message.sessionId,
        run,
      });
    } catch (err) {
      handleGhError(err, ws, message.sessionId, 'get CI run detail');
    }
  }

  return {
    handleCIRuns,
    handleCIRunDetail,
  };
}
