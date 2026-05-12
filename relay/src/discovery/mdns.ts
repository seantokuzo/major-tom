/**
 * mDNS / Bonjour advertise for the relay.
 *
 * Advertises `_majortom._tcp.local.` so the iOS app can discover the relay
 * by name on the local network without the user typing the Mac's LAN IP
 * (which drifts on DHCP renewal — see PHASE-PAIRING-REBOOT).
 */
import { Bonjour, type Service } from 'bonjour-service';
import { logger } from '../utils/logger.js';

const log = logger.child({ module: 'mdns' });

const SERVICE_TYPE = 'majortom';
const DEFAULT_NAME = 'Major Tom Relay';
const STOP_TIMEOUT_MS = 1_000;

export interface MdnsHandle {
  stop: () => Promise<void>;
}

export function startMdns(port: number): MdnsHandle {
  const bonjour = new Bonjour();
  // Default to a generic label so the relay's mDNS broadcast doesn't leak
  // the OS hostname on every Wi-Fi it touches. `MAJORTOM_RELAY_NAME` lets
  // multi-host setups distinguish their relays explicitly.
  const instanceName = process.env['MAJORTOM_RELAY_NAME']?.trim() || DEFAULT_NAME;

  let service: Service | undefined;
  try {
    service = bonjour.publish({
      name: instanceName,
      type: SERVICE_TYPE,
      port,
      txt: {
        version: '1',
        protocol: 'ws',
      },
    });
    log.info({ name: instanceName, port, type: `_${SERVICE_TYPE}._tcp` }, 'mDNS service published');
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
      bonjour.destroy();
    },
  };
}
