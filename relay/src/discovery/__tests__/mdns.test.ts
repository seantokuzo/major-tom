/**
 * Regression coverage for the mDNS crash (see fix/relay-mdns-crash).
 *
 * bonjour-service's default error callback is `(err) => { throw err; }`, and the
 * multicast socket reports failures asynchronously — so a routine
 * `send EHOSTUNREACH 224.0.0.251:5353` used to surface as an uncaught exception
 * and kill the whole relay process. These tests pin the contract that made that
 * possible: an error callback is always supplied, it never rethrows, and
 * `startMdns` always hands back a handle whose `stop()` is safe.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { networkInterfaces } from 'node:os';

/** Captures what the module under test passed to `new Bonjour(...)`. */
interface Capture {
  opts: unknown;
  errorCallback: ((err: unknown) => void) | undefined;
}

const captures: Capture[] = [];

/** Behaviour switches for the fake bonjour-service, reset per test. */
const fake = {
  constructorThrows: false,
  publishThrows: false,
  destroyThrows: false,
  /** `undefined` reproduces bonjour-service marking `Service.stop` optional. */
  stopImpl: undefined as ((cb: () => void) => void) | undefined,
  destroyCalls: 0,
};

vi.mock('bonjour-service', () => {
  class Bonjour {
    constructor(opts?: unknown, errorCallback?: (err: unknown) => void) {
      captures.push({ opts, errorCallback });
      if (fake.constructorThrows) throw new Error('multicast-dns refused these options');
    }

    publish() {
      if (fake.publishThrows) throw new Error('publish blew up');
      return { stop: fake.stopImpl };
    }

    destroy() {
      fake.destroyCalls++;
      if (fake.destroyThrows) throw new Error('destroy blew up');
    }
  }
  return { Bonjour, Service: class {} };
});

const { startMdns } = await import('../mdns.js');

/** The error callback handed to the most recent `new Bonjour(...)`. */
function lastErrorCallback(): (err: unknown) => void {
  const last = captures.at(-1);
  expect(last, 'expected startMdns to construct a Bonjour instance').toBeDefined();
  // The whole point of the fix: never let bonjour-service fall back to its
  // throwing default callback.
  expect(last?.errorCallback, 'startMdns must always supply an error callback').toBeTypeOf('function');
  return last?.errorCallback as (err: unknown) => void;
}

function errno(code: string): NodeJS.ErrnoException {
  const err: NodeJS.ErrnoException = new Error(`send ${code} 224.0.0.251:5353`);
  err.code = code;
  return err;
}

const ENV_KEYS = ['MAJORTOM_MDNS_INTERFACE', 'MAJORTOM_RELAY_NAME'] as const;
const savedEnv: Record<string, string | undefined> = {};

beforeEach(() => {
  captures.length = 0;
  fake.constructorThrows = false;
  fake.publishThrows = false;
  fake.destroyThrows = false;
  fake.stopImpl = (cb: () => void) => cb();
  fake.destroyCalls = 0;
  for (const k of ENV_KEYS) {
    savedEnv[k] = process.env[k];
    delete process.env[k];
  }
});

afterEach(() => {
  for (const k of ENV_KEYS) {
    if (savedEnv[k] === undefined) delete process.env[k];
    else process.env[k] = savedEnv[k];
  }
});

describe('startMdns — socket errors must never kill the relay', () => {
  it('supplies an error callback instead of bonjour-service’s throwing default', () => {
    startMdns(9090, 'fp123');
    expect(lastErrorCallback()).toBeTypeOf('function');
  });

  it('swallows the EHOSTUNREACH that used to crash the process', () => {
    startMdns(9090, 'fp123');
    const onError = lastErrorCallback();
    // This is the exact failure from the live incident.
    expect(() => onError(errno('EHOSTUNREACH'))).not.toThrow();
  });

  it.each(['EHOSTUNREACH', 'ENETUNREACH', 'EACCES', 'EPERM'])(
    'swallows repeated %s without throwing (socket re-reports every send)',
    (code) => {
      startMdns(9090, 'fp123');
      const onError = lastErrorCallback();
      for (let i = 0; i < 6; i++) {
        expect(() => onError(errno(code))).not.toThrow();
      }
    },
  );

  it('swallows unrecognised and non-Error values too', () => {
    startMdns(9090, 'fp123');
    const onError = lastErrorCallback();
    expect(() => onError(errno('ESOMETHINGELSE'))).not.toThrow();
    expect(() => onError(new Error('no code at all'))).not.toThrow();
    expect(() => onError('a bare string')).not.toThrow();
    expect(() => onError(undefined)).not.toThrow();
  });

  it('keeps a usable handle after a socket failure and stop() resolves', async () => {
    const handle = startMdns(9090, 'fp123');
    lastErrorCallback()(errno('EHOSTUNREACH'));
    await expect(handle.stop()).resolves.toBeUndefined();
    expect(fake.destroyCalls).toBe(1);
  });
});

describe('startMdns — degrades instead of throwing', () => {
  it('returns an inert but usable handle when the responder cannot be constructed', async () => {
    fake.constructorThrows = true;
    const handle = startMdns(9090, 'fp123');
    expect(handle.stop).toBeTypeOf('function');
    await expect(handle.stop()).resolves.toBeUndefined();
  });

  it('returns a usable handle when publish() throws', async () => {
    fake.publishThrows = true;
    const handle = startMdns(9090, 'fp123');
    await expect(handle.stop()).resolves.toBeUndefined();
    // Still tore the responder down even though no service was published.
    expect(fake.destroyCalls).toBe(1);
  });

  it('stop() resolves when the service exposes no stop method', async () => {
    fake.stopImpl = undefined;
    const handle = startMdns(9090, 'fp123');
    await expect(handle.stop()).resolves.toBeUndefined();
  });

  it('stop() does not throw when teardown fails, so shutdown continues', async () => {
    fake.destroyThrows = true;
    const handle = startMdns(9090, 'fp123');
    await expect(handle.stop()).resolves.toBeUndefined();
  });

  it('is safe to call stop() more than once', async () => {
    const handle = startMdns(9090, 'fp123');
    await expect(handle.stop()).resolves.toBeUndefined();
    await expect(handle.stop()).resolves.toBeUndefined();
  });
});

describe('startMdns — MAJORTOM_MDNS_INTERFACE', () => {
  /** A real external IPv4 interface on this host, if one exists. */
  function realInterface(): { name: string; address: string } | undefined {
    for (const [name, addrs] of Object.entries(networkInterfaces())) {
      for (const a of addrs ?? []) {
        if (a.family === 'IPv4' && !a.internal) return { name, address: a.address };
      }
    }
    return undefined;
  }

  it('passes no options when unset, preserving library default behaviour', () => {
    startMdns(9090, 'fp123');
    expect(captures.at(-1)?.opts).toBeUndefined();
  });

  it('ignores an interface that does not exist on this host', () => {
    process.env['MAJORTOM_MDNS_INTERFACE'] = 'definitely-not-an-interface-42';
    startMdns(9090, 'fp123');
    // Falls back to auto rather than binding a dead address.
    expect(captures.at(-1)?.opts).toBeUndefined();
  });

  it('ignores a blank value', () => {
    process.env['MAJORTOM_MDNS_INTERFACE'] = '   ';
    startMdns(9090, 'fp123');
    expect(captures.at(-1)?.opts).toBeUndefined();
  });

  it('resolves an interface name to its IPv4 address and pins bind to 0.0.0.0', () => {
    const iface = realInterface();
    if (iface === undefined) return; // no external IPv4 (isolated CI container)
    process.env['MAJORTOM_MDNS_INTERFACE'] = iface.name;
    startMdns(9090, 'fp123');
    // `bind` must accompany `interface`: multicast-dns would otherwise bind the
    // socket to the unicast address, which stops multicast reception on BSD.
    expect(captures.at(-1)?.opts).toEqual({ interface: iface.address, bind: '0.0.0.0' });
  });

  it('accepts a literal IPv4 address that exists on this host', () => {
    const iface = realInterface();
    if (iface === undefined) return;
    process.env['MAJORTOM_MDNS_INTERFACE'] = iface.address;
    startMdns(9090, 'fp123');
    expect(captures.at(-1)?.opts).toEqual({ interface: iface.address, bind: '0.0.0.0' });
  });
});
