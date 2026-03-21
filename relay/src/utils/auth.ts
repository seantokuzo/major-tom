import { randomBytes } from 'node:crypto';
import { appendFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { logger } from './logger.js';

/**
 * Load .env file from cwd if present. Respects existing env vars (no override).
 */
function loadDotenv(): void {
  try {
    const envPath = join(process.cwd(), '.env');
    const content = readFileSync(envPath, 'utf-8');
    for (const line of content.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const eqIdx = trimmed.indexOf('=');
      if (eqIdx === -1) continue;
      const key = trimmed.slice(0, eqIdx).trim();
      const value = trimmed.slice(eqIdx + 1).trim();
      // Don't override existing env vars
      if (!(key in process.env)) {
        process.env[key] = value;
      }
    }
  } catch {
    // .env file doesn't exist — that's fine
  }
}

// Load .env on module import
loadDotenv();

/**
 * Read AUTH_TOKEN from process.env. If not set, generate a 32-char hex token,
 * append it to the .env file, print it to console, and return it.
 */
export function getAuthToken(): string {
  const existing = process.env['AUTH_TOKEN'];
  if (existing) {
    logger.info('Auth token loaded from environment');
    return existing;
  }

  const token = randomBytes(16).toString('hex');

  // Append to .env file in the relay directory (cwd)
  try {
    const envPath = join(process.cwd(), '.env');
    appendFileSync(envPath, `\nAUTH_TOKEN=${token}\n`);
    logger.info('Auto-generated auth token appended to .env file');
  } catch {
    logger.warn('Could not write auth token to .env file — using in-memory token only');
  }

  console.log(`\n  AUTH_TOKEN=${token}\n`);
  logger.warn('Auth token auto-generated. Set AUTH_TOKEN in your .env file to persist it.');

  // Also set on process.env so it's available for the rest of this process
  process.env['AUTH_TOKEN'] = token;

  return token;
}

/**
 * Read CORS_ORIGINS from env, split by comma, trim, filter empty.
 * Returns ['*'] if not set (backwards compat for local dev).
 */
export function getAllowedOrigins(): string[] {
  const raw = process.env['CORS_ORIGINS'];
  if (!raw) return ['*'];

  const origins = raw
    .split(',')
    .map((o) => o.trim())
    .filter((o) => o.length > 0);

  return origins.length > 0 ? origins : ['*'];
}
