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
      // Phase 13 "The Shell": tmux full-redraw, `cat` on large files, and
      // vimdiff can burst frames well over 1 MiB. 8 MiB gives headroom
      // without making abuse any cheaper (the route still owns throttling).
      maxPayload: 8 * 1024 * 1024,
    },
  });
};

export const websocketPlugin = fp(websocketPluginImpl, { name: 'websocket' });
