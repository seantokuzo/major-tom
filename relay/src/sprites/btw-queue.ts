/**
 * BtwQueue — Per-subagent FIFO queue for "/btw" sprite messages.
 *
 * Design (see docs/SPRITE-WIRING-RESEARCH-RELAY.md Gate 3):
 *   The SDK exposes no direct handle to a subagent's conversation, so /btw
 *   messages are injected as a new user turn on the orchestrator session at
 *   the next turn boundary (between stream() returning and the next send()).
 *   The message text is wrapped with constraint framing that tells Claude
 *   to give a short status response without changing its task.
 *
 *   Multiple /btw messages to the same subagent queue FIFO (spec M1). When
 *   the subagent's sprite is unlinked (complete/failed/dismissed) before
 *   delivery, all queued entries for that subagent drop with a "completed
 *   before delivery" reason (spec scenario #4).
 *
 *   Response correlation is imprecise per research: after injection we mark
 *   the entry `injected` and the worker's stream loop captures the next
 *   assistant text output as the response. Good enough given the constraint
 *   framing asks for an immediate 1-2 sentence answer.
 *
 * Events emitted:
 *   - 'injected'  → { sessionId, subagentId, messageId }          — sent to SDK
 *   - 'responded' → { sessionId, subagentId, messageId, text }     — response captured
 *   - 'dropped'   → { sessionId, subagentId, messageId, reason }  — dropped before delivery
 *
 * Ownership:
 *   One BtwQueue per process hosting SDK sessions (single-worker adapter
 *   or each fleet worker). The ws.ts layer routes `sprite.message` to the
 *   owning worker via IPC (fleet) or directly (single-worker).
 */

import { EventEmitter } from 'node:events';
import { logger } from '../utils/logger.js';

export type BtwEntryStatus = 'queued' | 'injected' | 'awaiting_response';

export interface BtwQueueEntry {
  sessionId: string;
  subagentId: string;
  spriteHandle: string;
  messageId: string;
  /** Raw user text as received from the client */
  userText: string;
  /** Pre-built constraint-framed text actually sent to the SDK */
  constrainedText: string;
  queuedAt: number;
  status: BtwEntryStatus;
  injectedAt?: number;
}

export interface BtwEnqueueInput {
  sessionId: string;
  subagentId: string;
  spriteHandle: string;
  messageId: string;
  userText: string;
  role: string;
  task: string;
}

/**
 * Build the constraint-framed user turn that gets injected into the
 * orchestrator's session. Wording is locked per Phase spec Q3.
 */
export function buildConstrainedText(opts: {
  role: string;
  task: string;
  userText: string;
}): string {
  const { role, task, userText } = opts;
  // Escape single quotes to keep the framing parseable to Claude without
  // breaking the surrounding structure.
  const safeRole = role.replace(/'/g, "\\'");
  const safeTask = task.replace(/'/g, "\\'");
  const safeUser = userText.replace(/'/g, "\\'");
  return (
    `The user sent a non-blocking observation via sprite tap to subagent ` +
    `"${safeRole}" (task: "${safeTask}"): '${safeUser}'. ` +
    `Respond in 1-2 sentences about the subagent's current progress. ` +
    `Do NOT change the subagent's task, plan, or approach. ` +
    `Continue exactly as planned.`
  );
}

export interface BtwQueueEventMap {
  injected: {
    sessionId: string;
    subagentId: string;
    spriteHandle: string;
    messageId: string;
  };
  responded: {
    sessionId: string;
    subagentId: string;
    spriteHandle: string;
    messageId: string;
    text: string;
  };
  dropped: {
    sessionId: string;
    subagentId: string;
    spriteHandle: string;
    messageId: string;
    reason: string;
  };
}

type Listener<T> = (payload: T) => void;

export class BtwQueue extends EventEmitter {
  /** subagentId → FIFO queue of pending entries */
  private bySubagent = new Map<string, BtwQueueEntry[]>();

  constructor() {
    super();
    this.setMaxListeners(50);
  }

  /**
   * Enqueue a /btw message for later injection at the next turn boundary.
   * Returns the queued entry. Does NOT emit — injection is what fires
   * `injected`.
   */
  enqueue(input: BtwEnqueueInput): BtwQueueEntry {
    const entry: BtwQueueEntry = {
      sessionId: input.sessionId,
      subagentId: input.subagentId,
      spriteHandle: input.spriteHandle,
      messageId: input.messageId,
      userText: input.userText,
      constrainedText: buildConstrainedText({
        role: input.role,
        task: input.task,
        userText: input.userText,
      }),
      queuedAt: Date.now(),
      status: 'queued',
    };
    const list = this.bySubagent.get(input.subagentId) ?? [];
    list.push(entry);
    this.bySubagent.set(input.subagentId, list);
    logger.info(
      {
        sessionId: entry.sessionId,
        subagentId: entry.subagentId,
        spriteHandle: entry.spriteHandle,
        messageId: entry.messageId,
        queueDepth: list.length,
      },
      'BtwQueue: enqueued /btw message',
    );
    return entry;
  }

  /**
   * Return queued entries owned by `sessionId` (across all subagents) that
   * haven't been injected yet. Caller (the consumeStream loop at turn
   * boundary) iterates and calls `markInjected` as it sends each.
   */
  peekQueuedForSession(sessionId: string): BtwQueueEntry[] {
    const out: BtwQueueEntry[] = [];
    for (const list of this.bySubagent.values()) {
      for (const entry of list) {
        if (entry.status === 'queued' && entry.sessionId === sessionId) {
          out.push(entry);
        }
      }
    }
    // FIFO across all subagents in this session
    out.sort((a, b) => a.queuedAt - b.queuedAt);
    return out;
  }

  /**
   * Take the oldest queued entry for a specific subagent. Marks it
   * `injected`, emits 'injected'. The consumeStream loop uses this to
   * drain messages one at a time at the turn boundary.
   */
  takeNextForSubagent(subagentId: string): BtwQueueEntry | undefined {
    const list = this.bySubagent.get(subagentId);
    if (!list || list.length === 0) return undefined;
    const entry = list.find(e => e.status === 'queued');
    if (!entry) return undefined;
    entry.status = 'injected';
    entry.injectedAt = Date.now();
    logger.info(
      {
        sessionId: entry.sessionId,
        subagentId: entry.subagentId,
        messageId: entry.messageId,
      },
      'BtwQueue: marked injected',
    );
    this.emit('injected', {
      sessionId: entry.sessionId,
      subagentId: entry.subagentId,
      spriteHandle: entry.spriteHandle,
      messageId: entry.messageId,
    } satisfies BtwQueueEventMap['injected']);
    return entry;
  }

  /**
   * Transition an injected entry to `awaiting_response`. Called by the
   * adapter right after `sdkSession.send()` resolves so the stream loop
   * starts looking for the reply text.
   */
  markAwaitingResponse(messageId: string): BtwQueueEntry | undefined {
    for (const list of this.bySubagent.values()) {
      for (const entry of list) {
        if (entry.messageId === messageId) {
          entry.status = 'awaiting_response';
          return entry;
        }
      }
    }
    return undefined;
  }

  /**
   * Find the earliest entry that's currently awaiting a response for
   * the given session. Used by the adapter's stream handler to correlate
   * the next assistant text with the injected /btw.
   */
  findAwaitingForSession(sessionId: string): BtwQueueEntry | undefined {
    let candidate: BtwQueueEntry | undefined;
    for (const list of this.bySubagent.values()) {
      for (const entry of list) {
        if (
          entry.status === 'awaiting_response' &&
          entry.sessionId === sessionId
        ) {
          if (!candidate || entry.injectedAt! < candidate.injectedAt!) {
            candidate = entry;
          }
        }
      }
    }
    return candidate;
  }

  /**
   * Mark a message as responded. Removes it from the queue and emits
   * 'responded' so the ws layer can fan out `sprite.response` to clients.
   */
  markResponded(messageId: string, text: string): BtwQueueEntry | undefined {
    for (const [subagentId, list] of this.bySubagent) {
      const idx = list.findIndex(e => e.messageId === messageId);
      if (idx >= 0) {
        const entry = list[idx]!;
        list.splice(idx, 1);
        if (list.length === 0) this.bySubagent.delete(subagentId);
        logger.info(
          {
            sessionId: entry.sessionId,
            subagentId: entry.subagentId,
            messageId,
            textLength: text.length,
          },
          'BtwQueue: marked responded',
        );
        this.emit('responded', {
          sessionId: entry.sessionId,
          subagentId: entry.subagentId,
          spriteHandle: entry.spriteHandle,
          messageId: entry.messageId,
          text,
        } satisfies BtwQueueEventMap['responded']);
        return entry;
      }
    }
    return undefined;
  }

  /**
   * Drop all queued+injected entries for a subagent (e.g. subagent
   * completed before delivery). Emits 'dropped' for each with the same
   * reason. Returns the count dropped.
   */
  dropForSubagent(subagentId: string, reason: string): number {
    const list = this.bySubagent.get(subagentId);
    if (!list || list.length === 0) return 0;
    this.bySubagent.delete(subagentId);
    for (const entry of list) {
      logger.info(
        {
          sessionId: entry.sessionId,
          subagentId,
          messageId: entry.messageId,
          reason,
        },
        'BtwQueue: dropped (subagent-level)',
      );
      this.emit('dropped', {
        sessionId: entry.sessionId,
        subagentId,
        spriteHandle: entry.spriteHandle,
        messageId: entry.messageId,
        reason,
      } satisfies BtwQueueEventMap['dropped']);
    }
    return list.length;
  }

  /**
   * Drop all queued+injected entries for a session (e.g. session.end).
   * Used by the ws.ts session cleanup path to shed state.
   */
  dropForSession(sessionId: string, reason: string): number {
    let total = 0;
    for (const [subagentId, list] of [...this.bySubagent]) {
      const remain: BtwQueueEntry[] = [];
      for (const entry of list) {
        if (entry.sessionId === sessionId) {
          total++;
          logger.info(
            {
              sessionId,
              subagentId,
              messageId: entry.messageId,
              reason,
            },
            'BtwQueue: dropped (session-level)',
          );
          this.emit('dropped', {
            sessionId: entry.sessionId,
            subagentId,
            spriteHandle: entry.spriteHandle,
            messageId: entry.messageId,
            reason,
          } satisfies BtwQueueEventMap['dropped']);
        } else {
          remain.push(entry);
        }
      }
      if (remain.length === 0) this.bySubagent.delete(subagentId);
      else this.bySubagent.set(subagentId, remain);
    }
    return total;
  }

  /** Queue depth for a specific subagent (0 if unknown). */
  sizeFor(subagentId: string): number {
    return this.bySubagent.get(subagentId)?.length ?? 0;
  }

  /** Total queue depth across all subagents. */
  get size(): number {
    let n = 0;
    for (const list of this.bySubagent.values()) n += list.length;
    return n;
  }

  /** Typed event overloads for better DX at callsites. */
  override on<K extends keyof BtwQueueEventMap>(
    event: K,
    listener: Listener<BtwQueueEventMap[K]>,
  ): this;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  override on(event: string, listener: (...args: any[]) => void): this {
    return super.on(event, listener);
  }

  override emit<K extends keyof BtwQueueEventMap>(
    event: K,
    payload: BtwQueueEventMap[K],
  ): boolean;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  override emit(event: string, ...args: any[]): boolean {
    return super.emit(event, ...args);
  }
}
