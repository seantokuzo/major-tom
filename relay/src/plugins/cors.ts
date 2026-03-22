import type { FastifyPluginAsync } from 'fastify';
import cors from '@fastify/cors';

/**
 * CORS plugin — dynamic origin from CORS_ORIGINS env var.
 * Supports credentials (cookies) for session auth.
 */
export const corsPlugin: FastifyPluginAsync = async (fastify) => {
  const originsEnv = process.env['CORS_ORIGINS'];
  let allowedOrigins: string[] | null = null;

  if (originsEnv) {
    allowedOrigins = originsEnv
      .split(',')
      .map((o) => o.trim())
      .filter((o) => o.length > 0);
    if (allowedOrigins.length === 0) allowedOrigins = null;
  }

  await fastify.register(cors, {
    credentials: true,
    origin: (origin, cb) => {
      // No origin header = same-origin or non-browser (allow)
      if (!origin) return cb(null, true);
      // No whitelist configured = allow all
      if (!allowedOrigins || allowedOrigins.includes('*')) return cb(null, true);
      // Check whitelist
      if (allowedOrigins.includes(origin)) return cb(null, true);
      cb(new Error('CORS origin not allowed'), false);
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  });
};
