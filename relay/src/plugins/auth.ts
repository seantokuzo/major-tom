import fp from 'fastify-plugin';
import type { FastifyPluginAsync, FastifyRequest, FastifyReply } from 'fastify';
import { verifySessionToken, SESSION_COOKIE, type SessionPayload } from '../auth/session.js';
import type { UserRole } from '../users/types.js';

// Extend Fastify types with session user and userRegistry
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
  '/auth/methods', // public — clients need this to determine available auth methods
  '/auth/pin/login', // public — PIN auth handles its own rate limiting
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
 * For tokens without userId (legacy), looks up user by email in registry.
 * Must be registered with fastify-plugin to share across encapsulation boundaries.
 */
const authPluginImpl: FastifyPluginAsync = async (fastify) => {
  // Decorate request with null default
  fastify.decorateRequest('sessionUser', null);

  fastify.addHook('onRequest', async (request: FastifyRequest, reply: FastifyReply) => {
    // Always set to null initially
    request.sessionUser = null;

    // Skip auth for public paths
    if (isPublicPath(request.url)) return;

    // WebSocket upgrade auth is handled inside the WS route's WebSocket handler

    const token = request.cookies?.[SESSION_COOKIE];
    if (!token) {
      // No cookie — let the route decide if auth is required
      return;
    }

    try {
      const payload = await verifySessionToken(token);

      // For tokens without userId (legacy), try to look up user by email in registry
      if (!payload.userId && fastify.userRegistry) {
        const user = await fastify.userRegistry.getUserByEmail(payload.email);
        if (user) {
          payload.userId = user.id;
          payload.role = user.role;
        }
      }

      request.sessionUser = payload;
    } catch {
      // Invalid/expired token — clear cookie so we don't re-verify on every request
      reply.clearCookie(SESSION_COOKIE, { path: '/' });
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
    return reply.code(401).send({ error: 'Authentication required' });
  }
}

/**
 * Role hierarchy for access control.
 */
const ROLE_HIERARCHY: Record<UserRole, number> = { viewer: 0, operator: 1, admin: 2 };

/**
 * Route-level hook factory to require a minimum role.
 */
export function requireRole(minimumRole: UserRole) {
  return async (request: FastifyRequest, reply: FastifyReply) => {
    if (!request.sessionUser) {
      return reply.code(401).send({ error: 'Authentication required' });
    }
    const userRole = request.sessionUser.role;
    if (!userRole) {
      return reply.code(403).send({ error: 'Insufficient permissions — role missing' });
    }
    if (ROLE_HIERARCHY[userRole] < ROLE_HIERARCHY[minimumRole]) {
      return reply.code(403).send({ error: 'Insufficient permissions' });
    }
  };
}
