/**
 * Priority Scorer — scores approval requests into high/medium/low priority.
 *
 * Used by the notification system to determine urgency: high-priority fires
 * immediately even during quiet hours, low-priority gets batched into digests.
 *
 * Extends the existing danger scoring patterns from permission-filter.ts and
 * the client-side danger scoring utilities.
 */

import { logger } from '../utils/logger.js';

// ── Types ────────────────────────────────────────────────────

export type PriorityLevel = 'high' | 'medium' | 'low';

export interface ApprovalPriority {
  level: PriorityLevel;
  reason: string;
}

// ── High-priority patterns ───────────────────────────────────
// Destructive commands, sensitive file writes, elevated privileges

const HIGH_BASH_PATTERNS: Array<{ pattern: RegExp; reason: string }> = [
  // File system destructive
  { pattern: /\brm\s+-rf?\b/, reason: 'destructive file removal (rm -r)' },
  { pattern: /\brm\s+--force\b/, reason: 'forced file removal' },
  { pattern: /\brm\s+-[a-zA-Z]*r[a-zA-Z]*f/, reason: 'destructive file removal (rm -rf)' },
  { pattern: /\brm\s+-[a-zA-Z]*f[a-zA-Z]*r/, reason: 'destructive file removal (rm -fr)' },
  // Git destructive
  { pattern: /\bgit\s+push\s+.*--force\b/, reason: 'force push' },
  { pattern: /\bgit\s+push\s+-f\b/, reason: 'force push' },
  { pattern: /\bgit\s+reset\s+--hard\b/, reason: 'hard reset' },
  { pattern: /\bgit\s+clean\s+-[a-zA-Z]*f/, reason: 'git clean (forced)' },
  { pattern: /\bgit\s+checkout\s+--\s/, reason: 'destructive checkout' },
  { pattern: /\bgit\s+branch\s+-D\b/, reason: 'force delete branch' },
  // Elevated privileges
  { pattern: /\bsudo\b/, reason: 'elevated privileges (sudo)' },
  // Database destructive
  { pattern: /\bDROP\s+(TABLE|DATABASE|SCHEMA)\b/i, reason: 'database drop' },
  { pattern: /\bTRUNCATE\b/i, reason: 'database truncate' },
  { pattern: /\bDELETE\s+FROM\b/i, reason: 'database delete' },
  // System-level destructive
  { pattern: /\bmkfs\b/, reason: 'filesystem format' },
  { pattern: /\bdd\s+if=/, reason: 'disk write (dd)' },
  { pattern: /\bchmod\s+-R\s+777\b/, reason: 'recursive permission change' },
  { pattern: /\bcurl\b.*\|\s*(bash|sh)\b/, reason: 'pipe to shell' },
  { pattern: /\bwget\b.*\|\s*(bash|sh)\b/, reason: 'pipe to shell' },
  { pattern: /\b>\s*\/dev\/(?!null\b)/, reason: 'write to device' },
  { pattern: /\bkill\s+-9\b/, reason: 'force kill process' },
  { pattern: /\bkillall\b/, reason: 'kill all processes' },
  { pattern: /\bshutdown\b/, reason: 'system shutdown' },
  { pattern: /\breboot\b/, reason: 'system reboot' },
];

const HIGH_SENSITIVE_PATHS: Array<{ pattern: RegExp; reason: string }> = [
  { pattern: /\.env($|\.)/, reason: 'sensitive file write (.env)' },
  { pattern: /credentials/i, reason: 'sensitive file write (credentials)' },
  { pattern: /private[_-]?key/i, reason: 'sensitive file write (private key)' },
  { pattern: /\.ssh\//, reason: 'sensitive file write (.ssh)' },
  { pattern: /\.gnupg\//, reason: 'sensitive file write (.gnupg)' },
  { pattern: /\.aws\//, reason: 'sensitive file write (.aws)' },
  { pattern: /\/etc\//, reason: 'sensitive file write (/etc/)' },
];

// ── Medium-priority patterns ─────────────────────────────────
// State-modifying commands, source code writes, network ops

const MEDIUM_BASH_PATTERNS: Array<{ pattern: RegExp; reason: string }> = [
  { pattern: /\bgit\s+commit\b/, reason: 'git commit' },
  { pattern: /\bgit\s+push\b/, reason: 'git push' },
  { pattern: /\bnpm\s+install\b/, reason: 'npm install' },
  { pattern: /\bnpm\s+i\s/, reason: 'npm install' },
  { pattern: /\bnpm\s+publish\b/, reason: 'npm publish' },
  { pattern: /\bmkdir\b/, reason: 'directory creation' },
  { pattern: /\bmv\b/, reason: 'file move/rename' },
  { pattern: /\brm\b/, reason: 'file removal' },
  { pattern: /\bcurl\b/, reason: 'network request (curl)' },
  { pattern: /\bwget\b/, reason: 'network request (wget)' },
  { pattern: /\bnpx\b/, reason: 'npx execution' },
  { pattern: /\bdocker\s+(rm|rmi|stop|kill|run|exec)\b/, reason: 'docker state change' },
  { pattern: /\bchmod\b/, reason: 'permission change' },
  { pattern: /\bchown\b/, reason: 'ownership change' },
];

// ── Low-priority tools (read-only) ──────────────────────────

const LOW_PRIORITY_TOOLS = new Set([
  'read',
  'glob',
  'grep',
  'search',
  'list',
  'webfetch',
  'web_fetch',
  'notebook_read',
]);

// ── Scorer ──────────────────────────────────────────────────

/**
 * Extract the primary input for pattern matching.
 * Matches the logic in permission-filter.ts.
 */
function getPrimaryInput(
  toolName: string,
  details: Record<string, unknown>,
): string | undefined {
  // Unwrap nested tool_input if present
  const input = (details['tool_input'] && typeof details['tool_input'] === 'object')
    ? details['tool_input'] as Record<string, unknown>
    : details;

  const lower = toolName.toLowerCase();

  if (lower === 'bash' || lower === 'execute' || lower === 'shell') {
    return (input['command'] as string) ?? undefined;
  }

  if (['edit', 'replace', 'write', 'create', 'read'].includes(lower)) {
    return (input['file_path'] as string)
      ?? (input['path'] as string)
      ?? undefined;
  }

  if (['glob', 'grep', 'search'].includes(lower)) {
    return (input['pattern'] as string) ?? undefined;
  }

  return undefined;
}

/**
 * Score an approval request into a priority level.
 *
 * @param tool - The tool name (e.g., "Bash", "Edit", "Read")
 * @param description - Human-readable description of the operation
 * @param details - Tool input details (may contain nested tool_input)
 * @returns An ApprovalPriority with level and reason
 */
export function scorePriority(
  tool: string,
  description: string,
  details: Record<string, unknown>,
): ApprovalPriority {
  const toolLower = tool.toLowerCase();
  const primaryInput = getPrimaryInput(tool, details) ?? '';
  const checkString = primaryInput.toLowerCase() + ' ' + description.toLowerCase();

  // ── Low priority: read-only tools ────────────────────────
  if (LOW_PRIORITY_TOOLS.has(toolLower)) {
    return { level: 'low', reason: 'read-only operation' };
  }

  // ── High priority: bash destructive commands ─────────────
  if (toolLower === 'bash' || toolLower === 'execute' || toolLower === 'shell') {
    for (const { pattern, reason } of HIGH_BASH_PATTERNS) {
      if (pattern.test(primaryInput)) {
        return { level: 'high', reason: `destructive bash command: ${reason}` };
      }
    }

    // Medium priority bash commands
    for (const { pattern, reason } of MEDIUM_BASH_PATTERNS) {
      if (pattern.test(primaryInput)) {
        return { level: 'medium', reason: `state-modifying command: ${reason}` };
      }
    }

    // Bash commands that don't match any pattern are low
    return { level: 'low', reason: 'non-destructive bash command' };
  }

  // ── Write/Create tool ────────────────────────────────────
  if (toolLower === 'write' || toolLower === 'create') {
    const filePath = primaryInput.toLowerCase();

    // Check sensitive paths
    for (const { pattern, reason } of HIGH_SENSITIVE_PATHS) {
      if (pattern.test(filePath)) {
        return { level: 'high', reason };
      }
    }

    return { level: 'medium', reason: 'file write to source code' };
  }

  // ── Edit/Replace tool ────────────────────────────────────
  if (toolLower === 'edit' || toolLower === 'replace') {
    const filePath = primaryInput.toLowerCase();

    // Check sensitive paths
    for (const { pattern, reason } of HIGH_SENSITIVE_PATHS) {
      if (pattern.test(filePath)) {
        return { level: 'high', reason };
      }
    }

    return { level: 'medium', reason: 'file edit' };
  }

  // ── Unknown tools default to medium ──────────────────────
  logger.debug({ tool, checkString: checkString.slice(0, 100) }, 'Unknown tool — defaulting to medium priority');
  return { level: 'medium', reason: `unknown tool: ${tool}` };
}
