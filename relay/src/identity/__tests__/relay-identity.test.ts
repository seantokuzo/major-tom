import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createHash, createPublicKey, randomBytes, verify } from 'node:crypto';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { RelayIdentity } from '../relay-identity.js';

let baseDir: string;
let idFile: string;

beforeEach(async () => {
  baseDir = await mkdtemp(join(tmpdir(), 'relay-identity-'));
  idFile = join(baseDir, 'relay-identity.json');
});

afterEach(async () => {
  await rm(baseDir, { recursive: true, force: true });
});

/** Rebuild a verify-only public key from the base64url raw key the relay exposes. */
function publicKeyFrom(b64u: string) {
  return createPublicKey({ key: { kty: 'OKP', crv: 'Ed25519', x: b64u }, format: 'jwk' });
}

describe('RelayIdentity', () => {
  it('generates and persists a keypair on first load', async () => {
    const id = await RelayIdentity.load(idFile);
    expect(id.publicKeyBase64url).toMatch(/^[A-Za-z0-9_-]+$/);
    expect(Buffer.from(id.publicKeyBase64url, 'base64url')).toHaveLength(32);
    expect(id.fingerprint).toMatch(/^[A-Za-z0-9_-]+$/);

    const raw = JSON.parse(await readFile(idFile, 'utf-8')) as {
      alg: string;
      privateKeyPem: string;
    };
    expect(raw.alg).toBe('ed25519');
    expect(raw.privateKeyPem).toContain('BEGIN PRIVATE KEY');
  });

  it('is stable across reloads — same fingerprint + public key', async () => {
    const a = await RelayIdentity.load(idFile);
    const b = await RelayIdentity.load(idFile);
    expect(b.fingerprint).toBe(a.fingerprint);
    expect(b.publicKeyBase64url).toBe(a.publicKeyBase64url);
  });

  it('fingerprint is base64url(sha256(public key))', async () => {
    const id = await RelayIdentity.load(idFile);
    const expected = createHash('sha256')
      .update(Buffer.from(id.publicKeyBase64url, 'base64url'))
      .digest('base64url');
    expect(id.fingerprint).toBe(expected);
  });

  it('sign() produces a 64-byte signature that verifies against the public key', async () => {
    const id = await RelayIdentity.load(idFile);
    const msg = randomBytes(32);
    const sig = id.sign(msg);
    expect(sig).toHaveLength(64);
    expect(verify(null, msg, publicKeyFrom(id.publicKeyBase64url), sig)).toBe(true);
    // A different message must not verify against the same signature.
    expect(verify(null, randomBytes(32), publicKeyFrom(id.publicKeyBase64url), sig)).toBe(false);
  });

  it('regenerates (no throw) when the file is corrupt JSON', async () => {
    const first = await RelayIdentity.load(idFile);
    await writeFile(idFile, 'not json at all', 'utf-8');
    const second = await RelayIdentity.load(idFile);
    expect(second.fingerprint).not.toBe(first.fingerprint);
    const raw = JSON.parse(await readFile(idFile, 'utf-8')) as { alg: string };
    expect(raw.alg).toBe('ed25519');
  });

  it('regenerates (no throw) when the schema is wrong', async () => {
    await writeFile(
      idFile,
      JSON.stringify({ version: 1, alg: 'rsa', privateKeyPem: 123 }),
      'utf-8',
    );
    const id = await RelayIdentity.load(idFile);
    expect(id.publicKeyBase64url).toBeTruthy();
  });
});
