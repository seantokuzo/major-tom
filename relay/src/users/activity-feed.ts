import { randomUUID } from 'node:crypto';

export interface ActivityEntry {
  id: string;
  userId: string;
  userName: string;
  action: string;          // "approved Bash in project-x", "started session"
  sessionId?: string;
  timestamp: string;       // ISO 8601
}

export class ActivityFeed {
  private entries: ActivityEntry[] = [];
  private maxEntries = 200;

  record(userId: string, userName: string, action: string, sessionId?: string): ActivityEntry {
    const entry: ActivityEntry = {
      id: randomUUID(),
      userId,
      userName,
      action,
      sessionId,
      timestamp: new Date().toISOString(),
    };
    this.entries.push(entry);
    if (this.entries.length > this.maxEntries) {
      this.entries.shift();
    }
    return entry;
  }

  getRecent(limit: number = 50): ActivityEntry[] {
    return this.entries.slice(-limit);
  }

  clear(): void {
    this.entries = [];
  }
}
