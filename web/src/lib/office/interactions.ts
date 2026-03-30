// Agent Interactions — Idle chat, event reactions, social grouping
// Extends the existing social system with mood-aware behaviors.

import type { AgentMood } from './mood-engine';

// ── Chat Topics ─────────────────────────────────────────────

function pick(pool: string[]): string {
  return pool[Math.floor(Math.random() * pool.length)];
}

const IDLE_CHAT_TOPICS: string[][] = [
  // Complaining about tests
  ['Tests are failing again', "It's always the tests", 'Who broke CI?', 'Flaky test energy'],
  // Architecture discussions
  ['We should use microservices', "Nah, monolith's fine", 'Have you tried GraphQL?', 'Just add more cache'],
  // Dog jokes
  ['My dog ate my PR', 'Good boy energy', '*woof*', 'Dogs > cats, fight me'],
  // General dev life
  ['Standup was long', 'JIRA is down again', 'Merge conflict time', 'Who owns this repo?'],
  // Food
  ['Who ordered pizza?', 'Lunch?', 'Coffee run?', 'Fridge is empty again'],
];

/** Pick a random chat exchange (returns [line1, line2]) */
export function pickIdleChatExchange(): [string, string] {
  const topic = IDLE_CHAT_TOPICS[Math.floor(Math.random() * IDLE_CHAT_TOPICS.length)];
  const i = Math.floor(Math.random() * topic.length);
  const j = (i + 1 + Math.floor(Math.random() * (topic.length - 1))) % topic.length;
  return [topic[i], topic[j]];
}

// ── Event Reactions ─────────────────────────────────────────

export type OfficeEvent = 'approval_granted' | 'error' | 'task_complete' | 'pr_created';

const EVENT_REACTIONS: Record<OfficeEvent, string[]> = {
  approval_granted: ['Nice!', '*thumbs up*', 'Approved!', 'LGTM'],
  error: ['Uh oh', 'Yikes', '*concerned look*', 'That sucks'],
  task_complete: ['GG!', 'Ship it!', 'Nice work!', '*claps*', 'Woohoo!'],
  pr_created: ['PR time!', 'Review me!', 'Fingers crossed', 'LGTM in advance'],
};

/** Pick a reaction to an office event */
export function pickEventReaction(event: OfficeEvent): string {
  return pick(EVENT_REACTIONS[event]);
}

// ── Mood-Based Activity Preferences ─────────────────────────

/** Areas that agents prefer based on mood */
export const MOOD_AREA_PREFERENCES: Record<AgentMood, string[]> = {
  happy: [],  // no preference — default behavior
  neutral: [],
  focused: [],  // stays at desk
  bored: ['breakRoom', 'kitchen', 'dogParkField'],  // seeks entertainment
  frustrated: ['kitchen'],  // goes for coffee
  excited: ['breakRoom', 'mainOffice'],  // celebrates with others
};

// ── Social Grouping ─────────────────────────────────────────

/** Configuration for social grouping behavior */
export const SOCIAL_CONFIG = {
  /** Distance within which agents are considered "nearby" */
  proximityDistance: 80,
  /** Chance per scan tick for two nearby idle agents to start chatting */
  chatChance: 0.06,
  /** Duration of a chat exchange (ms) */
  chatDuration: 5000,
  /** How often to scan for social interactions (ms) */
  scanInterval: 8000,
  /** Minimum idle time before an agent seeks social interaction (ms) */
  minIdleBeforeSocial: 10_000,
  /** Distance agents try to maintain when grouping in common areas */
  groupingDistance: 40,
} as const;

// ── Celebration Animations ──────────────────────────────────

/** Types of celebration that can be triggered */
export type CelebrationType = 'mini' | 'full';

/** Get celebration config based on event type */
export function getCelebrationConfig(event: OfficeEvent): {
  type: CelebrationType;
  duration: number;
  bubbleText: string;
} | null {
  switch (event) {
    case 'task_complete':
      return { type: 'full', duration: 2000, bubbleText: pick(['Ship it!', 'Done!', 'GG!']) };
    case 'pr_created':
      return { type: 'full', duration: 2500, bubbleText: pick(['PR is up!', 'Review time!', 'Shipped!']) };
    case 'approval_granted':
      return { type: 'mini', duration: 1000, bubbleText: pick(['*nods*', 'Nice', 'Approved']) };
    case 'error':
      return null;  // no celebration for errors
  }
}

// ── Interaction State ───────────────────────────────────────

/** Tracks active interactions to prevent overlaps */
export interface InteractionTracker {
  /** Set of agent IDs currently in an interaction */
  activeAgents: Set<string>;
  /** Timestamp of last interaction scan */
  lastScan: number;
}

export function createInteractionTracker(): InteractionTracker {
  return {
    activeAgents: new Set(),
    lastScan: 0,
  };
}
