import type { FastifyPluginAsync } from 'fastify';
import { verifyGoogleIdToken } from '../auth/google.js';
import { pinManager } from '../auth/pin-manager.js';
import {
  createSessionToken,
  verifySessionToken,
  SESSION_COOKIE,
  getSessionCookieOptions,
} from '../auth/session.js';
import type { UserRegistry } from '../users/user-registry.js';
import type { UserRole } from '../users/types.js';
import { logger } from '../utils/logger.js';

interface AuthRouteDeps {
  userRegistry?: UserRegistry;
  multiUserEnabled: boolean;
  authGoogleEnabled: boolean;
  authPinEnabled: boolean;
}

/**
 * Auth routes factory — Google OAuth login, PIN login, invite codes, session check, logout.
 */
export function createAuthRoutes(deps: AuthRouteDeps): FastifyPluginAsync {
  const { userRegistry, multiUserEnabled, authGoogleEnabled, authPinEnabled } = deps;

  return async (fastify) => {
    const GOOGLE_CLIENT_ID = process.env['GOOGLE_CLIENT_ID'];
    const ALLOWED_EMAIL = process.env['ALLOWED_EMAIL'];
    const isSecure = process.env['NODE_ENV'] === 'production'
      || !!process.env['CLOUDFLARE_TUNNEL'];

    // ── Auth methods discovery endpoint ────────────────────
    /**
     * GET /auth/methods — returns which auth methods are available.
     * Public (no auth required). Used by clients to adapt login UI.
     */
    fastify.get('/auth/methods', async () => {
      return {
        google: authGoogleEnabled,
        pin: authPinEnabled,
        multiUser: multiUserEnabled,
      };
    });

    // ── Google OAuth routes (only when Google auth is enabled) ──
    if (authGoogleEnabled) {
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
       * When multi-user enabled: first user becomes admin, subsequent users need invite codes.
       * When single-user: first login = sole user, no roles.
       * Rate-limited to prevent brute force.
       */
      fastify.post<{ Body: { credential: string; inviteCode?: string } }>(
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

          const { credential, inviteCode } = request.body ?? {};
          if (!credential || typeof credential !== 'string') {
            return reply.code(400).send({ error: 'Missing credential' });
          }

          try {
            const payload = await verifyGoogleIdToken(credential, GOOGLE_CLIENT_ID);

            if (!payload.sub) {
              logger.error({ payload }, 'Google token payload missing sub claim');
              return reply.code(401).send({ error: 'Invalid Google credential' });
            }

            const email = payload.email;

            // Respect ALLOWED_EMAIL guard in all modes
            if (ALLOWED_EMAIL && email.toLowerCase() !== ALLOWED_EMAIL.toLowerCase()) {
              logger.warn({ email }, 'Google login blocked by ALLOWED_EMAIL mismatch');
              return reply.code(403).send({ error: 'Access denied' });
            }

            // Single-user mode — simple token without userId/role
            if (!multiUserEnabled || !userRegistry) {
              const sessionToken = await createSessionToken(payload.sub, email);
              reply.setCookie(SESSION_COOKIE, sessionToken, getSessionCookieOptions(isSecure));

              logger.info({ email }, 'User authenticated via Google OAuth (single-user mode)');
              return { email, name: payload.name, picture: payload.picture };
            }

            // Multi-user mode — full user registry flow
            const userId = payload.sub;
            let user = await userRegistry.getUserByEmail(email);

            if (!user && userRegistry.isEmpty()) {
              // First-user bootstrap — auto-create as admin
              user = {
                id: userId,
                email,
                name: payload.name,
                picture: payload.picture,
                role: 'admin',
                createdAt: new Date().toISOString(),
                lastLoginAt: new Date().toISOString(),
              };
              await userRegistry.createUser(user);
              logger.info({ email, userId }, 'First user bootstrapped as admin');
            } else if (!user) {
              // Registry has users but this person isn't one — check invite code
              if (!inviteCode) {
                return reply.code(403).send({ error: 'Access denied — invite code required' });
              }
              const redeemed = await userRegistry.redeemInviteCode(inviteCode, {
                id: userId,
                email,
                name: payload.name,
                picture: payload.picture,
              });
              if (!redeemed) {
                return reply.code(403).send({ error: 'Invalid or expired invite code' });
              }
              user = await userRegistry.getUser(userId);
              if (!user) {
                return reply.code(500).send({ error: 'Failed to create user after invite redemption' });
              }
            } else {
              // Existing user — update lastLoginAt
              await userRegistry.updateUser(user.id, {
                lastLoginAt: new Date().toISOString(),
                name: payload.name,
                picture: payload.picture,
              });
            }

            // Mint session JWT with userId and role
            const sessionToken = await createSessionToken(
              payload.sub,
              email,
              user.id,
              user.role,
            );

            // Set httpOnly cookie
            reply.setCookie(SESSION_COOKIE, sessionToken, getSessionCookieOptions(isSecure));

            logger.info({ email, userId: user.id, role: user.role }, 'User authenticated via Google OAuth');

            return {
              email,
              name: payload.name,
              picture: payload.picture,
              userId: user.id,
              role: user.role,
            };
          } catch (err) {
            logger.error({ err }, 'Google token verification failed');
            return reply.code(401).send({ error: 'Invalid Google credential' });
          }
        },
      );
    } else {
      // Google auth disabled — return 404 for Google routes
      fastify.get('/auth/google/client-id', async (_request, reply) => {
        return reply.code(404).send({ error: 'Google OAuth is disabled' });
      });
      fastify.post('/auth/google', async (_request, reply) => {
        return reply.code(404).send({ error: 'Google OAuth is disabled' });
      });
    }

    // ── PIN auth (only when PIN auth is enabled) ───────────

    if (authPinEnabled) {
      /**
       * POST /auth/pin/generate — generate a new 6-digit PIN.
       * Localhost-only for security.
       */
      fastify.post('/auth/pin/generate', async (request, reply) => {
        const ip = request.ip;
        if (ip !== '127.0.0.1' && ip !== '::1' && ip !== '::ffff:127.0.0.1') {
          return reply.code(403).send({ error: 'PIN generation is localhost-only' });
        }

        const { pin, expiresAt } = pinManager.generatePin();
        logger.info('New pairing PIN generated');
        return { pin, expiresAt };
      });

      /**
       * POST /auth/pin/login — exchange a valid PIN for a session cookie.
       * Rate-limited per IP.
       * Multi-user: maps to admin user from registry.
       * Single-user: mints simple token with PIN identity.
       */
      fastify.post<{ Body: { pin: string } }>('/auth/pin/login', async (request, reply) => {
        const { pin } = request.body ?? {};
        if (!pin || typeof pin !== 'string') {
          return reply.code(400).send({ error: 'Missing PIN' });
        }

        const ip = request.ip;

        // Rate limit check
        const limit = pinManager.checkRateLimit(ip);
        if (!limit.allowed) {
          return reply.code(429).send({
            error: 'Too many attempts',
            retryAfter: limit.retryAfter,
          });
        }

        // Validate and consume
        if (!pinManager.consumePin(pin)) {
          pinManager.recordFailedAttempt(ip);
          logger.warn({ ip }, 'Failed PIN login attempt');
          return reply.code(401).send({ error: 'Invalid or expired PIN' });
        }

        // Single-user mode — mint simple token without userId/role
        if (!multiUserEnabled || !userRegistry) {
          const sessionToken = await createSessionToken('pin-user', 'pin@localhost');
          reply.setCookie(SESSION_COOKIE, sessionToken, getSessionCookieOptions(isSecure));
          logger.info({ ip }, 'User authenticated via PIN (single-user mode)');
          return { email: 'pin@localhost', name: 'PIN User' };
        }

        // Multi-user mode — find admin user for PIN auth
        if (userRegistry.isEmpty()) {
          return reply.code(503).send({ error: 'Setup required — please login via Google first' });
        }

        const users = await userRegistry.listUsers();
        const adminUser = users.find((u) => u.role === 'admin') ?? users[0];
        if (!adminUser) {
          return reply.code(503).send({ error: 'No admin user found' });
        }

        // Mint session with admin's identity
        const sessionToken = await createSessionToken(
          adminUser.id,
          adminUser.email,
          adminUser.id,
          adminUser.role,
        );
        reply.setCookie(SESSION_COOKIE, sessionToken, getSessionCookieOptions(isSecure));

        logger.info({ ip, userId: adminUser.id }, 'User authenticated via PIN');

        return {
          email: adminUser.email,
          name: adminUser.name ?? 'PIN User',
          userId: adminUser.id,
          role: adminUser.role,
        };
      });
    } else {
      // PIN auth disabled — return 404 for PIN routes
      fastify.post('/auth/pin/generate', async (_request, reply) => {
        return reply.code(404).send({ error: 'PIN authentication is disabled' });
      });
      fastify.post('/auth/pin/login', async (_request, reply) => {
        return reply.code(404).send({ error: 'PIN authentication is disabled' });
      });
    }

    // ── Session management ────────────────────────────────

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

        // If JWT has userId/role, use them — but enrich with name/picture from registry
        if (payload.userId && payload.role) {
          const registeredUser = userRegistry ? await userRegistry.getUser(payload.userId) : null;
          return {
            email: payload.email,
            sub: payload.sub,
            userId: payload.userId,
            role: payload.role,
            name: registeredUser?.name,
            picture: registeredUser?.picture,
          };
        }

        // Legacy token — look up user by email in registry (multi-user only)
        if (userRegistry) {
          const user = await userRegistry.getUserByEmail(payload.email);
          if (user) {
            return {
              email: payload.email,
              sub: payload.sub,
              userId: user.id,
              role: user.role,
              name: user.name,
              picture: user.picture,
            };
          }
        }

        // No user record or single-user mode — return basic info
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

    // ── Invite management (admin only, multi-user only) ────

    if (multiUserEnabled && userRegistry) {
      /**
       * POST /auth/invite — admin generates an invite code.
       */
      fastify.post<{ Body: { role: UserRole } }>('/auth/invite', async (request, reply) => {
        if (!request.sessionUser) {
          return reply.code(401).send({ error: 'Authentication required' });
        }

        const userRole = request.sessionUser.role;
        if (userRole !== 'admin') {
          return reply.code(403).send({ error: 'Admin access required' });
        }

        const { role } = request.body ?? {};
        if (!role || !['admin', 'operator', 'viewer'].includes(role)) {
          return reply.code(400).send({ error: 'Invalid role — must be admin, operator, or viewer' });
        }

        const userId = request.sessionUser.userId ?? request.sessionUser.sub;
        const invite = await userRegistry.generateInviteCode(role, userId);

        return {
          code: invite.code,
          role: invite.role,
          expiresAt: invite.expiresAt,
        };
      });

      /**
       * GET /auth/invites — admin lists pending invites.
       */
      fastify.get('/auth/invites', async (request, reply) => {
        if (!request.sessionUser) {
          return reply.code(401).send({ error: 'Authentication required' });
        }

        const userRole = request.sessionUser.role;
        if (userRole !== 'admin') {
          return reply.code(403).send({ error: 'Admin access required' });
        }

        const invites = userRegistry.listPendingInvites();
        return { invites };
      });
    } else {
      // Multi-user disabled — invite endpoints return 404
      fastify.post('/auth/invite', async (_request, reply) => {
        return reply.code(404).send({ error: 'Multi-user features are disabled' });
      });
      fastify.get('/auth/invites', async (_request, reply) => {
        return reply.code(404).send({ error: 'Multi-user features are disabled' });
      });
    }
  };
}
