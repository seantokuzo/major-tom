// Relay identity — a persistent Ed25519 keypair stored in
// `~/.major-tom/relay-identity.json`. Gives the relay a stable, verifiable
// identity that is INDEPENDENT of the rotating `SESSION_SECRET` (which has
// its own regenerate footgun) and of the VAPID push key (wrong semantics).
//
// Why it exists: the iOS LAN-preference feature discovers relays over mDNS
// and would otherwise hand the authenticated session cookie to whichever
// host answered `_majortom._tcp` first. mDNS is unauthenticated, so a hostile
// LAN peer could impersonate the relay and harvest the cookie. This keypair
// lets the relay PROVE its identity: the public-key fingerprint is advertised
// (mDNS TXT) and the full key is exposed at `GET /identity`; the app pins it
// at pairing and later challenges a discovered host to sign a fresh nonce
// (`POST /identity/challenge`), verifying the signature against the pinned key
// before trusting it with credentials.
//
// Failure modes (mirrors relay-config.ts):
//   - Missing file  → fresh install, generate + persist (expected).
//   - Corrupt/bad schema / unparseable key → WARN, regenerate. Already-paired
//     devices must re-pair (their pinned key no longer matches). Rare.
//   - I/O failure on save → WARN, NOT thrown. The in-memory key still works
//     for this process; a new key is generated on the next boot.

import {
  createHash,
  createPrivateKey,
  createPublicKey,
  generateKeyPairSync,
  sign,
  type KeyObject,
} from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { logger } from '../utils/logger.js';

const log = logger.child({ module: 'relay-identity' });

export const DEFAULT_IDENTITY_FILE = join(
  homedir(),
  '.major-tom',
  'relay-identity.json',
);

interface PersistedIdentity {
  version: 1;
  alg: 'ed25519';
  /** PKCS#8 PEM of the Ed25519 private key. */
  privateKeyPem: string;
}

/**
 * Loads (or generates) the relay's Ed25519 identity. Construct via the async
 * `RelayIdentity.load()` factory — the constructor is private because key
 * material has to be read/derived before the instance is usable.
 */
export class RelayIdentity {
  private privateKey!: KeyObject;
  /** Raw 32-byte Ed25519 public key. */
  private publicKeyRaw!: Buffer;
  /** base64url of the raw public key — the wire form clients pin. */
  private publicKeyB64u!: string;
  /** base64url of sha256(raw public key) — short stable id for the TXT record. */
  private fingerprintValue!: string;

  private constructor(private readonly path: string) {}

  static async load(path: string = DEFAULT_IDENTITY_FILE): Promise<RelayIdentity> {
    const identity = new RelayIdentity(path);
    await identity.init();
    return identity;
  }

  private async init(): Promise<void> {
    let pem = await this.readPersistedPem();

    if (pem !== undefined) {
      try {
        this.privateKey = createPrivateKey(pem);
      } catch (err) {
        log.warn({ err }, 'relay-identity private key unparseable — regenerating (paired devices must re-pair)');
        pem = undefined;
      }
    }

    if (pem === undefined) {
      const { privateKey } = generateKeyPairSync('ed25519');
      this.privateKey = privateKey;
      const generatedPem = privateKey.export({ type: 'pkcs8', format: 'pem' });
      // `format: 'pem'` always yields a string; the union is just the broad
      // KeyObject.export signature.
      await this.persist(generatedPem as string);
      log.info('Generated new relay identity keypair');
    }

    this.derivePublic();
    log.info({ fingerprint: this.fingerprintValue }, 'Relay identity ready');
  }

  /** Returns the persisted private-key PEM, or undefined to regenerate. */
  private async readPersistedPem(): Promise<string | undefined> {
    let raw: string;
    try {
      raw = await readFile(this.path, 'utf-8');
    } catch (err) {
      const code = errnoCode(err);
      if (code !== 'ENOENT') {
        log.warn({ err, code, path: this.path }, 'relay-identity read failed — regenerating');
      }
      return undefined;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch (err) {
      log.warn({ err, path: this.path }, 'relay-identity.json is invalid JSON — regenerating');
      return undefined;
    }
    if (!isPersistedIdentity(parsed)) {
      log.warn({ path: this.path }, 'relay-identity.json has invalid schema — regenerating (paired devices must re-pair)');
      return undefined;
    }
    return parsed.privateKeyPem;
  }

  private derivePublic(): void {
    const publicKey = createPublicKey(this.privateKey);
    const jwk = publicKey.export({ format: 'jwk' });
    if (typeof jwk.x !== 'string') {
      throw new Error('Failed to derive Ed25519 public key (missing jwk.x)');
    }
    // JWK `x` for an OKP/Ed25519 key is the raw 32-byte public key, base64url.
    this.publicKeyB64u = jwk.x;
    this.publicKeyRaw = Buffer.from(jwk.x, 'base64url');
    this.fingerprintValue = createHash('sha256')
      .update(this.publicKeyRaw)
      .digest('base64url');
  }

  private async persist(pem: string): Promise<void> {
    const data: PersistedIdentity = {
      version: 1,
      alg: 'ed25519',
      privateKeyPem: pem,
    };
    try {
      await mkdir(dirname(this.path), { recursive: true });
      // mode 0600 — the private key must not be world-readable. Applied on
      // create (the only time we write); we never rewrite an existing file.
      await writeFile(this.path, JSON.stringify(data, null, 2), { encoding: 'utf-8', mode: 0o600 });
    } catch (err) {
      log.warn({ err, path: this.path }, 'Failed to persist relay identity — a new key will be generated next boot');
    }
  }

  /** Path the identity reads/writes — exposed for tests + diagnostics. */
  get filePath(): string {
    return this.path;
  }

  /** Raw Ed25519 public key as base64url — the value clients pin. */
  get publicKeyBase64url(): string {
    return this.publicKeyB64u;
  }

  /** base64url(sha256(public key)) — advertised in the mDNS TXT record. */
  get fingerprint(): string {
    return this.fingerprintValue;
  }

  /**
   * Sign arbitrary bytes (a domain-separated client challenge) with the
   * identity private key. Ed25519 → the algorithm argument is null.
   */
  sign(data: Buffer): Buffer {
    return sign(null, data, this.privateKey);
  }
}

function isPersistedIdentity(value: unknown): value is PersistedIdentity {
  if (typeof value !== 'object' || value === null) return false;
  const o = value as Record<string, unknown>;
  return o['alg'] === 'ed25519' && typeof o['privateKeyPem'] === 'string';
}

function errnoCode(err: unknown): string | undefined {
  if (typeof err === 'object' && err !== null && 'code' in err) {
    const code = (err as { code: unknown }).code;
    if (typeof code === 'string') return code;
  }
  return undefined;
}
