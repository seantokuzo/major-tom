import { existsSync, createReadStream } from 'node:fs';
import { join, extname, isAbsolute, relative, resolve } from 'node:path';
import { stat } from 'node:fs/promises';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { logger } from './utils/logger.js';

// ── MIME types ──────────────────────────────────────────────

const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.webmanifest': 'application/manifest+json',
  '.txt': 'text/plain; charset=utf-8',
};

// ── Static file server ──────────────────────────────────────

/**
 * Creates a request handler that serves static files from a directory.
 * Returns `null` if the static directory doesn't exist (graceful fallback).
 *
 * For SPA support, any request that doesn't match a real file gets `index.html`.
 */
export function createStaticHandler(
  staticDir: string,
): ((req: IncomingMessage, res: ServerResponse) => Promise<boolean>) | null {
  const resolvedDir = resolve(staticDir);
  const indexPath = join(resolvedDir, 'index.html');

  if (!existsSync(resolvedDir) || !existsSync(indexPath)) {
    logger.info({ staticDir: resolvedDir }, 'Static directory not found — PWA serving disabled');
    return null;
  }

  logger.info({ staticDir: resolvedDir }, 'Serving PWA static files');

  return async (req: IncomingMessage, res: ServerResponse): Promise<boolean> => {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      return false;
    }

    const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);
    let pathname: string;
    try {
      pathname = decodeURIComponent(url.pathname);
    } catch {
      res.writeHead(400);
      res.end('Bad request');
      return true;
    }

    // Prevent directory traversal
    if (pathname.includes('..')) {
      res.writeHead(403);
      res.end('Forbidden');
      return true;
    }

    // Try the requested path, then fall back to index.html (SPA)
    let filePath = join(resolvedDir, pathname);

    try {
      const fileStat = await stat(filePath);
      if (fileStat.isDirectory()) {
        filePath = join(filePath, 'index.html');
      }
    } catch {
      // File doesn't exist — SPA fallback to index.html
      filePath = indexPath;
    }

    // Verify the resolved path is within the static dir (safety check)
    const realPath = resolve(filePath);
    const rel = relative(resolvedDir, realPath);
    if (rel.startsWith('..') || isAbsolute(rel) || resolve(resolvedDir, rel) !== realPath) {
      res.writeHead(403);
      res.end('Forbidden');
      return true;
    }

    try {
      await stat(realPath);
    } catch {
      // Even the fallback doesn't exist (shouldn't happen, but be safe)
      return false;
    }

    const ext = extname(realPath).toLowerCase();
    const contentType = MIME_TYPES[ext] ?? 'application/octet-stream';

    if (req.method === 'HEAD') {
      res.writeHead(200, { 'Content-Type': contentType });
      res.end();
      return true;
    }

    const stream = createReadStream(realPath);
    stream.on('open', () => {
      res.writeHead(200, { 'Content-Type': contentType });
      stream.pipe(res);
    });
    stream.on('error', () => {
      if (!res.headersSent) {
        res.writeHead(500);
        res.end('Internal server error');
      } else {
        res.destroy();
      }
    });

    return true;
  };
}
