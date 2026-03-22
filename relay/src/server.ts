/**
 * Major Tom Relay Server — Entry Point
 *
 * Starts the Fastify server with all plugins and routes.
 * Handles graceful shutdown on SIGINT/SIGTERM.
 */
import { buildApp } from './app.js';

const PORT = parseInt(process.env['WS_PORT'] ?? '9090', 10);
const CLAUDE_WORK_DIR = process.env['CLAUDE_WORK_DIR'] ?? process.cwd();

async function main() {
  let app;
  try {
    app = await buildApp({
      port: PORT,
      claudeWorkDir: CLAUDE_WORK_DIR,
    });
  } catch (err) {
    console.error('Failed to build app:', err);
    process.exit(1);
  }

  // Graceful shutdown
  const shutdown = async (signal: string) => {
    app.log.info({ signal }, 'Received shutdown signal');
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
    console.log(` Auth:      Google OAuth (${process.env['ALLOWED_EMAIL'] ?? 'ALLOWED_EMAIL not set'})`);
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
