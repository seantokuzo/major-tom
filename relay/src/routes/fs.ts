/**
 * Filesystem message handlers — sandboxed directory browsing.
 *
 * Handles fs.ls, fs.readFile, and fs.cwd messages from clients.
 * All paths are resolved and validated against the configured sandbox root
 * (FS_SANDBOX_ROOT env var, defaulting to ~/Documents).
 */
import { readdir, readFile, lstat, realpath } from 'node:fs/promises';
import { resolve, join, relative, basename, isAbsolute } from 'node:path';
import { homedir } from 'node:os';
import { WebSocket } from 'ws';
import { logger } from '../utils/logger.js';

// ── Types ────────────────────────────────────────────────────

export interface FsEntry {
  name: string;
  type: 'file' | 'directory' | 'symlink';
  size: number;
  modified: string; // ISO 8601
  permissions?: string;
}

export interface FsLsMessage {
  type: 'fs.ls';
  path: string;
}

export interface FsReadFileMessage {
  type: 'fs.readFile';
  path: string;
}

export interface FsCwdMessage {
  type: 'fs.cwd';
}

export type FsClientMessage = FsLsMessage | FsReadFileMessage | FsCwdMessage;

export interface FsLsResponse {
  type: 'fs.ls.response';
  path: string;
  entries: FsEntry[];
}

export interface FsReadFileResponse {
  type: 'fs.readFile.response';
  path: string;
  content: string;
  size: number;
}

export interface FsCwdResponse {
  type: 'fs.cwd.response';
  path: string;
}

export interface FsErrorResponse {
  type: 'fs.error';
  message: string;
  path?: string;
}

export type FsServerMessage = FsLsResponse | FsReadFileResponse | FsCwdResponse | FsErrorResponse;

// ── Constants ────────────────────────────────────────────────

const MAX_READ_SIZE = 1 * 1024 * 1024; // 1 MB

// ── Sandbox resolution ───────────────────────────────────────

function getSandboxRoot(): string {
  const envRoot = process.env['FS_SANDBOX_ROOT'];
  if (envRoot) {
    // Expand ~ to homedir
    const expanded = envRoot.startsWith('~')
      ? join(homedir(), envRoot.slice(1))
      : envRoot;
    return resolve(expanded);
  }
  return resolve(homedir(), 'Documents');
}

function formatPermissions(mode: number): string {
  const perms = ['---', '--x', '-w-', '-wx', 'r--', 'r-x', 'rw-', 'rwx'];
  const owner = perms[(mode >> 6) & 7]!;
  const group = perms[(mode >> 3) & 7]!;
  const other = perms[mode & 7]!;
  return `${owner}${group}${other}`;
}

/**
 * Check whether `child` is strictly within `parent` using path.relative().
 * Safe against prefix collisions (e.g. /home/u/Documents vs /home/u/Documents_evil).
 */
function isWithinBoundary(parent: string, child: string): boolean {
  const rel = relative(parent, child);
  // Outside the boundary if relative path starts with '..' or is absolute
  return rel !== '' && !rel.startsWith('..') && !isAbsolute(rel);
}

/**
 * Validate that a resolved path is within the sandbox root.
 * Returns the resolved absolute path or null if outside sandbox.
 *
 * @param canonicalRoot - The realpath-resolved sandbox root (for symlink checks)
 */
async function validatePath(requestedPath: string, sandboxRoot: string, canonicalRoot: string): Promise<string | null> {
  // Resolve the path relative to sandbox root
  const resolved = resolve(sandboxRoot, requestedPath);

  // Must be within sandbox root (prevents traversal and prefix attacks)
  if (resolved !== sandboxRoot && !isWithinBoundary(sandboxRoot, resolved)) {
    return null;
  }

  // For symlinks, also verify the real path is within the canonical sandbox root
  try {
    const real = await realpath(resolved);
    if (real !== canonicalRoot && !isWithinBoundary(canonicalRoot, real)) {
      return null;
    }
  } catch {
    // File may not exist yet (that's fine for ls on non-existent dirs)
    // The actual operation will fail with a proper error
  }

  return resolved;
}

/**
 * Sanitize filesystem error messages to avoid leaking absolute paths to clients.
 * Maps common Node error codes to safe messages; falls back to a generic message.
 */
function sanitizeFsError(err: unknown): string {
  if (err instanceof Error) {
    const code = (err as NodeJS.ErrnoException).code;
    switch (code) {
      case 'ENOENT': return 'Path not found';
      case 'EACCES': return 'Permission denied';
      case 'EPERM': return 'Operation not permitted';
      case 'EISDIR': return 'Is a directory';
      case 'ENOTDIR': return 'Not a directory';
      default: return 'Filesystem operation failed';
    }
  }
  return 'Filesystem operation failed';
}

// ── Handlers ─────────────────────────────────────────────────

export function createFsHandlers(sendToClient: (ws: WebSocket, msg: FsServerMessage) => void) {
  const sandboxRoot = getSandboxRoot();

  // Resolve the canonical (realpath) sandbox root once at init for symlink-safe boundary checks
  let canonicalRoot = sandboxRoot;
  realpath(sandboxRoot)
    .then((resolved) => { canonicalRoot = resolved; })
    .catch(() => { /* fall back to raw sandboxRoot */ });

  logger.info({ sandboxRoot }, 'Filesystem sandbox initialized');

  async function handleFsLs(ws: WebSocket, message: FsLsMessage): Promise<void> {
    const requestedPath = message.path || '.';
    const resolved = await validatePath(requestedPath, sandboxRoot, canonicalRoot);

    if (!resolved) {
      sendToClient(ws, {
        type: 'fs.error',
        message: 'Access denied: path is outside sandbox',
        path: requestedPath,
      });
      return;
    }

    try {
      const dirents = await readdir(resolved, { withFileTypes: true });

      // Process directory entries in parallel for better performance
      const visibleDirents = dirents.filter((d) => !d.name.startsWith('.'));
      const settled = await Promise.all(
        visibleDirents.map(async (dirent): Promise<FsEntry | null> => {
          try {
            const fullPath = join(resolved, dirent.name);
            const stat = await lstat(fullPath);

            let entryType: FsEntry['type'] = 'file';
            if (dirent.isDirectory()) {
              entryType = 'directory';
            } else if (dirent.isSymbolicLink()) {
              entryType = 'symlink';

              // Verify symlink target is within sandbox
              try {
                const realTarget = await realpath(fullPath);
                if (realTarget !== sandboxRoot && !isWithinBoundary(sandboxRoot, realTarget)) {
                  return null; // Skip symlinks pointing outside sandbox
                }
              } catch {
                return null; // Skip broken symlinks
              }
            }

            return {
              name: dirent.name,
              type: entryType,
              size: stat.size,
              modified: stat.mtime.toISOString(),
              permissions: formatPermissions(stat.mode),
            };
          } catch {
            return null; // Skip entries we can't stat (permission denied, etc.)
          }
        }),
      );
      const entries: FsEntry[] = settled.filter((e): e is FsEntry => e !== null);

      // Sort: directories first, then alphabetically
      entries.sort((a, b) => {
        if (a.type === 'directory' && b.type !== 'directory') return -1;
        if (a.type !== 'directory' && b.type === 'directory') return 1;
        return a.name.localeCompare(b.name);
      });

      // Return a display-friendly path relative to sandbox
      const displayPath = relative(sandboxRoot, resolved) || '.';
      sendToClient(ws, {
        type: 'fs.ls.response',
        path: displayPath,
        entries,
      });
    } catch (err) {
      logger.warn({ path: resolved, err: err instanceof Error ? err.message : String(err) }, 'fs.ls failed');
      sendToClient(ws, {
        type: 'fs.error',
        message: sanitizeFsError(err),
        path: requestedPath,
      });
    }
  }

  async function handleFsReadFile(ws: WebSocket, message: FsReadFileMessage): Promise<void> {
    const requestedPath = message.path;
    const resolved = await validatePath(requestedPath, sandboxRoot, canonicalRoot);

    if (!resolved) {
      sendToClient(ws, {
        type: 'fs.error',
        message: 'Access denied: path is outside sandbox',
        path: requestedPath,
      });
      return;
    }

    try {
      const stat = await lstat(resolved);

      if (stat.isDirectory()) {
        sendToClient(ws, {
          type: 'fs.error',
          message: 'Cannot read a directory as a file',
          path: requestedPath,
        });
        return;
      }

      if (stat.size > MAX_READ_SIZE) {
        sendToClient(ws, {
          type: 'fs.error',
          message: `File too large: ${(stat.size / 1024 / 1024).toFixed(1)} MB (limit: 1 MB)`,
          path: requestedPath,
        });
        return;
      }

      const content = await readFile(resolved, 'utf-8');
      const displayPath = relative(sandboxRoot, resolved) || basename(resolved);

      sendToClient(ws, {
        type: 'fs.readFile.response',
        path: displayPath,
        content,
        size: stat.size,
      });
    } catch (err) {
      logger.warn({ path: resolved, err: err instanceof Error ? err.message : String(err) }, 'fs.readFile failed');
      sendToClient(ws, {
        type: 'fs.error',
        message: sanitizeFsError(err),
        path: requestedPath,
      });
    }
  }

  function handleFsCwd(ws: WebSocket): void {
    // Return the sandbox root as the "current working directory"
    // Use ~ shorthand for display
    const home = homedir();
    const displayPath = sandboxRoot.startsWith(home)
      ? '~' + sandboxRoot.slice(home.length)
      : sandboxRoot;

    sendToClient(ws, {
      type: 'fs.cwd.response',
      path: displayPath,
    });
  }

  return {
    sandboxRoot,
    handleFsLs,
    handleFsReadFile,
    handleFsCwd,
  };
}
