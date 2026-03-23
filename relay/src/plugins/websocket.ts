import type { FastifyPluginAsync } from 'fastify';
import fp from 'fastify-plugin';
import websocket from '@fastify/websocket';

/**
 * WebSocket plugin — registers @fastify/websocket with clientTracking.
 * Must use fastify-plugin to share across encapsulation boundaries,
 * otherwise the onRoute hook won't reach routes in other register() contexts.
 */
const websocketPluginImpl: FastifyPluginAsync = async (fastify) => {
  await fastify.register(websocket, {
    options: {
      clientTracking: true,
      maxPayload: 1_048_576, // 1 MB
    },
  });
};

export const websocketPlugin = fp(websocketPluginImpl, { name: 'websocket' });
