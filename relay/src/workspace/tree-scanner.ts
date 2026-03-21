import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { join, relative, sep } from 'node:path';
import { logger } from '../utils/logger.js';

const execFileAsync = promisify(execFile);

// ── Tree Node type ──────────────────────────────────────────

export interface TreeNode {
  name: string;
  path: string;
  type: 'file' | 'directory';
  children?: TreeNode[];
}

// ── Constants ───────────────────────────────────────────────

const MAX_DEPTH = 4;
const MAX_FILES = 1000;

// ── Scanner ─────────────────────────────────────────────────

/**
 * Scan workspace file tree using `git ls-files` for gitignore-aware results.
 * Returns a hierarchical tree structure rooted at the given path.
 *
 * @param workingDir — absolute path to the git repo root
 * @param subPath — optional relative path within the repo to scope the listing
 */
export async function scanWorkspaceTree(workingDir: string, subPath?: string): Promise<TreeNode[]> {
  const scanRoot = subPath ? join(workingDir, subPath) : workingDir;

  let fileList: string[];
  try {
    // git ls-files outputs tracked files relative to cwd, one per line
    // Using --cached --others --exclude-standard to include untracked but not ignored files
    const { stdout } = await execFileAsync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], {
      cwd: scanRoot,
      encoding: 'utf-8',
      maxBuffer: 2 * 1024 * 1024,
      timeout: 10_000,
    });
    fileList = stdout.split('\n').filter(Boolean);
  } catch (err) {
    logger.warn({ err, workingDir, subPath }, 'git ls-files failed, falling back to empty tree');
    return [];
  }

  // Cap file count
  if (fileList.length > MAX_FILES) {
    fileList = fileList.slice(0, MAX_FILES);
  }

  // Build tree from flat file list
  return buildTree(fileList, scanRoot, workingDir);
}

/**
 * Convert a flat list of relative file paths into a nested tree structure.
 */
function buildTree(files: string[], scanRoot: string, workingDir: string): TreeNode[] {
  // Map of directory path → TreeNode (for deduplication)
  const dirMap = new Map<string, TreeNode>();
  const rootChildren: TreeNode[] = [];

  for (const filePath of files) {
    const parts = filePath.split(/[/\\]/);

    // Enforce depth limit
    if (parts.length > MAX_DEPTH + 1) continue; // +1 because last part is the file itself

    let currentChildren = rootChildren;
    let currentPath = '';

    for (let i = 0; i < parts.length; i++) {
      const part = parts[i]!;
      currentPath = currentPath ? `${currentPath}/${part}` : part;
      const isFile = i === parts.length - 1;

      // Calculate the full path relative to the workingDir
      const fullRelative = scanRoot === workingDir
        ? currentPath
        : relative(workingDir, join(scanRoot, currentPath)).split(sep).join('/');

      if (isFile) {
        // Check depth: directory parts count
        if (i > MAX_DEPTH) continue;

        currentChildren.push({
          name: part,
          path: fullRelative,
          type: 'file',
        });
      } else {
        // Directory node — find or create
        const dirKey = fullRelative;
        let dirNode = dirMap.get(dirKey);
        if (!dirNode) {
          dirNode = {
            name: part,
            path: fullRelative,
            type: 'directory',
            children: [],
          };
          dirMap.set(dirKey, dirNode);
          currentChildren.push(dirNode);
        }
        currentChildren = dirNode.children!;
      }
    }
  }

  // Sort: directories first, then alphabetically
  sortTree(rootChildren);
  return rootChildren;
}

function sortTree(nodes: TreeNode[]): void {
  nodes.sort((a, b) => {
    if (a.type !== b.type) return a.type === 'directory' ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
  for (const node of nodes) {
    if (node.children) sortTree(node.children);
  }
}
