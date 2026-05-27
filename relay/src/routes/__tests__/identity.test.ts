/**
 * Integration tests for the public relay-identity routes.
 *
 * Registers the auth plugin so the test also proves `/identity` and
 * `/identity/challenge` are in the PUBLIC_PATHS allowlist (reachable with no
 * session cookie), and verifies the challenge signature against the relay's
 * exposed public key over the domain-separated message.
 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';
import cookie from '@fastify/cookie';
import { createPublicKey, randomBytes, verify } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { authPlugin } from '../../plugins/auth.js';
import { RelayIdentity } from '../../identity/relay-identity.js';
import { CHALLENGE_CONTEXT, createIdentityRoutes } from '../identity.js';

let app: FastifyInstance;
let baseDir: string;
let identity: RelayIdentity;

beforeEach(async () => {
  process.env['SESSION_SECRET'] = 'test-identity-route-secret-must-be-32-bytes!';
  baseDir = await mkdtemp(join(tmpdir(), 'identity-route-'));
  identity = await RelayIdentity.load(join(baseDir, 'relay-identity.json'));

  app = Fastify({ logger: false });
  await app.register(cookie);
  await app.register(authPlugin);
  await app.register(createIdentityRoutes({ identity }));
  await app.ready();
});

afterEach(async () => {
  await app.close();
  await rm(baseDir, { recursive: true, force: true });
});

function publicKeyFrom(b64u: string) {
  return createPublicKey({ key: { kty: 'OKP', crv: 'Ed25519', x: b64u }, format: 'jwk' });
}

describe('GET /identity', () => {
  it('is public and returns the relay public key + fingerprint', async () => {
    const res = await app.inject({ method: 'GET', url: '/identity' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      alg: 'ed25519',
      publicKey: identity.publicKeyBase64url,
      fingerprint: identity.fingerprint,
    });
  });
});

describe('POST /identity/challenge', () => {
  it('signs a valid nonce; signature verifies over context||nonce', async () => {
    const nonce = randomBytes(32);
    const res = await app.inject({
      method: 'POST',
      url: '/identity/challenge',
      headers: { 'content-type': 'application/json' },
      payload: { nonce: nonce.toString('base64') },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json() as { publicKey: string; signature: string };
    expect(body.publicKey).toBe(identity.publicKeyBase64url);

    const message = Buffer.concat([Buffer.from(CHALLENGE_CONTEXT, 'utf-8'), nonce]);
    expect(
      verify(null, message, publicKeyFrom(body.publicKey), Buffer.from(body.signature, 'base64')),
    ).toBe(true);
  });

  it('does NOT verify over the bare nonce — proves domain separation', async () => {
    const nonce = randomBytes(32);
    const res = await app.inject({
      method: 'POST',
      url: '/identity/challenge',
      headers: { 'content-type': 'application/json' },
      payload: { nonce: nonce.toString('base64') },
    });
    const body = res.json() as { publicKey: string; signature: string };
    expect(
      verify(null, nonce, publicKeyFrom(body.publicKey), Buffer.from(body.signature, 'base64')),
    ).toBe(false);
  });

  it('rejects a missing nonce with 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/identity/challenge',
      headers: { 'content-type': 'application/json' },
      payload: {},
    });
    expect(res.statusCode).toBe(400);
  });

  it('rejects a too-short nonce with 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/identity/challenge',
      headers: { 'content-type': 'application/json' },
      payload: { nonce: Buffer.alloc(8).toString('base64') },
    });
    expect(res.statusCode).toBe(400);
  });
});
