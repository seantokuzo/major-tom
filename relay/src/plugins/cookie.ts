import fp from 'fastify-plugin';
import type { FastifyPluginAsync } from 'fastify';
import cookie from '@fastify/cookie';

/**
 * Cookie parsing plugin.
 * Uses fastify-plugin to share across encapsulation boundaries.
 */
const cookiePluginImpl: FastifyPluginAsync = async (fastify) => {
  await fastify.register(cookie, {
    hook: 'onRequest',
  });
};

export const cookiePlugin = fp(cookiePluginImpl, { name: 'cookie' });
