import { randomUUID } from 'node:crypto';

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

export class Session {
  readonly id: string;
  readonly adapter: AdapterType;
  readonly workingDir: string;
  readonly startedAt: string;
  status: SessionStatus = 'active';
  tokenUsage?: { used: number; remaining: number };

  constructor(adapter: AdapterType, workingDir: string) {
    this.id = randomUUID();
    this.adapter = adapter;
    this.workingDir = workingDir;
    this.startedAt = new Date().toISOString();
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

  close(): void {
    this.status = 'closed';
  }
}
