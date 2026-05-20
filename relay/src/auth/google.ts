/**
 * Google OAuth ID token verification via jose.
 * Verifies tokens from "Sign In With Google" client-side flow.
 */
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from 'jose';

const GOOGLE_JWKS = createRemoteJWKSet(
  new URL('https://www.googleapis.com/oauth2/v3/certs'),
);

export interface GoogleTokenPayload extends JWTPayload {
  email: string;
  email_verified: boolean;
  name?: string;
  picture?: string;
  given_name?: string;
  family_name?: string;
}

/**
 * Verify a Google ID token and return the payload.
 * Checks issuer, audience, expiration, and email_verified.
 *
 * `audience` accepts either a single client ID (PWA-only deployments)
 * or an array (e.g. [web, iOS] when both PWA and native clients sign in
 * against the same relay — their ID tokens carry different `aud` claims).
 */
export async function verifyGoogleIdToken(
  idToken: string,
  audience: string | string[],
): Promise<GoogleTokenPayload> {
  const { payload } = await jwtVerify(idToken, GOOGLE_JWKS, {
    issuer: ['https://accounts.google.com', 'accounts.google.com'],
    audience,
  });

  const p = payload as GoogleTokenPayload;

  if (!p.email) {
    throw new Error('Google token missing email claim');
  }
  if (!p.email_verified) {
    throw new Error('Google email not verified');
  }

  return p;
}
