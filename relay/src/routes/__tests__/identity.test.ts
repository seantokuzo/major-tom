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
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
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
      verify(null, message, publicKeyFrom(body.publicKey), Buffer.from(body.signature, 'base64url')),
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
      verify(null, nonce, publicKeyFrom(body.publicKey), Buffer.from(body.signature, 'base64url')),
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

/**
 * Canonical signed-byte contract — the GREEN-lane tripwire (#180).
 *
 * The whole-suite goal: a future base64 ⇄ base64url "cleanup" on EITHER side of
 * the iOS↔relay handshake must not be able to silently desync it. So we pin the
 * EXACT (publicKeyB64url, nonceStdB64, signatureB64url, fingerprint) quadruple
 * against a CHECKED-IN, deterministic Ed25519 key. Any change to the encodings,
 * the domain-separation prefix, the nonce-decode base, the fingerprint hash, or
 * the message-assembly order flips one of these hardcoded strings and fails the
 * lane loudly.
 *
 * This exercises the REAL relay code path — not a re-implementation:
 *   - public key + fingerprint come from `RelayIdentity.derivePublic()` (loaded
 *     from the fixed PKCS#8 PEM persisted below),
 *   - the signature comes from `RelayIdentity.sign()`,
 *   - the message is assembled byte-for-byte the way `POST /identity/challenge`
 *     does it (`utf8(CHALLENGE_CONTEXT) || nonce`).
 *
 * The SAME quadruple is mirrored in the iOS DEBUG self-test
 * (`ios/MajorTom/Core/Services/RelayIdentityVerifier.swift` → `runSelfTest()`),
 * so the two clients verify against ONE source of truth. If you regenerate this
 * vector, regenerate that one identically.
 *
 * Fixed key material: a PKCS#8 Ed25519 private key built from the raw seed
 * bytes 0x01..0x20. Fixed nonce: bytes 0x00..0x1F as STANDARD base64 (with
 * padding) — the relay decodes the nonce with `Buffer.from(nonce, 'base64')`.
 */
describe('canonical /identity/challenge signed-byte vector (#180)', () => {
  // PKCS#8 PEM of the deterministic Ed25519 key (raw seed 0x01..0x20).
  const FIXED_PRIVATE_KEY_PEM = [
    '-----BEGIN PRIVATE KEY-----',
    'MC4CAQAwBQYDK2VwBCIEIAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8g',
    '-----END PRIVATE KEY-----',
    '',
  ].join('\n');

  // Fixed nonce bytes 0x00..0x1F as STANDARD base64 (32 bytes → passes the
  // 16–64 byte bound; STANDARD base64 keeps padding).
  const NONCE_STD_B64 = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';

  // The pinned quadruple. Hardcoded on purpose: these strings are the contract.
  const EXPECTED_PUBLIC_KEY_B64URL = 'ebVWLo_mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ';
  const EXPECTED_SIGNATURE_B64URL =
    'Q7L_CUIA7y7nO6T7uOd0ipZjlKvVA_wKGXGgZK0ZkEz5aei-B1jB1gRXHYcoLrOUaLKFWysFS84zOdAjpcfmCQ';
  const EXPECTED_FINGERPRINT = 'ZbYGc9btiEvwHCwiLYKtoHQPKawzVdapJcgfF_R6J7g';

  let fixtureDir: string;
  let fixedIdentity: RelayIdentity;

  beforeEach(async () => {
    fixtureDir = await mkdtemp(join(tmpdir(), 'identity-vector-'));
    const idFile = join(fixtureDir, 'relay-identity.json');
    await writeFile(
      idFile,
      JSON.stringify({ version: 1, alg: 'ed25519', privateKeyPem: FIXED_PRIVATE_KEY_PEM }),
      'utf-8',
    );
    // Loads the FIXED key — real derivePublic() + real sign() are exercised.
    fixedIdentity = await RelayIdentity.load(idFile);
  });

  afterEach(async () => {
    await rm(fixtureDir, { recursive: true, force: true });
  });

  it('derives the exact pinned public key (base64url) from the fixed key', () => {
    expect(fixedIdentity.publicKeyBase64url).toBe(EXPECTED_PUBLIC_KEY_B64URL);
  });

  it('derives the exact pinned fingerprint = base64url(sha256(rawPublicKey))', () => {
    expect(fixedIdentity.fingerprint).toBe(EXPECTED_FINGERPRINT);
  });

  it('produces the exact pinned signature over utf8(CHALLENGE_CONTEXT) || nonce', () => {
    // STANDARD-base64 nonce decode — identical to the route's
    // `Buffer.from(nonceB64, 'base64')`.
    const nonce = Buffer.from(NONCE_STD_B64, 'base64');
    expect(nonce).toHaveLength(32);

    // Message assembled byte-for-byte the way POST /identity/challenge does it.
    const message = Buffer.concat([Buffer.from(CHALLENGE_CONTEXT, 'utf-8'), nonce]);
    const signatureB64url = fixedIdentity.sign(message).toString('base64url');

    expect(signatureB64url).toBe(EXPECTED_SIGNATURE_B64URL);
  });

  it('the pinned signature verifies over the pinned public key + nonce', () => {
    const nonce = Buffer.from(NONCE_STD_B64, 'base64');
    const message = Buffer.concat([Buffer.from(CHALLENGE_CONTEXT, 'utf-8'), nonce]);
    const ok = verify(
      null,
      message,
      publicKeyFrom(EXPECTED_PUBLIC_KEY_B64URL),
      Buffer.from(EXPECTED_SIGNATURE_B64URL, 'base64url'),
    );
    expect(ok).toBe(true);
  });

  it('the live POST /identity/challenge route reproduces the pinned vector', async () => {
    // End-to-end through the route, with the fixed identity wired in — proves
    // the contract holds across the real Fastify handler, not just sign().
    const routeApp = Fastify({ logger: false });
    await routeApp.register(cookie);
    await routeApp.register(createIdentityRoutes({ identity: fixedIdentity }));
    await routeApp.ready();
    try {
      const res = await routeApp.inject({
        method: 'POST',
        url: '/identity/challenge',
        headers: { 'content-type': 'application/json' },
        payload: { nonce: NONCE_STD_B64 },
      });
      expect(res.statusCode).toBe(200);
      const body = res.json() as { alg: string; publicKey: string; signature: string };
      expect(body.alg).toBe('ed25519');
      expect(body.publicKey).toBe(EXPECTED_PUBLIC_KEY_B64URL);
      expect(body.signature).toBe(EXPECTED_SIGNATURE_B64URL);
    } finally {
      await routeApp.close();
    }
  });
});
