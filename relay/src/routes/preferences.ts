/**
 * User preferences routes — GET/PUT /api/user/preferences.
 *
 * Multi-user mode: preferences stored in the User record via UserRegistry.
 * Single-user mode: stored in ~/.major-tom/preferences.json (no auth needed).
 */
import type { FastifyPluginAsync } from 'fastify';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
import type { UserRegistry } from '../users/user-registry.js';
import type { UserPreferences } from '../users/types.js';
import { requireSession } from '../plugins/auth.js';
import { logger } from '../utils/logger.js';

const PREFS_DIR = join(homedir(), '.major-tom');
const SINGLE_USER_PREFS = join(PREFS_DIR, 'preferences.json');

interface PrefsDeps {
  userRegistry?: UserRegistry;
  multiUserEnabled: boolean;
}

/** Read single-user preferences from disk */
async function readSingleUserPrefs(): Promise<UserPreferences> {
  try {
    const data = await readFile(SINGLE_USER_PREFS, 'utf-8');
    return JSON.parse(data) as UserPreferences;
  } catch {
    return {};
  }
}

/** Write single-user preferences to disk */
async function writeSingleUserPrefs(prefs: UserPreferences): Promise<void> {
  await mkdir(PREFS_DIR, { recursive: true });
  await writeFile(SINGLE_USER_PREFS, JSON.stringify(prefs, null, 2), 'utf-8');
}

/** Validate the incoming preferences payload */
function validatePreferences(body: unknown): UserPreferences | null {
  if (!body || typeof body !== 'object') return null;
  const prefs: UserPreferences = {};
  const b = body as Record<string, unknown>;

  if (b.keybarConfig !== undefined) {
    if (b.keybarConfig === null) {
      // Allow explicit null to clear
      prefs.keybarConfig = undefined;
    } else if (typeof b.keybarConfig === 'object' && b.keybarConfig !== null) {
      const kc = b.keybarConfig as Record<string, unknown>;
      if (
        typeof kc.version === 'number' &&
        Array.isArray(kc.accessory) &&
        kc.accessory.every((k: unknown) => typeof k === 'string') &&
        Array.isArray(kc.specialty) &&
        kc.specialty.every((k: unknown) => typeof k === 'string')
      ) {
        prefs.keybarConfig = {
          version: kc.version,
          accessory: kc.accessory as string[],
          specialty: kc.specialty as string[],
        };
      } else {
        return null; // invalid shape
      }
    } else {
      return null;
    }
  }

  if (b.fontSize !== undefined) {
    if (b.fontSize === null) {
      prefs.fontSize = undefined;
    } else if (typeof b.fontSize === 'number' && b.fontSize >= 8 && b.fontSize <= 32) {
      prefs.fontSize = b.fontSize;
    } else {
      return null;
    }
  }

  return prefs;
}

export function createPreferencesRoutes(deps: PrefsDeps): FastifyPluginAsync {
  const { userRegistry, multiUserEnabled } = deps;

  return async (fastify) => {
    // GET /api/user/preferences
    fastify.get('/api/user/preferences', {
      preHandler: multiUserEnabled ? requireSession : undefined,
    }, async (request, reply) => {
      if (multiUserEnabled) {
        const userId = request.sessionUser?.userId;
        if (!userId || !userRegistry) {
          return reply.code(401).send({ error: 'Authentication required' });
        }
        const user = await userRegistry.getUser(userId);
        return reply.send(user?.preferences ?? {});
      }
      // Single-user mode — no auth needed
      const prefs = await readSingleUserPrefs();
      return reply.send(prefs);
    });

    // PUT /api/user/preferences
    fastify.put('/api/user/preferences', {
      preHandler: multiUserEnabled ? requireSession : undefined,
    }, async (request, reply) => {
      const validated = validatePreferences(request.body);
      if (validated === null) {
        return reply.code(400).send({ error: 'Invalid preferences payload' });
      }

      if (multiUserEnabled) {
        const userId = request.sessionUser?.userId;
        if (!userId || !userRegistry) {
          return reply.code(401).send({ error: 'Authentication required' });
        }
        const user = await userRegistry.getUser(userId);
        if (!user) {
          return reply.code(404).send({ error: 'User not found' });
        }
        // Merge with existing preferences
        const merged = { ...user.preferences, ...validated };
        await userRegistry.updateUser(userId, { preferences: merged });
        logger.info({ userId, fields: Object.keys(validated) }, 'User preferences updated');
        return reply.send(merged);
      }

      // Single-user mode
      const existing = await readSingleUserPrefs();
      const merged = { ...existing, ...validated };
      await writeSingleUserPrefs(merged);
      logger.info({ fields: Object.keys(validated) }, 'Single-user preferences updated');
      return reply.send(merged);
    });
  };
}
