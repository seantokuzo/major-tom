/**
 * Integration tests for `/api/relay-config`.
 *
 * Stands up a real Fastify instance with the auth plugin so the
 * `requireSession` preHandler runs against actual JWT verification.
 * Tests cover:
 *   - 401 when no session cookie
 *   - GET returns the persisted config
 *   - PATCH updates the persisted config and rejects invalid values
 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';
import cookie from '@fastify/cookie';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { authPlugin } from '../../plugins/auth.js';
import { createSessionToken, SESSION_COOKIE } from '../../auth/session.js';
import { createRelayConfigRoutes } from '../relay-config.js';
import { RelayConfigStore } from '../../config/relay-config.js';

let app: FastifyInstance;
let baseDir: string;
let configFile: string;
let store: RelayConfigStore;
let cookieHeader: string;

beforeEach(async () => {
  process.env['SESSION_SECRET'] = 'test-relay-config-secret-must-be-32-bytes!!';
  baseDir = await mkdtemp(join(tmpdir(), 'relay-config-route-'));
  configFile = join(baseDir, 'relay-config.json');
  store = new RelayConfigStore(configFile);
  await store.load();

  app = Fastify({ logger: false });
  await app.register(cookie);
  await app.register(authPlugin);
  await app.register(createRelayConfigRoutes({ configStore: store }));
  await app.ready();

  const token = await createSessionToken('test-user', 'tester@example.com', 'user-1', 'admin');
  cookieHeader = `${SESSION_COOKIE}=${token}`;
});

afterEach(async () => {
  await app.close();
  await rm(baseDir, { recursive: true, force: true });
});

describe('GET /api/relay-config', () => {
  it('rejects unauthenticated requests with 401', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/relay-config' });
    expect(res.statusCode).toBe(401);
  });

  it('returns an empty config when nothing is persisted', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/relay-config',
      headers: { cookie: cookieHeader },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({});
  });

  it('returns the persisted defaultSpawnCwd', async () => {
    await store.save({ defaultSpawnCwd: baseDir });
    const res = await app.inject({
      method: 'GET',
      url: '/api/relay-config',
      headers: { cookie: cookieHeader },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ defaultSpawnCwd: baseDir });
  });
});

describe('PATCH /api/relay-config', () => {
  it('rejects unauthenticated requests with 401', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: '/api/relay-config',
      payload: { defaultSpawnCwd: baseDir },
    });
    expect(res.statusCode).toBe(401);
  });

  it('persists a valid defaultSpawnCwd', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: '/api/relay-config',
      headers: { cookie: cookieHeader, 'content-type': 'application/json' },
      payload: { defaultSpawnCwd: baseDir },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ defaultSpawnCwd: baseDir });

    const fresh = new RelayConfigStore(configFile);
    const loaded = await fresh.load();
    expect(loaded.defaultSpawnCwd).toBe(baseDir);
  });

  it('clears defaultSpawnCwd when null is sent', async () => {
    await store.save({ defaultSpawnCwd: baseDir });
    const res = await app.inject({
      method: 'PATCH',
      url: '/api/relay-config',
      headers: { cookie: cookieHeader, 'content-type': 'application/json' },
      payload: { defaultSpawnCwd: null },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({});

    const fresh = new RelayConfigStore(configFile);
    const loaded = await fresh.load();
    expect(loaded.defaultSpawnCwd).toBeUndefined();
  });

  it('rejects defaultSpawnCwd that does not exist with 400', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: '/api/relay-config',
      headers: { cookie: cookieHeader, 'content-type': 'application/json' },
      payload: { defaultSpawnCwd: '/no/such/dir/major-tom/test' },
    });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toHaveProperty('error');
  });

  it('rejects defaultSpawnCwd that points at a file with 400', async () => {
    const filePath = join(baseDir, 'not-a-dir.txt');
    await writeFile(filePath, 'hi', 'utf-8');
    const res = await app.inject({
      method: 'PATCH',
      url: '/api/relay-config',
      headers: { cookie: cookieHeader, 'content-type': 'application/json' },
      payload: { defaultSpawnCwd: filePath },
    });
    expect(res.statusCode).toBe(400);
  });

  it('rejects non-string defaultSpawnCwd with 400', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: '/api/relay-config',
      headers: { cookie: cookieHeader, 'content-type': 'application/json' },
      payload: { defaultSpawnCwd: 12345 },
    });
    expect(res.statusCode).toBe(400);
  });

  it('rejects non-object body with 400', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: '/api/relay-config',
      headers: { cookie: cookieHeader, 'content-type': 'application/json' },
      payload: 'not-an-object',
    });
    expect(res.statusCode).toBe(400);
  });

  it('returns 500 when the disk write fails (does not silently claim success)', async () => {
    // Build an isolated app whose store points at a file path nested
    // INSIDE an existing file — `writeFile` rejects with ENOTDIR. Without
    // the `kind === 'io'` branch added in the disk-write fix, the route
    // would return 200 + the new value while disk has the old value.
    const sentinel = join(baseDir, 'sentinel.txt');
    await writeFile(sentinel, 'hi', 'utf-8');
    const blockedStore = new RelayConfigStore(join(sentinel, 'cfg.json'));
    await blockedStore.load();

    const blockedApp = Fastify({ logger: false });
    await blockedApp.register(cookie);
    await blockedApp.register(authPlugin);
    await blockedApp.register(createRelayConfigRoutes({ configStore: blockedStore }));
    await blockedApp.ready();
    try {
      const res = await blockedApp.inject({
        method: 'PATCH',
        url: '/api/relay-config',
        headers: { cookie: cookieHeader, 'content-type': 'application/json' },
        payload: { defaultSpawnCwd: baseDir },
      });
      expect(res.statusCode).toBe(500);
      expect(res.json()).toHaveProperty('error');
    } finally {
      await blockedApp.close();
    }
  });

  it('ignores unknown fields without rejecting', async () => {
    // PATCH should be permissive on unknown keys so future fields can land
    // without breaking older clients. Only the validated subset is
    // persisted.
    const res = await app.inject({
      method: 'PATCH',
      url: '/api/relay-config',
      headers: { cookie: cookieHeader, 'content-type': 'application/json' },
      payload: { defaultSpawnCwd: baseDir, unknownField: 'whatever' },
    });
    expect(res.statusCode).toBe(200);
    const persisted = await new RelayConfigStore(configFile).load();
    expect(persisted).toEqual({ defaultSpawnCwd: baseDir });
  });
});
