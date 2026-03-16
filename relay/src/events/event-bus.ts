import { EventEmitter } from 'node:events';
import type {
  OutputMessage,
  ApprovalRequestMessage,
  ToolStartMessage,
  ToolCompleteMessage,
  AgentSpawnMessage,
  AgentWorkingMessage,
  AgentIdleMessage,
  AgentCompleteMessage,
  AgentDismissedMessage,
  ServerMessage,
} from '../protocol/messages.js';

// ── Typed event map ─────────────────────────────────────────

export interface RelayEventMap {
  'output': OutputMessage;
  'approval.request': ApprovalRequestMessage;
  'tool.start': ToolStartMessage;
  'tool.complete': ToolCompleteMessage;
  'agent.spawn': AgentSpawnMessage;
  'agent.working': AgentWorkingMessage;
  'agent.idle': AgentIdleMessage;
  'agent.complete': AgentCompleteMessage;
  'agent.dismissed': AgentDismissedMessage;
  'server.message': ServerMessage;
}

type EventKey = keyof RelayEventMap;

// ── Typed EventBus ──────────────────────────────────────────

export class EventBus {
  private emitter = new EventEmitter();

  constructor() {
    this.emitter.setMaxListeners(50);
  }

  on<K extends EventKey>(event: K, handler: (payload: RelayEventMap[K]) => void): void {
    this.emitter.on(event, handler as (...args: unknown[]) => void);
  }

  off<K extends EventKey>(event: K, handler: (payload: RelayEventMap[K]) => void): void {
    this.emitter.off(event, handler as (...args: unknown[]) => void);
  }

  emit<K extends EventKey>(event: K, payload: RelayEventMap[K]): void {
    this.emitter.emit(event, payload);
    // Also emit on the catch-all channel for WebSocket broadcasting
    if (event !== 'server.message') {
      this.emitter.emit('server.message', payload);
    }
  }

  removeAllListeners(): void {
    this.emitter.removeAllListeners();
  }
}

export const eventBus = new EventBus();
