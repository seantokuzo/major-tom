// Office Session Manager — per-session OfficeState scoping
// Maintains a Map of sessionId → OfficeState so each Claude Code session
// gets its own sprite state (agents, desks, activities, timers).
//
// Each OfficeState has its OWN OfficeEngine instance. Only the active session's
// engine gets started by the OfficeCanvas component (which passes engine as a
// prop and manages start/stop via $effect lifecycle).
//
// Non-active sessions keep their state in memory (agents, positions, timers)
// but their engines are stopped. When the user switches back, the OfficeCanvas
// receives the new engine prop and restarts it.

import { createOfficeState, type OfficeState } from './state.svelte';

/** Sentinel key for the "no session" / default state */
const DEFAULT_KEY = '__default__';

/** Maximum number of cached session states before evicting oldest */
const MAX_CACHED_SESSIONS = 8;

export interface OfficeSessionManager {
  /** The currently active OfficeState — always non-null */
  readonly active: OfficeState;
  /** The session ID of the currently active state (null = default) */
  readonly activeSessionId: string | null;
  /** The display name of the active session (for session indicator badge) */
  readonly activeSessionName: string;

  /** Switch to a specific session's office state. Creates one if needed. */
  switchTo(sessionId: string | null, sessionName?: string): void;
  /** Get or create state for a session without switching to it */
  getOrCreate(sessionId: string | null): OfficeState;
  /** Remove a session's cached state (e.g. on session end) */
  evict(sessionId: string): void;
  /** Reset everything — clears all cached session states */
  reset(): void;
}

export function createOfficeSessionManager(): OfficeSessionManager {
  /** Session states keyed by sessionId (or DEFAULT_KEY for no-session) */
  const states = new Map<string, OfficeState>();
  /** Session display names */
  const sessionNames = new Map<string, string>();
  /** Insertion order for LRU eviction */
  const accessOrder: string[] = [];

  let activeKey = $state<string>(DEFAULT_KEY);
  let activeSessionName = $state<string>('No Session');

  /** Get or create the OfficeState for a given key */
  function getOrCreateByKey(key: string): OfficeState {
    let state = states.get(key);
    if (!state) {
      state = createOfficeState();
      states.set(key, state);

      // Track access order for LRU eviction
      accessOrder.push(key);
      evictOldIfNeeded();
    } else {
      // Move to end of access order (most recent)
      const idx = accessOrder.indexOf(key);
      if (idx >= 0) {
        accessOrder.splice(idx, 1);
        accessOrder.push(key);
      }
    }
    return state;
  }

  /** Evict oldest cached states if over limit (never evict active or default) */
  function evictOldIfNeeded(): void {
    while (accessOrder.length > MAX_CACHED_SESSIONS) {
      const oldest = accessOrder[0];
      if (oldest === activeKey || oldest === DEFAULT_KEY) {
        // Can't evict active or default — move to end and break
        accessOrder.shift();
        accessOrder.push(oldest);
        break;
      }
      accessOrder.shift();
      const state = states.get(oldest);
      if (state) {
        state.reset();
        state.engine.stop();
      }
      states.delete(oldest);
      sessionNames.delete(oldest);
    }
  }

  // Ensure the default state exists
  getOrCreateByKey(DEFAULT_KEY);

  const active = $derived.by(() => {
    return getOrCreateByKey(activeKey);
  });

  return {
    get active() { return active; },
    get activeSessionId() { return activeKey === DEFAULT_KEY ? null : activeKey; },
    get activeSessionName() { return activeSessionName; },

    switchTo(sessionId: string | null, sessionName?: string): void {
      const newKey = sessionId ?? DEFAULT_KEY;
      if (newKey === activeKey) {
        // Still update the name if provided
        if (sessionName) {
          sessionNames.set(newKey, sessionName);
          activeSessionName = sessionName;
        }
        return;
      }

      // Stop outgoing session's engine (OfficeCanvas will start the new one)
      const oldState = states.get(activeKey);
      if (oldState) {
        oldState.engine.stop();
      }

      // Switch active key — triggers $derived.by to recompute active
      activeKey = newKey;

      // Ensure the new state exists
      getOrCreateByKey(newKey);

      // Update name
      if (sessionName) {
        sessionNames.set(newKey, sessionName);
      }
      activeSessionName = sessionNames.get(newKey)
        ?? (sessionId ? sessionId.slice(0, 8) : 'No Session');
    },

    getOrCreate(sessionId: string | null): OfficeState {
      const key = sessionId ?? DEFAULT_KEY;
      return getOrCreateByKey(key);
    },

    evict(sessionId: string): void {
      if (sessionId === activeKey) {
        // Switch to default first
        activeKey = DEFAULT_KEY;
        activeSessionName = 'No Session';
      }
      const state = states.get(sessionId);
      if (state) {
        state.reset();
        state.engine.stop();
      }
      states.delete(sessionId);
      sessionNames.delete(sessionId);
      const idx = accessOrder.indexOf(sessionId);
      if (idx >= 0) accessOrder.splice(idx, 1);
    },

    reset(): void {
      // Reset all states
      for (const [, state] of states) {
        state.reset();
        state.engine.stop();
      }
      states.clear();
      sessionNames.clear();
      accessOrder.length = 0;

      activeKey = DEFAULT_KEY;
      activeSessionName = 'No Session';

      // Re-create default state
      getOrCreateByKey(DEFAULT_KEY);
    },
  };
}
