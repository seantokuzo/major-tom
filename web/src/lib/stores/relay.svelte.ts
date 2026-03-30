// Relay store — reactive state for the WebSocket connection, chat, and approvals
// Uses Svelte 5 runes ($state, $derived)

import { RelaySocket, type ConnectionState } from '../protocol/websocket';
import type {
  ApprovalDecision,
  ApprovalRequestMessage,
  SessionHistoryMessage,
  DeviceInfo,
  SessionResultMessage,
  ServerMessage,
} from '../protocol/messages';
import { promptHistory } from './prompt-history.svelte';
import { sessionsStore } from './sessions.svelte';
import { contextStore } from './context.svelte';
import { db } from '../db';
import { terminalStore } from './terminal.svelte';
import { sessionStateManager, extractDirName } from './session-state.svelte';
import { fleetStore } from './fleet.svelte';
import { toasts } from './toast.svelte';

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
  /** Set when tool was auto-allowed by permission filter */
  autoAllowed?: 'smart:settings' | 'smart:session' | 'god:yolo' | 'god:normal';
}

// ── Permission mode model ────────────────────────────────────

export type PermissionMode = 'manual' | 'smart' | 'delay' | 'god';
export type GodSubMode = 'normal' | 'yolo';

export interface PermissionModeState {
  mode: PermissionMode;
  delaySeconds: number;
  godSubMode: GodSubMode;
}

// ── Auth user model ─────────────────────────────────────────

export interface AuthUser {
  email: string;
  name?: string;
  picture?: string;
}

// ── localStorage keys (only for small synchronous state) ────

const STORAGE_KEYS = {
  sessionId: 'mt-session-id',
  authToken: 'mt-auth-token',
} as const;

// ── Relay store ─────────────────────────────────────────────

let nextId = 0;
function uid(): string {
  return `msg-${++nextId}-${Date.now()}`;
}

/**
 * Detect the relay server address from the current page origin.
 * Vite proxy handles routing in dev; same-origin in prod.
 */
function detectServerAddress(): string {
  if (typeof window === 'undefined') return 'localhost:9090';
  const { hostname, port } = window.location;
  return port ? `${hostname}:${port}` : hostname;
}

class RelayStore {
  // Auth (Google OAuth)
  user = $state<AuthUser | null>(null);
  authChecked = $state(false);

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
  isViewingHistory = $state(false);
  activeToolName = $state<string | null>(null);

  // Tool activity feed
  toolActivities = $state<ToolActivity[]>([]);

  // Devices
  devices = $state<DeviceInfo[]>([]);

  // Command palette
  inputPrefix = $state('');

  // Permission mode (synced with relay)
  permissionMode = $state<PermissionModeState>({
    mode: 'smart',
    delaySeconds: 5,
    godSubMode: 'normal',
  });

  // Manual disconnect flag — prevents auto-reconnect after user clicks Disconnect
  manuallyDisconnected = $state(false);

  // Derived
  isConnected = $derived(this.connectionState === 'connected');
  hasSession = $derived(this.sessionId !== null);
  isDisconnected = $derived(this.connectionState === 'disconnected');
  isReconnecting = $derived(this.connectionState === 'reconnecting');
  get isAuthenticated(): boolean {
    return this.user !== null;
  }

  /** Display name for the active session (from sessionStateManager) */
  get sessionName(): string {
    if (!this.sessionId) return '';
    return sessionStateManager.getSessionName(this.sessionId);
  }

  // Internal
  private socket = new RelaySocket();
  private wasConnected = false;
  private storedSessionId: string | null = null;
  private persistenceInitialized = false;
  private isReattaching = false;
  /** Pending working dir from startSessionAt — used to tag session on session.info */
  private pendingWorkingDir: string | null = null;

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

    // Restore synchronous state from localStorage, then async from IndexedDB
    this.restoreFromStorage();

    // Check auth session (cookie-based)
    this.checkAuth();

    // Wire fleet store's request function
    fleetStore.setRequestFn(() => this.requestFleetStatus());
  }

  // ── Auth (Google OAuth) ──────────────────────────────────

  async checkAuth(): Promise<void> {
    if (typeof window === 'undefined') {
      this.authChecked = true;
      return;
    }
    try {
      const res = await fetch('/auth/me', { credentials: 'include' });
      if (res.ok) {
        const data = await res.json();
        this.user = { email: data.email, name: data.name, picture: data.picture };
      } else {
        this.user = null;
      }
    } catch {
      this.user = null;
    }
    this.authChecked = true;
  }

  async login(credential: string): Promise<{ success: boolean; error?: string }> {
    try {
      const res = await fetch('/auth/google', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ credential }),
      });
      if (res.ok) {
        const data = await res.json();
        this.user = { email: data.email, name: data.name, picture: data.picture };
        return { success: true };
      }
      const body = await res.json().catch(() => ({ error: 'Login failed' }));
      return { success: false, error: body.error ?? 'Login failed' };
    } catch {
      return { success: false, error: 'Could not reach server' };
    }
  }

  async loginWithPin(pin: string): Promise<{ success: boolean; error?: string }> {
    try {
      const res = await fetch('/auth/pin/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ pin }),
      });
      if (res.ok) {
        const data = await res.json();
        this.user = { email: data.email, name: data.name, picture: data.picture };
        return { success: true };
      }
      const body = await res.json().catch(() => ({ error: 'Invalid PIN' }));
      return { success: false, error: body.error ?? 'Invalid PIN' };
    } catch {
      return { success: false, error: 'Could not reach server' };
    }
  }

  async logout(): Promise<void> {
    try {
      await fetch('/auth/logout', { method: 'POST', credentials: 'include' });
    } catch {
      // Best-effort
    }
    this.user = null;
    this.disconnect();
  }

  // ── Persistence ───────────────────────────────────────────

  private restoreFromStorage(): void {
    if (typeof window === 'undefined') return;

    try {
      const storedSessionId = localStorage.getItem(STORAGE_KEYS.sessionId);
      if (storedSessionId) {
        this.storedSessionId = storedSessionId;
        // Don't set sessionId yet — wait for successful reattach

        // Load messages for this session from IndexedDB (async)
        this.loadMessagesFromDb(storedSessionId);
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

  /** Load messages from IndexedDB for a given session */
  private async loadMessagesFromDb(sessionId: string): Promise<void> {
    try {
      const rows = await db.messages
        .where('sessionId')
        .equals(sessionId)
        .toArray();

      if (rows.length > 0 && this.messages.length === 0) {
        // Only apply DB rows if no newer messages have arrived (e.g. from socket reattach)
        // Sort by timestamp ascending — lexical messageId order breaks at counter 10+
        rows.sort((a, b) => a.timestamp.localeCompare(b.timestamp));
        this.messages = rows.map((row) => ({
          id: row.messageId,
          role: row.role,
          content: row.content,
          timestamp: new Date(row.timestamp),
          ...(row.toolMeta ? { toolMeta: row.toolMeta } : {}),
        }));
      }
    } catch (e) {
      console.warn('[MajorTom] Failed to load messages from IndexedDB:', e);
    }
  }

  /** Call from an $effect in a component to persist messages reactively */
  persistMessages(): void {
    if (!this.persistenceInitialized || typeof window === 'undefined') return;
    // Delegate to session state manager which handles IndexedDB
    sessionStateManager.persistActive(this).catch(() => {
      // IndexedDB unavailable — degrade gracefully
    });
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
    this.manuallyDisconnected = false;
    this.connectionError = null;
    this.socket.connect(this.serverAddress, this.authToken ?? undefined);
  }

  disconnect(): void {
    this.manuallyDisconnected = true;
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
    // connect() handles cleanup of existing connection (nulls onclose, closes ws)
    if (this.isConnected || this.isReconnecting) {
      this.socket.connect(this.serverAddress, this.authToken ?? undefined);
    }
  }

  startSession(): void {
    // Starting a new session — clear stale state from any prior session
    this.messages = [];
    this.pendingApprovals = [];
    this.agents = [];
    this.sessionStats = { totalCost: 0, turnCount: 0, totalDuration: 0, inputTokens: 0, outputTokens: 0 };
    this.isWaitingForResponse = false;
    this.activeToolName = null;
    this.toolActivities = [];
    this.isViewingHistory = false;
    contextStore.clear();
    this.socket.send({ type: 'session.start', adapter: 'cli' });
  }

  newSession(): void {
    // Snapshot current session before tearing down
    if (this.sessionId) {
      sessionStateManager.snapshotFrom(this);
      sessionStateManager.saveToDb(this.sessionId).catch(() => {});
    }
    // Tear down current session and clear input state
    this.sessionId = null;
    this.inputText = '';
    this.inputPrefix = '';
    sessionStateManager.activeSessionId = null;
    this.persistSessionId();
    // Don't auto-start — go to terminal so user picks a directory
  }

  /** Start a new session (legacy path — starts without directory picker) */
  newSessionImmediate(): void {
    if (this.sessionId) {
      sessionStateManager.snapshotFrom(this);
      sessionStateManager.saveToDb(this.sessionId).catch(() => {});
    }
    this.sessionId = null;
    this.inputText = '';
    this.inputPrefix = '';
    sessionStateManager.activeSessionId = null;
    this.persistSessionId();
    if (this.isConnected) {
      this.startSession();
    }
  }

  /** End current session and return to terminal (no auto-restart) */
  endSession(): void {
    const endingId = this.sessionId;
    if (endingId && this.isConnected) {
      this.socket.send({ type: 'session.end', sessionId: endingId });
    }
    // Snapshot before clearing so it's saved
    if (endingId) {
      sessionStateManager.snapshotFrom(this);
      sessionStateManager.saveToDb(endingId).catch(() => {});
    }
    this.sessionId = null;
    this.inputText = '';
    this.inputPrefix = '';
    this.messages = [];
    this.pendingApprovals = [];
    this.agents = [];
    this.sessionStats = { totalCost: 0, turnCount: 0, totalDuration: 0, inputTokens: 0, outputTokens: 0 };
    this.isWaitingForResponse = false;
    this.activeToolName = null;
    this.toolActivities = [];
    this.isViewingHistory = false;
    sessionStateManager.activeSessionId = null;
    this.persistSessionId();
    contextStore.clear();
  }

  clearMessages(): void {
    this.messages = [];
  }

  sendPrompt(overrideText?: string): void {
    if (this.isViewingHistory) return;
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

    // Record in prompt history (use original text, not prefixed)
    promptHistory.add(text);

    this.isWaitingForResponse = true;
    this.activeToolName = null;

    this.socket.send({
      type: 'prompt',
      sessionId: this.sessionId,
      text: finalText,
    });
  }

  sendApproval(requestId: string, decision: ApprovalDecision): void {
    if (this.isViewingHistory) return;
    const approval = this.pendingApprovals.find((a) => a.id === requestId);
    const toolUseId = approval?.toolUseId;
    this.socket.send({ type: 'approval', requestId, decision, toolUseId });
    this.pendingApprovals = this.pendingApprovals.filter((a) => a.id !== requestId);
  }

  sendAgentMessage(agentId: string, text: string): void {
    if (this.isViewingHistory) return;
    const trimmed = text.trim();
    if (!trimmed || !this.sessionId) return;

    this.messages.push({
      id: uid(),
      role: 'user',
      content: `[To agent ${agentId}]: ${trimmed}`,
      timestamp: new Date(),
    });

    this.isWaitingForResponse = true;
    this.activeToolName = null;

    this.socket.send({
      type: 'agent.message',
      sessionId: this.sessionId,
      agentId,
      text: trimmed,
    });
  }

  cancelOperation(): void {
    if (!this.sessionId) return;
    this.socket.send({ type: 'cancel', sessionId: this.sessionId });
  }

  setPermissionMode(
    mode: PermissionMode,
    delaySeconds?: number,
    godSubMode?: GodSubMode,
  ): void {
    this.permissionMode.mode = mode;
    if (delaySeconds !== undefined) this.permissionMode.delaySeconds = delaySeconds;
    if (godSubMode) this.permissionMode.godSubMode = godSubMode;

    this.socket.send({
      type: 'settings.approval',
      mode,
      delaySeconds: delaySeconds ?? this.permissionMode.delaySeconds,
      godSubMode: godSubMode ?? this.permissionMode.godSubMode,
    });
  }

  requestFleetStatus(): void {
    if (!this.isConnected) return;
    this.socket.send({ type: 'fleet.status' });
  }

  requestSessionList(): void {
    if (!this.isConnected) return;
    sessionsStore.markLoading();
    this.socket.send({ type: 'session.list' });
    // Snapshot current state so session list is accurate
    if (this.sessionId) {
      sessionStateManager.snapshotFrom(this);
    }
  }

  switchSession(sessionId: string): void {
    // Snapshot current session state before switching
    if (this.sessionId && this.sessionId !== sessionId) {
      sessionStateManager.snapshotFrom(this);
      // Fire-and-forget save to IndexedDB
      sessionStateManager.saveToDb(this.sessionId).catch(() => {});
    }

    // Set sessionId immediately so any prompt sent after switchSession targets the right session
    this.sessionId = sessionId;
    sessionStateManager.activeSessionId = sessionId;
    // Persist immediately so a reload during attach reattaches to the correct session
    this.persistSessionId();

    // Try to restore target session from cache for instant switch
    const restored = sessionStateManager.restoreTo(this, sessionId);
    if (!restored) {
      // No cached state — clear for a fresh start
      this.messages = [];
      this.pendingApprovals = [];
      this.agents = [];
      this.sessionStats = { totalCost: 0, turnCount: 0, totalDuration: 0, inputTokens: 0, outputTokens: 0 };
      this.toolActivities = [];
      this.isWaitingForResponse = false;
      this.activeToolName = null;
      this.isViewingHistory = false;
    }

    // Send attach to relay server
    this.socket.send({ type: 'session.attach', sessionId });
  }

  requestDeviceList(): void {
    this.socket.send({ type: 'device.list' });
  }

  revokeDevice(deviceId: string): void {
    this.socket.send({ type: 'device.revoke', deviceId });
  }

  // ── Workspace tree & context ───────────────────────────

  requestWorkspaceTree(path?: string): void {
    contextStore.isLoadingTree = true;
    // Safety timeout — clear loading state if no response within 10s
    setTimeout(() => {
      if (contextStore.isLoadingTree) {
        contextStore.isLoadingTree = false;
      }
    }, 10_000);
    this.socket.send({ type: 'workspace.tree', path, sessionId: this.sessionId ?? undefined });
  }

  addContext(path: string): void {
    if (!this.sessionId) return;
    this.socket.send({
      type: 'context.add',
      sessionId: this.sessionId,
      path,
      contextType: 'file',
    });
  }

  removeContext(path: string): void {
    if (!this.sessionId) return;
    this.socket.send({
      type: 'context.remove',
      sessionId: this.sessionId,
      path,
    });
  }

  // ── Filesystem browsing ─────────────────────────────────

  requestFsLs(path: string): void {
    this.socket.send({ type: 'fs.ls', path });
  }

  requestFsReadFile(path: string): void {
    this.socket.send({ type: 'fs.readFile', path });
  }

  requestFsCwd(): void {
    this.socket.send({ type: 'fs.cwd' });
  }

  /** Start a session at a specific working directory */
  startSessionAt(workingDir: string): void {
    // Snapshot current session before starting new one
    if (this.sessionId) {
      sessionStateManager.snapshotFrom(this);
      sessionStateManager.saveToDb(this.sessionId).catch(() => {});
    }
    this.messages = [];
    this.pendingApprovals = [];
    this.agents = [];
    this.sessionStats = { totalCost: 0, turnCount: 0, totalDuration: 0, inputTokens: 0, outputTokens: 0 };
    this.isWaitingForResponse = false;
    this.activeToolName = null;
    this.toolActivities = [];
    this.isViewingHistory = false;
    contextStore.clear();
    this.pendingWorkingDir = workingDir;
    this.socket.send({ type: 'session.start', adapter: 'cli', workingDir });
  }

  // ── Command usage tracking (IndexedDB) ─────────────────────

  /** In-memory cache of command usage counts, synced from IndexedDB */
  private commandUsageCache: Record<string, number> = {};
  private commandUsageLoaded = false;

  /** Load command usage from IndexedDB into cache */
  private async loadCommandUsage(): Promise<void> {
    if (this.commandUsageLoaded) return;
    try {
      const setting = await db.settings.get('commandUsage');
      if (setting && typeof setting.value === 'object' && setting.value !== null) {
        this.commandUsageCache = setting.value as Record<string, number>;
      }
      this.commandUsageLoaded = true;
    } catch {
      // IndexedDB unavailable — use empty cache
    }
  }

  getCommandUsage(): Record<string, number> {
    if (typeof window === 'undefined') return {};
    // Kick off async load if not yet loaded — returns cache (may be empty on first call)
    if (!this.commandUsageLoaded) {
      this.loadCommandUsage();
    }
    return { ...this.commandUsageCache };
  }

  trackCommandUsage(command: string): void {
    if (typeof window === 'undefined') return;
    this.commandUsageCache[command] = (this.commandUsageCache[command] || 0) + 1;
    // Fire-and-forget persist to IndexedDB
    db.settings.put({ key: 'commandUsage', value: { ...this.commandUsageCache } }).catch(() => {
      // IndexedDB unavailable — in-memory only
    });
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

      case 'session.info': {
        this.sessionId = message.sessionId;
        this.isViewingHistory = false;
        this.persistSessionId();

        // Register with session state manager, using pending working dir if available
        const wd = this.pendingWorkingDir;
        this.pendingWorkingDir = null;
        sessionStateManager.registerSession(
          message.sessionId,
          wd ? extractDirName(wd) : undefined,
          wd ?? undefined,
        );

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
      }

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
        // Guard against duplicate spawn messages (e.g. reconnect replay)
        if (!this.agents.some(a => a.id === message.agentId)) {
          this.agents.push({
            id: message.agentId,
            parentId: message.parentId,
            task: message.task,
            role: message.role,
            status: 'spawned',
          });
        }
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

      case 'error': {
        this.isWaitingForResponse = false;
        this.activeToolName = null;
        this.isReattaching = false;
        const isSessionGone =
          message.code === 'SESSION_NOT_FOUND' ||
          message.code === 'SESSION_EXPIRED' ||
          (typeof message.message === 'string' && message.message.includes('Session not found'));
        if (isSessionGone) {
          // Dead session — clear stale state, user gets a clean "Start Session" screen
          const deadId = this.sessionId;
          this.sessionId = null;
          this.storedSessionId = null;
          this.persistSessionId();
          this.messages = [];
          this.pendingApprovals = [];
          this.agents = [];
          this.toolActivities = [];
          if (deadId) sessionStateManager.removeSession(deadId);
        } else {
          this.messages.push({
            id: uid(),
            role: 'system',
            content: `Error: ${message.message}`,
            timestamp: new Date(),
          });
        }
        break;
      }

      case 'notification':
        this.messages.push({
          id: uid(),
          role: 'system',
          content: message.title ? `${message.title}: ${message.message}` : message.message,
          timestamp: new Date(),
        });
        break;

      case 'session.ended': {
        // Session was ended (by us or another client) — clean up
        const endedId = message.sessionId;
        if (this.sessionId === endedId) {
          this.sessionId = null;
          this.messages = [];
          this.pendingApprovals = [];
          this.agents = [];
          this.toolActivities = [];
          this.sessionStats = { totalCost: 0, turnCount: 0, totalDuration: 0, inputTokens: 0, outputTokens: 0 };
          this.isWaitingForResponse = false;
          this.activeToolName = null;
          sessionStateManager.activeSessionId = null;
          this.persistSessionId();
        }
        sessionStateManager.removeSession(endedId);
        break;
      }

      case 'connection.status':
        // Handled implicitly by socket state
        break;

      case 'workspace.tree.response':
        contextStore.handleTreeResponse(message.files);
        break;

      case 'context.add.response':
        contextStore.handleContextAddResponse(message);
        break;

      case 'context.remove.response':
        contextStore.handleContextRemoveResponse(message);
        break;

      case 'session.list.response':
        sessionsStore.handleListResponse(message.sessions);
        // Update session state manager with relay's session list
        sessionStateManager.updateFromRelayList(message.sessions);
        break;

      case 'session.history':
        this.handleSessionHistory(message);
        break;

      case 'device.list.response':
        this.devices = message.devices;
        break;

      case 'device.revoke.response':
        if (message.success) {
          this.devices = this.devices.filter((d) => d.id !== message.deviceId);
          this.messages.push({
            id: uid(),
            role: 'system',
            content: 'Device revoked successfully',
            timestamp: new Date(),
          });
        } else {
          this.messages.push({
            id: uid(),
            role: 'system',
            content: `Failed to revoke device ${message.deviceId}`,
            timestamp: new Date(),
          });
        }
        break;

      case 'approval.auto': {
        // Tool was auto-allowed by permission filter — record as immediately
        // completed so it doesn't conflict with tool.start/tool.complete lifecycle.
        const now = new Date();
        this.toolActivities.push({
          id: uid(),
          tool: message.tool,
          startedAt: now,
          completedAt: now,
          success: true,
          duration: 0,
          autoAllowed: message.reason,
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
      }

      case 'permission.mode':
        this.permissionMode = {
          mode: message.mode,
          delaySeconds: message.delaySeconds,
          godSubMode: message.godSubMode,
        };
        break;

      // ── Filesystem responses ──────────────────────────────
      case 'fs.ls.response':
        terminalStore.isLoading = false;
        // If this was a cd validation, update cwd
        if (terminalStore.pendingCdTarget) {
          terminalStore.cwd = terminalStore.pendingCdTarget;
          terminalStore.pendingCdTarget = null;
        } else {
          terminalStore.addOutput(terminalStore.formatLsOutput(message.entries, terminalStore.lastLsDetailed ?? false));
        }
        break;

      case 'fs.readFile.response':
        terminalStore.isLoading = false;
        terminalStore.addOutput(message.content);
        break;

      case 'fs.cwd.response':
        terminalStore.isLoading = false;
        terminalStore.sandboxRoot = message.path;
        // cwd uses sandbox-relative notation — ~ represents the sandbox root
        terminalStore.cwd = '~';
        break;

      case 'fs.error':
        terminalStore.isLoading = false;
        terminalStore.pendingCdTarget = null; // Clear pending cd on error
        terminalStore.addError(message.message);
        break;

      // ── Fleet status messages ──────────────────────────────
      case 'fleet.status.response':
        fleetStore.handleStatusResponse(message);
        break;

      case 'fleet.worker.spawned':
        fleetStore.handleWorkerSpawned(message);
        toasts.info(`Worker spawned for ${message.dirName}`);
        break;

      case 'fleet.worker.crashed':
        fleetStore.handleWorkerCrashed(message);
        toasts.error(`Worker for ${message.dirName} crashed — restarting`);
        break;

      case 'fleet.worker.restarted':
        fleetStore.handleWorkerRestarted(message);
        toasts.success(`Worker for ${message.dirName} restarted`);
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

  private handleSessionHistory(message: SessionHistoryMessage): void {
    // Replace current messages with historical transcript (read-only mode)
    this.sessionId = message.sessionId;
    // Don't persist as the live session — this is read-only history
    this.isViewingHistory = true;
    this.pendingApprovals = [];
    this.agents = [];
    this.toolActivities = [];
    this.activeToolName = null;
    this.isWaitingForResponse = false;
    this.messages = message.entries.map((entry) => ({
      id: uid(),
      role: entry.type === 'result' ? 'system' as const : entry.type === 'tool' ? 'tool' as const : entry.type as 'user' | 'assistant' | 'system',
      content: entry.content,
      timestamp: new Date(entry.timestamp),
      ...(entry.meta && entry.type === 'tool'
        ? {
            toolMeta: {
              tool: (entry.meta['tool'] as string) ?? 'unknown',
              input: entry.meta['input'] as Record<string, unknown> | undefined,
              output: entry.meta['output'] as string | undefined,
              success: entry.meta['success'] as boolean | undefined,
            },
          }
        : {}),
    }));
    // Push a system message indicating this is history
    this.messages.push({
      id: uid(),
      role: 'system',
      content: 'Viewing closed session history (read-only)',
      timestamp: new Date(),
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
