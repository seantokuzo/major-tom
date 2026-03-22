import fp from 'fastify-plugin';
import type { FastifyPluginAsync, FastifyRequest, FastifyReply } from 'fastify';
import { verifySessionToken, SESSION_COOKIE, type SessionPayload } from '../auth/session.js';
import { logger } from '../utils/logger.js';

// Extend Fastify types with session user
declare module 'fastify' {
  interface FastifyRequest {
    sessionUser: SessionPayload | null;
  }
}

/** Routes that don't require authentication */
const PUBLIC_PATHS = new Set([
  '/health',
  '/auth/google',
  '/auth/google/client-id',
  '/auth/me', // returns 401 if no session — frontend uses this to check auth state
]);

/** Path prefixes that are always public (static files handled by @fastify/static) */
function isPublicPath(url: string): boolean {
  // Strip query string for matching
  const path = url.split('?')[0] ?? url;
  return PUBLIC_PATHS.has(path);
}

/**
 * Auth plugin — verifies session JWT cookie on every request.
 * Decorates request with `sessionUser`.
 * Must be registered with fastify-plugin to share across encapsulation boundaries.
 */
const authPluginImpl: FastifyPluginAsync = async (fastify) => {
  // Decorate request with null default
  fastify.decorateRequest('sessionUser', null);

  fastify.addHook('onRequest', async (request: FastifyRequest, _reply: FastifyReply) => {
    // Always set to null initially
    request.sessionUser = null;

    // Skip auth for public paths
    if (isPublicPath(request.url)) return;

    // Static files are handled by @fastify/static before this hook
    // WebSocket upgrade auth is handled in the WS route's preValidation hook

    const token = request.cookies?.[SESSION_COOKIE];
    if (!token) {
      // No cookie — let the route decide if auth is required
      return;
    }

    try {
      const payload = await verifySessionToken(token);

      // Check allowed email
      const allowedEmail = process.env['ALLOWED_EMAIL'];
      if (allowedEmail && payload.email.toLowerCase() !== allowedEmail.toLowerCase()) {
        logger.warn({ email: payload.email }, 'Session token for non-allowed email');
        request.sessionUser = null;
        return;
      }

      request.sessionUser = payload;
    } catch {
      // Invalid/expired token — clear it silently
      request.sessionUser = null;
    }
  });
};

export const authPlugin = fp(authPluginImpl, {
  name: 'auth',
});

/**
 * Route-level hook to require authentication.
 * Use as preHandler on routes that must be authenticated.
 */
export async function requireSession(request: FastifyRequest, reply: FastifyReply) {
  if (!request.sessionUser) {
    reply.code(401).send({ error: 'Authentication required' });
  }
}
