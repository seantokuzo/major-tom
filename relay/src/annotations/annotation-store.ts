import { randomUUID } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { logger } from '../utils/logger.js';

export interface Annotation {
  id: string;
  userId: string;
  userName: string;
  turnIndex?: number;     // Pin to specific turn
  text: string;
  mentions: string[];     // userIds
  createdAt: string;      // ISO 8601
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class AnnotationStore {
  private dir: string;
  private cache = new Map<string, Annotation[]>();
  private dirty = new Set<string>();
  private saveTimer: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    this.dir = join(homedir(), '.major-tom', 'annotations');
  }

  private validateSessionId(sessionId: string): void {
    if (!UUID_PATTERN.test(sessionId)) {
      throw new Error(`Invalid sessionId: must be a valid UUID`);
    }
  }

  async ensureDir(): Promise<void> {
    await mkdir(this.dir, { recursive: true });
  }

  async addAnnotation(sessionId: string, annotation: Omit<Annotation, 'id' | 'createdAt'>): Promise<Annotation> {
    this.validateSessionId(sessionId);
    const full: Annotation = {
      ...annotation,
      id: randomUUID(),
      createdAt: new Date().toISOString(),
    };

    let list = this.cache.get(sessionId);
    if (!list) {
      list = await this.load(sessionId);
    }
    list.push(full);
    this.cache.set(sessionId, list);
    this.dirty.add(sessionId);
    this.scheduleSave();
    return full;
  }

  async getAnnotations(sessionId: string): Promise<Annotation[]> {
    this.validateSessionId(sessionId);
    if (this.cache.has(sessionId)) {
      return this.cache.get(sessionId)!;
    }
    const list = await this.load(sessionId);
    this.cache.set(sessionId, list);
    return list;
  }

  private async load(sessionId: string): Promise<Annotation[]> {
    try {
      const filePath = join(this.dir, `${sessionId}.json`);
      const data = await readFile(filePath, 'utf-8');
      return JSON.parse(data) as Annotation[];
    } catch {
      return [];
    }
  }

  private scheduleSave(): void {
    if (this.saveTimer) return;
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      this.flush().catch(err => logger.error({ err }, 'Failed to flush annotations'));
    }, 2000);
  }

  async flush(): Promise<void> {
    await this.ensureDir();
    const snapshot = new Set(this.dirty);
    for (const sessionId of snapshot) {
      const list = this.cache.get(sessionId);
      if (!list) {
        this.dirty.delete(sessionId);
        continue;
      }
      try {
        const filePath = join(this.dir, `${sessionId}.json`);
        await writeFile(filePath, JSON.stringify(list, null, 2));
        this.dirty.delete(sessionId);
      } catch (err) {
        logger.error({ err, sessionId }, 'Failed to save annotations — will retry next flush');
      }
    }
  }

  dispose(): void {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer);
      this.saveTimer = null;
    }
  }
}
