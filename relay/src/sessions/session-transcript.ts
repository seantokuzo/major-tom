// Session transcript — in-memory circular buffer of conversation entries

export interface TranscriptEntry {
  type: 'user' | 'assistant' | 'tool' | 'system' | 'result';
  content: string;
  timestamp: string;
  meta?: Record<string, unknown>;
}

const MAX_ENTRIES = 500;
const MAX_CONTENT_LENGTH = 5000;

function truncateContent(content: string): string {
  if (content.length <= MAX_CONTENT_LENGTH) return content;
  return content.slice(0, MAX_CONTENT_LENGTH) + '...[truncated]';
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
