import type { IncomingMessage, ServerResponse } from 'node:http';

/**
 * Read the full request body as a UTF-8 string, with a size limit to prevent DoS.
 */
export function readBody(req: IncomingMessage, maxBytes = 65_536): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > maxBytes) {
        req.destroy();
        reject(Object.assign(new Error('Request body too large'), { code: 'BODY_TOO_LARGE' }));
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf-8')));
    req.on('error', reject);
  });
}

/**
 * Send a JSON response with optional CORS origin header.
 */
export function sendJson(
  res: ServerResponse,
  status: number,
  body: unknown,
  corsOrigin?: string,
): void {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (corsOrigin) {
    headers['Access-Control-Allow-Origin'] = corsOrigin;
    if (corsOrigin !== '*') {
      headers['Vary'] = 'Origin';
    }
  }
  res.writeHead(status, headers);
  res.end(JSON.stringify(body));
}

/**
 * Validate the request's Origin header against a whitelist.
 * Returns the matching origin string, or null if no match.
 * A whitelist containing '*' matches any origin.
 */
export function getCorsOrigin(req: IncomingMessage, allowedOrigins: string[]): string | null {
  if (allowedOrigins.includes('*')) return '*';
  const origin = req.headers['origin'];
  if (!origin) return null;
  return allowedOrigins.includes(origin) ? origin : null;
}

/**
 * Check the Authorization header for a valid Bearer token.
 */
export function requireAuth(req: IncomingMessage, token: string): boolean {
  const auth = req.headers['authorization'];
  if (!auth) return false;
  return auth === `Bearer ${token}`;
}
