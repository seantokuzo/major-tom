// Mood Engine — Per-agent mood state derived from session events
// Moods affect visuals (sprite tinting, speech, idle behavior preferences).

// ── Mood Types ──────────────────────────────────────────────

export type AgentMood = 'happy' | 'neutral' | 'focused' | 'bored' | 'frustrated' | 'excited';

/** Mood derivation inputs tracked per agent */
export interface MoodInputs {
  /** Timestamp of last tool/work event */
  lastActivityTime: number;
  /** Number of consecutive tool errors or denials */
  consecutiveErrors: number;
  /** Whether a task was just completed */
  justCompletedTask: boolean;
  /** Timestamp when justCompletedTask was set (for auto-decay) */
  completedAt: number;
  /** Whether agent has been continuously working */
  workStartTime: number | null;
  /** Total errors in last 5 turns */
  recentErrors: number;
}

/** Create default mood inputs for a new agent */
export function createMoodInputs(): MoodInputs {
  return {
    lastActivityTime: Date.now(),
    consecutiveErrors: 0,
    justCompletedTask: false,
    completedAt: 0,
    workStartTime: null,
    recentErrors: 0,
  };
}

// ── Mood Derivation ─────────────────────────────────────────

/** Derive mood from current inputs. Called on a timer, not every event. */
export function deriveMood(inputs: MoodInputs): AgentMood {
  const now = Date.now();
  const idleMs = now - inputs.lastActivityTime;

  // Excited: just completed a task (decays after 30s)
  if (inputs.justCompletedTask && now - inputs.completedAt < 30_000) {
    return 'excited';
  }

  // Frustrated: 2+ consecutive errors
  if (inputs.consecutiveErrors >= 2) {
    return 'frustrated';
  }

  // Bored: idle for >3 minutes
  if (idleMs > 180_000) {
    return 'bored';
  }

  // Focused: working continuously for >2 minutes
  if (inputs.workStartTime !== null && now - inputs.workStartTime > 120_000) {
    return 'focused';
  }

  // Happy: no recent errors (last 5 turns)
  if (inputs.recentErrors === 0 && idleMs < 180_000) {
    return 'happy';
  }

  return 'neutral';
}

// ── Mood Visual Config ──────────────────────────────────────

export interface MoodVisuals {
  /** Color overlay for sprite tinting */
  tintColor: string;
  /** Tint opacity (0-1) */
  tintOpacity: number;
  /** Whether to pulse the tint */
  pulse: boolean;
  /** Pulse speed (radians per second) */
  pulseSpeed: number;
}

export const MOOD_VISUALS: Record<AgentMood, MoodVisuals> = {
  happy: {
    tintColor: 'rgba(255, 220, 100, 0.12)',
    tintOpacity: 0.12,
    pulse: false,
    pulseSpeed: 0,
  },
  neutral: {
    tintColor: 'rgba(0, 0, 0, 0)',
    tintOpacity: 0,
    pulse: false,
    pulseSpeed: 0,
  },
  focused: {
    tintColor: 'rgba(80, 140, 255, 0.10)',
    tintOpacity: 0.10,
    pulse: false,
    pulseSpeed: 0,
  },
  bored: {
    tintColor: 'rgba(128, 128, 128, 0.15)',
    tintOpacity: 0.15,
    pulse: false,
    pulseSpeed: 0,
  },
  frustrated: {
    tintColor: 'rgba(255, 60, 60, 0.12)',
    tintOpacity: 0.12,
    pulse: true,
    pulseSpeed: 3,
  },
  excited: {
    tintColor: 'rgba(255, 200, 50, 0.15)',
    tintOpacity: 0.15,
    pulse: true,
    pulseSpeed: 5,
  },
};

// ── Mood Speech Pools ───────────────────────────────────────

function pick(pool: string[]): string {
  return pool[Math.floor(Math.random() * pool.length)];
}

const MOOD_SPEECH: Record<AgentMood, string[]> = {
  happy: [],  // happy agents use default speech
  neutral: [],
  focused: ['...'],  // rarely speaks
  bored: [
    'Anyone want coffee?',
    'Is it 5pm yet?',
    '*yawns*',
    'So bored...',
    '*stretches*',
    'Waiting for PR review...',
    '*stares into void*',
    'Maybe I should refactor something',
  ],
  frustrated: [
    'This test is killing me',
    "WHY won't this compile",
    'UGHHHH',
    'Who wrote this code',
    'I need a break',
    '...seriously?',
    'FML',
    'Stack Overflow please save me',
  ],
  excited: [
    "LET'S GOOO!",
    'Shipped it!',
    'PR approved!',
    'YESSS!',
    'We did it!',
    'Deploy time!',
    'Another one done!',
    'On a roll!',
  ],
};

/** Pick a mood-appropriate speech bubble (returns null if mood has no special speech) */
export function pickMoodSpeech(mood: AgentMood): string | null {
  const pool = MOOD_SPEECH[mood];
  if (!pool || pool.length === 0) return null;
  return pick(pool);
}

// ── Mood Engine Class ───────────────────────────────────────

export class MoodEngine {
  /** Per-agent mood state */
  private _moods = new Map<string, AgentMood>();
  /** Per-agent mood derivation inputs */
  private _inputs = new Map<string, MoodInputs>();
  /** Update timer */
  private _interval: ReturnType<typeof setInterval> | null = null;

  /** Get current mood for an agent */
  getMood(agentId: string): AgentMood {
    return this._moods.get(agentId) ?? 'neutral';
  }

  /** Get all agent moods */
  getAllMoods(): Map<string, AgentMood> {
    return this._moods;
  }

  /** Register a new agent */
  addAgent(agentId: string): void {
    this._inputs.set(agentId, createMoodInputs());
    this._moods.set(agentId, 'neutral');
  }

  /** Remove an agent */
  removeAgent(agentId: string): void {
    this._inputs.delete(agentId);
    this._moods.delete(agentId);
  }

  /** Record a work activity (tool call, code generation, etc.) */
  recordActivity(agentId: string): void {
    const inputs = this._inputs.get(agentId);
    if (!inputs) return;
    inputs.lastActivityTime = Date.now();
    if (inputs.workStartTime === null) {
      inputs.workStartTime = Date.now();
    }
    inputs.consecutiveErrors = 0;
  }

  /** Record a tool error or denial */
  recordError(agentId: string): void {
    const inputs = this._inputs.get(agentId);
    if (!inputs) return;
    inputs.consecutiveErrors++;
    inputs.recentErrors++;
    inputs.lastActivityTime = Date.now();
  }

  /** Record task completion */
  recordCompletion(agentId: string): void {
    const inputs = this._inputs.get(agentId);
    if (!inputs) return;
    inputs.justCompletedTask = true;
    inputs.completedAt = Date.now();
    inputs.consecutiveErrors = 0;
    inputs.recentErrors = 0;
    inputs.workStartTime = null;
  }

  /** Record agent going idle */
  recordIdle(agentId: string): void {
    const inputs = this._inputs.get(agentId);
    if (!inputs) return;
    inputs.workStartTime = null;
  }

  /** Start periodic mood updates (every 30 seconds) */
  start(): void {
    if (this._interval) return;
    this._interval = setInterval(() => this.updateAllMoods(), 30_000);
  }

  /** Stop periodic updates */
  stop(): void {
    if (this._interval) {
      clearInterval(this._interval);
      this._interval = null;
    }
  }

  /** Recalculate all agent moods */
  updateAllMoods(): void {
    for (const [agentId, inputs] of this._inputs) {
      // Decay justCompletedTask after 30s
      if (inputs.justCompletedTask && Date.now() - inputs.completedAt > 30_000) {
        inputs.justCompletedTask = false;
      }

      const newMood = deriveMood(inputs);
      this._moods.set(agentId, newMood);
    }
  }

  /** Reset all state */
  reset(): void {
    this._moods.clear();
    this._inputs.clear();
  }
}
