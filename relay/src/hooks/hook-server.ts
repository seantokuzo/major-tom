/**
 * Major Tom — Hook HTTP Server
 *
 * Plain Node `http` server (NOT Fastify) that handles inbound POSTs from
 * the installed shell hook scripts. Lives on its own loopback-only port
 * (default 9091, env `HOOK_PORT`) so the hooks can curl the relay
 * without going through Cloudflare or auth.
 *
 * Phase 13 Wave 2 added:
 *   - Routing-mode awareness via `X-MT-Mode` / `X-MT-Tab` headers
 *   - tool_use_id-based dedup (same id arriving twice attaches to the
 *     same pending entry instead of creating a second)
 *   - Bypass-mode escape hatch for Claude Code #37420 (defensive — the
 *     shell script also checks, but a manual curl probe might not)
 *   - SubagentStart placeholder endpoint
 *   - Push notification fire on enqueue
 *
 * Phase 13 Wave 3 added:
 *   - `/hooks/subagent-start` now actually emits an `agent-lifecycle`
 *     spawn event (was a log-only placeholder)
 *   - `/hooks/subagent-stop` new endpoint that emits `dismissed` with
 *     `last_assistant_message` as the summary
 *   - Both go through the injected `reportAgentLifecycle` callback
 *     (a bound `FleetManager.reportAgentLifecycle`) so ws.ts's existing
 *     agent-lifecycle fanout handles tracker updates + broadcast with
 *     no changes to the downstream path
 */
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { basename } from 'node:path';
import { logger } from '../utils/logger.js';
import { ApprovalQueue } from './approval-queue.js';
import {
  evaluatePermission,
  mergePermissionSettings,
  readPermissionSettings,
  readPermissionSettingsForCwd,
} from './permission-matcher.js';
import { sweepOrphanedSubagentsForSession } from './orphan-sweep.js';
import type { NotificationBatcher } from '../push/notification-batcher.js';
import type { AgentEvent } from '../adapters/adapter.interface.js';
import type { ServerMessage } from '../protocol/messages.js';
import type { TabRegistry } from '../tabs/tab-registry.js';
import type { SessionManager } from '../sessions/session-manager.js';

function readBody(req: IncomingMessage, maxBytes = 65_536): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > maxBytes) {
        req.destroy();
        reject(Object.assign(new Error('Request body too large'), { code: 'BODY_TOO_LARGE' }));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
    req.on('error', reject);
  });
}

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

/**
 * Inspect a hook header value, normalize, and validate against an allow-list.
 * Hook scripts are trusted (loopback only) but a malformed header still
 * shouldn't crash the server.
 */
function readHeader<T extends string>(
  req: IncomingMessage,
  name: string,
  allowed: readonly T[],
  fallback: T,
): T {
  const raw = req.headers[name.toLowerCase()];
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (typeof value === 'string' && (allowed as readonly string[]).includes(value)) {
    return value as T;
  }
  return fallback;
}

const ROUTING_MODES = ['local', 'remote', 'hybrid'] as const;
type RoutingMode = (typeof ROUTING_MODES)[number];

/**
 * Map our internal ApprovalDecision to Claude Code's hook envelope shape.
 * Claude Code's permissionDecision is `'allow' | 'deny' | 'ask'`. Our
 * `'skip'` and `'allow_always'` collapse to `'ask'` and `'allow'` resp.
 */
function decisionToPermissionDecision(decision: string): 'allow' | 'deny' | 'ask' {
  if (decision === 'allow' || decision === 'allow_always') return 'allow';
  if (decision === 'deny') return 'deny';
  return 'ask';
}

/**
 * QA-FIXES.md #10 — Short, human-readable task line for a tool call,
 * surfaced on the sprite inspector when a subagent transitions to
 * `.working`. Keep it under ~60 chars so it fits the inspector row.
 *
 * Basename paths (leave URLs + queries alone) and truncate anything else.
 */
export function humanizeToolTask(
  tool: string,
  input: Record<string, unknown> | undefined,
): string {
  const truncate = (s: string, max = 50): string =>
    s.length > max ? s.slice(0, max - 1) + '…' : s;
  const basenameOf = (p: string): string => {
    const idx = p.lastIndexOf('/');
    return idx >= 0 ? p.slice(idx + 1) : p;
  };
  const str = (key: string): string | undefined => {
    const v = input?.[key];
    return typeof v === 'string' ? v : undefined;
  };

  switch (tool) {
    case 'Read': {
      const p = str('file_path');
      return p ? `Reading ${basenameOf(p)}` : 'Reading a file';
    }
    case 'Edit':
    case 'MultiEdit': {
      const p = str('file_path');
      return p ? `Editing ${basenameOf(p)}` : 'Editing a file';
    }
    case 'Write': {
      const p = str('file_path');
      return p ? `Writing ${basenameOf(p)}` : 'Writing a file';
    }
    case 'Bash': {
      const cmd = str('command');
      if (!cmd) return 'Running a shell command';
      // First word or first pipe-segment for a tighter summary.
      const head = cmd.split(/\s+/, 1)[0] ?? cmd;
      return truncate(`Running ${head}`);
    }
    case 'Grep': {
      const pattern = str('pattern');
      return pattern ? truncate(`Searching: ${pattern}`) : 'Searching code';
    }
    case 'Glob': {
      const pattern = str('pattern');
      return pattern ? truncate(`Globbing ${pattern}`) : 'Listing files';
    }
    case 'WebFetch': {
      const url = str('url');
      return url ? truncate(`Fetching ${url}`) : 'Fetching a page';
    }
    case 'WebSearch': {
      const query = str('query');
      return query ? truncate(`Searching web: ${query}`) : 'Searching the web';
    }
    case 'Agent':
    case 'Task': {
      const sub = str('subagent_type') ?? str('description');
      return sub ? truncate(`Spawning ${sub}`) : 'Spawning a subagent';
    }
    case 'TodoWrite':
      return 'Updating todo list';
    case 'NotebookEdit':
      return 'Editing notebook';
    default:
      return truncate(tool);
  }
}

/**
 * Tab-Keyed Offices bridge. Wired from `app.ts`; absent in tests that don't
 * care about the tab pathway. When absent, `/hooks/session-start` and
 * `/hooks/stop` respond 200 with `{}` but emit a warn log and skip the
 * TabRegistry + SessionManager mutations (safe degradation for relay
 * deployments that disable the feature).
 */
export interface TabBridgeDeps {
  tabRegistry: TabRegistry;
  sessionManager: SessionManager;
  /** Broadcast a message to every connected WebSocket client. */
  broadcast: (message: ServerMessage) => void;
  /**
   * Look up the owner userId for a given tabId. Populated at PTY-attach
   * time by shell.ts; undefined for tabs whose PTY is not yet authenticated.
   */
  getUserIdForTab: (tabId: string) => string | undefined;
}

interface HookServerDeps {
  approvalQueue: ApprovalQueue;
  notificationBatcher?: NotificationBatcher;
  /**
   * Phase 13 Wave 3 — injected by `app.ts` as
   * `fleetManager.reportAgentLifecycle.bind(fleetManager)`. The PTY
   * shell-hook endpoints call this to push spawn/dismiss events into
   * the same agent-lifecycle fanout that SDK-originated events use.
   * Optional so existing callers that construct a hook server without
   * fleet access (e.g. tests) still work.
   */
  reportAgentLifecycle?: (event: AgentEvent) => void;
  /** Tab-Keyed Offices — see {@link TabBridgeDeps}. */
  tabBridge?: TabBridgeDeps;
}

// ── Hook HTTP Server ────────────────────────────────────────
// Claude Code hook scripts POST to these endpoints.
// pre-tool-use blocks until the iOS app sends an approval decision.

export function createHookServer(
  approvalQueueOrDeps: ApprovalQueue | HookServerDeps,
  port: number,
) {
  // Backwards-compat: legacy callers pass an ApprovalQueue directly.
  // Wave 2 callers pass a deps object.
  const deps: HookServerDeps =
    approvalQueueOrDeps instanceof ApprovalQueue
      ? { approvalQueue: approvalQueueOrDeps }
      : approvalQueueOrDeps;
  const { approvalQueue, notificationBatcher, reportAgentLifecycle, tabBridge } = deps;

  const server = createServer(async (req, res) => {
    const url = req.url ?? '';
    const method = req.method ?? '';

    try {
      // Health check
      if (method === 'GET' && url === '/health') {
        sendJson(res, 200, { status: 'ok', pendingApprovals: approvalQueue.size });
        return;
      }

      // ── Pre-tool-use ─────────────────────────────────────
      // Phase 13 Wave 2: routing-mode aware. The shell hook script sets
      // `X-MT-Mode` and `X-MT-Tab` headers. We branch on mode:
      //   local  — fire a notification, return 'ask' (TUI keeps owning)
      //   remote — block until phone resolves, return real decision
      //   hybrid — fire a notification, return 'ask', AND let the relay's
      //            send-keys race resolve the TUI prompt if phone wins
      if (method === 'POST' && url === '/hooks/pre-tool-use') {
        const body = await readBody(req);
        let hookData: Record<string, unknown>;
        try {
          hookData = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }

        // Bypass-mode escape hatch — Claude Code #37420. If the shell
        // hook script missed this (it shouldn't, but defensive), we
        // catch it server-side and return 'allow' instead of 'ask'.
        const permissionMode = hookData['permission_mode'];
        if (permissionMode === 'bypassPermissions') {
          logger.warn(
            { tool: hookData['tool_name'] },
            'Bypass mode detected at hook server — returning allow (Claude Code #37420 escape)',
          );
          sendJson(res, 200, {
            hookSpecificOutput: {
              hookEventName: 'PreToolUse',
              permissionDecision: 'allow',
            },
          });
          return;
        }

        const tool = (hookData['tool_name'] as string) ?? 'unknown';
        const toolInput = hookData['tool_input'] as Record<string, unknown> | undefined;
        const toolUseId = (hookData['tool_use_id'] as string) ?? '';
        if (!toolUseId) {
          // Without a tool_use_id we can't dedup or correlate the SDK +
          // hook intercept paths. Reject with 400 so the shell script
          // surfaces a useful error.
          sendJson(res, 400, { error: 'Missing tool_use_id in hook payload' });
          return;
        }

        // QA-FIXES.md #10 — PTY-launched subagents have no other signal that
        // transitions the sprite from .spawned to .working. Claude Code's
        // PreToolUse payload includes `agent_id` for subagent tool calls
        // (absent for main-orchestrator calls). Emit a synthetic `working`
        // lifecycle event so the sprite's status and task text update to
        // show what the subagent is actually doing. Fires early, before
        // any approval gating, so the UI updates even on auto-allowed
        // calls where we never enqueue an approval.
        const agentIdForTool =
          typeof hookData['agent_id'] === 'string' ? (hookData['agent_id'] as string) : undefined;
        const sessionIdForTool =
          typeof hookData['session_id'] === 'string' ? (hookData['session_id'] as string) : undefined;
        if (reportAgentLifecycle && agentIdForTool && sessionIdForTool) {
          reportAgentLifecycle({
            sessionId: sessionIdForTool,
            agentId: agentIdForTool,
            event: 'working',
            task: humanizeToolTask(tool, toolInput),
          });
        }

        const routingMode = readHeader<RoutingMode>(
          req,
          'X-MT-Mode',
          ROUTING_MODES,
          'local',
        );
        const tabIdHeader = req.headers['x-mt-tab'];
        const tabId =
          typeof tabIdHeader === 'string'
            ? tabIdHeader
            : Array.isArray(tabIdHeader)
              ? tabIdHeader[0]
              : undefined;

        // Allowlist short-circuit. If the user has pre-approved this tool
        // in their settings.json, return 'allow' directly — no enqueue, no
        // push. Without this, every Bash(*)/mcp__* call still floods the
        // phone because hook permissionDecision:"ask" overrides the
        // allowlist. Ask rules take precedence so specific patterns (like
        // Bash(rm:*)) still prompt.
        //
        // Sources merged:
        //   - ~/.major-tom/claude-config/settings.json (installer-imported
        //     from the user's global ~/.claude/settings.json)
        //   - <cwd>/.claude/settings.json            (project-shared rules)
        //   - <cwd>/.claude/settings.local.json      (project-local, the
        //     file where "allow always" clicks accumulate)
        // `cwd` is present on every Claude Code hook payload.
        const globalSettings = readPermissionSettings();
        const cwdFromHook =
          typeof hookData['cwd'] === 'string' ? (hookData['cwd'] as string) : undefined;
        const projectSettings = cwdFromHook
          ? readPermissionSettingsForCwd(cwdFromHook)
          : { allow: [], ask: [] };
        const permissionSettings = mergePermissionSettings(globalSettings, projectSettings);
        const evaluated = evaluatePermission(tool, toolInput, permissionSettings);
        if (evaluated === 'allow') {
          logger.debug(
            { tool, toolUseId, tabId },
            'Tool pre-approved by user allowlist — skipping approval enqueue',
          );
          sendJson(res, 200, {
            hookSpecificOutput: {
              hookEventName: 'PreToolUse',
              permissionDecision: 'allow',
            },
          });
          return;
        }

        const description = toolInput ? JSON.stringify(toolInput) : '';

        // Fire push (best-effort, never blocks the response).
        if (notificationBatcher) {
          notificationBatcher.addApprovalRequest(tool, toolUseId);
        }

        // Enqueue with the Wave 2 routing-aware entrypoint. Dedup is
        // handled inside the queue using toolUseId.
        // Local + hybrid don't BLOCK the hook — they fire-and-forget
        // the enqueue and immediately return 'ask'. The PWA picks up
        // the enqueue via the eventBus broadcast.
        if (routingMode === 'local' || routingMode === 'hybrid') {
          // We still call enqueueAndWait so the queue knows about the
          // entry (for the PWA to fetch via /api/approvals/pending and
          // for hybrid send-keys resolution). We just don't await it.
          void approvalQueue.enqueueAndWait({
            dedupKey: toolUseId,
            source: 'hook',
            routingMode,
            tool,
            description,
            details: hookData,
            ...(tabId && { tabId }),
          });
          sendJson(res, 200, {
            hookSpecificOutput: {
              hookEventName: 'PreToolUse',
              permissionDecision: 'ask',
            },
          });
          return;
        }

        // routingMode === 'remote' — BLOCK until the phone resolves.
        const decision = await approvalQueue.enqueueAndWait({
          dedupKey: toolUseId,
          source: 'hook',
          routingMode: 'remote',
          tool,
          description,
          details: hookData,
          ...(tabId && { tabId }),
        });

        sendJson(res, 200, {
          hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: decisionToPermissionDecision(decision),
          },
        });
        return;
      }

      // ── Subagent-start ───────────────────────────────────
      // Phase 13 Wave 3 — PTY-originated `SubagentStart` hook events.
      // Parse `agent_id` / `agent_type` out of the hook payload and
      // push a `spawn` agent-lifecycle event into the shared fanout.
      //
      // Unlike the SDK adapter path, we CANNOT correlate back to a
      // prior `PreToolUse(Task)` here — each shell hook invocation is
      // a fresh subprocess with no shared state. So PTY-originated
      // sprites fall back to `agent_type` as their label. That's fine:
      // the SDK side recovers the richer description via the in-process
      // `pendingTaskByToolUseId` map; the PTY side gets a coarser but
      // still-correct label.
      if (method === 'POST' && url === '/hooks/subagent-start') {
        const body = await readBody(req);
        let payload: Record<string, unknown>;
        try {
          payload = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }

        const agentId = typeof payload['agent_id'] === 'string' ? (payload['agent_id'] as string) : '';
        const agentType =
          typeof payload['agent_type'] === 'string' ? (payload['agent_type'] as string) : 'subagent';

        if (!agentId) {
          logger.warn(
            { tabId: req.headers['x-mt-tab'], session: payload['session_id'] },
            'SubagentStart hook missing agent_id — dropping',
          );
          sendJson(res, 400, { error: 'Missing agent_id in hook payload' });
          return;
        }

        logger.info(
          { tabId: req.headers['x-mt-tab'], session: payload['session_id'], agentId, agentType },
          'SubagentStart hook received',
        );

        // session_id from the Claude hook payload — best-effort mapping to Major Tom sessionId.
        // In fleet mode the worker knows the real sessionId; in PTY mode this is the Claude SDK
        // session_id which the downstream handler uses for routing.
        const hookSessionId =
          typeof payload['session_id'] === 'string' ? (payload['session_id'] as string) : 'unknown';

        if (reportAgentLifecycle) {
          reportAgentLifecycle({
            sessionId: hookSessionId,
            agentId,
            event: 'spawn',
            task: agentType,
            role: agentType,
          });
        } else {
          logger.warn(
            { agentId, agentType },
            'SubagentStart hook received but reportAgentLifecycle not wired — dropping (check createHookServer deps)',
          );
        }

        // `SubagentStart` expects an empty-object envelope (no-op).
        sendJson(res, 200, {});
        return;
      }

      // ── Subagent-stop ────────────────────────────────────
      // Phase 13 Wave 3 — PTY-originated `SubagentStop` hook events.
      // Mirrors `/hooks/subagent-start` shape. Emits a `dismissed`
      // agent-lifecycle event. NOTE: the payload also carries
      // `last_assistant_message`, but `ws.ts`'s `dismissed` branch
      // ignores `event.result` (only `complete` forwards it), so
      // passing it here would be dead data.
      if (method === 'POST' && url === '/hooks/subagent-stop') {
        const body = await readBody(req);
        let payload: Record<string, unknown>;
        try {
          payload = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }

        const agentId = typeof payload['agent_id'] === 'string' ? (payload['agent_id'] as string) : '';

        if (!agentId) {
          logger.warn(
            { tabId: req.headers['x-mt-tab'], session: payload['session_id'] },
            'SubagentStop hook missing agent_id — dropping',
          );
          sendJson(res, 400, { error: 'Missing agent_id in hook payload' });
          return;
        }

        logger.info(
          { tabId: req.headers['x-mt-tab'], session: payload['session_id'], agentId },
          'SubagentStop hook received',
        );

        const stopSessionId =
          typeof payload['session_id'] === 'string' ? (payload['session_id'] as string) : 'unknown';

        if (reportAgentLifecycle) {
          reportAgentLifecycle({
            sessionId: stopSessionId,
            agentId,
            event: 'dismissed',
          });
        } else {
          logger.warn(
            { agentId },
            'SubagentStop hook received but reportAgentLifecycle not wired — dropping (check createHookServer deps)',
          );
        }

        sendJson(res, 200, {});
        return;
      }

      // ── Session-start ────────────────────────────────────
      // Tab-Keyed Offices — fires on every `claude` boot inside an iOS
      // terminal tab. Registers the session with both SessionManager
      // (for the existing session pipeline) and TabRegistry (for the
      // tab→session mapping), then broadcasts tab.session.started so
      // the Office Manager can light up the new session without polling.
      if (method === 'POST' && url === '/hooks/session-start') {
        const body = await readBody(req);
        let payload: Record<string, unknown>;
        try {
          payload = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }

        const sessionId =
          typeof payload['session_id'] === 'string' ? (payload['session_id'] as string) : '';
        const cwd = typeof payload['cwd'] === 'string' ? (payload['cwd'] as string) : '';
        const tabHeader = req.headers['x-mt-tab'];
        const tabId =
          typeof tabHeader === 'string'
            ? tabHeader
            : Array.isArray(tabHeader)
              ? tabHeader[0]
              : undefined;

        if (!sessionId) {
          sendJson(res, 400, { error: 'Missing session_id in hook payload' });
          return;
        }
        if (!tabId || tabId === 'unknown') {
          // Missing X-MT-Tab means the PTY wasn't launched with our tab-id
          // env (e.g. a `claude` invoked from Ground Control or an ad-hoc
          // shell). Acknowledge with {} so claude still boots — we just
          // won't track the session as a tab.
          logger.info(
            { sessionId },
            'SessionStart hook without X-MT-Tab — skipping TabRegistry (legacy path)',
          );
          sendJson(res, 200, {});
          return;
        }

        if (!tabBridge) {
          logger.warn(
            { tabId, sessionId },
            'SessionStart hook received but tabBridge not wired — dropping (check createHookServer deps)',
          );
          sendJson(res, 200, {});
          return;
        }

        const userId = tabBridge.getUserIdForTab(tabId);
        // Detect duplicate SessionStart hooks. Claude Code can fire the
        // hook twice for the same session_id in edge cases; both
        // SessionManager.registerExternal and TabRegistry.registerSession-
        // Start are idempotent, but we still want to avoid emitting the
        // broadcast pair a second time (Office Manager would double-light
        // the arrival).
        const wasAlreadyRegistered =
          tabBridge.tabRegistry.getTabForSession(sessionId) !== undefined;
        const session = tabBridge.sessionManager.registerExternal(sessionId, cwd);
        tabBridge.tabRegistry.registerSessionStart(sessionId, tabId, cwd, userId);

        logger.info(
          { tabId, sessionId, cwd, userId, duplicate: wasAlreadyRegistered },
          'SessionStart hook registered tab↔session binding',
        );

        if (!wasAlreadyRegistered) {
          // Use the Session's authoritative startedAt — generating a fresh
          // ISO string here would drift on duplicate hooks and diverge from
          // SessionManager's record.
          tabBridge.broadcast({
            type: 'tab.session.started',
            tabId,
            sessionId,
            workingDirName: cwd ? basename(cwd) : '',
            startedAt: session.startedAt,
          });
          tabBridge.broadcast({
            type: 'session.info',
            sessionId,
            adapter: session.adapter,
            startedAt: session.startedAt,
          });
        }

        sendJson(res, 200, {});
        return;
      }

      // ── Stop / SessionEnd ────────────────────────────────
      // Both Claude Code events signal "the agent/session is done" in our
      // system. `Stop` fires when the main agent finishes a turn; older
      // versions of Claude Code only emitted this. `SessionEnd` fires when
      // the user ends the session themselves — `/exit`, `/clear`, `/logout`,
      // closing the terminal. CRITICAL: `/exit` does NOT fire `Stop`, so
      // without SessionEnd the session stays "active" forever and any
      // still-linked subagents orphan in the iOS Office (QA-FIXES.md #7b).
      //
      // Both endpoints share the same cleanup: close the Session, mark the
      // session ended in TabRegistry (leaves TabMeta alive so dogs stay in
      // the Office; tab teardown happens only on PTY grace-expire), sweep
      // orphaned subagents, then broadcast the ended events.
      if (
        method === 'POST' &&
        (url === '/hooks/stop' || url === '/hooks/session-end')
      ) {
        const hookName = url === '/hooks/stop' ? 'Stop' : 'SessionEnd';
        const body = await readBody(req);
        let payload: Record<string, unknown>;
        try {
          payload = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }

        const sessionId =
          typeof payload['session_id'] === 'string' ? (payload['session_id'] as string) : '';
        if (!sessionId) {
          sendJson(res, 400, { error: 'Missing session_id in hook payload' });
          return;
        }

        if (!tabBridge) {
          logger.warn(
            { sessionId, hook: hookName },
            'Session-end hook received but tabBridge not wired — dropping (check createHookServer deps)',
          );
          sendJson(res, 200, {});
          return;
        }

        // SessionEnd duplicates Stop in the common `/exit` path (Stop
        // fires first on the final turn, SessionEnd fires on the exit
        // itself). If the session is already closed + unregistered when
        // the second hook lands, short-circuit: skip the re-broadcast so
        // clients don't see duplicate session.ended events.
        const alreadyClosed =
          tabBridge.tabRegistry.getTabForSession(sessionId) === undefined &&
          tabBridge.sessionManager.tryGet(sessionId)?.status !== 'active';

        const tab = tabBridge.tabRegistry.getTabForSession(sessionId);
        tabBridge.sessionManager.tryGet(sessionId)?.close();
        tabBridge.tabRegistry.registerSessionEnd(sessionId);

        // QA-FIXES.md #7b — sweep any subagents whose SubagentStop never
        // fired. Must run BEFORE the session.ended broadcast so the
        // agent.dismissed / sprite.unlink events arrive before the
        // client's session-end teardown. Silent when nothing's linked.
        if (reportAgentLifecycle) {
          sweepOrphanedSubagentsForSession(sessionId, reportAgentLifecycle, 'session-stop');
        }

        if (!alreadyClosed) {
          const endedAt = new Date().toISOString();
          if (tab) {
            tabBridge.broadcast({
              type: 'tab.session.ended',
              tabId: tab.tabId,
              sessionId,
              endedAt,
            });
          }
          tabBridge.broadcast({
            type: 'session.ended',
            sessionId,
          });
        }

        logger.info(
          {
            tabId: tab?.tabId,
            sessionId,
            hook: hookName,
            reason: typeof payload['reason'] === 'string' ? payload['reason'] : undefined,
            alreadyClosed,
          },
          'Session-end hook closed session and updated TabRegistry',
        );

        sendJson(res, 200, {});
        return;
      }

      // ── Post-tool-use (legacy) ───────────────────────────
      if (method === 'POST' && url === '/hooks/post-tool-use') {
        const body = await readBody(req);
        let hookData: Record<string, unknown>;
        try {
          hookData = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }
        // Wave 2: post-tool-use is best-effort logging only — the SDK
        // adapter has its own tool.complete event path, and the shell
        // hook flow doesn't have post hooks installed yet.
        logger.debug(
          { sessionId: hookData['session_id'], tool: hookData['tool_name'] },
          'post-tool-use hook received',
        );
        sendJson(res, 200, { status: 'ok' });
        return;
      }

      // ── Notification (legacy) ────────────────────────────
      if (method === 'POST' && url === '/hooks/notification') {
        const body = await readBody(req);
        let hookData: Record<string, unknown>;
        try {
          hookData = JSON.parse(body) as Record<string, unknown>;
        } catch {
          sendJson(res, 400, { error: 'Invalid JSON in hook payload' });
          return;
        }
        logger.info({ payload: hookData }, 'Notification hook received');
        sendJson(res, 200, { status: 'ok' });
        return;
      }

      // 404
      sendJson(res, 404, { error: 'Not found' });
    } catch (err) {
      if ((err as { code?: string }).code === 'BODY_TOO_LARGE') {
        sendJson(res, 413, { error: 'Request body too large' });
        return;
      }
      logger.error({ err, url, method }, 'Hook server error');
      sendJson(res, 500, { error: 'Internal server error' });
    }
  });

  // Loopback only — these endpoints are trusted by Claude Code's hook
  // scripts running inside each PTY, no authentication. NEVER bind to
  // 0.0.0.0 or expose this port through Cloudflare.
  server.listen(port, '127.0.0.1', () => {
    logger.info({ port, host: '127.0.0.1' }, 'Hook HTTP server listening');
  });

  return server;
}
