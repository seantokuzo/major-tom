/**
 * Event Buffer — bounded ring buffer of recent ServerMessage events per session.
 *
 * Each event gets a monotonically increasing sequence number. When a client
 * reconnects with a lastSeq, we replay all events with seq > lastSeq.
 *
 * The buffer is bounded: oldest events are evicted when the buffer is full.
 * This ensures bounded memory usage regardless of session length.
 */

import type { ServerMessage } from '../protocol/messages.js';
import { logger } from '../utils/logger.js';

// ── Types ────────────────────────────────────────────────────

export interface BufferedEvent {
  seq: number;
  timestamp: string;
  message: ServerMessage;
}

export interface EventBufferConfig {
  /** Max events to keep per session. Default: 500 */
  maxEvents: number;
  /** Max age of events in ms. Events older than this may be pruned. Default: 10 min */
  maxAgeMs: number;
}

const DEFAULT_CONFIG: EventBufferConfig = {
  maxEvents: 500,
  maxAgeMs: 10 * 60 * 1000,
};

// ── Per-session event buffer ─────────────────────────────────

class SessionEventBuffer {
  private events: BufferedEvent[] = [];
  private nextSeq = 1;
  private config: EventBufferConfig;

  constructor(config: EventBufferConfig) {
    this.config = config;
  }

  /** Push an event into the buffer, returns its sequence number */
  push(message: ServerMessage): number {
    const seq = this.nextSeq++;
    this.events.push({
      seq,
      timestamp: new Date().toISOString(),
      message,
    });

    // Evict oldest when over capacity
    if (this.events.length > this.config.maxEvents) {
      this.events.shift();
    }

    return seq;
  }

  /** Get all events with seq > afterSeq */
  getAfter(afterSeq: number): BufferedEvent[] {
    // Prune old events first
    this.pruneExpired();

    // Binary search-ish: events are in order, so find the first one > afterSeq
    const idx = this.events.findIndex((e) => e.seq > afterSeq);
    if (idx === -1) return [];
    return this.events.slice(idx);
  }

  /** Get the current (latest) sequence number */
  get currentSeq(): number {
    return this.nextSeq - 1;
  }

  /** Get count of buffered events */
  get size(): number {
    return this.events.length;
  }

  /** Prune events older than maxAgeMs */
  private pruneExpired(): void {
    const cutoff = Date.now() - this.config.maxAgeMs;
    let pruned = 0;

    while (this.events.length > 0) {
      const oldest = this.events[0];
      if (oldest && new Date(oldest.timestamp).getTime() < cutoff) {
        this.events.shift();
        pruned++;
      } else {
        break;
      }
    }

    if (pruned > 0) {
      logger.debug({ pruned }, 'Event buffer: pruned expired events');
    }
  }

  /** Clear all events */
  clear(): void {
    this.events = [];
  }
}

// ── Event Buffer Manager (manages per-session buffers) ───────

export class EventBufferManager {
  private buffers = new Map<string, SessionEventBuffer>();
  private config: EventBufferConfig;

  constructor(config: Partial<EventBufferConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  /** Record an event for a session. Returns the assigned sequence number. */
  record(sessionId: string, message: ServerMessage): number {
    let buffer = this.buffers.get(sessionId);
    if (!buffer) {
      buffer = new SessionEventBuffer(this.config);
      this.buffers.set(sessionId, buffer);
    }
    return buffer.push(message);
  }

  /** Get all events for a session after a given sequence number */
  getEventsAfter(sessionId: string, afterSeq: number): BufferedEvent[] {
    const buffer = this.buffers.get(sessionId);
    if (!buffer) return [];
    return buffer.getAfter(afterSeq);
  }

  /** Get the current sequence number for a session */
  getCurrentSeq(sessionId: string): number {
    const buffer = this.buffers.get(sessionId);
    return buffer?.currentSeq ?? 0;
  }

  /** Remove the buffer for a session (on session close/destroy) */
  removeSession(sessionId: string): void {
    const buffer = this.buffers.get(sessionId);
    if (buffer) {
      buffer.clear();
      this.buffers.delete(sessionId);
    }
  }

  /** Get buffer stats for debugging/health */
  getStats(): Array<{ sessionId: string; eventCount: number; currentSeq: number }> {
    const stats: Array<{ sessionId: string; eventCount: number; currentSeq: number }> = [];
    for (const [sessionId, buffer] of this.buffers) {
      stats.push({
        sessionId,
        eventCount: buffer.size,
        currentSeq: buffer.currentSeq,
      });
    }
    return stats;
  }

  /** Clear all buffers */
  dispose(): void {
    for (const buffer of this.buffers.values()) {
      buffer.clear();
    }
    this.buffers.clear();
  }
}
