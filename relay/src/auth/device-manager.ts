import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { logger } from '../utils/logger.js';

export interface Device {
  id: string;
  name: string;
  token: string;
  createdAt: string;
  lastSeenAt: string;
}

const MAJOR_TOM_DIR = join(homedir(), '.major-tom');
const DEVICES_FILE = join(MAJOR_TOM_DIR, 'devices.json');

const PERSIST_DEBOUNCE_MS = 30_000; // 30 seconds

export class DeviceManager {
  private devices: Device[] = [];
  private persistTimer: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    this.load();
  }

  /**
   * Register a new device. Generates UUID id and 32-byte hex token.
   * Throws if persistence fails (caller should handle).
   */
  register(name: string): Device {
    const device: Device = {
      id: randomUUID(),
      name,
      token: randomBytes(32).toString('hex'),
      createdAt: new Date().toISOString(),
      lastSeenAt: new Date().toISOString(),
    };

    this.devices.push(device);

    try {
      this.persist();
    } catch (err) {
      // Roll back: remove from in-memory list so we don't return an unpersisted token
      this.devices.pop();
      throw err;
    }

    logger.info({ deviceId: device.id, name }, 'Device registered');
    return device;
  }

  /**
   * Validate a token. Returns the device if found, updates lastSeenAt in memory.
   * Debounces disk writes to avoid I/O on every auth check.
   */
  validateToken(token: string): Device | null {
    const device = this.devices.find((d) => d.token === token);
    if (!device) return null;

    device.lastSeenAt = new Date().toISOString();
    this.persistDebounced();
    return device;
  }

  /**
   * Revoke a device by id. Returns true if found and removed.
   */
  revoke(deviceId: string): boolean {
    const idx = this.devices.findIndex((d) => d.id === deviceId);
    if (idx === -1) return false;

    const [removed] = this.devices.splice(idx, 1);
    this.persist();

    logger.info({ deviceId, name: removed!.name }, 'Device revoked');
    return true;
  }

  /**
   * List all registered devices.
   */
  list(): Device[] {
    return [...this.devices];
  }

  /**
   * Flush any pending debounced writes. Call on shutdown.
   */
  flush(): void {
    if (this.persistTimer) {
      clearTimeout(this.persistTimer);
      this.persistTimer = null;
      try {
        this.persist();
      } catch {
        // Best-effort on shutdown
      }
    }
  }

  private load(): void {
    try {
      const raw = readFileSync(DEVICES_FILE, 'utf-8');
      const parsed = JSON.parse(raw) as unknown;
      if (Array.isArray(parsed)) {
        this.devices = parsed as Device[];
        logger.info({ count: this.devices.length }, 'Device registry loaded');
      }
    } catch {
      // File doesn't exist or is invalid — start fresh
      this.devices = [];
    }
  }

  /**
   * Persist device registry to disk. Throws on failure.
   */
  private persist(): void {
    mkdirSync(MAJOR_TOM_DIR, { recursive: true, mode: 0o700 });
    writeFileSync(DEVICES_FILE, JSON.stringify(this.devices, null, 2), { encoding: 'utf-8', mode: 0o600 });
  }

  /**
   * Debounced persist — collapses multiple calls within 30s into one write.
   * Used for lastSeenAt updates to avoid disk thrashing.
   */
  private persistDebounced(): void {
    if (this.persistTimer) return; // Already scheduled
    this.persistTimer = setTimeout(() => {
      this.persistTimer = null;
      try {
        this.persist();
      } catch (err) {
        logger.error({ err }, 'Failed to persist device registry (debounced)');
      }
    }, PERSIST_DEBOUNCE_MS);
  }
}

export const deviceManager = new DeviceManager();
