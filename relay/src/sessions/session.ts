import { randomUUID } from 'node:crypto';
import { basename } from 'node:path';

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
  workingDir: string;
  status: SessionStatus;
  startedAt: string;
  totalCost: number;
  inputTokens: number;
  outputTokens: number;
  turnCount: number;
  totalDuration: number;
}

export class Session {
  readonly id: string;
  readonly adapter: AdapterType;
  readonly workingDir: string;
  readonly startedAt: string;
  status: SessionStatus = 'active';
  tokenUsage?: { used: number; remaining: number };

  // Accumulated metadata
  totalCost = 0;
  inputTokens = 0;
  outputTokens = 0;
  turnCount = 0;
  totalDuration = 0;

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
      workingDir: basename(this.workingDir),
      status: this.status,
      startedAt: this.startedAt,
      totalCost: this.totalCost,
      inputTokens: this.inputTokens,
      outputTokens: this.outputTokens,
      turnCount: this.turnCount,
      totalDuration: this.totalDuration,
    };
  }

  close(): void {
    this.status = 'closed';
  }
}
