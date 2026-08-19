/**
 * mDNS / Bonjour advertise for the relay.
 *
 * Advertises `_majortom._tcp.local.` so the iOS app can discover the relay
 * by name on the local network without the user typing the Mac's LAN IP
 * (which drifts on DHCP renewal — see PHASE-PAIRING-REBOOT).
 *
 * Discovery is a CONVENIENCE, never a dependency: the relay is still fully
 * reachable over the tunnel and by explicit host:port when mDNS is dead. So
 * every failure in here degrades to a warning — nothing in this module may
 * take the process down.
 */
import { networkInterfaces } from 'node:os';
import { Bonjour, type Service, type ServiceConfig } from 'bonjour-service';
import { logger } from '../utils/logger.js';

const log = logger.child({ module: 'mdns' });

const SERVICE_TYPE = 'majortom';
const DEFAULT_NAME = 'Major Tom Relay';
const STOP_TIMEOUT_MS = 1_000;

/**
 * Error codes that mean "this host cannot put multicast on the wire". They are
 * reported asynchronously by the dgram socket, one per send attempt, so they
 * arrive repeatedly once discovery is broken.
 *
 * On macOS 15+ these are also what an un-approved binary gets when the OS
 * denies it Local Network access — the send fails at the kernel with
 * EHOSTUNREACH even though routing is perfectly healthy.
 */
const MULTICAST_BLOCKED_CODES = new Set(['EHOSTUNREACH', 'ENETUNREACH', 'EACCES', 'EPERM']);

export interface MdnsHandle {
  stop: () => Promise<void>;
}

/**
 * bonjour-service types the constructor's first argument as
 * `Partial<ServiceConfig>`, but that type is a lie about runtime behaviour: the
 * object is forwarded verbatim to `multicast-dns`
 * (`bonjour-service/dist/lib/mdns-server.js` → `multicast_dns(opts)`).
 * `interface` and `bind` are multicast-dns options that bonjour-service's
 * published types simply don't model.
 *
 * Verified against bonjour-service@1.3.0 and multicast-dns@7.2.5. `interface`
 * selects which local address gets `addMembership` + `setMulticastInterface`;
 * `bind` selects the socket bind address, defaulting to `opts.interface` — which
 * is why we always pass `bind: '0.0.0.0'` alongside it (see resolveMdnsOptions).
 */
interface MulticastDnsOptions extends Partial<ServiceConfig> {
  interface?: string;
  bind?: string;
}

/** Narrow an unknown thrown value to a Node `errno` code without asserting. */
function errorCode(err: unknown): string | undefined {
  if (typeof err === 'object' && err !== null && 'code' in err) {
    const code = (err as { code: unknown }).code;
    if (typeof code === 'string') return code;
  }
  return undefined;
}

/**
 * Resolve `MAJORTOM_MDNS_INTERFACE` to a local IPv4 address.
 *
 * Accepts either an interface NAME (`en0`, `eth0`, `enp3s0`) or a literal IPv4
 * address. Returns `undefined` when unset or unresolvable, which leaves
 * multicast-dns on its default behaviour (join every IPv4 interface).
 *
 * This is deliberately OPT-IN rather than auto-selected. Auto-pinning an
 * interface is not a safe default: multicast-dns uses `opts.interface` as the
 * socket BIND address too, and a socket bound to a specific unicast address does
 * not receive multicast on macOS/BSD — so auto-pinning would silently stop the
 * relay answering discovery queries. Operators of genuinely multi-homed hosts
 * (the Linux team-server mode) get the knob; single-homed hosts need nothing.
 */
function resolveMdnsInterface(): string | undefined {
  const raw = process.env['MAJORTOM_MDNS_INTERFACE']?.trim();
  if (raw === undefined || raw === '') return undefined;

  const ifaces = networkInterfaces();

  // Exact interface-name match — resolve to its first non-internal IPv4.
  const byName = ifaces[raw];
  if (byName !== undefined) {
    const v4 = byName.find((a) => a.family === 'IPv4' && !a.internal);
    if (v4 !== undefined) {
      log.info({ name: raw, address: v4.address }, 'mDNS bound to configured interface');
      return v4.address;
    }
    log.warn(
      { name: raw },
      'MAJORTOM_MDNS_INTERFACE names an interface with no external IPv4 address — ignoring, falling back to auto',
    );
    return undefined;
  }

  // Literal address — only accept it if it actually exists on this host,
  // otherwise multicast-dns binds to a dead address and discovery goes silent.
  for (const addrs of Object.values(ifaces)) {
    for (const a of addrs ?? []) {
      if (a.family === 'IPv4' && a.address === raw) {
        log.info({ address: raw }, 'mDNS bound to configured interface address');
        return raw;
      }
    }
  }

  log.warn(
    { value: raw },
    'MAJORTOM_MDNS_INTERFACE matches no local interface name or IPv4 address — ignoring, falling back to auto',
  );
  return undefined;
}

/** Build the multicast-dns options, pairing `interface` with an explicit bind. */
function resolveMdnsOptions(): MulticastDnsOptions | undefined {
  const iface = resolveMdnsInterface();
  if (iface === undefined) return undefined;
  // `bind` MUST accompany `interface`: multicast-dns falls back to
  // `opts.bind || opts.interface` for the socket bind address, and binding to a
  // unicast address stops multicast reception on macOS/BSD.
  return { interface: iface, bind: '0.0.0.0' };
}

export function startMdns(port: number, fingerprint?: string): MdnsHandle {
  const instanceName = process.env['MAJORTOM_RELAY_NAME']?.trim() || DEFAULT_NAME;
  const opts = resolveMdnsOptions();
  const ifaceLabel = opts?.interface ?? 'auto';

  // One loud warning per process, then silence. The socket re-reports the same
  // failure on every announce and every query response, so logging each one
  // buries the rest of the relay's output.
  let blockedWarningLogged = false;
  const onSocketError = (err: unknown) => {
    const code = errorCode(err);
    if (code !== undefined && MULTICAST_BLOCKED_CODES.has(code)) {
      if (!blockedWarningLogged) {
        blockedWarningLogged = true;
        log.warn(
          { err, code, interface: ifaceLabel, service: `_${SERVICE_TYPE}._tcp` },
          'mDNS multicast is BLOCKED on this host — LAN auto-discovery is DOWN. ' +
            'The relay is unaffected otherwise: the tunnel and explicit host:port still work, ' +
            'but the iOS app cannot find this relay by itself and will fall back to the tunnel. ' +
            'On macOS 15+ this is usually the Local Network privacy gate: grant Local Network ' +
            'access to the app running the relay (System Settings > Privacy & Security > Local Network). ' +
            'On a multi-homed host, set MAJORTOM_MDNS_INTERFACE to the LAN interface name or IPv4 address.',
        );
      }
      return;
    }
    // Anything else is unexpected — surface it, but still never throw.
    log.warn({ err, code, interface: ifaceLabel }, 'mDNS socket error — discovery degraded, relay continues');
  };

  // The second constructor arg is bonjour-service's error callback. Its DEFAULT
  // is `(err) => { throw err; }` (bonjour-service/dist/lib/mdns-server.js), and
  // the multicast socket reports failures ASYNCHRONOUSLY — so a
  // `send EHOSTUNREACH 224.0.0.251:5353` becomes an uncaught exception that
  // kills the entire relay. The try/catch below cannot help with that: it only
  // catches synchronous throws.
  let bonjour: Bonjour;
  try {
    bonjour = new Bonjour(opts, onSocketError);
  } catch (err) {
    // multicast-dns throws synchronously for some option combinations. Discovery
    // is optional; hand back an inert handle so callers need no special case.
    log.warn({ err, interface: ifaceLabel }, 'Failed to start mDNS responder — discovery disabled, relay continues');
    return { stop: async () => {} };
  }

  let service: Service | undefined;
  try {
    service = bonjour.publish({
      name: instanceName,
      type: SERVICE_TYPE,
      port,
      txt: {
        version: '1',
        protocol: 'ws',
        // Ed25519 public-key fingerprint (base64url sha256). The iOS app pins
        // this at pairing and uses it as a fast discovery FILTER — it is NOT a
        // security boundary, since mDNS TXT is plaintext multicast that any LAN
        // host can echo. Trust is established by the signed /identity/challenge,
        // verified against the pinned public key. Omitted if the relay has no
        // identity (older callers / tests).
        ...(fingerprint !== undefined ? { fp: fingerprint } : {}),
      },
    });
    log.info(
      { name: instanceName, port, type: `_${SERVICE_TYPE}._tcp`, interface: ifaceLabel },
      'mDNS service published',
    );
  } catch (err) {
    log.warn({ err }, 'Failed to publish mDNS service — discovery will not work on this network');
  }

  return {
    stop: async () => {
      const s = service;
      if (s) {
        // Race the stop callback against a deadline so a stalled
        // bonjour-service teardown doesn't hang `app.close()` during
        // shutdown (the next signal would be SIGKILL with state loss).
        // Optional call on `s.stop` matches the bonjour-service type,
        // which marks the method as optional — if it's absent the
        // inner promise never resolves and the timeout wins.
        await Promise.race([
          new Promise<void>((resolve) => { s.stop?.(() => resolve()); }),
          new Promise<void>((resolve) => setTimeout(resolve, STOP_TIMEOUT_MS)),
        ]);
      }
      // Teardown itself must never throw — `stop()` runs on the shutdown path,
      // where an exception would skip `app.close()` and lose session state.
      try {
        bonjour.destroy();
      } catch (err) {
        log.warn({ err }, 'mDNS teardown failed — continuing shutdown');
      }
    },
  };
}
