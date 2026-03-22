import type { FastifyPluginAsync } from 'fastify';
import type { PushManager, PushSubscriptionData } from '../push/push-manager.js';
import { requireSession } from '../plugins/auth.js';

interface PushDeps {
  pushManager: PushManager;
}

/**
 * Push notification routes.
 * GET /push/vapid-key is public; subscribe/unsubscribe require session auth.
 */
export function createPushRoutes(deps: PushDeps): FastifyPluginAsync {
  return async (fastify) => {
    // Public — frontend needs this before subscribing
    fastify.get('/push/vapid-key', async () => {
      return { publicKey: deps.pushManager.getVapidPublicKey() };
    });

    // Auth required
    fastify.post<{ Body: PushSubscriptionData }>(
      '/push/subscribe',
      { preHandler: requireSession },
      async (request, reply) => {
        const sub = request.body;
        if (!sub?.endpoint || !sub.keys?.p256dh || !sub.keys?.auth) {
          return reply.code(400).send({
            error: 'Invalid subscription: requires endpoint, keys.p256dh, keys.auth',
          });
        }
        deps.pushManager.subscribe(sub);
        return { status: 'ok' };
      },
    );

    fastify.post<{ Body: { endpoint: string } }>(
      '/push/unsubscribe',
      { preHandler: requireSession },
      async (request, reply) => {
        const { endpoint } = request.body ?? {};
        if (!endpoint) {
          return reply.code(400).send({ error: 'Missing endpoint field' });
        }
        deps.pushManager.unsubscribe(endpoint);
        return { status: 'ok' };
      },
    );
  };
}
