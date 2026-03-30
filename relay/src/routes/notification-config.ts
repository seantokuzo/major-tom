/**
 * Notification config routes — GET/PUT for notification settings.
 * Both routes require authentication.
 */

import type { FastifyPluginAsync } from 'fastify';
import type { NotificationConfigManager, NotificationConfig } from '../push/notification-config.js';
import { requireSession } from '../plugins/auth.js';

interface NotificationConfigDeps {
  notificationConfigManager: NotificationConfigManager;
}

export function createNotificationConfigRoutes(
  deps: NotificationConfigDeps,
): FastifyPluginAsync {
  return async (fastify) => {
    // GET /api/config/notifications — returns current notification config
    fastify.get(
      '/api/config/notifications',
      { preHandler: requireSession },
      async () => {
        return deps.notificationConfigManager.getConfig();
      },
    );

    // PUT /api/config/notifications — updates notification config
    fastify.put<{ Body: Partial<NotificationConfig> }>(
      '/api/config/notifications',
      { preHandler: requireSession },
      async (request, reply) => {
        const body = request.body;
        if (!body || typeof body !== 'object') {
          return reply.code(400).send({ error: 'Invalid request body' });
        }

        try {
          const updated = await deps.notificationConfigManager.updateConfig(body);
          return updated;
        } catch (err: unknown) {
          const message = err instanceof Error ? err.message : 'Unknown error';
          return reply.code(400).send({ error: message });
        }
      },
    );
  };
}
