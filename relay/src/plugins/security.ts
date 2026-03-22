import type { FastifyPluginAsync } from 'fastify';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';

/**
 * Security headers (helmet) + global rate limiting.
 */
export const securityPlugin: FastifyPluginAsync = async (fastify) => {
  // Security headers
  await fastify.register(helmet, {
    global: true,
    contentSecurityPolicy: {
      useDefaults: false,
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'", "'unsafe-inline'", 'https://accounts.google.com', 'https://apis.google.com'],
        styleSrc: ["'self'", "'unsafe-inline'", 'https://accounts.google.com'],
        frameSrc: ['https://accounts.google.com'],
        connectSrc: ["'self'", 'wss:', 'ws:'],
        imgSrc: ["'self'", 'data:', 'https:'],
        fontSrc: ["'self'"],
        objectSrc: ["'none'"],
        baseUri: ["'self'"],
        formAction: ["'self'"],
      },
    },
    hsts: {
      maxAge: 31536000,
      includeSubDomains: true,
    },
    frameguard: { action: 'deny' },
    referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
  });

  // Global rate limiting (generous defaults, tightened per-route)
  await fastify.register(rateLimit, {
    global: true,
    max: 200,
    timeWindow: '1 minute',
    keyGenerator: (request) =>
      (request.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim()
      || request.ip,
  });
};
