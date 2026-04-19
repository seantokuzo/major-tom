/**
 * Major Tom — permission-matcher
 *
 * Lightweight allowlist/asklist evaluator for Claude Code permission rules.
 * Used by the PreToolUse hook handler to short-circuit approvals when the
 * user has pre-approved the tool — without this, every tool call hits
 * PreToolUse → enqueues an approval → fires a push, even for pre-approved
 * tools, because hook `permissionDecision:"ask"` overrides the allowlist.
 *
 * Rule syntax (subset of Claude Code's spec):
 *   - `ToolName`              — exact tool-name match, any input
 *   - `ToolName(*)`           — same as above, explicit wildcard
 *   - `ToolName(prefix:*)`    — for Bash: command must start with `prefix`
 *   - `ToolNamePrefix*`       — prefix match on tool name (for mcp__foo_*)
 *
 * Evaluation:
 *   - If an `ask` rule matches → return 'ask' (flood through normal approval)
 *   - Else if an `allow` rule matches → return 'allow' (skip enqueue)
 *   - Else → return 'ask' (default)
 *
 * Ask takes precedence over allow so specific deny-ish patterns (like
 * `Bash(rm:*)`) always prompt even if a broader allow (`Bash(*)`) is set.
 */
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

export const DEFAULT_SETTINGS_PATH = join(
  homedir(),
  '.major-tom',
  'claude-config',
  'settings.json',
);

export interface PermissionSettings {
  allow: string[];
  ask: string[];
}

interface Rule {
  /** Tool name or tool-name prefix (if `toolIsPrefix`). */
  tool: string;
  /** True when the rule ends in `*` — match tool name by prefix. */
  toolIsPrefix: boolean;
  /** Input pattern inside parens, or null when no parens were provided. */
  pattern: string | null;
}

const RULE_RE = /^([^(]+?)(?:\(([^)]*)\))?$/;

function parseRule(raw: string): Rule | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  const m = RULE_RE.exec(trimmed);
  if (!m || !m[1]) return null;
  const toolRaw = m[1].trim();
  if (!toolRaw) return null;
  const toolIsPrefix = toolRaw.endsWith('*');
  const tool = toolIsPrefix ? toolRaw.slice(0, -1) : toolRaw;
  return { tool, toolIsPrefix, pattern: m[2] ?? null };
}

function toolMatches(actualTool: string, rule: Rule): boolean {
  if (rule.toolIsPrefix) return actualTool.startsWith(rule.tool);
  return actualTool === rule.tool;
}

function patternMatches(
  toolName: string,
  toolInput: Record<string, unknown> | undefined,
  pattern: string,
): boolean {
  if (pattern === '*') return true;

  // `prefix:*` — Bash command must start with `prefix` (trailing space tolerated).
  if (pattern.endsWith(':*')) {
    const prefix = pattern.slice(0, -2);
    if (toolName === 'Bash') {
      const cmd = typeof toolInput?.command === 'string' ? (toolInput.command as string) : '';
      return cmd === prefix || cmd.startsWith(prefix + ' ') || cmd.startsWith(prefix);
    }
    // Non-Bash: try file_path prefix
    const path =
      typeof toolInput?.file_path === 'string' ? (toolInput.file_path as string) : '';
    return path.startsWith(prefix);
  }

  // Literal match on Bash command or path input.
  if (toolName === 'Bash') {
    const cmd = typeof toolInput?.command === 'string' ? (toolInput.command as string) : '';
    return cmd === pattern;
  }
  const path = typeof toolInput?.file_path === 'string' ? (toolInput.file_path as string) : '';
  return path === pattern;
}

function ruleMatches(
  toolName: string,
  toolInput: Record<string, unknown> | undefined,
  raw: string,
): boolean {
  const rule = parseRule(raw);
  if (!rule) return false;
  if (!toolMatches(toolName, rule)) return false;
  if (rule.pattern === null) return true; // exact tool name, no input constraint
  return patternMatches(toolName, toolInput, rule.pattern);
}

/**
 * Evaluate a tool call against the settings' allow + ask lists.
 *
 * Returns `'allow'` only when the call matches an allow rule AND does NOT
 * match any ask rule. Otherwise returns `'ask'`, which the hook handler
 * uses as the signal to proceed with the normal approval flow.
 */
export function evaluatePermission(
  toolName: string,
  toolInput: Record<string, unknown> | undefined,
  settings: PermissionSettings,
): 'allow' | 'ask' {
  for (const rule of settings.ask) {
    if (ruleMatches(toolName, toolInput, rule)) return 'ask';
  }
  for (const rule of settings.allow) {
    if (ruleMatches(toolName, toolInput, rule)) return 'allow';
  }
  return 'ask';
}

/**
 * Read `permissions.allow` + `permissions.ask` from a Major Tom Claude
 * config settings file. Returns empty lists on missing/malformed file.
 */
export function readPermissionSettings(path = DEFAULT_SETTINGS_PATH): PermissionSettings {
  if (!existsSync(path)) return { allow: [], ask: [] };
  try {
    const raw = readFileSync(path, 'utf-8');
    const parsed = JSON.parse(raw) as {
      permissions?: { allow?: unknown; ask?: unknown };
    };
    const perms = parsed.permissions ?? {};
    const allow = Array.isArray(perms.allow)
      ? perms.allow.filter((x): x is string => typeof x === 'string')
      : [];
    const ask = Array.isArray(perms.ask)
      ? perms.ask.filter((x): x is string => typeof x === 'string')
      : [];
    return { allow, ask };
  } catch {
    return { allow: [], ask: [] };
  }
}

/**
 * Merge two permission sets (allow + ask are concatenated). Order matters
 * for nothing because the evaluator short-circuits on first match within
 * each list and `ask` is always checked before `allow`.
 */
export function mergePermissionSettings(
  a: PermissionSettings,
  b: PermissionSettings,
): PermissionSettings {
  return {
    allow: [...a.allow, ...b.allow],
    ask: [...a.ask, ...b.ask],
  };
}

/**
 * Read the project-scoped allowlist + asklist for a given cwd. Claude Code
 * stores two flavors in `<cwd>/.claude/`:
 *   - `settings.json`        — checked-in shared rules
 *   - `settings.local.json`  — user-local, gitignored rules (accumulated
 *                              from "allow always" clicks)
 * Both are merged. Missing files return empty sets.
 */
export function readPermissionSettingsForCwd(cwd: string): PermissionSettings {
  const shared = readPermissionSettings(join(cwd, '.claude', 'settings.json'));
  const local = readPermissionSettings(join(cwd, '.claude', 'settings.local.json'));
  return mergePermissionSettings(shared, local);
}
