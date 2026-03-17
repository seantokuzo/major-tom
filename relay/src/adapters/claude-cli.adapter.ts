import { EventEmitter } from 'node:events';
import { writeFile, unlink, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as pty from 'node-pty';
import { Session } from '../sessions/session.js';
import { SessionManager } from '../sessions/session-manager.js';
import type {
  IAdapter,
  ApprovalRequest,
  ToolInfo,
  ToolResult,
  AgentEvent,
} from './adapter.interface.js';
import { logger } from '../utils/logger.js';

// ── Claude Code CLI Adapter ─────────────────────────────────
// Spawns Claude Code in a PTY via node-pty.
// Output is streamed to connected iOS clients.
// Input (prompts) is forwarded as PTY stdin.
// Hooks handle structured events (approvals, tool calls, agents).

const __dirname = dirname(fileURLToPath(import.meta.url));

/** Absolute path to relay/hooks/ directory */
const HOOKS_DIR = resolve(__dirname, '../../hooks');

interface PtySession {
  session: Session;
  process: pty.IPty;
  settingsFile?: string;
}

/**
 * Build a Claude Code settings object that wires up our hook scripts.
 * Uses the `hooks` key with PreToolUse, PostToolUse, and Notification events.
 */
function buildHookSettings(): Record<string, unknown> {
  return {
    hooks: {
      PreToolUse: [
        {
          matcher: '.*',
          hooks: [
            {
              type: 'command',
              command: `bash ${HOOKS_DIR}/pre-tool-use.sh`,
              timeout: 300,
            },
          ],
        },
      ],
      PostToolUse: [
        {
          matcher: '.*',
          hooks: [
            {
              type: 'command',
              command: `bash ${HOOKS_DIR}/post-tool-use.sh`,
              timeout: 10,
            },
          ],
        },
      ],
      Notification: [
        {
          matcher: '.*',
          hooks: [
            {
              type: 'command',
              command: `bash ${HOOKS_DIR}/notification.sh`,
              timeout: 10,
            },
          ],
        },
      ],
    },
  };
}

export class ClaudeCliAdapter implements IAdapter {
  readonly type = 'cli' as const;
  private emitter = new EventEmitter();
  private ptySessions = new Map<string, PtySession>();
  private sessionManager: SessionManager;
  private hookPort: number;

  constructor(sessionManager: SessionManager, hookPort = 9091) {
    this.sessionManager = sessionManager;
    this.hookPort = hookPort;
  }

  async start(workingDir: string): Promise<Session> {
    const session = this.sessionManager.create('cli', workingDir);

    // Write a temporary settings file with hook configuration
    const settingsFile = await this.writeHookSettings(session.id);
    const hookUrl = `http://localhost:${this.hookPort}`;

    const ptyProcess = pty.spawn('claude', ['--settings', settingsFile], {
      name: 'xterm-color',
      cols: 120,
      rows: 40,
      cwd: workingDir,
      env: {
        ...process.env,
        TERM: 'xterm-color',
        MAJOR_TOM_HOOK_URL: hookUrl,
      },
    });

    const ptySession: PtySession = { session, process: ptyProcess, settingsFile };
    this.ptySessions.set(session.id, ptySession);

    ptyProcess.onData((data: string) => {
      this.emitter.emit('output', session.id, data);
    });

    ptyProcess.onExit(({ exitCode, signal }) => {
      logger.info({ sessionId: session.id, exitCode, signal }, 'Claude CLI process exited');
      session.close();
      this.ptySessions.delete(session.id);
      // Clean up temp settings file
      void this.cleanupSettingsFile(settingsFile);
    });

    logger.info(
      { sessionId: session.id, workingDir, pid: ptyProcess.pid, hookUrl, settingsFile },
      'Claude CLI session started with hooks configured',
    );

    return session;
  }

  /**
   * Write a temporary settings JSON file with Major Tom hook configuration.
   * Uses a temp directory under relay so we don't pollute the user's project.
   */
  private async writeHookSettings(sessionId: string): Promise<string> {
    const tmpDir = resolve(__dirname, '../../.tmp');
    await mkdir(tmpDir, { recursive: true });

    const settingsPath = resolve(tmpDir, `hooks-${sessionId}.json`);
    const settings = buildHookSettings();
    await writeFile(settingsPath, JSON.stringify(settings, null, 2), 'utf-8');

    logger.debug({ settingsPath }, 'Wrote hook settings file');
    return settingsPath;
  }

  /**
   * Clean up a temporary settings file after a session ends.
   */
  private async cleanupSettingsFile(filePath: string): Promise<void> {
    try {
      await unlink(filePath);
      logger.debug({ filePath }, 'Cleaned up hook settings file');
    } catch (err) {
      // Not critical — file may already be gone
      logger.debug({ filePath, err }, 'Could not clean up hook settings file');
    }
  }

  async attach(sessionId: string): Promise<Session> {
    const session = this.sessionManager.get(sessionId);
    if (!this.ptySessions.has(sessionId)) {
      throw new Error(`No PTY process for session ${sessionId}`);
    }
    return session;
  }

  async sendPrompt(sessionId: string, text: string, _context?: string[]): Promise<void> {
    const ptySession = this.ptySessions.get(sessionId);
    if (!ptySession) {
      throw new Error(`No PTY process for session ${sessionId}`);
    }

    // Write the prompt text followed by Enter
    ptySession.process.write(text + '\r');
    logger.debug({ sessionId, textLength: text.length }, 'Prompt sent to CLI');
  }

  async cancelOperation(sessionId: string): Promise<void> {
    const ptySession = this.ptySessions.get(sessionId);
    if (!ptySession) return;

    // Send Ctrl+C (ETX) to interrupt
    ptySession.process.write('\x03');
    logger.info({ sessionId }, 'Cancel signal sent to CLI');
  }

  on(event: 'output', handler: (sessionId: string, chunk: string) => void): void;
  on(event: 'approval-request', handler: (request: ApprovalRequest) => void): void;
  on(event: 'tool-start', handler: (info: ToolInfo) => void): void;
  on(event: 'tool-complete', handler: (result: ToolResult) => void): void;
  on(event: 'agent-lifecycle', handler: (event: AgentEvent) => void): void;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  on(event: string, handler: (...args: any[]) => void): void {
    this.emitter.on(event, handler);
  }

  // Called by the hook server when structured events come in
  emitApprovalRequest(request: ApprovalRequest): void {
    this.emitter.emit('approval-request', request);
  }

  emitToolStart(info: ToolInfo): void {
    this.emitter.emit('tool-start', info);
  }

  emitToolComplete(result: ToolResult): void {
    this.emitter.emit('tool-complete', result);
  }

  emitAgentLifecycle(event: AgentEvent): void {
    this.emitter.emit('agent-lifecycle', event);
  }

  async dispose(): Promise<void> {
    for (const [sessionId, ptySession] of this.ptySessions) {
      logger.info({ sessionId }, 'Disposing CLI session');
      ptySession.process.kill();
      ptySession.session.close();
      if (ptySession.settingsFile) {
        await this.cleanupSettingsFile(ptySession.settingsFile);
      }
    }
    this.ptySessions.clear();
    this.emitter.removeAllListeners();
  }
}
