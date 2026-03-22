import type { FastifyPluginAsync } from 'fastify';
import cookie from '@fastify/cookie';

/**
 * Cookie parsing plugin.
 */
export const cookiePlugin: FastifyPluginAsync = async (fastify) => {
  await fastify.register(cookie, {
    hook: 'onRequest',
  });
};
