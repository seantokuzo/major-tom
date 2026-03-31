/**
 * User Registry — persists users and invite codes to ~/.major-tom/users/.
 * Follows the same pattern as SessionPersistence for JSON file storage.
 */
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { randomBytes } from 'node:crypto';
import { logger } from '../utils/logger.js';
import type { User, UserRole, InviteCode } from './types.js';

const USERS_DIR = join(homedir(), '.major-tom', 'users');
const REGISTRY_FILE = join(USERS_DIR, '_registry.json');
const INVITES_FILE = join(USERS_DIR, '_invites.json');
const DEBOUNCE_MS = 2000;
const INVITE_EXPIRY_MS = 24 * 60 * 60 * 1000; // 24 hours
const INVITE_CODE_LENGTH = 8;

interface RegistryEntry {
  id: string;
  email: string;
  role: UserRole;
}

export class UserRegistry {
  private registry: RegistryEntry[] = [];
  private invites: InviteCode[] = [];
  private registryTimer: ReturnType<typeof setTimeout> | null = null;
  private invitesTimer: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    void this.ensureDir();
  }

  private async ensureDir(): Promise<void> {
    try {
      await mkdir(USERS_DIR, { recursive: true });
    } catch (err) {
      logger.error({ err }, 'Failed to create users directory');
    }
  }

  private userFilePath(userId: string): string {
    const safe = userId.replace(/[^a-zA-Z0-9\-_]/g, '');
    if (!safe || safe !== userId) {
      throw new Error(`Invalid user ID: ${userId}`);
    }
    return join(USERS_DIR, `${safe}.json`);
  }

  /** Load registry index and invites from disk */
  async load(): Promise<void> {
    await this.ensureDir();
    try {
      const data = await readFile(REGISTRY_FILE, 'utf-8');
      this.registry = JSON.parse(data) as RegistryEntry[];
    } catch {
      this.registry = [];
    }
    try {
      const data = await readFile(INVITES_FILE, 'utf-8');
      this.invites = JSON.parse(data) as InviteCode[];
    } catch {
      this.invites = [];
    }
    logger.info({ userCount: this.registry.length, pendingInvites: this.invites.filter(i => !i.redeemedBy).length }, 'User registry loaded');
  }

  /** Get the number of registered users (synchronous) */
  getUserCount(): number {
    return this.registry.length;
  }

  /** Get a user by ID */
  async getUser(id: string): Promise<User | null> {
    try {
      const data = await readFile(this.userFilePath(id), 'utf-8');
      return JSON.parse(data) as User;
    } catch {
      return null;
    }
  }

  /** Get a user by email */
  async getUserByEmail(email: string): Promise<User | null> {
    const entry = this.registry.find(
      (e) => e.email.toLowerCase() === email.toLowerCase(),
    );
    if (!entry) return null;
    return this.getUser(entry.id);
  }

  /** Create a new user */
  async createUser(user: User): Promise<void> {
    await this.ensureDir();
    await writeFile(this.userFilePath(user.id), JSON.stringify(user, null, 2), 'utf-8');
    // Add to registry index
    const existing = this.registry.findIndex((e) => e.id === user.id);
    if (existing >= 0) {
      this.registry[existing] = { id: user.id, email: user.email, role: user.role };
    } else {
      this.registry.push({ id: user.id, email: user.email, role: user.role });
    }
    this.debouncedSaveRegistry();
    logger.info({ userId: user.id, email: user.email, role: user.role }, 'User created');
  }

  /** Update an existing user (partial) */
  async updateUser(id: string, partial: Partial<User>): Promise<void> {
    const user = await this.getUser(id);
    if (!user) throw new Error(`User not found: ${id}`);
    const updated = { ...user, ...partial, id }; // Never allow id change
    await writeFile(this.userFilePath(id), JSON.stringify(updated, null, 2), 'utf-8');
    // Update registry index
    const entry = this.registry.find((e) => e.id === id);
    if (entry) {
      if (partial.email) entry.email = partial.email;
      if (partial.role) entry.role = partial.role;
      this.debouncedSaveRegistry();
    }
    logger.info({ userId: id, fields: Object.keys(partial) }, 'User updated');
  }

  /** Delete a user */
  async deleteUser(id: string): Promise<void> {
    try {
      const { unlink } = await import('node:fs/promises');
      await unlink(this.userFilePath(id));
    } catch {
      // File may not exist
    }
    this.registry = this.registry.filter((e) => e.id !== id);
    this.debouncedSaveRegistry();
    logger.info({ userId: id }, 'User deleted');
  }

  /** List all users (full objects) */
  async listUsers(): Promise<User[]> {
    const users: User[] = [];
    for (const entry of this.registry) {
      const user = await this.getUser(entry.id);
      if (user) users.push(user);
    }
    return users;
  }

  /** Check if registry has any users */
  isEmpty(): boolean {
    return this.registry.length === 0;
  }

  // ── Invite code methods ────────────────────────────────────

  /** Generate a new invite code */
  async generateInviteCode(role: UserRole, createdBy: string): Promise<InviteCode> {
    const code = randomBytes(INVITE_CODE_LENGTH)
      .toString('base64url')
      .slice(0, INVITE_CODE_LENGTH)
      .toUpperCase();

    const invite: InviteCode = {
      code,
      role,
      createdBy,
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + INVITE_EXPIRY_MS).toISOString(),
    };

    this.invites.push(invite);
    this.debouncedSaveInvites();
    logger.info({ code, role, createdBy }, 'Invite code generated');
    return invite;
  }

  /** Redeem an invite code — returns the invite if valid, null otherwise */
  async redeemInviteCode(code: string, userDetails: { id: string; email: string; name?: string; picture?: string }): Promise<InviteCode | null> {
    const normalizedCode = code.trim().toUpperCase();
    const invite = this.invites.find(
      (i) => i.code === normalizedCode && !i.redeemedBy && new Date(i.expiresAt) > new Date(),
    );
    if (!invite) return null;

    invite.redeemedBy = userDetails.id;
    invite.redeemedAt = new Date().toISOString();
    this.debouncedSaveInvites();

    // Create user from invite
    const user: User = {
      id: userDetails.id,
      email: userDetails.email,
      name: userDetails.name,
      picture: userDetails.picture,
      role: invite.role,
      createdAt: new Date().toISOString(),
      lastLoginAt: new Date().toISOString(),
      invitedBy: invite.createdBy,
    };
    await this.createUser(user);

    logger.info({ code, userId: userDetails.id, role: invite.role }, 'Invite code redeemed');
    return invite;
  }

  /** List pending (unredeemed, unexpired) invites */
  listPendingInvites(): InviteCode[] {
    const now = new Date();
    return this.invites.filter(
      (i) => !i.redeemedBy && new Date(i.expiresAt) > now,
    );
  }

  // ── Persistence helpers ────────────────────────────────────

  private debouncedSaveRegistry(): void {
    if (this.registryTimer) clearTimeout(this.registryTimer);
    this.registryTimer = setTimeout(() => {
      this.registryTimer = null;
      void this.writeRegistry();
    }, DEBOUNCE_MS);
  }

  private debouncedSaveInvites(): void {
    if (this.invitesTimer) clearTimeout(this.invitesTimer);
    this.invitesTimer = setTimeout(() => {
      this.invitesTimer = null;
      void this.writeInvites();
    }, DEBOUNCE_MS);
  }

  private async writeRegistry(): Promise<void> {
    try {
      await this.ensureDir();
      await writeFile(REGISTRY_FILE, JSON.stringify(this.registry, null, 2), 'utf-8');
      logger.debug('User registry index saved');
    } catch (err) {
      logger.error({ err }, 'Failed to save user registry index');
    }
  }

  private async writeInvites(): Promise<void> {
    try {
      await this.ensureDir();
      await writeFile(INVITES_FILE, JSON.stringify(this.invites, null, 2), 'utf-8');
      logger.debug('Invites file saved');
    } catch (err) {
      logger.error({ err }, 'Failed to save invites file');
    }
  }

  /** Flush all pending writes immediately (for shutdown) */
  async flush(): Promise<void> {
    if (this.registryTimer) {
      clearTimeout(this.registryTimer);
      this.registryTimer = null;
      await this.writeRegistry();
    }
    if (this.invitesTimer) {
      clearTimeout(this.invitesTimer);
      this.invitesTimer = null;
      await this.writeInvites();
    }
  }

  /** Cancel pending writes */
  dispose(): void {
    if (this.registryTimer) clearTimeout(this.registryTimer);
    if (this.invitesTimer) clearTimeout(this.invitesTimer);
    this.registryTimer = null;
    this.invitesTimer = null;
  }
}
