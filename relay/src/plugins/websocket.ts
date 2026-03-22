import type { FastifyPluginAsync } from 'fastify';
import websocket from '@fastify/websocket';

/**
 * WebSocket plugin — registers @fastify/websocket with clientTracking.
 */
export const websocketPlugin: FastifyPluginAsync = async (fastify) => {
  await fastify.register(websocket, {
    options: {
      clientTracking: true,
      maxPayload: 1_048_576, // 1 MB
    },
  });
};
