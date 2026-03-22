import type { FastifyPluginAsync } from 'fastify';
import { verifyGoogleIdToken } from '../auth/google.js';
import {
  createSessionToken,
  verifySessionToken,
  SESSION_COOKIE,
  getSessionCookieOptions,
} from '../auth/session.js';
import { logger } from '../utils/logger.js';

/**
 * Auth routes — Google OAuth login, session check, logout.
 */
export const authRoutes: FastifyPluginAsync = async (fastify) => {
  const GOOGLE_CLIENT_ID = process.env['GOOGLE_CLIENT_ID'];
  const ALLOWED_EMAIL = process.env['ALLOWED_EMAIL'];
  const isSecure = process.env['NODE_ENV'] === 'production'
    || !!process.env['CLOUDFLARE_TUNNEL'];

  /**
   * GET /auth/google/client-id — frontend needs this to initialize GSI.
   * Public (no auth required).
   */
  fastify.get('/auth/google/client-id', async (_request, reply) => {
    if (!GOOGLE_CLIENT_ID) {
      return reply.code(503).send({ error: 'Google OAuth not configured' });
    }
    return { clientId: GOOGLE_CLIENT_ID };
  });

  /**
   * POST /auth/google — exchange Google ID token for session cookie.
   * Rate-limited to prevent brute force.
   */
  fastify.post<{ Body: { credential: string } }>(
    '/auth/google',
    {
      config: {
        rateLimit: {
          max: 10,
          timeWindow: '5 minutes',
        },
      },
    },
    async (request, reply) => {
      if (!GOOGLE_CLIENT_ID) {
        return reply.code(503).send({ error: 'Google OAuth not configured' });
      }
      if (!ALLOWED_EMAIL) {
        return reply.code(503).send({ error: 'ALLOWED_EMAIL not configured' });
      }

      const { credential } = request.body ?? {};
      if (!credential || typeof credential !== 'string') {
        return reply.code(400).send({ error: 'Missing credential' });
      }

      try {
        const payload = await verifyGoogleIdToken(credential, GOOGLE_CLIENT_ID);

        // Check allowed email
        if (payload.email.toLowerCase() !== ALLOWED_EMAIL.toLowerCase()) {
          logger.warn({ email: payload.email }, 'Login attempt from non-allowed email');
          return reply.code(403).send({ error: 'Access denied' });
        }

        // Mint session JWT
        const sessionToken = await createSessionToken(payload.sub!, payload.email);

        // Set httpOnly cookie
        reply.setCookie(SESSION_COOKIE, sessionToken, getSessionCookieOptions(isSecure));

        logger.info({ email: payload.email }, 'User authenticated via Google OAuth');

        return {
          email: payload.email,
          name: payload.name,
          picture: payload.picture,
        };
      } catch (err) {
        logger.error({ err }, 'Google token verification failed');
        return reply.code(401).send({ error: 'Invalid Google credential' });
      }
    },
  );

  /**
   * GET /auth/me — check current session. Returns user info or 401.
   * Used by frontend to determine auth state on load.
   */
  fastify.get('/auth/me', async (request, reply) => {
    const token = request.cookies?.[SESSION_COOKIE];
    if (!token) {
      return reply.code(401).send({ error: 'Not authenticated' });
    }

    try {
      const payload = await verifySessionToken(token);
      return {
        email: payload.email,
        sub: payload.sub,
      };
    } catch {
      // Clear invalid cookie
      reply.clearCookie(SESSION_COOKIE, { path: '/' });
      return reply.code(401).send({ error: 'Session expired' });
    }
  });

  /**
   * POST /auth/logout — clear session cookie.
   */
  fastify.post('/auth/logout', async (_request, reply) => {
    reply.clearCookie(SESSION_COOKIE, { path: '/' });
    return { status: 'ok' };
  });
};
