// Relay store — reactive state for the WebSocket connection, chat, and approvals
// Uses Svelte 5 runes ($state, $derived)

import { RelaySocket, type ConnectionState } from '../protocol/websocket';
import type {
  ApprovalDecision,
  ApprovalRequestMessage,
  SessionResultMessage,
  ServerMessage,
} from '../protocol/messages';

// ── Chat message model ──────────────────────────────────────

export interface ToolMeta {
  tool: string;
  input?: Record<string, unknown>;
  output?: string;
  success?: boolean;
}

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant' | 'tool' | 'system';
  content: string;
  timestamp: Date;
  /** Present on role === 'tool' messages — carries tool name, input, and output */
  toolMeta?: ToolMeta;
}

// ── Approval request model ──────────────────────────────────

export interface ApprovalRequest {
  id: string;
  tool: string;
  description: string;
  details?: Record<string, unknown>;
  toolUseId?: string;
  receivedAt: Date;
}

// ── Agent model ─────────────────────────────────────────────

export interface Agent {
  id: string;
  parentId?: string;
  task: string;
  role: string;
  status: 'spawned' | 'working' | 'idle' | 'complete' | 'dismissed';
  result?: string;
}

// ── Session stats model ─────────────────────────────────────

export interface SessionStats {
  totalCost: number;
  turnCount: number;
  totalDuration: number;
  inputTokens: number;
  outputTokens: number;
}

export interface ToolActivity {
  id: string;
  tool: string;
  startedAt: Date;
  completedAt: Date | null;
  success: boolean | null;
  duration: number | null;
  input?: Record<string, unknown>;
}

// ── localStorage keys ───────────────────────────────────────

const STORAGE_KEYS = {
  messages: 'mt-chat-messages',
  sessionId: 'mt-session-id',
  commandUsage: 'mt-command-usage',
  authToken: 'mt-auth-token',
} as const;

// ── Serialization helpers ───────────────────────────────────

interface SerializedMessage {
  id: string;
  role: 'user' | 'assistant' | 'tool' | 'system';
  content: string;
  timestamp: string;
  toolMeta?: ToolMeta;
}

/** Truncate large string values in toolMeta to prevent localStorage quota blowout */
function truncateToolMeta(meta: ToolMeta): ToolMeta {
  const truncate = (val: unknown): unknown => {
    if (typeof val === 'string' && val.length > 500) return val.slice(0, 500) + '\u2026[truncated]';
    if (typeof val === 'object' && val !== null) {
      const out: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(val)) out[k] = truncate(v);
      return out;
    }
    return val;
  };
  const result: ToolMeta = { ...meta, input: truncate(meta.input) as Record<string, unknown> };
  // Also truncate output which can be a very large JSON string
  if (typeof result.output === 'string' && result.output.length > 500) {
    result.output = result.output.slice(0, 500) + '\u2026[truncated]';
  }
  return result;
}

function serializeMessages(messages: ChatMessage[]): string {
  const serializable: SerializedMessage[] = messages.map((m) => ({
    id: m.id,
    role: m.role,
    content: m.content,
    timestamp: m.timestamp.toISOString(),
    ...(m.toolMeta ? { toolMeta: truncateToolMeta(m.toolMeta) } : {}),
  }));
  return JSON.stringify(serializable);
}

function deserializeMessages(json: string): ChatMessage[] {
  try {
    const parsed = JSON.parse(json) as SerializedMessage[];
    return parsed.map((m) => ({
      ...m,
      timestamp: new Date(m.timestamp),
    }));
  } catch {
    return [];
  }
}

// ── Relay store ─────────────────────────────────────────────

let nextId = 0;
function uid(): string {
  return `msg-${++nextId}-${Date.now()}`;
}

/**
 * Detect the relay server address from the current page origin.
 * If served from a remote host (e.g. Cloudflare Tunnel), use that host.
 * Otherwise fall back to localhost:9090.
 */
function detectServerAddress(): string {
  if (typeof window === 'undefined') return 'localhost:9090';
  const { hostname, port } = window.location;
  if (!hostname || hostname === 'localhost' || hostname === '127.0.0.1') {
    return 'localhost:9090';
  }
  return port ? `${hostname}:${port}` : hostname;
}

class RelayStore {
  // Connection
  connectionState = $state<ConnectionState>('disconnected');
  serverAddress = $state(detectServerAddress());
  authToken = $state<string | null>(null);
  sessionId = $state<string | null>(null);
  reconnectAttempt = $state(0);
  maxReconnectAttempts = $state(20);
  lastConnectedAt = $state<Date | null>(null);
  lastDisconnectedAt = $state<Date | null>(null);
  connectionError = $state<string | null>(null);

  // Chat
  messages = $state<ChatMessage[]>([]);
  inputText = $state('');

  // Approvals
  pendingApprovals = $state<ApprovalRequest[]>([]);

  // Agents
  agents = $state<Agent[]>([]);

  // Session stats
  sessionStats = $state<SessionStats>({ totalCost: 0, turnCount: 0, totalDuration: 0, inputTokens: 0, outputTokens: 0 });

  // Streaming state
  isWaitingForResponse = $state(false);
  activeToolName = $state<string | null>(null);

  // Tool activity feed
  toolActivities = $state<ToolActivity[]>([]);

  // Command palette
  inputPrefix = $state('');

  // Derived
  isConnected = $derived(this.connectionState === 'connected');
  hasSession = $derived(this.sessionId !== null);
  isDisconnected = $derived(this.connectionState === 'disconnected');
  isReconnecting = $derived(this.connectionState === 'reconnecting');

  // Internal
  private socket = new RelaySocket();
  private wasConnected = false;
  private storedSessionId: string | null = null;
  private persistenceInitialized = false;
  private isReattaching = false;

  constructor() {
    this.socket.onStateChange = (state) => {
      const wasConnected = this.wasConnected;
      this.connectionState = state;

      if (state === 'connected') {
        this.wasConnected = true;
        this.lastConnectedAt = new Date();
        this.lastDisconnectedAt = null;
        this.reconnectAttempt = 0;
        this.connectionError = null;

        // On (re)connect, try to reattach stored session if we have one and aren't already reattaching
        if (this.storedSessionId && !this.isReattaching) {
          this.attemptReattach();
        }
      } else if (state === 'reconnecting' || (state === 'disconnected' && wasConnected)) {
        // Only record disconnect time once per disconnect cycle
        if (!this.lastDisconnectedAt) {
          this.lastDisconnectedAt = new Date();
        }
        if (state === 'disconnected') {
          this.wasConnected = false;
        }
      }
    };

    this.socket.onReconnectAttempt = (attempt, maxAttempts) => {
      this.reconnectAttempt = attempt;
      this.maxReconnectAttempts = maxAttempts;
    };

    this.socket.onMaxRetriesExceeded = () => {
      this.connectionError = `Failed to connect after ${this.maxReconnectAttempts} attempts`;
    };

    this.socket.onMessage = (message) => {
      this.handleMessage(message);
    };

    // Restore from localStorage
    this.restoreFromStorage();
  }

  // ── Persistence ───────────────────────────────────────────

  private restoreFromStorage(): void {
    if (typeof window === 'undefined') return;

    try {
      const storedMessages = localStorage.getItem(STORAGE_KEYS.messages);
      if (storedMessages) {
        this.messages = deserializeMessages(storedMessages);
      }

      const storedSessionId = localStorage.getItem(STORAGE_KEYS.sessionId);
      if (storedSessionId) {
        this.storedSessionId = storedSessionId;
        // Don't set sessionId yet — wait for successful reattach
      }

      const storedToken = localStorage.getItem(STORAGE_KEYS.authToken);
      if (storedToken) {
        const trimmedToken = storedToken.trim();
        if (trimmedToken) {
          this.authToken = trimmedToken;
        }
      }
    } catch {
      // localStorage unavailable (privacy mode, quota exceeded) — start fresh
    }

    // Set up persistence effect after restoring
    this.persistenceInitialized = true;
  }

  /** Call from an $effect in a component to persist messages reactively */
  persistMessages(): void {
    if (!this.persistenceInitialized || typeof window === 'undefined') return;
    try {
      const json = serializeMessages(this.messages);
      localStorage.setItem(STORAGE_KEYS.messages, json);
    } catch {
      // localStorage unavailable or quota exceeded — degrade gracefully
    }
  }

  private persistSessionId(): void {
    if (typeof window === 'undefined') return;
    try {
      if (this.sessionId) {
        localStorage.setItem(STORAGE_KEYS.sessionId, this.sessionId);
        this.storedSessionId = this.sessionId;
      } else {
        localStorage.removeItem(STORAGE_KEYS.sessionId);
        this.storedSessionId = null;
      }
    } catch {
      // localStorage unavailable — update in-memory state only
      this.storedSessionId = this.sessionId;
    }
  }

  private attemptReattach(): void {
    if (!this.storedSessionId) return;
    this.isReattaching = true;
    this.socket.send({ type: 'session.attach', sessionId: this.storedSessionId });
  }

  // ── Actions ─────────────────────────────────────────────

  connect(): void {
    this.connectionError = null;
    this.socket.connect(this.serverAddress, this.authToken ?? undefined);
  }

  disconnect(): void {
    this.socket.disconnect();
    this.sessionId = null;
    this.wasConnected = false;
  }

  /** Manual retry -- resets error state and reconnect counter, then connects */
  retry(): void {
    this.connectionError = null;
    this.reconnectAttempt = 0;
    this.socket.connect(this.serverAddress, this.authToken ?? undefined);
  }

  /** Set or clear the auth token. Persists to localStorage and reconnects if connected. */
  setAuthToken(token: string | null): void {
    this.authToken = token;
    if (typeof window !== 'undefined') {
      try {
        if (token) {
          localStorage.setItem(STORAGE_KEYS.authToken, token);
        } else {
          localStorage.removeItem(STORAGE_KEYS.authToken);
        }
      } catch {
        // localStorage unavailable — in-memory only
      }
    }
    // Reconnect with new token if currently connected
    if (this.isConnected || this.isReconnecting) {
      this.socket.disconnect();
      this.socket.connect(this.serverAddress, this.authToken ?? undefined);
    }
  }

  startSession(): void {
    this.socket.send({ type: 'session.start', adapter: 'cli' });
  }

  newSession(): void {
    // Tear down current session, clear everything, start fresh
    this.messages = [];
    this.sessionId = null;
    this.pendingApprovals = [];
    this.agents = [];
    this.sessionStats = { totalCost: 0, turnCount: 0, totalDuration: 0, inputTokens: 0, outputTokens: 0 };
    this.isWaitingForResponse = false;
    this.activeToolName = null;
    this.toolActivities = [];
    this.inputText = '';
    this.inputPrefix = '';
    this.persistSessionId();
    if (this.isConnected) {
      this.startSession();
    }
  }

  clearMessages(): void {
    this.messages = [];
  }

  sendPrompt(overrideText?: string): void {
    const text = overrideText ?? this.inputText.trim();
    if (!text || !this.sessionId) return;

    // Apply prefix if set (e.g., /btw mode)
    const finalText = this.inputPrefix ? `${this.inputPrefix}${text}` : text;

    this.messages.push({
      id: uid(),
      role: 'user',
      content: finalText,
      timestamp: new Date(),
    });
    if (!overrideText) this.inputText = '';
    this.inputPrefix = '';

    this.isWaitingForResponse = true;
    this.activeToolName = null;

    this.socket.send({
      type: 'prompt',
      sessionId: this.sessionId,
      text: finalText,
    });
  }

  sendApproval(requestId: string, decision: ApprovalDecision): void {
    const approval = this.pendingApprovals.find((a) => a.id === requestId);
    const toolUseId = approval?.toolUseId;
    this.socket.send({ type: 'approval', requestId, decision, toolUseId });
    this.pendingApprovals = this.pendingApprovals.filter((a) => a.id !== requestId);
  }

  cancelOperation(): void {
    if (!this.sessionId) return;
    this.socket.send({ type: 'cancel', sessionId: this.sessionId });
  }

  // ── Command usage tracking ────────────────────────────────

  getCommandUsage(): Record<string, number> {
    if (typeof window === 'undefined') return {};
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEYS.commandUsage) || '{}');
    } catch {
      return {};
    }
  }

  trackCommandUsage(command: string): void {
    if (typeof window === 'undefined') return;
    try {
      const usage = this.getCommandUsage();
      usage[command] = (usage[command] || 0) + 1;
      localStorage.setItem(STORAGE_KEYS.commandUsage, JSON.stringify(usage));
    } catch {
      // localStorage unavailable — skip tracking
    }
  }

  // ── Message routing ─────────────────────────────────────

  private handleMessage(message: ServerMessage): void {
    switch (message.type) {
      case 'output':
        this.isWaitingForResponse = false;
        this.activeToolName = null;
        this.appendOutput(message.chunk);
        break;

      case 'approval.request':
        this.isWaitingForResponse = false;
        this.activeToolName = null;
        this.addApproval(message);
        break;

      case 'session.info':
        this.sessionId = message.sessionId;
        this.persistSessionId();
        // Only show "Session restored" when we were explicitly reattaching
        if (this.isReattaching && this.messages.length > 0) {
          this.messages.push({
            id: uid(),
            role: 'system',
            content: 'Session restored',
            timestamp: new Date(),
          });
        }
        this.isReattaching = false;
        break;

      case 'session.result':
        this.isWaitingForResponse = false;
        this.activeToolName = null;
        this.handleSessionResult(message);
        break;

      case 'tool.start':
        this.activeToolName = message.tool;
        this.messages.push({
          id: uid(),
          role: 'tool',
          content: `Using ${message.tool}...`,
          timestamp: new Date(),
          toolMeta: {
            tool: message.tool,
            input: message.input,
          },
        });
        // Track in activity feed
        this.toolActivities.push({
          id: uid(),
          tool: message.tool,
          startedAt: new Date(),
          completedAt: null,
          success: null,
          duration: null,
          input: message.input,
        });
        if (this.toolActivities.length > 50) {
          const completedIdx = this.toolActivities.findIndex(a => a.completedAt !== null);
          if (completedIdx >= 0) {
            this.toolActivities.splice(completedIdx, 1);
          } else {
            this.toolActivities.shift();
          }
        }
        break;

      case 'tool.complete':
        this.activeToolName = null;
        this.messages.push({
          id: uid(),
          role: 'tool',
          content: `${message.tool} ${message.success ? 'completed' : 'failed'}`,
          timestamp: new Date(),
          toolMeta: {
            tool: message.tool,
            output: message.output,
            success: message.success,
          },
        });
        // Update activity feed — match oldest incomplete entry (FIFO for parallel tool uses)
        {
          const running = this.toolActivities.find(
            (a) => a.tool === message.tool && !a.completedAt
          );
          if (running) {
            running.completedAt = new Date();
            running.success = message.success;
            running.duration = running.completedAt.getTime() - running.startedAt.getTime();
          }
        }
        break;

      case 'agent.spawn':
        this.agents.push({
          id: message.agentId,
          parentId: message.parentId,
          task: message.task,
          role: message.role,
          status: 'spawned',
        });
        this.messages.push({
          id: uid(),
          role: 'system',
          content: `Agent spawned: ${message.role} \u2014 ${message.task}`,
          timestamp: new Date(),
        });
        break;

      case 'agent.working': {
        const agent = this.agents.find((a) => a.id === message.agentId);
        if (agent) {
          agent.status = 'working';
          agent.task = message.task;
        }
        break;
      }

      case 'agent.idle': {
        const agent = this.agents.find((a) => a.id === message.agentId);
        if (agent) agent.status = 'idle';
        break;
      }

      case 'agent.complete': {
        const agent = this.agents.find((a) => a.id === message.agentId);
        if (agent) {
          agent.status = 'complete';
          agent.result = message.result;
        }
        this.messages.push({
          id: uid(),
          role: 'system',
          content: `Agent completed: ${message.result}`,
          timestamp: new Date(),
        });
        break;
      }

      case 'agent.dismissed': {
        const agent = this.agents.find((a) => a.id === message.agentId);
        if (agent) agent.status = 'dismissed';
        break;
      }

      case 'error':
        this.isWaitingForResponse = false;
        this.activeToolName = null;
        this.isReattaching = false;
        // Handle session attach failure
        if (message.code === 'SESSION_NOT_FOUND' || message.code === 'SESSION_EXPIRED') {
          this.sessionId = null;
          this.storedSessionId = null;
          this.persistSessionId();
          this.messages.push({
            id: uid(),
            role: 'system',
            content: 'Session expired \u2014 start a new session',
            timestamp: new Date(),
          });
        } else {
          this.messages.push({
            id: uid(),
            role: 'system',
            content: `Error: ${message.message}`,
            timestamp: new Date(),
          });
        }
        break;

      case 'notification':
        this.messages.push({
          id: uid(),
          role: 'system',
          content: message.title ? `${message.title}: ${message.message}` : message.message,
          timestamp: new Date(),
        });
        break;

      case 'connection.status':
        // Handled implicitly by socket state
        break;

      case 'workspace.tree.response':
        // Not handled in chat view yet
        break;
    }
  }

  private appendOutput(chunk: string): void {
    const last = this.messages[this.messages.length - 1];
    if (last?.role === 'assistant') {
      // Mutate in place — Svelte 5 $state tracks this
      last.content += chunk;
    } else {
      this.messages.push({
        id: uid(),
        role: 'assistant',
        content: chunk,
        timestamp: new Date(),
      });
    }
  }

  private addApproval(event: ApprovalRequestMessage): void {
    const toolUseId = event.details?.['tool_use_id'] as string | undefined;
    this.pendingApprovals.push({
      id: event.requestId,
      tool: event.tool,
      description: event.description,
      details: event.details,
      toolUseId,
      receivedAt: new Date(),
    });
  }

  private handleSessionResult(result: SessionResultMessage): void {
    this.sessionStats.totalCost += result.costUsd;
    this.sessionStats.turnCount += result.numTurns;
    this.sessionStats.totalDuration += result.durationMs;
    if (typeof result.inputTokens === 'number' && Number.isFinite(result.inputTokens)) {
      this.sessionStats.inputTokens += result.inputTokens;
    }
    if (typeof result.outputTokens === 'number' && Number.isFinite(result.outputTokens)) {
      this.sessionStats.outputTokens += result.outputTokens;
    }
  }
}

// Singleton instance
export const relay = new RelayStore();
