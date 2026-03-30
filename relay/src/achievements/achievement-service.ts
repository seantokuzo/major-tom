/**
 * AchievementService — evaluates, persists, and broadcasts achievement state.
 *
 * Persists to ~/.major-tom/achievements.json (atomic writes, same pattern as notification-config.ts).
 * Evaluates conditions against incoming events.
 * Tracks cumulative progress (counters) and one-shot unlocks.
 * Emits achievement.unlocked and achievement.progress events.
 */

import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { randomUUID } from 'node:crypto';
import { logger } from '../utils/logger.js';
import {
  ACHIEVEMENT_DEFINITIONS,
  type AchievementDefinition,
  type AchievementCondition,
} from './achievement-definitions.js';

// ── Persisted State Types ─────────────────────────────────────

export interface AchievementUnlock {
  achievementId: string;
  unlockedAt: string;
}

export interface AchievementState {
  /** Counter values keyed by counterKey */
  counters: Record<string, number>;
  /** Set of event keys that have been triggered */
  triggeredEvents: string[];
  /** Achievements that have been unlocked */
  unlocked: AchievementUnlock[];
}

/** Single achievement status returned by the API */
export interface AchievementStatus {
  id: string;
  name: string;
  description: string;
  category: string;
  icon: string;
  unlocked: boolean;
  unlockedAt: string | null;
  progress: number | null;
  target: number | null;
  percentage: number | null;
  secret: boolean;
}

// ── Event payloads ────────────────────────────────────────────

export interface AchievementUnlockedPayload {
  achievementId: string;
  name: string;
  description: string;
  category: string;
  icon: string;
  unlockedAt: string;
}

export interface AchievementProgressPayload {
  achievementId: string;
  name: string;
  current: number;
  target: number;
  percentage: number;
}

// ── Listener type ─────────────────────────────────────────────

type UnlockListener = (payload: AchievementUnlockedPayload) => void;
type ProgressListener = (payload: AchievementProgressPayload) => void;

// ── Constants ─────────────────────────────────────────────────

const STATE_DIR = join(homedir(), '.major-tom');
const STATE_FILE = join(STATE_DIR, 'achievements.json');
const PERSIST_DEBOUNCE_MS = 2000;

// ── AchievementService ────────────────────────────────────────

export class AchievementService {
  private state: AchievementState = {
    counters: {},
    triggeredEvents: [],
    unlocked: [],
  };

  private unlockedSet = new Set<string>();
  private loaded = false;
  private persistTimer: ReturnType<typeof setTimeout> | null = null;
  private persistPromise: Promise<void> = Promise.resolve();

  private unlockListeners: UnlockListener[] = [];
  private progressListeners: ProgressListener[] = [];

  // ── Lifecycle ─────────────────────────────────────────────

  async load(): Promise<void> {
    try {
      const data = await readFile(STATE_FILE, 'utf-8');
      const parsed = JSON.parse(data) as Partial<AchievementState>;

      this.state = {
        counters: parsed.counters && typeof parsed.counters === 'object'
          ? parsed.counters
          : {},
        triggeredEvents: Array.isArray(parsed.triggeredEvents)
          ? parsed.triggeredEvents
          : [],
        unlocked: Array.isArray(parsed.unlocked)
          ? parsed.unlocked
          : [],
      };

      // Rebuild unlock set
      for (const u of this.state.unlocked) {
        this.unlockedSet.add(u.achievementId);
      }

      logger.info(
        { unlocked: this.state.unlocked.length, counters: Object.keys(this.state.counters).length },
        'Achievement state loaded from disk',
      );
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code !== 'ENOENT') {
        logger.warn({ err }, 'Failed to read achievement state — starting fresh');
      }
    }
    this.loaded = true;
  }

  // ── Event listeners ───────────────────────────────────────

  onUnlock(listener: UnlockListener): void {
    this.unlockListeners.push(listener);
  }

  onProgress(listener: ProgressListener): void {
    this.progressListeners.push(listener);
  }

  // ── Event checking entry point ────────────────────────────

  /**
   * Process an achievement-relevant event.
   * Call this from event hooks with the event type and data.
   */
  checkEvent(eventType: string, eventData: Record<string, unknown> = {}): void {
    if (!this.loaded) return;

    switch (eventType) {
      case 'session.start':
        this.incrementCounter('sessions_started');
        this.checkTimeAchievements();
        break;

      case 'session.end': {
        this.incrementCounter('sessions_completed');
        const durationMs = typeof eventData['durationMs'] === 'number' ? eventData['durationMs'] : 0;
        const costUsd = typeof eventData['costUsd'] === 'number' ? eventData['costUsd'] : 0;

        // Track longest session
        const current = this.getCounter('longest_session_ms');
        if (durationMs > current) {
          this.setCounter('longest_session_ms', durationMs);
        }

        // Track total cost in cents for integer-safe thresholds
        const costCents = Math.round(costUsd * 100);
        this.incrementCounter('total_cost_cents', costCents);

        // Penny Pincher — session under $0.01
        if (costUsd > 0 && costUsd < 0.01) {
          this.triggerEvent('cheap_session');
        }
        break;
      }

      case 'approval.granted': {
        this.incrementCounter('approvals_granted');
        const approvalDurationMs = typeof eventData['durationMs'] === 'number' ? eventData['durationMs'] : Infinity;
        if (approvalDurationMs <= 2000) {
          this.triggerEvent('fast_approval');
        }
        const source = typeof eventData['source'] === 'string' ? eventData['source'] : '';
        if (source === 'watch') {
          this.triggerEvent('approval_from_watch');
        }
        break;
      }

      case 'approval.denied':
        this.incrementCounter('approvals_denied');
        break;

      case 'god_mode.enabled':
        this.triggerEvent('god_mode_enabled');
        break;

      case 'tool.start': {
        const tool = typeof eventData['tool'] === 'string' ? eventData['tool'] : '';
        const toolLower = tool.toLowerCase();
        if (toolLower.includes('bash') || toolLower.includes('shell')) {
          this.incrementCounter('tool_bash_count');
        }
        if (toolLower.includes('edit') || toolLower === 'edit') {
          this.incrementCounter('tool_edit_count');
        }
        if (toolLower.includes('read') || toolLower === 'read') {
          this.incrementCounter('tool_read_count');
        }
        if (toolLower.includes('write') || toolLower === 'write') {
          this.incrementCounter('tool_write_count');
        }
        if (toolLower.includes('grep') || toolLower.includes('glob') || toolLower.includes('search')) {
          this.incrementCounter('tool_grep_count');
        }
        break;
      }

      case 'agent.spawn':
        this.incrementCounter('agents_spawned');
        break;

      case 'all_agent_types_active':
        this.triggerEvent('all_agent_types_active');
        break;

      case 'fleet.started':
        this.triggerEvent('fleet_mode_started');
        break;

      case 'worker.crashed':
        this.triggerEvent('worker_crash_survived');
        break;

      case 'widget.viewed':
        this.triggerEvent('widget_viewed');
        break;
    }
  }

  // ── Counter & event manipulation ──────────────────────────

  private incrementCounter(key: string, amount = 1): void {
    const prev = this.state.counters[key] ?? 0;
    this.state.counters[key] = prev + amount;
    this.evaluateAll();
    this.schedulePersist();
  }

  private setCounter(key: string, value: number): void {
    this.state.counters[key] = value;
    this.evaluateAll();
    this.schedulePersist();
  }

  private getCounter(key: string): number {
    return this.state.counters[key] ?? 0;
  }

  private triggerEvent(eventKey: string): void {
    if (!this.state.triggeredEvents.includes(eventKey)) {
      this.state.triggeredEvents.push(eventKey);
    }
    this.evaluateAll();
    this.schedulePersist();
  }

  // ── Time-based checks ─────────────────────────────────────

  private checkTimeAchievements(): void {
    const hour = new Date().getHours();
    if (hour >= 0 && hour < 5) {
      this.triggerEvent('used_after_midnight');
    }
    if (hour >= 4 && hour < 6) {
      this.triggerEvent('used_before_6am');
    }
  }

  // ── Condition evaluation ──────────────────────────────────

  private evaluateCondition(condition: AchievementCondition): boolean {
    switch (condition.type) {
      case 'counter':
        return (this.state.counters[condition.counterKey] ?? 0) >= condition.threshold;

      case 'event':
        return this.state.triggeredEvents.includes(condition.eventKey);

      case 'duration':
        return (this.state.counters[condition.counterKey] ?? 0) >= condition.threshold;

      case 'composite':
        return condition.conditions.every((c) => this.evaluateCondition(c));
    }
  }

  private getProgress(definition: AchievementDefinition): { current: number; target: number } | null {
    const { condition } = definition;
    if (condition.type === 'counter' || condition.type === 'duration') {
      return {
        current: this.state.counters[condition.counterKey] ?? 0,
        target: condition.threshold,
      };
    }
    return null;
  }

  private evaluateAll(): void {
    for (const definition of ACHIEVEMENT_DEFINITIONS) {
      if (this.unlockedSet.has(definition.id)) continue;

      const met = this.evaluateCondition(definition.condition);
      if (met) {
        this.unlock(definition);
      } else {
        // Emit progress for counter/duration achievements
        const progress = this.getProgress(definition);
        if (progress && progress.current > 0) {
          this.emitProgress(definition, progress.current, progress.target);
        }
      }
    }
  }

  private unlock(definition: AchievementDefinition): void {
    const now = new Date().toISOString();
    this.unlockedSet.add(definition.id);
    this.state.unlocked.push({
      achievementId: definition.id,
      unlockedAt: now,
    });

    // Update the meta counter for meta-achievements
    this.state.counters['achievements_unlocked'] = this.state.unlocked.length;

    const payload: AchievementUnlockedPayload = {
      achievementId: definition.id,
      name: definition.name,
      description: definition.description,
      category: definition.category,
      icon: definition.icon,
      unlockedAt: now,
    };

    logger.info({ achievementId: definition.id, name: definition.name }, 'Achievement unlocked');

    // Ensure unlock is persisted promptly
    this.schedulePersist();

    for (const listener of this.unlockListeners) {
      try {
        listener(payload);
      } catch (err) {
        logger.error({ err, achievementId: definition.id }, 'Error in achievement unlock listener');
      }
    }

    // Re-evaluate in case this unlock triggers meta achievements (e.g., "Achievement Hunter")
    // Use microtask to avoid stack overflow from recursive evaluateAll
    queueMicrotask(() => {
      for (const def of ACHIEVEMENT_DEFINITIONS) {
        if (this.unlockedSet.has(def.id)) continue;
        if (def.category === 'meta' && this.evaluateCondition(def.condition)) {
          this.unlock(def);
        }
      }
    });
  }

  private emitProgress(definition: AchievementDefinition, current: number, target: number): void {
    const percentage = Math.min(Math.round((current / target) * 100), 99);
    const payload: AchievementProgressPayload = {
      achievementId: definition.id,
      name: definition.name,
      current,
      target,
      percentage,
    };

    for (const listener of this.progressListeners) {
      try {
        listener(payload);
      } catch (err) {
        logger.error({ err, achievementId: definition.id }, 'Error in achievement progress listener');
      }
    }
  }

  // ── Public API ────────────────────────────────────────────

  /** Get all achievements with their current status */
  getAllStatus(): AchievementStatus[] {
    return ACHIEVEMENT_DEFINITIONS.map((def) => {
      const unlockEntry = this.state.unlocked.find((u) => u.achievementId === def.id);
      const progress = this.getProgress(def);

      return {
        id: def.id,
        name: def.name,
        description: def.description,
        category: def.category,
        icon: def.icon,
        unlocked: this.unlockedSet.has(def.id),
        unlockedAt: unlockEntry?.unlockedAt ?? null,
        progress: progress?.current ?? null,
        target: progress?.target ?? null,
        percentage: progress
          ? Math.min(Math.round((progress.current / progress.target) * 100), this.unlockedSet.has(def.id) ? 100 : 99)
          : null,
        secret: def.secret ?? false,
      };
    });
  }

  /** Get count of unlocked achievements */
  getUnlockedCount(): number {
    return this.state.unlocked.length;
  }

  /** Get total achievement count */
  getTotalCount(): number {
    return ACHIEVEMENT_DEFINITIONS.length;
  }

  /** Reset all achievement state (dev/debug) */
  async reset(): Promise<void> {
    this.state = {
      counters: {},
      triggeredEvents: [],
      unlocked: [],
    };
    this.unlockedSet.clear();
    await this.persistNow();
    logger.info('Achievement state reset');
  }

  // ── Persistence ───────────────────────────────────────────

  private schedulePersist(): void {
    if (this.persistTimer) return;
    this.persistTimer = setTimeout(() => {
      this.persistTimer = null;
      void this.persistNow();
    }, PERSIST_DEBOUNCE_MS);
  }

  private async persistNow(): Promise<void> {
    this.persistPromise = this.persistPromise.then(async () => {
      try {
        await mkdir(STATE_DIR, { recursive: true });

        const tmpFile = join(STATE_DIR, `achievements.${randomUUID().slice(0, 8)}.tmp`);
        await writeFile(tmpFile, JSON.stringify(this.state, null, 2), 'utf-8');
        await rename(tmpFile, STATE_FILE);

        logger.debug(
          { unlocked: this.state.unlocked.length },
          'Achievement state persisted',
        );
      } catch (err) {
        logger.error({ err }, 'Failed to persist achievement state');
      }
    });

    await this.persistPromise;
  }

  /** Flush any pending persistence (for shutdown) */
  async flush(): Promise<void> {
    if (this.persistTimer) {
      clearTimeout(this.persistTimer);
      this.persistTimer = null;
    }
    await this.persistNow();
  }

  /** Dispose — flush and clean up */
  async dispose(): Promise<void> {
    await this.flush();
  }
}
