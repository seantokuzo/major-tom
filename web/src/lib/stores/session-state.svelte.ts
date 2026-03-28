// Session state manager — per-session isolated state with in-memory cache + IndexedDB persistence
// Uses Svelte 5 runes ($state)
//
// Strategy: relay.svelte.ts keeps its $state fields (so component reactivity is unbroken).
// This manager caches snapshots of per-session state. On session switch, relay calls
// snapshotFrom(relay) to save current, then restoreTo(relay) to load target.

import { db, type DbMessage } from '../db';
import type {
  ChatMessage,
  ApprovalRequest,
  Agent,
  SessionStats,
  ToolActivity,
  PermissionModeState,
} from './relay.svelte';

// ── Cached session snapshot ──────────────────────────────────

export interface SessionSnapshot {
  sessionId: string;
  name: string;
  workingDir: string;
  messages: ChatMessage[];
  agents: Agent[];
  pendingApprovals: ApprovalRequest[];
  permissionMode: PermissionModeState;
  sessionStats: SessionStats;
  toolActivities: ToolActivity[];
  isWaitingForResponse: boolean;
  activeToolName: string | null;
  isViewingHistory: boolean;
}

function createEmptySnapshot(sessionId: string, name?: string, workingDir?: string): SessionSnapshot {
  return {
    sessionId,
    name: name ?? extractDirName(workingDir ?? ''),
    workingDir: workingDir ?? '',
    messages: [],
    agents: [],
    pendingApprovals: [],
    permissionMode: { mode: 'smart', delaySeconds: 5, godSubMode: 'normal' },
    sessionStats: { totalCost: 0, turnCount: 0, totalDuration: 0, inputTokens: 0, outputTokens: 0 },
    toolActivities: [],
    isWaitingForResponse: false,
    activeToolName: null,
    isViewingHistory: false,
  };
}

/** Extract directory basename for auto-naming */
function extractDirName(dir: string): string {
  if (!dir) return 'New Session';
  const parts = dir.replace(/\/+$/, '').split('/');
  return parts[parts.length - 1] || 'New Session';
}

// Re-export for convenience
export { extractDirName };

// ── Session list entry (for panel display) ────────────────────

export interface SessionListEntry {
  sessionId: string;
  name: string;
  workingDir: string;
  status: 'active' | 'idle' | 'closed';
  totalCost: number;
  agentCount: number;
}

// ── Interface for snapshotting from/restoring to relay ─────────

export interface RelayStateAccessor {
  sessionId: string | null;
  messages: ChatMessage[];
  agents: Agent[];
  pendingApprovals: ApprovalRequest[];
  permissionMode: PermissionModeState;
  sessionStats: SessionStats;
  toolActivities: ToolActivity[];
  isWaitingForResponse: boolean;
  activeToolName: string | null;
  isViewingHistory: boolean;
}

// ── Session state manager ────────────────────────────────────

class SessionStateManager {
  // In-memory cache of session snapshots for instant switching
  private cache = new Map<string, SessionSnapshot>();

  // Chain concurrent saves per-session so only one runs at a time
  private persistChains = new Map<string, Promise<void>>();

  // Active session ID
  activeSessionId = $state<string | null>(null);

  // Session names (separate from snapshots so we can name sessions without full snapshots)
  private names = new Map<string, string>();

  // Whether the session panel is open
  panelOpen = $state(false);

  // Session list for panel display
  sessionList = $state<SessionListEntry[]>([]);

  // ── Snapshot management ────────────────────────────────────

  /** Take a snapshot of relay's current per-session state and store in cache */
  snapshotFrom(relay: RelayStateAccessor): void {
    const id = relay.sessionId;
    if (!id) return;

    const snap: SessionSnapshot = {
      sessionId: id,
      name: this.names.get(id) ?? extractDirName(''),
      workingDir: '',
      messages: [...relay.messages],
      agents: [...relay.agents],
      pendingApprovals: [...relay.pendingApprovals],
      permissionMode: { ...relay.permissionMode },
      sessionStats: { ...relay.sessionStats },
      toolActivities: [...relay.toolActivities],
      isWaitingForResponse: relay.isWaitingForResponse,
      activeToolName: relay.activeToolName,
      isViewingHistory: relay.isViewingHistory,
    };

    // Preserve existing name/workingDir if already cached
    const existing = this.cache.get(id);
    if (existing) {
      snap.name = existing.name;
      snap.workingDir = existing.workingDir;
    }

    this.cache.set(id, snap);
  }

  /** Restore a cached snapshot into relay's state fields */
  restoreTo(relay: RelayStateAccessor, sessionId: string): boolean {
    const snap = this.cache.get(sessionId);
    if (!snap) return false;

    relay.messages = [...snap.messages];
    relay.agents = [...snap.agents];
    relay.pendingApprovals = [...snap.pendingApprovals];
    relay.permissionMode = { ...snap.permissionMode };
    relay.sessionStats = { ...snap.sessionStats };
    relay.toolActivities = [...snap.toolActivities];
    relay.isWaitingForResponse = snap.isWaitingForResponse;
    relay.activeToolName = snap.activeToolName;
    relay.isViewingHistory = snap.isViewingHistory;
    return true;
  }

  // ── Session lifecycle ──────────────────────────────────────

  /** Register a session (create cache entry if needed). Called on session.info */
  registerSession(sessionId: string, name?: string, workingDir?: string): void {
    if (!this.cache.has(sessionId)) {
      this.cache.set(sessionId, createEmptySnapshot(sessionId, name, workingDir));
    }
    const snap = this.cache.get(sessionId)!;
    if (name) {
      snap.name = name;
      this.names.set(sessionId, name);
    }
    if (workingDir) {
      snap.workingDir = workingDir;
      if (!this.names.has(sessionId) || snap.name === 'New Session') {
        snap.name = extractDirName(workingDir);
        this.names.set(sessionId, snap.name);
      }
    }
    this.activeSessionId = sessionId;
    this.refreshSessionList();
  }

  /** Remove a session from cache (e.g. dead session error) */
  removeSession(sessionId: string): void {
    this.cache.delete(sessionId);
    this.names.delete(sessionId);
    if (this.activeSessionId === sessionId) {
      this.activeSessionId = null;
    }
    this.refreshSessionList();
  }

  /** Get session name */
  getSessionName(sessionId: string): string {
    return this.names.get(sessionId) ?? this.cache.get(sessionId)?.name ?? 'Session';
  }

  /** Rename a session */
  async renameSession(sessionId: string, newName: string): Promise<void> {
    this.names.set(sessionId, newName);
    const snap = this.cache.get(sessionId);
    if (snap) snap.name = newName;

    // Persist to IndexedDB
    try {
      const existing = await db.sessionMeta.get(sessionId);
      await db.sessionMeta.put({
        sessionId,
        name: newName,
        lastActive: new Date().toISOString(),
        ...(existing ? { dir: existing.dir, cost: existing.cost, tokens: existing.tokens } : {}),
      });
    } catch {
      // IndexedDB unavailable
    }
    this.refreshSessionList();
  }

  /** Update session list from relay's session.list.response */
  updateFromRelayList(relaySessions: Array<{ id: string; workingDirName: string; status: string; totalCost: number }>): void {
    for (const rs of relaySessions) {
      if (!this.cache.has(rs.id)) {
        // Create a lightweight entry from relay metadata
        const snap = createEmptySnapshot(rs.id, undefined, rs.workingDirName);
        snap.sessionStats.totalCost = rs.totalCost;
        this.cache.set(rs.id, snap);
      } else {
        const snap = this.cache.get(rs.id)!;
        if (!snap.workingDir && rs.workingDirName) {
          snap.workingDir = rs.workingDirName;
        }
        if (snap.name === 'New Session' && rs.workingDirName) {
          snap.name = extractDirName(rs.workingDirName);
          this.names.set(rs.id, snap.name);
        }
      }
    }
    this.refreshSessionList();
  }

  // ── IndexedDB persistence ──────────────────────────────────

  /** Save a snapshot to IndexedDB (incremental — upserts changed, deletes removed) */
  async saveToDb(sessionId: string): Promise<void> {
    const snap = this.cache.get(sessionId);
    if (!snap) return;

    try {
      await db.transaction('rw', db.messages, db.sessionMeta, async () => {
        // Build rows from current snapshot
        const rows: DbMessage[] = snap.messages.map((m) => ({
          sessionId,
          messageId: m.id,
          role: m.role,
          content: m.content,
          timestamp: m.timestamp.toISOString(),
          ...(m.toolMeta ? { toolMeta: m.toolMeta } : {}),
        }));

        // Upsert all current messages (uses compound index [sessionId+messageId])
        if (rows.length > 0) {
          await db.messages.bulkPut(rows);
        }

        // Delete messages that no longer exist in the snapshot
        const currentMessageIds = new Set(snap.messages.map((m) => m.id));
        const existingRows = await db.messages.where('sessionId').equals(sessionId).toArray();
        const staleKeys = existingRows
          .filter((row) => !currentMessageIds.has(row.messageId))
          .map((row) => [row.sessionId, row.messageId] as [string, string]);
        if (staleKeys.length > 0) {
          await db.messages.bulkDelete(staleKeys);
        }

        await db.sessionMeta.put({
          sessionId,
          name: snap.name,
          dir: snap.workingDir,
          cost: snap.sessionStats.totalCost,
          tokens: snap.sessionStats.inputTokens + snap.sessionStats.outputTokens,
          lastActive: new Date().toISOString(),
        });
      });
    } catch (e) {
      console.warn('[SessionState] Failed to save to IndexedDB:', e);
    }
  }

  /** Load a session from IndexedDB into cache */
  async loadFromDb(sessionId: string): Promise<boolean> {
    try {
      const [rows, meta] = await Promise.all([
        db.messages.where('sessionId').equals(sessionId).toArray(),
        db.sessionMeta.get(sessionId),
      ]);

      if (rows.length === 0 && !meta) return false;

      const snap = createEmptySnapshot(
        sessionId,
        meta?.name ?? undefined,
        meta?.dir ?? undefined,
      );

      if (rows.length > 0) {
        // Sort by timestamp ascending — lexical messageId order breaks at counter 10+
        rows.sort((a, b) => a.timestamp.localeCompare(b.timestamp));
        snap.messages = rows.map((row) => ({
          id: row.messageId,
          role: row.role,
          content: row.content,
          timestamp: new Date(row.timestamp),
          ...(row.toolMeta ? { toolMeta: row.toolMeta } : {}),
        }));
      }

      if (meta?.cost) snap.sessionStats.totalCost = meta.cost;
      if (meta?.name) this.names.set(sessionId, meta.name);

      this.cache.set(sessionId, snap);
      return true;
    } catch (e) {
      console.warn('[SessionState] Failed to load from IndexedDB:', e);
      return false;
    }
  }

  /** Persist active session messages (called from ChatView persist effect).
   *  Chains saves per-session so only one saveToDb runs at a time, preventing
   *  interleaved writes where an older snapshot could clobber a newer one. */
  async persistActive(relay: RelayStateAccessor): Promise<void> {
    const id = relay.sessionId;
    if (!id) return;
    // Update cache from current relay state first
    this.snapshotFrom(relay);

    // Chain onto previous save for this session
    const prev = this.persistChains.get(id) ?? Promise.resolve();
    const next = prev.then(() => this.saveToDb(id)).catch(() => {
      // saveToDb already logs warnings internally
    });
    this.persistChains.set(id, next);
    await next;
  }

  // ── Session list ────────────────────────────────────────────

  private refreshSessionList(): void {
    const entries: SessionListEntry[] = [];
    for (const [id, snap] of this.cache) {
      entries.push({
        sessionId: id,
        name: this.names.get(id) ?? snap.name,
        workingDir: snap.workingDir,
        status: id === this.activeSessionId ? 'active' : (snap.messages.length > 0 ? 'idle' : 'closed'),
        totalCost: snap.sessionStats.totalCost,
        agentCount: snap.agents.filter(a => a.status !== 'dismissed' && a.status !== 'complete').length,
      });
    }
    // Active session first, then rest
    entries.sort((a, b) => {
      if (a.sessionId === this.activeSessionId) return -1;
      if (b.sessionId === this.activeSessionId) return 1;
      return 0;
    });
    this.sessionList = entries;
  }

  /** Toggle session panel open/closed */
  togglePanel(): void {
    this.panelOpen = !this.panelOpen;
  }

  /** Close session panel */
  closePanel(): void {
    this.panelOpen = false;
  }
}

// Singleton
export const sessionStateManager = new SessionStateManager();
