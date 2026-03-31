/**
 * Session JWT management via jose (HS256 symmetric signing).
 * Creates and verifies session tokens stored in httpOnly cookies.
 */
import { SignJWT, jwtVerify, type JWTPayload } from 'jose';
import { randomBytes } from 'node:crypto';
import { appendFileSync, chmodSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { logger } from '../utils/logger.js';
import type { UserRole } from '../users/types.js';

export interface SessionPayload extends JWTPayload {
  sub: string;   // Google user ID
  email: string;
  userId?: string;
  role?: UserRole;
}

let sessionSecret: Uint8Array;

/**
 * Get or generate the session secret. Auto-appends to .env if generated.
 */
export function getSessionSecret(): Uint8Array {
  if (sessionSecret) return sessionSecret;

  const envSecret = process.env['SESSION_SECRET'];
  if (envSecret && envSecret.length >= 32) {
    sessionSecret = new TextEncoder().encode(envSecret);
    logger.info('Session secret loaded from environment');
    return sessionSecret;
  }

  // Auto-generate and persist
  const generated = randomBytes(32).toString('hex');
  sessionSecret = new TextEncoder().encode(generated);

  try {
    const envPath = resolve(process.cwd(), '.env');
    const isNew = !existsSync(envPath);
    appendFileSync(envPath, `\nSESSION_SECRET=${generated}\n`);
    if (isNew) chmodSync(envPath, 0o600); // owner-only for new .env files
    logger.info('Session secret generated and saved to .env');
  } catch {
    logger.warn('Could not persist session secret to .env — will regenerate on restart');
  }

  return sessionSecret;
}

/**
 * Mint a new session JWT.
 */
export async function createSessionToken(
  googleSub: string,
  email: string,
  userId?: string,
  role?: UserRole,
): Promise<string> {
  const secret = getSessionSecret();

  const claims: Record<string, unknown> = { sub: googleSub, email };
  if (userId) claims.userId = userId;
  if (role) claims.role = role;

  return new SignJWT(claims)
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setIssuer('major-tom')
    .setExpirationTime('7d')
    .sign(secret);
}

/**
 * Verify a session JWT. Returns the payload or throws.
 */
export async function verifySessionToken(token: string): Promise<SessionPayload> {
  const secret = getSessionSecret();

  const { payload } = await jwtVerify(token, secret, {
    issuer: 'major-tom',
  });

  return payload as SessionPayload;
}

/** Cookie name for the session token */
export const SESSION_COOKIE = 'mt-session';

/** Cookie options for setting the session */
export function getSessionCookieOptions(isSecure: boolean) {
  return {
    path: '/',
    httpOnly: true,
    secure: isSecure,
    sameSite: 'lax' as const,
    maxAge: 7 * 24 * 60 * 60, // 7 days in seconds
  };
}
