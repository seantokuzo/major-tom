// Relay identity routes (PUBLIC — no auth).
//
// These back the iOS LAN-preference identity binding:
//   - GET  /identity            → the relay's Ed25519 public key + fingerprint.
//                                  The app fetches this at pairing (against the
//                                  OAuth'd host it trusts) and pins the key.
//   - POST /identity/challenge  → signs a client-supplied random nonce with the
//                                  identity private key. The app verifies this
//                                  signature against the pinned key before
//                                  trusting a discovered LAN host with the
//                                  session cookie.
//
// SECURITY NOTE: the mDNS TXT `fp` and this public key are NOT secrets — they
// are broadcast/served to anyone. The trust anchor is *possession of the
// private key*, proven by the signature here. A host that merely echoes the
// fingerprint or public key cannot produce a valid signature, so it fails the
// challenge. (This defeats an impersonating "first responder"; it does not by
// itself defeat an on-path MITM that forwards the nonce to the real relay —
// that needs channel binding / TLS, tracked as follow-up hardening.)

import type { FastifyPluginAsync } from 'fastify';
import type { RelayIdentity } from '../identity/relay-identity.js';

/**
 * Domain-separation prefix for challenge signatures. The relay signs
 * `CHALLENGE_CONTEXT_BYTES || nonce`, never the bare nonce, so a signature
 * produced here can never be mistaken for a signature in some other protocol
 * that signs raw bytes with the same key. iOS MUST verify over the identical
 * byte construction.
 */
export const CHALLENGE_CONTEXT = 'major-tom/relay-identity/v1:';

/** Bounds on the decoded client nonce — enough entropy, but not an open-ended
 *  signing oracle for large attacker-chosen blobs. */
const MIN_NONCE_BYTES = 16;
const MAX_NONCE_BYTES = 64;

interface IdentityDeps {
  identity: RelayIdentity;
}

export function createIdentityRoutes(deps: IdentityDeps): FastifyPluginAsync {
  return async (fastify) => {
    fastify.get('/identity', async () => ({
      alg: 'ed25519',
      publicKey: deps.identity.publicKeyBase64url,
      fingerprint: deps.identity.fingerprint,
    }));

    fastify.post('/identity/challenge', async (request, reply) => {
      const body = request.body as { nonce?: unknown } | undefined;
      const nonceB64 = body?.nonce;
      if (typeof nonceB64 !== 'string' || nonceB64.length === 0) {
        return reply.code(400).send({ error: 'nonce (base64 string) is required' });
      }

      const nonce = Buffer.from(nonceB64, 'base64');
      if (nonce.length < MIN_NONCE_BYTES || nonce.length > MAX_NONCE_BYTES) {
        return reply
          .code(400)
          .send({ error: `nonce must decode to ${MIN_NONCE_BYTES}-${MAX_NONCE_BYTES} bytes` });
      }

      const message = Buffer.concat([Buffer.from(CHALLENGE_CONTEXT, 'utf-8'), nonce]);
      const signature = deps.identity.sign(message);
      return {
        alg: 'ed25519',
        publicKey: deps.identity.publicKeyBase64url,
        signature: signature.toString('base64'),
      };
    });
  };
}
