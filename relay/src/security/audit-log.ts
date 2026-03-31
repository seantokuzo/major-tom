import { appendFile, readdir, readFile, unlink, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { logger } from '../utils/logger.js';

export interface AuditEntry {
  timestamp: string;      // ISO 8601
  userId: string;
  email: string;
  role: string;
  action: string;         // e.g., 'prompt', 'approval.allow', 'session.start'
  sessionId?: string;
  path?: string;
  details?: string;
}

const RETENTION_INTERVAL_MS = 24 * 60 * 60 * 1000; // Run cleanup once per day

export class AuditLog {
  private dir: string;
  private retentionDays: number;
  private retentionTimer: ReturnType<typeof setInterval> | null = null;

  constructor(retentionDays = 30) {
    this.dir = join(homedir(), '.major-tom', 'audit');
    this.retentionDays = retentionDays;
  }

  async init(): Promise<void> {
    await mkdir(this.dir, { recursive: true });
    await this.rotateOld();
    // Schedule periodic cleanup for long-running relay instances
    this.retentionTimer = setInterval(() => void this.rotateOld(), RETENTION_INTERVAL_MS);
  }

  /** Cancel scheduled cleanup */
  dispose(): void {
    if (this.retentionTimer) {
      clearInterval(this.retentionTimer);
      this.retentionTimer = null;
    }
  }

  /** Append an audit entry to today's log file */
  async record(entry: Omit<AuditEntry, 'timestamp'>): Promise<void> {
    const full: AuditEntry = { ...entry, timestamp: new Date().toISOString() };
    const filename = this.todayFilename();
    const filepath = join(this.dir, filename);
    try {
      await appendFile(filepath, JSON.stringify(full) + '\n');
    } catch (err) {
      logger.error({ err, entry: full }, 'Failed to write audit entry');
    }
  }

  /** Query audit entries with optional filters */
  async query(filters: {
    startTime?: string;  // ISO 8601
    endTime?: string;
    userId?: string;
    action?: string;
    limit?: number;
  } = {}): Promise<AuditEntry[]> {
    const { startTime, endTime, userId, action, limit = 200 } = filters;
    const results: AuditEntry[] = [];

    // Get relevant files by date range
    const files = await this.getRelevantFiles(startTime, endTime);

    // Read in reverse chronological order (newest first)
    for (const file of files.reverse()) {
      const filepath = join(this.dir, file);
      const entries = await this.readLogFile(filepath);

      for (const entry of entries.reverse()) {
        // Apply filters
        if (startTime && entry.timestamp < startTime) continue;
        if (endTime && entry.timestamp > endTime) continue;
        if (userId && entry.userId !== userId) continue;
        if (action && !entry.action.includes(action)) continue;

        results.push(entry);
        if (results.length >= limit) return results;
      }
    }

    return results;
  }

  /** Delete log files older than retention period */
  private async rotateOld(): Promise<void> {
    try {
      const files = await readdir(this.dir);
      const cutoff = new Date();
      cutoff.setDate(cutoff.getDate() - this.retentionDays);
      const cutoffStr = cutoff.toISOString().split('T')[0]; // YYYY-MM-DD

      for (const file of files) {
        if (!file.endsWith('.jsonl')) continue;
        const dateStr = file.replace('audit-', '').replace('.jsonl', '');
        if (dateStr < cutoffStr!) {
          await unlink(join(this.dir, file));
          logger.info({ file }, 'Rotated old audit log');
        }
      }
    } catch (err) {
      logger.error({ err }, 'Failed to rotate audit logs');
    }
  }

  private todayFilename(): string {
    const date = new Date().toISOString().split('T')[0];
    return `audit-${date}.jsonl`;
  }

  private async getRelevantFiles(startTime?: string, endTime?: string): Promise<string[]> {
    const files = await readdir(this.dir);
    return files
      .filter(f => f.startsWith('audit-') && f.endsWith('.jsonl'))
      .filter(f => {
        const dateStr = f.replace('audit-', '').replace('.jsonl', '');
        if (startTime && dateStr < startTime.split('T')[0]!) return false;
        if (endTime && dateStr > endTime.split('T')[0]!) return false;
        return true;
      })
      .sort();
  }

  private async readLogFile(filepath: string): Promise<AuditEntry[]> {
    const entries: AuditEntry[] = [];
    try {
      const content = await readFile(filepath, 'utf-8');
      for (const line of content.split('\n')) {
        if (!line.trim()) continue;
        try {
          entries.push(JSON.parse(line));
        } catch { /* skip malformed lines */ }
      }
    } catch { /* file doesn't exist or can't be read */ }
    return entries;
  }
}
