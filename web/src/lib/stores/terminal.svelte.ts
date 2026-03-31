// Terminal store — reactive state for the filesystem browser terminal
// Uses Svelte 5 runes ($state, $derived)

import type { FsEntry } from '../protocol/messages';

// ── Terminal output model ────────────────────────────────────

export interface TerminalLine {
  id: string;
  type: 'command' | 'output' | 'error' | 'info';
  content: string;
}

// ── Terminal store ───────────────────────────────────────────

let lineId = 0;
function nextLineId(): string {
  return `tl-${++lineId}-${Date.now()}`;
}

class TerminalStore {
  // Current working directory (display path, starts from sandbox root)
  cwd = $state('~');
  // Full sandbox root path (set by fs.cwd response)
  sandboxRoot = $state('');

  // Terminal output history
  lines = $state<TerminalLine[]>([]);

  // Command history for arrow-up cycling
  commandHistory = $state<string[]>([]);
  private historyIndex = -1;
  private savedInput = '';
  private navigating = false;

  // Current input
  inputText = $state('');

  // Loading state
  isLoading = $state(false);

  // Track last ls flag for formatting response
  lastLsDetailed: boolean | null = null;

  // Pending cd target — when set, the next fs.ls.response will update cwd
  pendingCdTarget: string | null = null;

  // ── Output helpers ───────────────────────────────────────

  addCommand(command: string): void {
    this.lines.push({
      id: nextLineId(),
      type: 'command',
      content: command,
    });
  }

  addOutput(content: string): void {
    this.lines.push({
      id: nextLineId(),
      type: 'output',
      content,
    });
  }

  addError(content: string): void {
    this.lines.push({
      id: nextLineId(),
      type: 'error',
      content,
    });
  }

  addInfo(content: string): void {
    this.lines.push({
      id: nextLineId(),
      type: 'info',
      content,
    });
  }

  clear(): void {
    this.lines = [];
  }

  // ── Command history navigation ───────────────────────────

  addToHistory(command: string): void {
    const trimmed = command.trim();
    if (!trimmed) return;
    // Deduplicate: remove if already exists
    const idx = this.commandHistory.indexOf(trimmed);
    if (idx >= 0) this.commandHistory.splice(idx, 1);
    this.commandHistory.unshift(trimmed);
    // Keep max 100 entries
    if (this.commandHistory.length > 100) {
      this.commandHistory.length = 100;
    }
    this.resetNavigation();
  }

  navigate(direction: 'up' | 'down', currentInput: string): string | null {
    if (this.commandHistory.length === 0) return null;

    if (!this.navigating) {
      if (direction === 'down') return null;
      this.navigating = true;
      this.savedInput = currentInput;
      this.historyIndex = 0;
      return this.commandHistory[0] ?? null;
    }

    if (direction === 'up') {
      const next = this.historyIndex + 1;
      if (next >= this.commandHistory.length) {
        return this.commandHistory[this.historyIndex] ?? null;
      }
      this.historyIndex = next;
      return this.commandHistory[this.historyIndex] ?? null;
    } else {
      const next = this.historyIndex - 1;
      if (next < 0) {
        this.navigating = false;
        this.historyIndex = -1;
        return this.savedInput;
      }
      this.historyIndex = next;
      return this.commandHistory[this.historyIndex] ?? null;
    }
  }

  resetNavigation(): void {
    this.navigating = false;
    this.historyIndex = -1;
    this.savedInput = '';
  }

  get isNavigating(): boolean {
    return this.navigating;
  }

  // ── Directory helpers ────────────────────────────────────

  /** Resolve a path relative to cwd. Handles `.`, `..`, absolute paths */
  resolvePath(path: string): string {
    if (!path || path === '.') return this.cwd;

    // Absolute path (starts with ~ or /)
    if (path.startsWith('~') || path.startsWith('/')) {
      return this.normalizePath(path);
    }

    // Relative path — combine with cwd
    const base = this.cwd === '~' ? '~' : this.cwd;
    const combined = base === '~' ? `~/${path}` : `${base}/${path}`;
    return this.normalizePath(combined);
  }

  /** Normalize a path — resolve .. and . segments */
  private normalizePath(path: string): string {
    // Handle ~ prefix
    const hasHome = path.startsWith('~');
    const rawParts = (hasHome ? path.slice(1) : path).split('/').filter(Boolean);

    const resolved: string[] = [];
    for (const part of rawParts) {
      if (part === '.') continue;
      if (part === '..') {
        resolved.pop();
      } else {
        resolved.push(part);
      }
    }

    const result = resolved.join('/');
    if (hasHome) {
      return result ? `~/${result}` : '~';
    }
    return result ? `/${result}` : '/';
  }

  // ── ls formatting ────────────────────────────────────────

  formatLsOutput(entries: FsEntry[], detailed: boolean): string {
    if (entries.length === 0) return '(empty directory)';

    if (!detailed) {
      // Simple listing: columns of names
      return entries
        .map((e) => {
          const suffix = e.type === 'directory' ? '/' : e.type === 'symlink' ? '@' : '';
          const prefix = e.restricted ? '\u{1F512} ' : '';
          return `${prefix}${e.name}${suffix}`;
        })
        .join('  ');
    }

    // Detailed listing (-la style)
    const lines: string[] = [];
    for (const entry of entries) {
      const typeChar =
        entry.type === 'directory' ? 'd' : entry.type === 'symlink' ? 'l' : '-';
      const perms = entry.permissions ?? 'rw-r--r--';
      const size = formatSize(entry.size);
      const date = formatDate(entry.modified);
      const name = entry.type === 'directory' ? `${entry.name}/` : entry.name;
      const lock = entry.restricted ? ' [restricted]' : '';
      lines.push(`${typeChar}${perms}  ${size.padStart(8)}  ${date}  ${name}${lock}`);
    }
    return lines.join('\n');
  }
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}K`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)}M`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(1)}G`;
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  const month = months[d.getMonth()] ?? 'Jan';
  const day = String(d.getDate()).padStart(2, ' ');
  const hours = String(d.getHours()).padStart(2, '0');
  const mins = String(d.getMinutes()).padStart(2, '0');
  return `${month} ${day} ${hours}:${mins}`;
}

// Singleton
export const terminalStore = new TerminalStore();
