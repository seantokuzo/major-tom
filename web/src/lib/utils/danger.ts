// Danger scoring for tool approval requests

export type DangerLevel = 'high' | 'medium' | 'normal';

const HIGH_PATTERNS = [
  /\brm\s+(-[a-zA-Z]*r|-[a-zA-Z]*f|--recursive|--force)/i,
  /\brm\s+-rf\b/i,
  /\bsudo\b/i,
  /\bgit\s+push\s+--force\b/i,
  /\bgit\s+push\s+-f\b/i,
  /\bgit\s+reset\s+--hard\b/i,
  /\bgit\s+clean\s+-[a-zA-Z]*f/i,
  /\bDROP\s+(TABLE|DATABASE)\b/i,
  /\bTRUNCATE\s+TABLE\b/i,
  /\bDELETE\s+FROM\b/i,
  /\bmkfs\b/i,
  /\bdd\s+if=/i,
  /\bchmod\s+777\b/i,
  /\bcurl\b.*\|\s*(bash|sh)\b/i,
  /\bwget\b.*\|\s*(bash|sh)\b/i,
  /\b>\s*\/dev\/sd[a-z]/i,
];

const MEDIUM_PATTERNS = [
  /\bgit\s+push\b/i,
  /\bnpm\s+publish\b/i,
  /\bnpx\b/i,
  /\bcurl\b/i,
  /\bwget\b/i,
  /\brm\b/i,
  /\bmv\b/i,
  /\bchmod\b/i,
  /\bchown\b/i,
  /\bkill\b/i,
  /\bpkill\b/i,
  /\bdocker\s+(rm|rmi|stop|kill)\b/i,
];

/**
 * Score the danger level of a bash command.
 */
export function scoreBashDanger(command: string): DangerLevel {
  for (const pattern of HIGH_PATTERNS) {
    if (pattern.test(command)) return 'high';
  }
  for (const pattern of MEDIUM_PATTERNS) {
    if (pattern.test(command)) return 'medium';
  }
  return 'normal';
}

/**
 * Score the danger of any tool approval request.
 */
export function scoreToolDanger(
  tool: string,
  details?: Record<string, unknown>
): DangerLevel {
  const toolLower = tool.toLowerCase();

  if (toolLower === 'bash' || toolLower === 'execute' || toolLower === 'shell') {
    const command = (details?.['command'] as string) ?? '';
    return scoreBashDanger(command);
  }

  if (toolLower === 'write' || toolLower === 'create') {
    return 'medium';
  }

  if (toolLower === 'edit' || toolLower === 'replace') {
    return 'normal';
  }

  return 'normal';
}

/**
 * Get CSS border color for a danger level.
 */
export function dangerColor(level: DangerLevel): string {
  switch (level) {
    case 'high':
      return '#f87171'; // red
    case 'medium':
      return '#fbbf24'; // yellow/amber
    case 'normal':
      return '#4ade80'; // green
  }
}

/**
 * Get the tool icon emoji.
 */
export function toolIcon(tool: string): string {
  const map: Record<string, string> = {
    bash: '\uD83D\uDD27',       // wrench
    execute: '\uD83D\uDD27',
    shell: '\uD83D\uDD27',
    edit: '\u270F\uFE0F',        // pencil
    replace: '\u270F\uFE0F',
    write: '\uD83D\uDCDD',       // memo
    create: '\uD83D\uDCDD',
    read: '\uD83D\uDCD6',        // open book
    webfetch: '\uD83C\uDF10',    // globe
    web_fetch: '\uD83C\uDF10',
    glob: '\uD83D\uDD0D',        // magnifying glass
    grep: '\uD83D\uDD0D',
    search: '\uD83D\uDD0D',
    list: '\uD83D\uDCC2',        // folder
    notebook_edit: '\uD83D\uDCD3', // notebook
  };
  return map[tool.toLowerCase()] ?? '\u2699\uFE0F'; // gear fallback
}
