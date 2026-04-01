/**
 * GitHub message handlers — GitHub API operations scoped to session workingDir.
 *
 * Handles github.pullRequests, github.pullRequest.detail, github.issues,
 * github.issue.detail messages via the `gh` CLI.
 * All operations run in the session's working directory.
 */
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { WebSocket } from 'ws';
import { logger } from '../utils/logger.js';
import type {
  GitHubPullRequestEntry,
  GitHubPullRequestDetail,
  GitHubIssueEntry,
  GitHubIssueDetail,
  GitHubCheckEntry,
  GitHubReviewEntry,
  GitHubCommentEntry,
  GitHubPullRequestsMessage,
  GitHubPullRequestDetailMessage,
  GitHubIssuesMessage,
  GitHubIssueDetailMessage,
  GitHubPullRequestsResponseMessage,
  GitHubPullRequestDetailResponseMessage,
  GitHubIssuesResponseMessage,
  GitHubIssueDetailResponseMessage,
  GitHubErrorResponseMessage,
} from '../protocol/messages.js';

const execFileAsync = promisify(execFile);

export type GitHubServerMessage =
  | GitHubPullRequestsResponseMessage
  | GitHubPullRequestDetailResponseMessage
  | GitHubIssuesResponseMessage
  | GitHubIssueDetailResponseMessage
  | GitHubErrorResponseMessage;

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

function mapPrState(state: string): 'open' | 'closed' | 'merged' {
  const upper = state.toUpperCase();
  if (upper === 'MERGED') return 'merged';
  if (upper === 'CLOSED') return 'closed';
  return 'open';
}

function mapIssueState(state: string): 'open' | 'closed' {
  return state.toUpperCase() === 'CLOSED' ? 'closed' : 'open';
}

function isPositiveInt(n: unknown): n is number {
  return typeof n === 'number' && Number.isInteger(n) && n > 0;
}

// ── Handler factory ──────────────────────────────────────────

export function createGitHubHandlers(
  sendToClient: (ws: WebSocket, msg: GitHubServerMessage) => void,
) {
  function sendError(ws: WebSocket, sessionId: string, message: string): void {
    sendToClient(ws, { type: 'github.error', sessionId, message });
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

  async function handleGitHubPullRequests(ws: WebSocket, message: GitHubPullRequestsMessage, workingDir: string): Promise<void> {
    try {
      const state = message.state ?? 'open';
      const raw = await runGh([
        'pr', 'list',
        '--state', state,
        '--json', 'number,title,state,author,createdAt,updatedAt,url,isDraft,headRefName,baseRefName,additions,deletions,reviewDecision',
        '--limit', '30',
      ], workingDir);

      const parsed = JSON.parse(raw) as Array<Record<string, unknown>>;

      const pullRequests: GitHubPullRequestEntry[] = parsed.map((pr) => ({
        number: pr.number as number,
        title: pr.title as string,
        state: mapPrState(pr.state as string),
        author: (pr.author as Record<string, unknown>)?.login as string ?? '',
        createdAt: pr.createdAt as string,
        updatedAt: pr.updatedAt as string,
        url: pr.url as string,
        draft: pr.isDraft as boolean ?? false,
        headBranch: pr.headRefName as string ?? '',
        baseBranch: pr.baseRefName as string ?? '',
        additions: pr.additions as number ?? 0,
        deletions: pr.deletions as number ?? 0,
        reviewDecision: pr.reviewDecision as string ?? '',
      }));

      sendToClient(ws, {
        type: 'github.pullRequests.response',
        sessionId: message.sessionId,
        pullRequests,
      });
    } catch (err) {
      handleGhError(err, ws, message.sessionId, 'list pull requests');
    }
  }

  async function handleGitHubPullRequestDetail(ws: WebSocket, message: GitHubPullRequestDetailMessage, workingDir: string): Promise<void> {
    if (!isPositiveInt(message.number)) {
      sendError(ws, message.sessionId, 'Invalid pull request number');
      return;
    }

    try {
      const raw = await runGh([
        'pr', 'view', String(message.number),
        '--json', 'number,title,body,state,author,createdAt,updatedAt,mergedAt,url,isDraft,headRefName,baseRefName,additions,deletions,changedFiles,reviewDecision,statusCheckRollup,reviews,comments',
      ], workingDir);

      const pr = JSON.parse(raw) as Record<string, unknown>;

      const checks: GitHubCheckEntry[] = Array.isArray(pr.statusCheckRollup)
        ? (pr.statusCheckRollup as Array<Record<string, unknown>>).map((c) => ({
            name: (c.name as string) ?? (c.context as string) ?? '',
            status: (c.status as string) ?? '',
            conclusion: (c.conclusion as string) ?? '',
          }))
        : [];

      const reviews: GitHubReviewEntry[] = Array.isArray(pr.reviews)
        ? (pr.reviews as Array<Record<string, unknown>>).map((r) => ({
            author: (r.author as Record<string, unknown>)?.login as string ?? '',
            state: (r.state as string) ?? '',
            body: (r.body as string) ?? '',
            submittedAt: (r.submittedAt as string) ?? '',
          }))
        : [];

      const comments: GitHubCommentEntry[] = Array.isArray(pr.comments)
        ? (pr.comments as Array<Record<string, unknown>>).map((c) => ({
            author: (c.author as Record<string, unknown>)?.login as string ?? '',
            body: (c.body as string) ?? '',
            createdAt: (c.createdAt as string) ?? '',
          }))
        : [];

      const detail: GitHubPullRequestDetail = {
        number: pr.number as number,
        title: pr.title as string,
        body: (pr.body as string) ?? '',
        state: mapPrState(pr.state as string),
        author: (pr.author as Record<string, unknown>)?.login as string ?? '',
        createdAt: pr.createdAt as string,
        updatedAt: pr.updatedAt as string,
        mergedAt: (pr.mergedAt as string) ?? null,
        url: pr.url as string,
        draft: pr.isDraft as boolean ?? false,
        headBranch: pr.headRefName as string ?? '',
        baseBranch: pr.baseRefName as string ?? '',
        additions: pr.additions as number ?? 0,
        deletions: pr.deletions as number ?? 0,
        changedFiles: pr.changedFiles as number ?? 0,
        reviewDecision: pr.reviewDecision as string ?? '',
        checks,
        reviews,
        comments,
      };

      sendToClient(ws, {
        type: 'github.pullRequest.detail.response',
        sessionId: message.sessionId,
        detail,
      });
    } catch (err) {
      handleGhError(err, ws, message.sessionId, 'get pull request detail');
    }
  }

  async function handleGitHubIssues(ws: WebSocket, message: GitHubIssuesMessage, workingDir: string): Promise<void> {
    try {
      const state = message.state ?? 'open';
      const raw = await runGh([
        'issue', 'list',
        '--state', state,
        '--json', 'number,title,state,author,createdAt,updatedAt,url,labels,assignees,comments',
        '--limit', '30',
      ], workingDir);

      const parsed = JSON.parse(raw) as Array<Record<string, unknown>>;

      const issues: GitHubIssueEntry[] = parsed.map((issue) => ({
        number: issue.number as number,
        title: issue.title as string,
        state: mapIssueState(issue.state as string),
        author: (issue.author as Record<string, unknown>)?.login as string ?? '',
        createdAt: issue.createdAt as string,
        updatedAt: issue.updatedAt as string,
        url: issue.url as string,
        labels: Array.isArray(issue.labels)
          ? (issue.labels as Array<Record<string, unknown>>).map((l) => (l.name as string) ?? '')
          : [],
        assignees: Array.isArray(issue.assignees)
          ? (issue.assignees as Array<Record<string, unknown>>).map((a) => (a.login as string) ?? '')
          : [],
        commentCount: Array.isArray(issue.comments) ? issue.comments.length : 0,
      }));

      sendToClient(ws, {
        type: 'github.issues.response',
        sessionId: message.sessionId,
        issues,
      });
    } catch (err) {
      handleGhError(err, ws, message.sessionId, 'list issues');
    }
  }

  async function handleGitHubIssueDetail(ws: WebSocket, message: GitHubIssueDetailMessage, workingDir: string): Promise<void> {
    if (!isPositiveInt(message.number)) {
      sendError(ws, message.sessionId, 'Invalid issue number');
      return;
    }

    try {
      const raw = await runGh([
        'issue', 'view', String(message.number),
        '--json', 'number,title,body,state,author,createdAt,updatedAt,url,labels,assignees,comments',
      ], workingDir);

      const issue = JSON.parse(raw) as Record<string, unknown>;

      const comments: GitHubCommentEntry[] = Array.isArray(issue.comments)
        ? (issue.comments as Array<Record<string, unknown>>).map((c) => ({
            author: (c.author as Record<string, unknown>)?.login as string ?? '',
            body: (c.body as string) ?? '',
            createdAt: (c.createdAt as string) ?? '',
          }))
        : [];

      const detail: GitHubIssueDetail = {
        number: issue.number as number,
        title: issue.title as string,
        body: (issue.body as string) ?? '',
        state: mapIssueState(issue.state as string),
        author: (issue.author as Record<string, unknown>)?.login as string ?? '',
        createdAt: issue.createdAt as string,
        updatedAt: issue.updatedAt as string,
        url: issue.url as string,
        labels: Array.isArray(issue.labels)
          ? (issue.labels as Array<Record<string, unknown>>).map((l) => (l.name as string) ?? '')
          : [],
        assignees: Array.isArray(issue.assignees)
          ? (issue.assignees as Array<Record<string, unknown>>).map((a) => (a.login as string) ?? '')
          : [],
        comments,
      };

      sendToClient(ws, {
        type: 'github.issue.detail.response',
        sessionId: message.sessionId,
        detail,
      });
    } catch (err) {
      handleGhError(err, ws, message.sessionId, 'get issue detail');
    }
  }

  return {
    handleGitHubPullRequests,
    handleGitHubPullRequestDetail,
    handleGitHubIssues,
    handleGitHubIssueDetail,
  };
}
