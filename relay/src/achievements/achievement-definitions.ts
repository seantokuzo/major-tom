/**
 * Achievement Definitions — ~30 achievements across 7 categories.
 *
 * Each achievement has a unique id, display info, category, and
 * a condition that describes how it's unlocked (counter threshold,
 * one-shot event, or composite check).
 */

// ── Categories ────────────────────────────────────────────────

export type AchievementCategory =
  | 'sessions'
  | 'approvals'
  | 'cost'
  | 'agents'
  | 'tools'
  | 'fleet'
  | 'meta';

// ── Condition types ───────────────────────────────────────────

/** Counter-based: unlock when a tracked counter hits `threshold` */
export interface CounterCondition {
  type: 'counter';
  /** Key used to look up the counter in achievement state */
  counterKey: string;
  threshold: number;
}

/** One-shot: unlock on a specific event occurrence */
export interface EventCondition {
  type: 'event';
  /** The event key that triggers this achievement */
  eventKey: string;
}

/** Time-based: unlock when a duration (ms) exceeds threshold */
export interface DurationCondition {
  type: 'duration';
  /** Key used to look up a tracked duration value */
  counterKey: string;
  threshold: number;
}

/** Composite: unlock when multiple sub-conditions are ALL met */
export interface CompositeCondition {
  type: 'composite';
  /** All conditions must be satisfied */
  conditions: AchievementCondition[];
}

export type AchievementCondition =
  | CounterCondition
  | EventCondition
  | DurationCondition
  | CompositeCondition;

// ── Achievement definition ────────────────────────────────────

export interface AchievementDefinition {
  id: string;
  name: string;
  description: string;
  category: AchievementCategory;
  icon: string;
  condition: AchievementCondition;
  /** Whether this achievement is secret (hidden until unlocked) */
  secret?: boolean;
}

// ── Definitions ───────────────────────────────────────────────

export const ACHIEVEMENT_DEFINITIONS: readonly AchievementDefinition[] = [
  // ── Sessions ───────────────────────────────────────────────
  {
    id: 'first_contact',
    name: 'First Contact',
    description: 'Start your first session',
    category: 'sessions',
    icon: '🚀',
    condition: { type: 'counter', counterKey: 'sessions_started', threshold: 1 },
  },
  {
    id: 'frequent_flyer',
    name: 'Frequent Flyer',
    description: 'Start 10 sessions',
    category: 'sessions',
    icon: '✈️',
    condition: { type: 'counter', counterKey: 'sessions_started', threshold: 10 },
  },
  {
    id: 'centurion',
    name: 'Centurion',
    description: 'Complete 100 sessions',
    category: 'sessions',
    icon: '🏛️',
    condition: { type: 'counter', counterKey: 'sessions_completed', threshold: 100 },
  },
  {
    id: 'marathon_runner',
    name: 'Marathon Runner',
    description: 'Run a single session for over 4 hours',
    category: 'sessions',
    icon: '🏃',
    condition: { type: 'duration', counterKey: 'longest_session_ms', threshold: 4 * 60 * 60 * 1000 },
  },
  {
    id: 'night_owl',
    name: 'Night Owl',
    description: 'Use Major Tom after midnight',
    category: 'sessions',
    icon: '🦉',
    condition: { type: 'event', eventKey: 'used_after_midnight' },
  },
  {
    id: 'early_bird',
    name: 'Early Bird',
    description: 'Use Major Tom before 6am',
    category: 'sessions',
    icon: '🐦',
    condition: { type: 'event', eventKey: 'used_before_6am' },
  },

  // ── Approvals ──────────────────────────────────────────────
  {
    id: 'rubber_stamp',
    name: 'Rubber Stamp',
    description: 'Approve your first tool request',
    category: 'approvals',
    icon: '✅',
    condition: { type: 'counter', counterKey: 'approvals_granted', threshold: 1 },
  },
  {
    id: 'big_approver',
    name: 'Big Approver',
    description: 'Approve 100 tool requests',
    category: 'approvals',
    icon: '📋',
    condition: { type: 'counter', counterKey: 'approvals_granted', threshold: 100 },
  },
  {
    id: 'gatekeeper',
    name: 'Gatekeeper',
    description: 'Approve 500 tool requests',
    category: 'approvals',
    icon: '🏰',
    condition: { type: 'counter', counterKey: 'approvals_granted', threshold: 500 },
  },
  {
    id: 'speed_demon',
    name: 'Speed Demon',
    description: 'Approve a tool request within 2 seconds',
    category: 'approvals',
    icon: '⚡',
    condition: { type: 'event', eventKey: 'fast_approval' },
  },
  {
    id: 'trust_fall',
    name: 'Trust Fall',
    description: 'Enable God mode for the first time',
    category: 'approvals',
    icon: '🙏',
    condition: { type: 'event', eventKey: 'god_mode_enabled' },
  },
  {
    id: 'denied',
    name: 'Denied!',
    description: 'Deny a tool request for the first time',
    category: 'approvals',
    icon: '🚫',
    condition: { type: 'counter', counterKey: 'approvals_denied', threshold: 1 },
  },
  {
    id: 'wrist_controller',
    name: 'Wrist Controller',
    description: 'Approve a tool request from Apple Watch',
    category: 'approvals',
    icon: '⌚',
    condition: { type: 'event', eventKey: 'approval_from_watch' },
  },

  // ── Cost ───────────────────────────────────────────────────
  {
    id: 'penny_pincher',
    name: 'Penny Pincher',
    description: 'Complete a session for under $0.01',
    category: 'cost',
    icon: '🪙',
    condition: { type: 'event', eventKey: 'cheap_session' },
  },
  {
    id: 'ten_spot',
    name: 'Ten Spot',
    description: 'Spend $10 total across all sessions',
    category: 'cost',
    icon: '💵',
    condition: { type: 'counter', counterKey: 'total_cost_cents', threshold: 1000 },
  },
  {
    id: 'benjamin',
    name: 'Benjamin',
    description: 'Spend $100 total across all sessions',
    category: 'cost',
    icon: '💰',
    condition: { type: 'counter', counterKey: 'total_cost_cents', threshold: 10000 },
  },
  {
    id: 'high_roller',
    name: 'High Roller',
    description: 'Spend $1,000 total across all sessions',
    category: 'cost',
    icon: '🎰',
    condition: { type: 'counter', counterKey: 'total_cost_cents', threshold: 100000 },
  },

  // ── Agents ─────────────────────────────────────────────────
  {
    id: 'agent_smith',
    name: 'Agent Smith',
    description: 'Spawn your first subagent',
    category: 'agents',
    icon: '🕴️',
    condition: { type: 'counter', counterKey: 'agents_spawned', threshold: 1 },
  },
  {
    id: 'army_builder',
    name: 'Army Builder',
    description: 'Spawn 50 subagents total',
    category: 'agents',
    icon: '🪖',
    condition: { type: 'counter', counterKey: 'agents_spawned', threshold: 50 },
  },
  {
    id: 'full_house',
    name: 'Full House',
    description: 'Have all 9 agent types active simultaneously',
    category: 'agents',
    icon: '🃏',
    condition: { type: 'event', eventKey: 'all_agent_types_active' },
  },

  // ── Tools ──────────────────────────────────────────────────
  {
    id: 'shell_commander',
    name: 'Shell Commander',
    description: 'Use the Bash tool 100 times',
    category: 'tools',
    icon: '💻',
    condition: { type: 'counter', counterKey: 'tool_bash_count', threshold: 100 },
  },
  {
    id: 'code_surgeon',
    name: 'Code Surgeon',
    description: 'Use the Edit tool 50 times',
    category: 'tools',
    icon: '🔪',
    condition: { type: 'counter', counterKey: 'tool_edit_count', threshold: 50 },
  },
  {
    id: 'bookworm',
    name: 'Bookworm',
    description: 'Use the Read tool 200 times',
    category: 'tools',
    icon: '📖',
    condition: { type: 'counter', counterKey: 'tool_read_count', threshold: 200 },
  },
  {
    id: 'file_writer',
    name: 'File Writer',
    description: 'Use the Write tool 25 times',
    category: 'tools',
    icon: '📝',
    condition: { type: 'counter', counterKey: 'tool_write_count', threshold: 25 },
  },
  {
    id: 'detective',
    name: 'Detective',
    description: 'Use the Grep tool 50 times',
    category: 'tools',
    icon: '🔍',
    condition: { type: 'counter', counterKey: 'tool_grep_count', threshold: 50 },
  },

  // ── Fleet ──────────────────────────────────────────────────
  {
    id: 'fleet_commander',
    name: 'Fleet Commander',
    description: 'Start fleet mode with multiple workers',
    category: 'fleet',
    icon: '🚢',
    condition: { type: 'event', eventKey: 'fleet_mode_started' },
  },
  {
    id: 'crash_recovery',
    name: 'Crash Recovery',
    description: 'Survive a worker crash and keep going',
    category: 'fleet',
    icon: '🔥',
    condition: { type: 'event', eventKey: 'worker_crash_survived' },
  },
  {
    id: 'widget_watcher',
    name: 'Widget Watcher',
    description: 'View data via a home screen widget',
    category: 'fleet',
    icon: '📱',
    condition: { type: 'event', eventKey: 'widget_viewed' },
  },

  // ── Meta ───────────────────────────────────────────────────
  {
    id: 'achievement_hunter',
    name: 'Achievement Hunter',
    description: 'Unlock 10 achievements',
    category: 'meta',
    icon: '🏆',
    condition: { type: 'counter', counterKey: 'achievements_unlocked', threshold: 10 },
  },
  {
    id: 'completionist',
    name: 'Completionist',
    description: 'Unlock every achievement (except this one)',
    category: 'meta',
    icon: '👑',
    condition: { type: 'counter', counterKey: 'achievements_unlocked', threshold: 29 },
    secret: true,
  },
] as const;

/** Lookup map for fast access by id */
export const ACHIEVEMENT_MAP = new Map<string, AchievementDefinition>(
  ACHIEVEMENT_DEFINITIONS.map((a) => [a.id, a]),
);

/** Total count of achievements (excluding completionist for its threshold) */
export const ACHIEVEMENT_COUNT = ACHIEVEMENT_DEFINITIONS.length;
