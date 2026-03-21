import { randomUUID } from 'node:crypto';
import { basename } from 'node:path';
import { SessionTranscript } from './session-transcript.js';

export type AdapterType = 'cli' | 'vscode';
export type SessionStatus = 'active' | 'idle' | 'closed';

export interface SessionInfo {
  id: string;
  adapter: AdapterType;
  workingDir: string;
  status: SessionStatus;
  startedAt: string;
  tokenUsage?: { used: number; remaining: number };
}

export interface SessionMeta {
  id: string;
  adapter: AdapterType;
  workingDirName: string;
  status: SessionStatus;
  startedAt: string;
  totalCost: number;
  inputTokens: number;
  outputTokens: number;
  turnCount: number;
  totalDuration: number;
}

// ── Context file limits ─────────────────────────────────────

const MAX_FILE_SIZE = 50 * 1024;       // 50 KB per file
const MAX_TOTAL_CONTEXT = 200 * 1024;  // 200 KB total

export class Session {
  readonly id: string;
  readonly adapter: AdapterType;
  readonly workingDir: string;
  readonly startedAt: string;
  status: SessionStatus = 'active';
  tokenUsage?: { used: number; remaining: number };

  // Transcript
  readonly transcript = new SessionTranscript();

  // Accumulated metadata
  totalCost = 0;
  inputTokens = 0;
  outputTokens = 0;
  turnCount = 0;
  totalDuration = 0;

  /** path → file content */
  contextFiles: Map<string, string> = new Map();
  /** total bytes of all context files */
  contextSize: number = 0;

  constructor(adapter: AdapterType, workingDir: string) {
    this.id = randomUUID();
    this.adapter = adapter;
    this.workingDir = workingDir;
    this.startedAt = new Date().toISOString();
  }

  addResult(result: {
    costUsd: number;
    numTurns: number;
    durationMs: number;
    inputTokens?: number;
    outputTokens?: number;
  }): void {
    this.totalCost += result.costUsd;
    this.turnCount += result.numTurns;
    this.totalDuration += result.durationMs;
    if (typeof result.inputTokens === 'number' && Number.isFinite(result.inputTokens)) {
      this.inputTokens += result.inputTokens;
    }
    if (typeof result.outputTokens === 'number' && Number.isFinite(result.outputTokens)) {
      this.outputTokens += result.outputTokens;
    }
  }

  toInfo(): SessionInfo {
    return {
      id: this.id,
      adapter: this.adapter,
      workingDir: this.workingDir,
      status: this.status,
      startedAt: this.startedAt,
      tokenUsage: this.tokenUsage,
    };
  }

  toMeta(): SessionMeta {
    return {
      id: this.id,
      adapter: this.adapter,
      workingDirName: basename(this.workingDir),
      status: this.status,
      startedAt: this.startedAt,
      totalCost: this.totalCost,
      inputTokens: this.inputTokens,
      outputTokens: this.outputTokens,
      turnCount: this.turnCount,
      totalDuration: this.totalDuration,
    };
  }

  // ── Context file management ────────────────────────────────

  addContextFile(path: string, content: string): { ok: boolean; error?: string } {
    const size = Buffer.byteLength(content, 'utf-8');

    if (size > MAX_FILE_SIZE) {
      return { ok: false, error: `File too large: ${(size / 1024).toFixed(1)} KB exceeds ${MAX_FILE_SIZE / 1024} KB limit` };
    }

    // If replacing an existing file, subtract its old size first
    const existing = this.contextFiles.get(path);
    const existingSize = existing ? Buffer.byteLength(existing, 'utf-8') : 0;
    const newTotal = this.contextSize - existingSize + size;

    if (newTotal > MAX_TOTAL_CONTEXT) {
      return { ok: false, error: `Total context would be ${(newTotal / 1024).toFixed(1)} KB, exceeds ${MAX_TOTAL_CONTEXT / 1024} KB limit` };
    }

    this.contextFiles.set(path, content);
    this.contextSize = newTotal;
    return { ok: true };
  }

  removeContextFile(path: string): void {
    const content = this.contextFiles.get(path);
    if (content) {
      this.contextSize -= Buffer.byteLength(content, 'utf-8');
      this.contextFiles.delete(path);
    }
  }

  getContextText(): string {
    if (this.contextFiles.size === 0) return '';

    const parts: string[] = ['<attached-files>'];
    for (const [filePath, content] of this.contextFiles) {
      const escapedPath = filePath.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      parts.push(`<file path="${escapedPath}">`);
      parts.push(content);
      parts.push('</file>');
    }
    parts.push('</attached-files>\n\n');
    return parts.join('\n');
  }


  close(): void {
    this.status = 'closed';
  }
}
