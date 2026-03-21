import { pinManager } from '../auth/pin-manager.js';

const POLL_INTERVAL_MS = 1_000;

/**
 * Run the CLI pair mode: generate a PIN, display it, and wait for it to be claimed.
 */
export async function runPairMode(): Promise<void> {
  const { pin, expiresAt } = pinManager.generatePin();
  const expiryMs = expiresAt.getTime() - Date.now();

  console.log('\n  ┌─────────────────────────────────┐');
  console.log('  │       Major Tom — Pair Device    │');
  console.log('  ├─────────────────────────────────┤');
  console.log(`  │                                 │`);
  console.log(`  │         PIN:  ${pin}            │`);
  console.log(`  │                                 │`);
  console.log(`  │   Expires in ${Math.ceil(expiryMs / 1000)}s              │`);
  console.log('  └─────────────────────────────────┘\n');
  console.log('  Enter this PIN in your Major Tom app to pair.\n');

  return new Promise<void>((resolve) => {
    const timer = setInterval(() => {
      const status = pinManager.getClaimStatus();

      if (status.claimed) {
        clearInterval(timer);
        console.log(`  Device paired successfully: ${status.deviceName ?? 'unknown'}`);
        console.log('  You can close this terminal.\n');
        resolve();
        return;
      }

      if (!pinManager.isActive()) {
        clearInterval(timer);
        console.log('  PIN expired. Run `node dist/server.js pair` to generate a new one.\n');
        resolve();
        return;
      }

      const remaining = Math.ceil((expiresAt.getTime() - Date.now()) / 1000);
      process.stdout.write(`\r  Waiting for pairing... ${remaining}s remaining  `);
    }, POLL_INTERVAL_MS);
  });
}
