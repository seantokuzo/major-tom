// Relay store — reactive state for the WebSocket connection, chat, and approvals
// Uses Svelte 5 runes ($state, $derived)

import { RelaySocket, type ConnectionState } from '../protocol/websocket';
import type {
  ApprovalDecision,
  ApprovalRequestMessage,
  ServerMessage,
} from '../protocol/messages';

// ── Chat message model ──────────────────────────────────────

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant' | 'tool' | 'system';
  content: string;
  timestamp: Date;
}

// ── Approval request model ──────────────────────────────────

export interface ApprovalRequest {
  id: string;
  tool: string;
  description: string;
  details?: Record<string, unknown>;
  receivedAt: Date;
}

// ── Relay store ─────────────────────────────────────────────

let nextId = 0;
function uid(): string {
  return `msg-${++nextId}-${Date.now()}`;
}

class RelayStore {
  // Connection
  connectionState = $state<ConnectionState>('disconnected');
  serverAddress = $state('localhost:9090');
  sessionId = $state<string | null>(null);

  // Chat
  messages = $state<ChatMessage[]>([]);
  inputText = $state('');

  // Approvals
  pendingApprovals = $state<ApprovalRequest[]>([]);

  // Derived
  isConnected = $derived(this.connectionState === 'connected');
  hasSession = $derived(this.sessionId !== null);

  // Internal
  private socket = new RelaySocket();

  constructor() {
    this.socket.onStateChange = (state) => {
      this.connectionState = state;
    };

    this.socket.onMessage = (message) => {
      this.handleMessage(message);
    };
  }

  // ── Actions ─────────────────────────────────────────────

  connect(): void {
    this.socket.connect(this.serverAddress);
  }

  disconnect(): void {
    this.socket.disconnect();
    this.sessionId = null;
  }

  startSession(): void {
    this.socket.send({ type: 'session.start', adapter: 'cli' });
  }

  sendPrompt(): void {
    const text = this.inputText.trim();
    if (!text || !this.sessionId) return;

    this.messages.push({
      id: uid(),
      role: 'user',
      content: text,
      timestamp: new Date(),
    });
    this.inputText = '';

    this.socket.send({
      type: 'prompt',
      sessionId: this.sessionId,
      text,
    });
  }

  sendApproval(requestId: string, decision: ApprovalDecision): void {
    this.socket.send({ type: 'approval', requestId, decision });
    this.pendingApprovals = this.pendingApprovals.filter((a) => a.id !== requestId);
  }

  cancelOperation(): void {
    if (!this.sessionId) return;
    this.socket.send({ type: 'cancel', sessionId: this.sessionId });
  }

  // ── Message routing ─────────────────────────────────────

  private handleMessage(message: ServerMessage): void {
    switch (message.type) {
      case 'output':
        this.appendOutput(message.chunk);
        break;

      case 'approval.request':
        this.addApproval(message);
        break;

      case 'session.info':
        this.sessionId = message.sessionId;
        break;

      case 'tool.start':
        this.messages.push({
          id: uid(),
          role: 'tool',
          content: `Using ${message.tool}...`,
          timestamp: new Date(),
        });
        break;

      case 'tool.complete':
        this.messages.push({
          id: uid(),
          role: 'tool',
          content: `${message.tool} ${message.success ? 'completed' : 'failed'}`,
          timestamp: new Date(),
        });
        break;

      case 'error':
        this.messages.push({
          id: uid(),
          role: 'system',
          content: `Error: ${message.message}`,
          timestamp: new Date(),
        });
        break;

      case 'notification':
        this.messages.push({
          id: uid(),
          role: 'system',
          content: message.title ? `${message.title}: ${message.message}` : message.message,
          timestamp: new Date(),
        });
        break;

      case 'connection.status':
        // Handled implicitly by socket state
        break;
    }
  }

  private appendOutput(chunk: string): void {
    const last = this.messages[this.messages.length - 1];
    if (last?.role === 'assistant') {
      // Mutate in place — Svelte 5 $state tracks this
      last.content += chunk;
    } else {
      this.messages.push({
        id: uid(),
        role: 'assistant',
        content: chunk,
        timestamp: new Date(),
      });
    }
  }

  private addApproval(event: ApprovalRequestMessage): void {
    this.pendingApprovals.push({
      id: event.requestId,
      tool: event.tool,
      description: event.description,
      details: event.details,
      receivedAt: new Date(),
    });
  }
}

// Singleton instance
export const relay = new RelayStore();
