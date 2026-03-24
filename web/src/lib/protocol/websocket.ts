// WebSocket client with auto-reconnect

import type { ClientMessage, ServerMessage } from './messages';

export type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'reconnecting';

export type MessageHandler = (message: ServerMessage) => void;
export type StateHandler = (state: ConnectionState) => void;
export type ReconnectHandler = (attempt: number, maxAttempts: number) => void;
export type MaxRetriesHandler = () => void;

const MAX_RECONNECT_ATTEMPTS = 20;
const MAX_RECONNECT_DELAY = 30_000;

export class RelaySocket {
  private ws: WebSocket | null = null;
  private url: string = '';
  private token: string | null = null;
  private intentionalClose = false;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;

  reconnectAttempt = 0;
  state: ConnectionState = 'disconnected';

  onMessage: MessageHandler | null = null;
  onStateChange: StateHandler | null = null;
  onReconnectAttempt: ReconnectHandler | null = null;
  onMaxRetriesExceeded: MaxRetriesHandler | null = null;

  connect(host: string, token?: string): void {
    // Clean up any existing connection first
    if (this.ws) {
      this.ws.onclose = null; // prevent reconnect from firing
      this.ws.close(1000, 'Reconnecting');
      this.ws = null;
    }
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    this.intentionalClose = false;
    this.reconnectAttempt = 0;
    this.token = token ?? null;
    const isSecure = typeof window !== 'undefined' && window.location.protocol === 'https:';
    const defaultScheme = isSecure ? 'wss://' : 'ws://';
    const rawUrl = host.startsWith('ws://') || host.startsWith('wss://') ? host : `${defaultScheme}${host}`;
    // Ensure /ws path for Fastify relay (avoid doubling if already present)
    const parsedUrl = new URL(rawUrl);
    if (!parsedUrl.pathname.endsWith('/ws')) {
      parsedUrl.pathname = parsedUrl.pathname.replace(/\/?$/, '/ws');
    }
    const baseUrl = parsedUrl.toString().replace(/\/$/, '');
    if (this.token) {
      const separator = baseUrl.includes('?') ? '&' : '?';
      this.url = `${baseUrl}${separator}token=${encodeURIComponent(this.token)}`;
    } else {
      this.url = baseUrl;
    }
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
      this.onMaxRetriesExceeded?.();
      return;
    }

    this.setState('reconnecting');
    this.reconnectAttempt++;
    this.onReconnectAttempt?.(this.reconnectAttempt, MAX_RECONNECT_ATTEMPTS);
    const delay = Math.min(Math.pow(2, this.reconnectAttempt - 1) * 1000, MAX_RECONNECT_DELAY);

    this.reconnectTimer = setTimeout(() => {
      if (!this.intentionalClose) {
        this.setState('connecting');
        this.establish();
      }
    }, delay);
  }

  private setState(state: ConnectionState): void {
    this.state = state;
    this.onStateChange?.(state);
  }
}
