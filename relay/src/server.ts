/**
 * Major Tom Relay Server — Entry Point
 *
 * Starts the Fastify server with all plugins and routes.
 * Handles graceful shutdown on SIGINT/SIGTERM.
 */
import { writeFileSync, unlinkSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildApp } from './app.js';
import { pinManager } from './auth/pin-manager.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PIN_FILE = resolve(__dirname, '..', '.pin');

const PORT = parseInt(process.env['WS_PORT'] ?? '9090', 10);
// Phase 13 Wave 2 — port for the internal hook HTTP server. Loopback only.
// The shell hook script (`pretooluse.sh`) curls 127.0.0.1:HOOK_PORT/hooks/...
const HOOK_PORT = parseInt(process.env['HOOK_PORT'] ?? '9091', 10);
const CLAUDE_WORK_DIR = process.env['CLAUDE_WORK_DIR'] ?? process.cwd();
const MULTI_USER_ENABLED = (process.env['MULTI_USER_ENABLED'] ?? 'false').toLowerCase() === 'true';
const AUTH_GOOGLE_ENABLED = process.env['AUTH_GOOGLE_ENABLED'] !== undefined
  ? process.env['AUTH_GOOGLE_ENABLED'].toLowerCase() === 'true'
  : !!process.env['GOOGLE_CLIENT_ID'];
const AUTH_PIN_ENABLED = (process.env['AUTH_PIN_ENABLED'] ?? 'true').toLowerCase() === 'true';

async function main() {
  let app;
  try {
    app = await buildApp({
      port: PORT,
      hookPort: HOOK_PORT,
      claudeWorkDir: CLAUDE_WORK_DIR,
      multiUserEnabled: MULTI_USER_ENABLED,
      authGoogleEnabled: AUTH_GOOGLE_ENABLED,
      authPinEnabled: AUTH_PIN_ENABLED,
    });
  } catch (err) {
    console.error('Failed to build app:', err);
    process.exit(1);
  }

  // Graceful shutdown
  const shutdown = async (signal: string) => {
    app.log.info({ signal }, 'Received shutdown signal');
    try { unlinkSync(PIN_FILE); } catch { /* ignore */ }
    await app.close();
    process.exit(0);
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));

  try {
    await app.listen({ port: PORT, host: '0.0.0.0' });

    // Startup info
    console.log('');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(' Major Tom Relay Server');
    console.log('');
    console.log(` Listening: http://0.0.0.0:${PORT}`);
    if (AUTH_GOOGLE_ENABLED) {
      console.log(` Auth:      Google OAuth (${process.env['ALLOWED_EMAIL'] ?? 'ALLOWED_EMAIL not set'})`);
    }
    if (MULTI_USER_ENABLED) {
      console.log(` Mode:      Multi-user enabled`);
    }

    // Auto-generate a pairing PIN on startup (only if PIN auth is enabled)
    if (AUTH_PIN_ENABLED) {
      const { pin, expiresAt } = pinManager.generatePin();
      const expiryMin = Math.ceil((expiresAt.getTime() - Date.now()) / 60_000);

      // Write PIN to file so start.sh can read it for its banner
      try {
        writeFileSync(PIN_FILE, JSON.stringify({ pin, expiresAt: expiresAt.toISOString() }));
      } catch { /* non-critical */ }

      console.log('');
      console.log(` ┌───────────────────────────────┐`);
      console.log(` │     Quick Login PIN: ${pin}    │`);
      console.log(` │     Expires in ${String(expiryMin).padStart(2, ' ')} min          │`);
      console.log(` └───────────────────────────────┘`);
    }

    if (!AUTH_GOOGLE_ENABLED && !AUTH_PIN_ENABLED) {
      console.log('');
      console.log(' ⚠  WARNING: No auth methods enabled!');
    }

    console.log('');
    console.log(' Ctrl+C to stop');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('');
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

main();
