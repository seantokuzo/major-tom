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

export class DeviceManager {
  private devices: Device[] = [];

  constructor() {
    this.load();
  }

  /**
   * Register a new device. Generates UUID id and 32-byte hex token.
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
    this.persist();

    logger.info({ deviceId: device.id, name }, 'Device registered');
    return device;
  }

  /**
   * Validate a token. Returns the device if found, updates lastSeenAt.
   */
  validateToken(token: string): Device | null {
    const device = this.devices.find((d) => d.token === token);
    if (!device) return null;

    device.lastSeenAt = new Date().toISOString();
    this.persist();
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

  private persist(): void {
    try {
      mkdirSync(MAJOR_TOM_DIR, { recursive: true });
      writeFileSync(DEVICES_FILE, JSON.stringify(this.devices, null, 2), 'utf-8');
    } catch (err) {
      logger.error({ err }, 'Failed to persist device registry');
    }
  }
}

export const deviceManager = new DeviceManager();
