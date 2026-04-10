/**
 * Keybar store — persists the user's custom accessory + specialty key
 * layout to localStorage, exposes reactive lists of `KeySpec` for the UI.
 *
 * Storage key: `mt-keybar-config-v1`.
 *
 * Wrapped in try/catch because privacy mode / disabled storage throws on
 * access (Safari Private Browsing, Firefox "block third-party cookies" on
 * embedded frames, etc). Failures fall back to in-memory defaults — the
 * user still gets a working keybar, just no persistence.
 */

import {
  KEY_LIBRARY,
  DEFAULT_ACCESSORY_KEYS,
  DEFAULT_SPECIALTY_KEYS,
  getKey,
  type KeySpec,
} from '../shell/keys';

const STORAGE_KEY = 'mt-keybar-config-v1';
const SYNC_DEBOUNCE_MS = 800;

interface KeybarConfig {
  version: 1;
  accessory: string[];
  specialty: string[];
}

function defaultConfig(): KeybarConfig {
  return {
    version: 1,
    accessory: [...DEFAULT_ACCESSORY_KEYS],
    specialty: [...DEFAULT_SPECIALTY_KEYS],
  };
}

function sanitize(ids: unknown): string[] {
  if (!Array.isArray(ids)) return [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const id of ids) {
    if (typeof id !== 'string') continue;
    if (seen.has(id)) continue;
    if (!getKey(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

function loadFromStorage(): KeybarConfig {
  if (typeof window === 'undefined') return defaultConfig();
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return defaultConfig();
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null) return defaultConfig();
    const obj = parsed as Record<string, unknown>;
    const accessory = sanitize(obj['accessory']);
    const specialty = sanitize(obj['specialty']);
    return {
      version: 1,
      // An empty array after sanitize means saved data was corrupt or referenced
      // retired key ids — fall back to defaults rather than show an empty bar.
      accessory: accessory.length > 0 ? accessory : [...DEFAULT_ACCESSORY_KEYS],
      specialty: specialty.length > 0 ? specialty : [...DEFAULT_SPECIALTY_KEYS],
    };
  } catch {
    return defaultConfig();
  }
}

function saveToStorage(config: KeybarConfig): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
  } catch {
    // privacy mode / quota / blocked storage — ignore, in-memory state still works
  }
}

class KeybarStore {
  /** Active key IDs on the accessory row, in render order. */
  accessoryIds = $state<string[]>([]);
  /** Active key IDs on the specialty grid, in render order. */
  specialtyIds = $state<string[]>([]);

  /** Resolved `KeySpec` arrays for the UI. */
  accessoryKeys = $derived<KeySpec[]>(
    this.accessoryIds.map((id) => getKey(id)).filter((k): k is KeySpec => !!k)
  );
  specialtyKeys = $derived<KeySpec[]>(
    this.specialtyIds.map((id) => getKey(id)).filter((k): k is KeySpec => !!k)
  );

  /** Full library for the customize picker. */
  readonly library: KeySpec[] = KEY_LIBRARY;

  /** Whether we've loaded from the relay (prevents double-apply). */
  private synced = false;
  private syncTimer: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    const cfg = loadFromStorage();
    this.accessoryIds = cfg.accessory;
    this.specialtyIds = cfg.specialty;
  }

  // ── Relay sync ──────────────────────────────────────────────────────

  /**
   * Pull preferences from the relay and apply if the server has a custom
   * config. Called once after auth check completes.
   * Server config wins over local defaults; if local is customized (not
   * defaults) and server is empty, we push local config up.
   */
  async syncFromRelay(): Promise<void> {
    if (this.synced) return;
    this.synced = true;
    try {
      const res = await fetch('/api/user/preferences', { credentials: 'include' });
      if (!res.ok) return; // 401, 404, etc — fallback to local

      const prefs = await res.json() as Record<string, unknown>;
      const remote = prefs.keybarConfig as
        | { version: number; accessory: string[]; specialty: string[] }
        | undefined;

      if (remote && Array.isArray(remote.accessory) && remote.accessory.length > 0) {
        // Server has a config — apply it
        const accessory = sanitize(remote.accessory);
        const specialty = sanitize(remote.specialty);
        if (accessory.length > 0) {
          this.accessoryIds = accessory;
          this.specialtyIds = specialty.length > 0 ? specialty : [...DEFAULT_SPECIALTY_KEYS];
          saveToStorage({ version: 1, accessory: this.accessoryIds, specialty: this.specialtyIds });
        }
      } else if (!this.isDefault()) {
        // Local is customized but server is empty — push local up
        this.pushToRelay();
      }
    } catch {
      // Network error — stay with local config
    }
  }

  /** Check if current config matches defaults */
  private isDefault(): boolean {
    return (
      JSON.stringify(this.accessoryIds) === JSON.stringify(DEFAULT_ACCESSORY_KEYS) &&
      JSON.stringify(this.specialtyIds) === JSON.stringify(DEFAULT_SPECIALTY_KEYS)
    );
  }

  /** Debounced push to relay */
  private scheduleSyncToRelay(): void {
    if (this.syncTimer) clearTimeout(this.syncTimer);
    this.syncTimer = setTimeout(() => {
      this.syncTimer = null;
      this.pushToRelay();
    }, SYNC_DEBOUNCE_MS);
  }

  /** Push current config to relay (fire-and-forget) */
  private pushToRelay(): void {
    const payload = {
      keybarConfig: {
        version: 1,
        accessory: this.accessoryIds,
        specialty: this.specialtyIds,
      },
    };
    fetch('/api/user/preferences', {
      method: 'PUT',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    }).catch(() => {
      // Network error — local state is still saved, will sync next time
    });
  }

  // ── Accessory row mutators ───────────────────────────────────────────

  addAccessoryKey(id: string): void {
    if (!getKey(id)) return;
    if (this.accessoryIds.includes(id)) return;
    this.accessoryIds = [...this.accessoryIds, id];
    this.persist();
  }

  removeAccessoryKey(id: string): void {
    if (!this.accessoryIds.includes(id)) return;
    this.accessoryIds = this.accessoryIds.filter((k) => k !== id);
    this.persist();
  }

  moveAccessoryKey(id: string, direction: -1 | 1): void {
    const idx = this.accessoryIds.indexOf(id);
    if (idx === -1) return;
    const nextIdx = idx + direction;
    if (nextIdx < 0 || nextIdx >= this.accessoryIds.length) return;
    const next = [...this.accessoryIds];
    const [key] = next.splice(idx, 1);
    if (!key) return;
    next.splice(nextIdx, 0, key);
    this.accessoryIds = next;
    this.persist();
  }

  // ── Specialty grid mutators ──────────────────────────────────────────

  addSpecialtyKey(id: string): void {
    if (!getKey(id)) return;
    if (this.specialtyIds.includes(id)) return;
    this.specialtyIds = [...this.specialtyIds, id];
    this.persist();
  }

  removeSpecialtyKey(id: string): void {
    if (!this.specialtyIds.includes(id)) return;
    this.specialtyIds = this.specialtyIds.filter((k) => k !== id);
    this.persist();
  }

  moveSpecialtyKey(id: string, direction: -1 | 1): void {
    const idx = this.specialtyIds.indexOf(id);
    if (idx === -1) return;
    const nextIdx = idx + direction;
    if (nextIdx < 0 || nextIdx >= this.specialtyIds.length) return;
    const next = [...this.specialtyIds];
    const [key] = next.splice(idx, 1);
    if (!key) return;
    next.splice(nextIdx, 0, key);
    this.specialtyIds = next;
    this.persist();
  }

  // ── Reset ────────────────────────────────────────────────────────────

  resetToDefaults(): void {
    this.accessoryIds = [...DEFAULT_ACCESSORY_KEYS];
    this.specialtyIds = [...DEFAULT_SPECIALTY_KEYS];
    this.persist();
  }

  // ── Persistence ──────────────────────────────────────────────────────

  private persist(): void {
    saveToStorage({
      version: 1,
      accessory: this.accessoryIds,
      specialty: this.specialtyIds,
    });
    this.scheduleSyncToRelay();
  }
}

export const keybarStore = new KeybarStore();
