/**
 * mDNS / Bonjour advertise for the relay.
 *
 * Advertises `_majortom._tcp.local.` so the iOS app can discover the relay
 * by name on the local network without the user typing the Mac's LAN IP
 * (which drifts on DHCP renewal — see PHASE-PAIRING-REBOOT).
 */
import { Bonjour, type Service } from 'bonjour-service';
import { hostname } from 'node:os';
import { logger } from '../utils/logger.js';

const log = logger.child({ module: 'mdns' });

const SERVICE_TYPE = 'majortom';

export interface MdnsHandle {
  stop: () => Promise<void>;
}

export function startMdns(port: number): MdnsHandle {
  const bonjour = new Bonjour();
  const instanceName = `Major Tom Relay (${hostname()})`;

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
      if (service?.stop) {
        await new Promise<void>((resolve) => {
          service!.stop!(() => resolve());
        });
      }
      bonjour.destroy();
    },
  };
}
