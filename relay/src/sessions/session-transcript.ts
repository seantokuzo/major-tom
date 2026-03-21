// Session transcript — in-memory circular buffer of conversation entries

export interface TranscriptEntry {
  type: 'user' | 'assistant' | 'tool' | 'system' | 'result';
  content: string;
  timestamp: string;
  meta?: Record<string, unknown>;
}

const MAX_ENTRIES = 500;
const MAX_CONTENT_LENGTH = 5000;
const MAX_META_FIELD_LENGTH = 500;

function truncateContent(content: string): string {
  if (content.length <= MAX_CONTENT_LENGTH) return content;
  const suffix = '...[truncated]';
  return content.slice(0, MAX_CONTENT_LENGTH - suffix.length) + suffix;
}

/** Truncate a meta field value (input/output) to MAX_META_FIELD_LENGTH chars */
export function truncateMetaField(value: unknown): unknown {
  if (typeof value === 'string' && value.length > MAX_META_FIELD_LENGTH) {
    return value.slice(0, MAX_META_FIELD_LENGTH - 14) + '...[truncated]';
  }
  if (typeof value === 'object' && value !== null) {
    const serialized = JSON.stringify(value);
    if (serialized.length > MAX_META_FIELD_LENGTH) {
      return serialized.slice(0, MAX_META_FIELD_LENGTH - 14) + '...[truncated]';
    }
  }
  return value;
}

export class SessionTranscript {
  private entries: TranscriptEntry[] = [];

  append(entry: TranscriptEntry): void {
    const truncated: TranscriptEntry = {
      ...entry,
      content: truncateContent(entry.content),
    };
    this.entries.push(truncated);
    // FIFO eviction when over limit
    if (this.entries.length > MAX_ENTRIES) {
      this.entries.shift();
    }
  }

  getAll(): TranscriptEntry[] {
    return [...this.entries];
  }

  get length(): number {
    return this.entries.length;
  }
}
