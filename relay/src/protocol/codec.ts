import type { ClientMessage, ServerMessage } from './messages.js';
import { logger } from '../utils/logger.js';

export class CodecError extends Error {
  constructor(message: string, public readonly raw: string) {
    super(message);
    this.name = 'CodecError';
  }
}

export function decodeClientMessage(raw: string): ClientMessage {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new CodecError('Invalid JSON', raw);
  }

  if (typeof parsed !== 'object' || parsed === null || !('type' in parsed)) {
    throw new CodecError('Message missing "type" field', raw);
  }

  // Runtime validation could be added here with zod/etc if needed
  return parsed as ClientMessage;
}

export function encodeServerMessage(message: ServerMessage): string {
  return JSON.stringify(message);
}

export function safeDecode(raw: string): ClientMessage | null {
  try {
    return decodeClientMessage(raw);
  } catch (err) {
    logger.warn({ err, raw }, 'Failed to decode client message');
    return null;
  }
}
