import type { FastifyPluginAsync } from 'fastify';
import fastifyStatic from '@fastify/static';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';
import { logger } from '../utils/logger.js';

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Static file serving for the PWA.
 * Serves from web/dist/ with SPA fallback to index.html.
 */
export const staticPlugin: FastifyPluginAsync = async (fastify) => {
  const disabled =
    process.env['NO_STATIC'] === '1' || process.argv.includes('--no-static');

  if (disabled) {
    logger.info('Static file serving disabled');
    return;
  }

  const staticDir = join(__dirname, '..', '..', '..', 'web', 'dist');

  if (!existsSync(staticDir)) {
    logger.warn({ staticDir }, 'Static directory not found — skipping static serving');
    return;
  }

  logger.info({ staticDir }, 'Serving PWA static files');

  await fastify.register(fastifyStatic, {
    root: staticDir,
    cacheControl: true,
    maxAge: '30d',
    immutable: true,
  });

  // SPA fallback: unmatched routes serve index.html
  fastify.setNotFoundHandler((request, reply) => {
    // Don't serve index.html for API-like paths
    if (
      request.url.startsWith('/api/') ||
      request.url.startsWith('/auth/') ||
      request.url.startsWith('/push/') ||
      request.url.startsWith('/ws')
    ) {
      reply.code(404).send({ error: 'Not found' });
      return;
    }
    reply.sendFile('index.html', { maxAge: 0, immutable: false, cacheControl: true });
  });
};
