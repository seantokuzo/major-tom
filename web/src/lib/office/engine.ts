// Office engine — game loop, animation, and position interpolation
// Manages the rendering pipeline and per-agent animation state machines.

import type { CharacterType, Point } from './types';

// ── Animation Types ──────────────────────────────────────────

export type AnimationType = 'none' | 'idle-bob' | 'work-shake' | 'celebrate' | 'shiver' | 'fade-out';

interface AnimationState {
  type: AnimationType;
  startTime: number;
  /** Number of cycles completed (for celebrate) */
  cycles: number;
}

interface MoveState {
  from: Point;
  to: Point;
  startTime: number;
  duration: number; // ms
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
}

// ── Easing ───────────────────────────────────────────────────

function easeInOut(t: number): number {
  return t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2;
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
    this.lastTime = now;

    // Update all agents
    for (const agent of this.agents.values()) {
      this.updateMove(agent, now);
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
    });
  }

  removeAgent(id: string): void {
    this.agents.delete(id);
  }

  moveAgent(id: string, to: Point, durationMs: number): void {
    const agent = this.agents.get(id);
    if (!agent) return;
    agent.move = {
      from: { ...agent.position },
      to: { ...to },
      startTime: performance.now(),
      duration: durationMs,
    };
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
  }

  setStatusColor(id: string, color: string): void {
    const agent = this.agents.get(id);
    if (agent) agent.statusColor = color;
  }

  updateName(id: string, name: string): void {
    const agent = this.agents.get(id);
    if (agent) agent.name = name;
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

  private updateMove(agent: EngineAgent, now: number): void {
    if (!agent.move) return;
    const { from, to, startTime, duration } = agent.move;
    const elapsed = now - startTime;
    const t = Math.min(elapsed / duration, 1);
    const eased = easeInOut(t);

    agent.position.x = from.x + (to.x - from.x) * eased;
    agent.position.y = from.y + (to.y - from.y) * eased;

    if (t >= 1) {
      agent.position.x = to.x;
      agent.position.y = to.y;
      agent.move = null;
    }
  }

  private updateAnimation(agent: EngineAgent, now: number): void {
    const elapsed = now - agent.animation.startTime;
    const ms = elapsed;

    switch (agent.animation.type) {
      case 'none':
        break;

      case 'idle-bob': {
        // ±3px vertical, 0.8s per direction (1.6s full cycle)
        const cycle = 1600;
        const phase = (ms % cycle) / cycle;
        agent.animOffset.y = Math.sin(phase * Math.PI * 2) * 3;
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
    }
  }
}
