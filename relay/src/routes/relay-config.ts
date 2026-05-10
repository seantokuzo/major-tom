/**
 * Relay-config routes — GET/PATCH /api/relay-config.
 *
 * Currently exposes a single field: `defaultSpawnCwd` (the cwd new PTY
 * tabs spawn into when no fresh per-tab workingDir is available). iOS
 * Settings → Developer reads/writes through this endpoint; Ground
 * Control will surface the same field later (closes QA-FIXES #19).
 *
 * Auth: required in both single- and multi-user mode. The setting is
 * relay-wide, so any authenticated client can read/update it for now —
 * an admin-only gate can layer on once multi-user mode hardens.
 */
import type { FastifyPluginAsync } from 'fastify';
import { requireSession } from '../plugins/auth.js';
import { logger } from '../utils/logger.js';
import {
  RelayConfigError,
  type RelayConfig,
  type RelayConfigStore,
} from '../config/relay-config.js';

interface RelayConfigDeps {
  configStore: RelayConfigStore;
}

/**
 * Validate an incoming PATCH body. Returns the normalized partial config
 * (only fields the caller meant to set) or `null` on shape errors. The
 * deeper "is this a real directory?" validation happens inside
 * `RelayConfigStore.save`, which throws `RelayConfigError` — this layer
 * stays cheap and focused on shape.
 */
function validatePatch(body: unknown): Partial<RelayConfig> | null {
  if (!body || typeof body !== 'object') return null;
  const b = body as Record<string, unknown>;
  const out: Partial<RelayConfig> = {};

  if ('defaultSpawnCwd' in b) {
    const v = b['defaultSpawnCwd'];
    if (v === null || v === '') {
      // Explicit clear — falls back to env var / implicit defaults at
      // resolve time. Represented as undefined in the persisted config.
      out.defaultSpawnCwd = undefined;
    } else if (typeof v === 'string') {
      out.defaultSpawnCwd = v;
    } else {
      return null;
    }
  }

  return out;
}

export function createRelayConfigRoutes(deps: RelayConfigDeps): FastifyPluginAsync {
  const { configStore } = deps;

  return async (fastify) => {
    fastify.get(
      '/api/relay-config',
      { preHandler: requireSession },
      async (_request, reply) => {
        return reply.send(configStore.get());
      },
    );

    fastify.patch(
      '/api/relay-config',
      { preHandler: requireSession },
      async (request, reply) => {
        const partial = validatePatch(request.body);
        if (partial === null) {
          return reply.code(400).send({ error: 'Invalid relay-config payload' });
        }

        const next: RelayConfig = { ...configStore.get(), ...partial };
        try {
          await configStore.save(next);
        } catch (err) {
          if (err instanceof RelayConfigError) {
            const status = err.kind === 'io' ? 500 : 400;
            return reply.code(status).send({ error: err.message });
          }
          logger.warn({ err }, 'Relay config save threw unexpectedly');
          return reply.code(500).send({ error: 'Failed to save relay config' });
        }
        logger.info(
          { fields: Object.keys(partial) },
          'Relay config updated',
        );
        return reply.send(configStore.get());
      },
    );
  };
}
