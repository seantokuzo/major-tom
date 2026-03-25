import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { logger } from '../utils/logger.js';

// ── Permission Mode Types ──────────────────────────────────

export type PermissionMode = 'manual' | 'smart' | 'delay' | 'god';
export type GodSubMode = 'normal' | 'yolo';

export interface PermissionModeState {
  mode: PermissionMode;
  delaySeconds: number;
  godSubMode: GodSubMode;
}

export type AutoAllowReason =
  | 'smart:settings'
  | 'smart:session'
  | 'god:yolo'
  | 'god:normal';

export interface AutoAllowResult {
  allowed: true;
  reason: AutoAllowReason;
}

export interface ManualResult {
  allowed: false;
}

export type FilterResult = AutoAllowResult | ManualResult;

// ── Destructive command patterns (God Normal blocks these) ──

const DESTRUCTIVE_PATTERNS: RegExp[] = [
  // File system
  /\brm\s+-rf?\b/,
  /\brm\s+--force\b/,
  /\brm\s+-[a-zA-Z]*r[a-zA-Z]*f/,
  /\brm\s+-[a-zA-Z]*f[a-zA-Z]*r/,
  /\brmdir\b/,
  // Git destructive
  /\bgit\s+push\s+.*--force\b/,
  /\bgit\s+push\s+-f\b/,
  /\bgit\s+reset\s+--hard\b/,
  /\bgit\s+clean\s+-[a-zA-Z]*f/,
  /\bgit\s+checkout\s+--\s/,
  /\bgit\s+branch\s+-D\b/,
  /\bgit\s+rebase\b/,
  // Process/system
  /\bkill\s+-9\b/,
  /\bkillall\b/,
  /\bpkill\b/,
  /\bshutdown\b/,
  /\breboot\b/,
  // Database
  /\bDROP\s+(TABLE|DATABASE|SCHEMA)\b/i,
  /\bTRUNCATE\b/i,
  /\bDELETE\s+FROM\b/i,
  // Docker
  /\bdocker\s+system\s+prune\b/,
  /\bdocker\s+rm\s+-f\b/,
  // Dangerous writes
  /\b>\s*\/dev\/(?!null\b)/,
  /\bdd\s+if=/,
  /\bmkfs\b/,
  /\bchmod\s+-R\s+777\b/,
];

// ── Settings.json pattern matching ─────────────────────────

interface ParsedPattern {
  /** e.g., 'Bash', 'Edit', 'mcp__github__*' */
  toolPattern: string;
  /** e.g., 'npm run:*' for Bash(npm run:*), undefined if no parens */
  inputPattern?: string;
}

function parsePattern(raw: string): ParsedPattern {
  const parenIdx = raw.indexOf('(');
  if (parenIdx === -1) {
    return { toolPattern: raw };
  }
  const toolPattern = raw.slice(0, parenIdx);
  // Strip trailing )
  const inputPart = raw.slice(parenIdx + 1).replace(/\)$/, '');
  return { toolPattern, inputPattern: inputPart || undefined };
}

function globMatch(pattern: string, value: string): boolean {
  if (pattern === '*') return true;
  if (pattern === value) return true;

  // Convert glob to regex: * → .*, ** → .*, ? → .
  const escaped = pattern
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replace(/\*/g, '.*')
    .replace(/\?/g, '.');
  return new RegExp(`^${escaped}$`).test(value);
}

function toolMatchesPattern(
  parsed: ParsedPattern,
  toolName: string,
  primaryInput: string | undefined,
): boolean {
  // Match tool name (glob)
  if (!globMatch(parsed.toolPattern, toolName)) return false;

  // If no input pattern specified, tool name match is sufficient
  if (!parsed.inputPattern) return true;

  // If input pattern specified but no input to match against, no match
  if (!primaryInput) return false;

  // Input patterns use colon prefix matching: "npm run:*" matches commands starting with "npm run"
  // The colon acts as a separator between a command prefix and an argument pattern.
  // e.g., "npm run:lint" matches "npm run lint --fix"
  const colonIdx = parsed.inputPattern.indexOf(':');
  if (colonIdx !== -1) {
    const prefix = parsed.inputPattern.slice(0, colonIdx);
    const suffix = parsed.inputPattern.slice(colonIdx + 1);
    if (suffix === '*') {
      return primaryInput.startsWith(prefix);
    }
    // Treat colon as a separator — match prefix then glob-match suffix against
    // the first argument token after the prefix.
    const trimmedPrefix = prefix.trimEnd();
    const trimmedInput = primaryInput.trimStart();
    if (!trimmedInput.startsWith(trimmedPrefix)) return false;
    const afterPrefix = trimmedInput.slice(trimmedPrefix.length).trimStart();
    if (afterPrefix.length === 0) return false;
    const firstSpaceIdx = afterPrefix.search(/\s/);
    const firstToken = firstSpaceIdx === -1 ? afterPrefix : afterPrefix.slice(0, firstSpaceIdx);
    return globMatch(suffix, firstToken);
  }

  return globMatch(parsed.inputPattern, primaryInput);
}

/** Extract the "primary input" for a tool — used for pattern matching */
function getPrimaryInput(
  toolName: string,
  input: Record<string, unknown>,
): string | undefined {
  const lower = toolName.toLowerCase();
  if (lower === 'bash' || lower === 'execute' || lower === 'shell') {
    return (input['command'] as string) ?? undefined;
  }
  if (
    lower === 'edit' ||
    lower === 'replace' ||
    lower === 'write' ||
    lower === 'create' ||
    lower === 'read'
  ) {
    return (
      (input['file_path'] as string) ??
      (input['path'] as string) ??
      undefined
    );
  }
  if (lower === 'glob' || lower === 'grep' || lower === 'search') {
    return (input['pattern'] as string) ?? undefined;
  }
  return undefined;
}

// ── PermissionFilter ───────────────────────────────────────

export class PermissionFilter {
  private allowPatterns: ParsedPattern[] = [];
  private denyPatterns: ParsedPattern[] = [];
  private sessionAllowlist = new Set<string>();
  private modeState: PermissionModeState = {
    mode: 'smart',
    delaySeconds: 5,
    godSubMode: 'normal',
  };

  constructor() {
    this.loadSettings();
  }

  // ── Settings.json loading ──────────────────────────────

  private loadSettings(): void {
    const home = process.env['HOME'] ?? process.env['USERPROFILE'] ?? '';
    const settingsPath = resolve(home, '.claude', 'settings.json');

    try {
      const raw = readFileSync(settingsPath, 'utf-8');
      const settings = JSON.parse(raw);
      const perms = settings?.permissions;
      if (!perms) {
        logger.info('No permissions block in settings.json — smart mode will show all approvals');
        return;
      }

      if (Array.isArray(perms.allow)) {
        this.allowPatterns = perms.allow.map(parsePattern);
        logger.info(
          { count: this.allowPatterns.length },
          'Loaded allow patterns from settings.json',
        );
      }

      if (Array.isArray(perms.deny)) {
        this.denyPatterns = perms.deny.map(parsePattern);
        logger.info(
          { count: this.denyPatterns.length },
          'Loaded deny patterns from settings.json',
        );
      }
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
        logger.info('No ~/.claude/settings.json found — smart mode will show all approvals');
      } else {
        logger.warn({ err }, 'Failed to parse ~/.claude/settings.json');
      }
    }
  }

  // ── Mode management ────────────────────────────────────

  getMode(): PermissionModeState {
    return { ...this.modeState };
  }

  setMode(
    mode: PermissionMode,
    delaySeconds?: number,
    godSubMode?: GodSubMode,
  ): void {
    this.modeState.mode = mode;
    if (delaySeconds !== undefined) {
      this.modeState.delaySeconds = Math.max(1, Math.min(300, Math.floor(delaySeconds)));
    }
    if (godSubMode) {
      this.modeState.godSubMode = godSubMode;
    }
    logger.info({ ...this.modeState }, 'Permission mode updated');
  }

  // ── Session allowlist ──────────────────────────────────

  addSessionAllow(toolName: string): void {
    this.sessionAllowlist.add(toolName);
    logger.info({ toolName, size: this.sessionAllowlist.size }, 'Added to session allowlist');
  }

  clearSessionAllowlist(): void {
    this.sessionAllowlist.clear();
    logger.info('Session allowlist cleared');
  }

  getSessionAllowlist(): string[] {
    return [...this.sessionAllowlist];
  }

  // ── Core filter logic ──────────────────────────────────

  check(toolName: string, input: Record<string, unknown>): FilterResult {
    const { mode } = this.modeState;

    switch (mode) {
      case 'manual':
        return { allowed: false };

      case 'god':
        return this.checkGodMode(toolName, input);

      case 'smart':
        return this.checkSmartMode(toolName, input);

      case 'delay':
        // Delay mode is handled by ApprovalQueue timers, not here
        return { allowed: false };

      default:
        return { allowed: false };
    }
  }

  private checkGodMode(
    toolName: string,
    input: Record<string, unknown>,
  ): FilterResult {
    if (this.modeState.godSubMode === 'yolo') {
      return { allowed: true, reason: 'god:yolo' };
    }

    // Normal sub-mode: block destructive commands
    if (this.isDestructiveCommand(toolName, input)) {
      return { allowed: false };
    }

    return { allowed: true, reason: 'god:normal' };
  }

  private checkSmartMode(
    toolName: string,
    input: Record<string, unknown>,
  ): FilterResult {
    const primaryInput = getPrimaryInput(toolName, input);

    // 1. Check session allowlist (from "Always" taps)
    if (this.sessionAllowlist.has(toolName)) {
      return { allowed: true, reason: 'smart:session' };
    }

    // 2. Check deny patterns first (deny overrides allow)
    for (const pattern of this.denyPatterns) {
      if (toolMatchesPattern(pattern, toolName, primaryInput)) {
        return { allowed: false };
      }
    }

    // 3. Check settings.json allow patterns
    for (const pattern of this.allowPatterns) {
      if (toolMatchesPattern(pattern, toolName, primaryInput)) {
        return { allowed: true, reason: 'smart:settings' };
      }
    }

    // 4. No match — show approval card
    return { allowed: false };
  }

  private isDestructiveCommand(
    toolName: string,
    input: Record<string, unknown>,
  ): boolean {
    const lower = toolName.toLowerCase();
    if (lower !== 'bash' && lower !== 'execute' && lower !== 'shell') {
      return false;
    }
    const command = (input['command'] as string) ?? '';
    return DESTRUCTIVE_PATTERNS.some((pat) => pat.test(command));
  }
}
