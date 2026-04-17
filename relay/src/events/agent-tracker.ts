import { logger } from '../utils/logger.js';
import { eventBus } from './event-bus.js';

// ── Agent state tracking for office visualization ───────────

export interface AgentState {
  sessionId: string;
  agentId: string;
  parentId?: string;
  role: string;
  task: string;
  status: 'spawned' | 'working' | 'idle' | 'complete' | 'dismissed';
  spawnedAt: string;
  updatedAt: string;
}

class AgentTracker {
  private agents = new Map<string, AgentState>();

  getAll(): AgentState[] {
    return [...this.agents.values()];
  }

  get(agentId: string): AgentState | undefined {
    return this.agents.get(agentId);
  }

  /** Get all agents for a specific session */
  getBySession(sessionId: string): AgentState[] {
    return [...this.agents.values()].filter(a => a.sessionId === sessionId);
  }

  spawn(agentId: string, role: string, task: string, sessionId: string, parentId?: string): void {
    const now = new Date().toISOString();
    const state: AgentState = {
      sessionId,
      agentId,
      parentId,
      role,
      task,
      status: 'spawned',
      spawnedAt: now,
      updatedAt: now,
    };
    this.agents.set(agentId, state);
    logger.info({ agentId, role, task, sessionId }, 'Agent spawned');

    eventBus.emit('agent.spawn', {
      type: 'agent.spawn',
      sessionId,
      agentId,
      parentId,
      task,
      role,
    });
  }

  working(agentId: string, task: string): void {
    const agent = this.agents.get(agentId);
    if (!agent) return;
    agent.status = 'working';
    agent.task = task;
    agent.updatedAt = new Date().toISOString();

    eventBus.emit('agent.working', { type: 'agent.working', sessionId: agent.sessionId, agentId, task });
  }

  idle(agentId: string): void {
    const agent = this.agents.get(agentId);
    if (!agent) return;
    agent.status = 'idle';
    agent.updatedAt = new Date().toISOString();

    eventBus.emit('agent.idle', { type: 'agent.idle', sessionId: agent.sessionId, agentId });
  }

  complete(agentId: string, result: string): void {
    const agent = this.agents.get(agentId);
    if (!agent) return;
    agent.status = 'complete';
    agent.updatedAt = new Date().toISOString();

    eventBus.emit('agent.complete', { type: 'agent.complete', sessionId: agent.sessionId, agentId, result });
  }

  dismiss(agentId: string): void {
    const agent = this.agents.get(agentId);
    if (!agent) return;
    agent.status = 'dismissed';
    agent.updatedAt = new Date().toISOString();
    this.agents.delete(agentId);

    eventBus.emit('agent.dismissed', { type: 'agent.dismissed', sessionId: agent.sessionId, agentId });
  }
}

export const agentTracker = new AgentTracker();
