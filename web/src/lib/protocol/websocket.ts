// WebSocket client with auto-reconnect

import type { ClientMessage, ServerMessage } from './messages';

export type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'reconnecting';

export type MessageHandler = (message: ServerMessage) => void;
export type StateHandler = (state: ConnectionState) => void;

const MAX_RECONNECT_ATTEMPTS = 10;
const MAX_RECONNECT_DELAY = 30_000;

export class RelaySocket {
  private ws: WebSocket | null = null;
  private url: string = '';
  private reconnectAttempt = 0;
  private intentionalClose = false;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;

  state: ConnectionState = 'disconnected';

  onMessage: MessageHandler | null = null;
  onStateChange: StateHandler | null = null;

  connect(host: string): void {
    this.intentionalClose = false;
    this.reconnectAttempt = 0;
    this.url = host.startsWith('ws://') || host.startsWith('wss://') ? host : `ws://${host}`;
    this.setState('connecting');
    this.establish();
  }

  disconnect(): void {
    this.intentionalClose = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.ws?.close(1000, 'User disconnect');
    this.ws = null;
    this.setState('disconnected');
  }

  send(message: ClientMessage): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  private establish(): void {
    try {
      this.ws = new WebSocket(this.url);
    } catch {
      this.handleDisconnect();
      return;
    }

    this.ws.onopen = () => {
      this.setState('connected');
      this.reconnectAttempt = 0;
    };

    this.ws.onmessage = (event) => {
      try {
        const message = JSON.parse(event.data as string) as ServerMessage;
        this.onMessage?.(message);
      } catch {
        console.warn('Failed to parse server message:', event.data);
      }
    };

    this.ws.onclose = () => {
      if (!this.intentionalClose) {
        this.handleDisconnect();
      }
    };

    this.ws.onerror = () => {
      // onclose will fire after this — reconnect handled there
    };
  }

  private handleDisconnect(): void {
    this.ws = null;

    if (this.intentionalClose) return;
    if (this.reconnectAttempt >= MAX_RECONNECT_ATTEMPTS) {
      this.setState('disconnected');
      return;
    }

    this.setState('reconnecting');
    this.reconnectAttempt++;
    const delay = Math.min(Math.pow(2, this.reconnectAttempt) * 1000, MAX_RECONNECT_DELAY);

    this.reconnectTimer = setTimeout(() => {
      if (!this.intentionalClose) {
        this.establish();
      }
    }, delay);
  }

  private setState(state: ConnectionState): void {
    this.state = state;
    this.onStateChange?.(state);
  }
}
