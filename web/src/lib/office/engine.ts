// Office engine — game loop, animation, and position interpolation
// Manages the rendering pipeline and per-agent animation state machines.

import type { CharacterType, Point } from './types';

// ── Animation Types ──────────────────────────────────────────

export type AnimationType = 'none' | 'idle' | 'work-shake' | 'frantic-work' | 'celebrate' | 'shiver' | 'fade-out' | 'fade-in';

export interface SpeechBubble {
  text: string;
  startTime: number;
  duration: number;
}

/** Direction the character sprite faces */
export type FacingDirection = 'down' | 'up' | 'left' | 'right';

interface AnimationState {
  type: AnimationType;
  startTime: number;
  /** Number of cycles completed (for celebrate) */
  cycles: number;
}

interface MoveState {
  waypoints: Point[];     // remaining waypoints to visit
  currentTarget: Point;   // current waypoint being moved toward
  speed: number;          // pixels per second
}

export interface EngineAgent {
  id: string;
  characterType: CharacterType;
  name: string;
  position: Point;
  alpha: number;
  rotation: number;
  animation: AnimationState;
  move: MoveState | null;
  /** Visual offset from animation (bob, shake, etc.) */
  animOffset: Point;
  statusColor: string;
  /** Current idle activity label (shown under name in canvas) */
  idleActivity: string | null;
  /** Which office view this agent is currently in */
  currentView: import('./types').OfficeView | null;
  /** Direction the sprite faces */
  facing: FacingDirection;
  /** Whether the agent is currently walking (auto-set by engine) */
  isMoving: boolean;
  /** Walking animation phase (0-1, cycles while moving) */
  walkPhase: number;
  /** ID of partner agent for paired activities (e.g. ping pong) */
  pairedWith: string | null;
  /** Active speech bubble (auto-expires) */
  speechBubble: SpeechBubble | null;
}

// ── Engine ───────────────────────────────────────────────────

export class OfficeEngine {
  agents = new Map<string, EngineAgent>();
  private animFrameId: number | null = null;
  private lastTime = 0;

  /** External render callback — called each frame with the engine ref */
  onRender: ((engine: OfficeEngine) => void) | null = null;

  start(): void {
    if (this.animFrameId !== null) return;
    this.lastTime = performance.now();
    this.tick(this.lastTime);
  }

  stop(): void {
    if (this.animFrameId !== null) {
      cancelAnimationFrame(this.animFrameId);
      this.animFrameId = null;
    }
  }

  private tick = (now: number): void => {
    this.animFrameId = requestAnimationFrame(this.tick);

    // ~30fps throttle
    if (now - this.lastTime < 30) return;
    const dt = (now - this.lastTime) / 1000; // seconds since last frame
    this.lastTime = now;

    // Update all agents
    for (const agent of this.agents.values()) {
      this.updateMove(agent, dt);
      this.updateAnimation(agent, now);
    }

    // Render callback
    this.onRender?.(this);
  };

  // ── Agent Management ─────────────────────────────────────

  addAgent(id: string, characterType: CharacterType, name: string, position: Point): void {
    if (this.agents.has(id)) return;
    this.agents.set(id, {
      id,
      characterType,
      name,
      position: { ...position },
      alpha: 1,
      rotation: 0,
      animation: { type: 'none', startTime: 0, cycles: 0 },
      move: null,
      animOffset: { x: 0, y: 0 },
      statusColor: 'rgb(153, 153, 153)',
      idleActivity: null,
      currentView: 'office',
      facing: 'down',
      isMoving: false,
      walkPhase: 0,
      pairedWith: null,
      speechBubble: null,
    });
  }

  removeAgent(id: string): void {
    this.agents.delete(id);
  }

  clear(): void {
    this.agents.clear();
  }

  /** Move agent along a series of waypoints at a given speed (px/s). */
  moveAgentAlongPath(id: string, waypoints: Point[], speed: number = 120): void {
    const agent = this.agents.get(id);
    if (!agent || waypoints.length === 0) return;
    const remaining = [...waypoints];
    const first = remaining.shift()!;
    agent.move = {
      waypoints: remaining,
      currentTarget: { ...first },
      speed,
    };
  }

  /** Backwards-compatible convenience: move to a single point over a duration. */
  moveAgent(id: string, to: Point, durationMs: number): void {
    const agent = this.agents.get(id);
    if (!agent) return;
    const dx = to.x - agent.position.x;
    const dy = to.y - agent.position.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    const speed = dist / (durationMs / 1000) || 120;
    this.moveAgentAlongPath(id, [to], speed);
  }

  setAnimation(id: string, type: AnimationType): void {
    const agent = this.agents.get(id);
    if (!agent) return;
    agent.animation = { type, startTime: performance.now(), cycles: 0 };
    if (type === 'none') {
      agent.animOffset = { x: 0, y: 0 };
      agent.rotation = 0;
    }
    if (type === 'fade-out') {
      agent.alpha = 1; // will fade over 0.5s
    }
    if (type === 'fade-in') {
      agent.alpha = 0; // will fade in over 0.3s
    }
  }

  setStatusColor(id: string, color: string): void {
    const agent = this.agents.get(id);
    if (agent) agent.statusColor = color;
  }

  updateName(id: string, name: string): void {
    const agent = this.agents.get(id);
    if (agent) agent.name = name;
  }

  setIdleActivity(id: string, activity: string | null): void {
    const agent = this.agents.get(id);
    if (agent) agent.idleActivity = activity;
  }

  setCurrentView(id: string, view: import('./types').OfficeView | null): void {
    const agent = this.agents.get(id);
    if (agent) agent.currentView = view;
  }

  setFacing(id: string, facing: FacingDirection): void {
    const agent = this.agents.get(id);
    if (agent) agent.facing = facing;
  }

  setPairedWith(id: string, partnerId: string | null): void {
    const agent = this.agents.get(id);
    if (agent) agent.pairedWith = partnerId;
  }

  setSpeechBubble(id: string, text: string, duration: number = 2500): void {
    const agent = this.agents.get(id);
    if (!agent) return;
    agent.speechBubble = { text, startTime: performance.now(), duration };
  }

  getAgentAtPoint(point: Point, hitSize: number = 20): EngineAgent | null {
    // Check agents in reverse order (top-most first)
    const entries = Array.from(this.agents.values()).reverse();
    for (const agent of entries) {
      const dx = point.x - agent.position.x;
      const dy = point.y - agent.position.y;
      if (Math.abs(dx) <= hitSize && Math.abs(dy) <= hitSize) {
        return agent;
      }
    }
    return null;
  }

  // ── Update Helpers ───────────────────────────────────────

  private updateMove(agent: EngineAgent, dt: number): void {
    if (!agent.move) {
      agent.isMoving = false;
      return;
    }

    agent.isMoving = true;

    const { currentTarget, speed } = agent.move;
    const dx = currentTarget.x - agent.position.x;
    const dy = currentTarget.y - agent.position.y;
    const dist = Math.sqrt(dx * dx + dy * dy);

    // Update facing based on movement direction
    if (dist > 1) {
      if (Math.abs(dx) > Math.abs(dy)) {
        agent.facing = dx > 0 ? 'right' : 'left';
      } else {
        agent.facing = dy > 0 ? 'down' : 'up';
      }
    }

    // Advance walk animation phase (~3 steps per second)
    agent.walkPhase = (agent.walkPhase + dt * 3) % 1;

    const step = speed * dt;

    // Calculate proposed next position
    let nextX: number;
    let nextY: number;

    if (step >= dist) {
      nextX = currentTarget.x;
      nextY = currentTarget.y;
    } else {
      const ratio = step / dist;
      nextX = agent.position.x + dx * ratio;
      nextY = agent.position.y + dy * ratio;
    }

    // Collision avoidance: check if any other agent in the same view is too close
    const COLLISION_DIST = 16;
    let blocked = false;
    for (const other of this.agents.values()) {
      if (other.id === agent.id) continue;
      if (other.currentView !== agent.currentView) continue;
      const cdx = nextX - other.position.x;
      const cdy = nextY - other.position.y;
      const cdist = Math.sqrt(cdx * cdx + cdy * cdy);
      if (cdist < COLLISION_DIST) {
        // Only block if the other agent is stationary or we're approaching them
        // (two moving agents can pass — avoids deadlocks)
        if (!other.isMoving) {
          blocked = true;
          // Nudge perpendicular to our movement direction
          const perpX = -dy / (dist || 1);
          const perpY = dx / (dist || 1);
          const nudge = 4;
          agent.position.x += perpX * nudge * dt * 10;
          agent.position.y += perpY * nudge * dt * 10;
          break;
        }
      }
    }

    if (blocked) return; // skip this frame's forward movement

    if (step >= dist) {
      // Reached current waypoint
      agent.position.x = currentTarget.x;
      agent.position.y = currentTarget.y;

      // Advance to next waypoint, or finish
      if (agent.move.waypoints.length > 0) {
        agent.move.currentTarget = agent.move.waypoints.shift()!;
      } else {
        agent.move = null;
        agent.isMoving = false;
        agent.walkPhase = 0;
      }
    } else {
      // Move toward current waypoint
      agent.position.x = nextX;
      agent.position.y = nextY;
    }
  }

  private updateAnimation(agent: EngineAgent, now: number): void {
    // Auto-expire speech bubbles
    if (agent.speechBubble) {
      if (now - agent.speechBubble.startTime > agent.speechBubble.duration) {
        agent.speechBubble = null;
      }
    }

    const elapsed = now - agent.animation.startTime;
    const ms = elapsed;

    switch (agent.animation.type) {
      case 'none':
        break;

      case 'idle': {
        // No offset — idle animations are rendered as pixel overlays
        // in renderCharacterAnimated() for natural per-character movement.
        agent.animOffset.x = 0;
        agent.animOffset.y = 0;
        break;
      }

      case 'work-shake': {
        // ±2px horizontal, 0.15s per direction, 0.5s pause
        // Total cycle: 0.3s shake + 0.5s pause = 0.8s
        const cycle = 800;
        const phase = ms % cycle;
        if (phase < 300) {
          // Shaking phase
          const shakePhase = (phase % 150) / 150;
          agent.animOffset.x = Math.sin(shakePhase * Math.PI * 2) * 2;
        } else {
          agent.animOffset.x = 0;
        }
        break;
      }

      case 'frantic-work': {
        // Same as work-shake but 2x speed, 1.5x amplitude, no pause — pure panic
        const cycle = 300;
        const phase = ms % cycle;
        const shakePhase = (phase % 75) / 75;
        agent.animOffset.x = Math.sin(shakePhase * Math.PI * 2) * 3;
        // Occasional tiny Y jitter for extra stress
        agent.animOffset.y = Math.sin(ms * 0.02) * 0.5;
        break;
      }

      case 'celebrate': {
        // 20px jump (0.2s up, 0.2s down) + 360° rotation (0.4s), 3 cycles
        const cycleDuration = 400;
        const totalDuration = cycleDuration * 3;
        if (ms > totalDuration) {
          agent.animOffset = { x: 0, y: 0 };
          agent.rotation = 0;
          agent.animation.type = 'none';
          break;
        }
        const cycleMs = ms % cycleDuration;
        const cycleT = cycleMs / cycleDuration;
        // Jump: parabola
        agent.animOffset.y = -20 * Math.sin(cycleT * Math.PI);
        // Spin
        agent.rotation = cycleT * Math.PI * 2;
        break;
      }

      case 'shiver': {
        // ±1.5px horizontal, 0.1s per shake, 1.2s pause
        const cycle = 1400; // 0.2s shake + 1.2s pause
        const phase = ms % cycle;
        if (phase < 200) {
          const shakePhase = (phase % 100) / 100;
          agent.animOffset.x = Math.sin(shakePhase * Math.PI * 2) * 1.5;
        } else {
          agent.animOffset.x = 0;
        }
        break;
      }

      case 'fade-out': {
        // 0.5s alpha fade
        const t = Math.min(ms / 500, 1);
        agent.alpha = 1 - t;
        if (t >= 1) {
          agent.animation.type = 'none';
        }
        break;
      }

      case 'fade-in': {
        // 0.3s alpha fade in
        const t = Math.min(ms / 300, 1);
        agent.alpha = t;
        if (t >= 1) {
          agent.animation.type = 'none';
        }
        break;
      }
    }
  }
}
