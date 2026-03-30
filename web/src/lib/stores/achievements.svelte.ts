// Achievement store — reactive state for achievement tracking and display
// Uses Svelte 5 runes ($state, $derived)

import type {
  AchievementStatusEntry,
  AchievementUnlockedMessage,
  AchievementProgressMessage,
  AchievementListResponseMessage,
} from '../protocol/messages';
import { db, type DbAchievement } from '../db';
import { toasts } from './toast.svelte';

// ── Achievement categories ────────────────────────────────────

export const ACHIEVEMENT_CATEGORIES = [
  { id: 'sessions', label: 'Sessions' },
  { id: 'approvals', label: 'Approvals' },
  { id: 'cost', label: 'Cost' },
  { id: 'agents', label: 'Agents' },
  { id: 'tools', label: 'Tools' },
  { id: 'fleet', label: 'Fleet' },
  { id: 'meta', label: 'Meta' },
] as const;

export type AchievementCategory = (typeof ACHIEVEMENT_CATEGORIES)[number]['id'];

// ── Achievement store ─────────────────────────────────────────

class AchievementStore {
  // Panel state
  panelOpen = $state(false);

  // Data
  achievements = $state<AchievementStatusEntry[]>([]);
  totalCount = $state(0);
  unlockedCount = $state(0);
  loading = $state(false);
  error = $state<string | null>(null);

  // Recent unlock for pulse animation
  recentUnlock = $state(false);
  private recentUnlockTimer: ReturnType<typeof setTimeout> | null = null;

  // Active category filter
  activeCategory = $state<AchievementCategory | 'all'>('all');

  // Polling
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private fetchInFlight = false;

  // Derived
  filteredAchievements = $derived(
    this.activeCategory === 'all'
      ? this.achievements
      : this.achievements.filter((a) => a.category === this.activeCategory),
  );

  categoryCounts = $derived(
    this.achievements.reduce(
      (acc, a) => {
        const cat = a.category as AchievementCategory;
        if (!acc[cat]) acc[cat] = { total: 0, unlocked: 0 };
        acc[cat].total++;
        if (a.unlocked) acc[cat].unlocked++;
        return acc;
      },
      {} as Record<AchievementCategory, { total: number; unlocked: number }>,
    ),
  );

  // ── Initialization ──────────────────────────────────────────

  /** Load cached achievements from IndexedDB for instant panel display */
  async loadFromCache(): Promise<void> {
    try {
      const cached = await db.achievements.toArray();
      if (cached.length > 0 && this.achievements.length === 0) {
        this.achievements = cached.map(dbRowToEntry);
        this.totalCount = cached.length;
        this.unlockedCount = cached.filter((a) => a.unlocked).length;
      }
    } catch {
      // IndexedDB unavailable — degrade gracefully
    }
  }

  // ── Panel control ─────────────────────────────────────────

  openPanel(): void {
    this.panelOpen = true;
    void this.fetchAchievements();
    this.startPolling(5_000);
  }

  closePanel(): void {
    this.panelOpen = false;
    this.stopPolling();
  }

  togglePanel(): void {
    if (this.panelOpen) {
      this.closePanel();
    } else {
      this.openPanel();
    }
  }

  setCategory(category: AchievementCategory | 'all'): void {
    this.activeCategory = category;
  }

  // ── Data fetching (REST API) ──────────────────────────────

  async fetchAchievements(): Promise<void> {
    if (this.fetchInFlight) return;
    this.fetchInFlight = true;
    this.loading = true;
    this.error = null;

    try {
      const res = await fetch('/api/achievements', {
        credentials: 'include',
      });

      if (!res.ok) {
        throw new Error(`HTTP ${res.status}: ${res.statusText}`);
      }

      const data = (await res.json()) as AchievementListResponseMessage;
      this.applyListData(data);
      void this.persistToCache(data.achievements);
    } catch (err) {
      this.error = err instanceof Error ? err.message : 'Failed to fetch achievements';
    } finally {
      this.loading = false;
      this.fetchInFlight = false;
    }
  }

  /** Fetch just the unlocked count for the header indicator */
  async fetchIndicatorCount(): Promise<void> {
    try {
      const res = await fetch('/api/achievements', { credentials: 'include' });
      if (res.ok) {
        const data = (await res.json()) as AchievementListResponseMessage;
        this.applyListData(data);
        void this.persistToCache(data.achievements);
      }
    } catch {
      // Silently fail — indicator is non-critical
    }
  }

  // ── WebSocket event handlers ──────────────────────────────

  handleUnlocked(msg: AchievementUnlockedMessage): void {
    const existing = this.achievements.find((a) => a.id === msg.achievementId);
    if (existing) {
      // Guard: only count transition from locked → unlocked
      const wasLocked = !existing.unlocked;
      existing.unlocked = true;
      existing.unlockedAt = msg.unlockedAt;
      existing.progress = existing.target;
      existing.percentage = 100;
      if (wasLocked) {
        this.unlockedCount++;
      }
    } else {
      // Not in list yet — add it and update both counts
      this.achievements.push({
        id: msg.achievementId,
        name: msg.name,
        description: msg.description,
        category: msg.category,
        icon: msg.icon,
        unlocked: true,
        unlockedAt: msg.unlockedAt,
        progress: null,
        target: null,
        percentage: 100,
        secret: false,
      });
      this.totalCount++;
      this.unlockedCount++;
    }

    this.triggerRecentUnlock();

    // Show toast
    toasts.success(`${msg.icon} Achievement Unlocked: ${msg.name}`);
  }

  handleProgress(msg: AchievementProgressMessage): void {
    const existing = this.achievements.find((a) => a.id === msg.achievementId);
    if (existing) {
      existing.progress = msg.current;
      existing.target = msg.target;
      existing.percentage = msg.percentage;
    }
  }

  handleListResponse(msg: AchievementListResponseMessage): void {
    this.applyListData(msg);
    void this.persistToCache(msg.achievements);
  }

  // ── Polling ───────────────────────────────────────────────

  startPolling(intervalMs: number): void {
    this.stopPolling();
    this.pollTimer = setInterval(() => {
      void this.fetchAchievements();
    }, intervalMs);
  }

  stopPolling(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }

  // ── Internal ──────────────────────────────────────────────

  private applyListData(data: AchievementListResponseMessage): void {
    this.achievements = data.achievements;
    this.totalCount = data.totalCount;
    this.unlockedCount = data.unlockedCount;
  }

  private triggerRecentUnlock(): void {
    this.recentUnlock = true;
    if (this.recentUnlockTimer) clearTimeout(this.recentUnlockTimer);
    this.recentUnlockTimer = setTimeout(() => {
      this.recentUnlock = false;
      this.recentUnlockTimer = null;
    }, 3000);
  }

  private async persistToCache(entries: AchievementStatusEntry[]): Promise<void> {
    try {
      const now = new Date().toISOString();
      const rows: DbAchievement[] = entries.map((a) => ({
        id: a.id,
        name: a.name,
        description: a.description,
        category: a.category,
        icon: a.icon,
        unlocked: a.unlocked,
        unlockedAt: a.unlockedAt,
        progress: a.progress,
        target: a.target,
        percentage: a.percentage,
        secret: a.secret,
        syncedAt: now,
      }));
      // Clear stale rows so removed/renamed achievements don't linger
      await db.achievements.clear();
      await db.achievements.bulkPut(rows);
    } catch {
      // IndexedDB unavailable — degrade gracefully
    }
  }
}

// ── Helpers ─────────────────────────────────────────────────

function dbRowToEntry(row: DbAchievement): AchievementStatusEntry {
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    category: row.category,
    icon: row.icon,
    unlocked: row.unlocked,
    unlockedAt: row.unlockedAt,
    progress: row.progress,
    target: row.target,
    percentage: row.percentage,
    secret: row.secret,
  };
}

// Singleton
export const achievementStore = new AchievementStore();
