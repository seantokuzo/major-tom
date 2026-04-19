/**
 * Major Tom — Hook installer (Phase 13 Wave 2)
 *
 * Idempotently installs the PreToolUse + SubagentStart hook scripts and
 * the matching `settings.json` into a Major-Tom-private Claude config dir
 * at `$HOME/.major-tom/claude-config/`. NEVER touches the user's real
 * `~/.claude/`.
 *
 * Versioning: each installed file's content is hashed (sha256) and
 * compared against the bundled template hash. If they differ — either a
 * fresh install OR a manual edit — the file is restored from the template.
 * This means the relay self-heals if a user (or a sloppy script) pokes
 * at the installed scripts.
 *
 * Called from `server.ts` startup as a function, NOT a child process,
 * so the install runs in-process and any failure surfaces with a stack
 * trace instead of a cryptic exit code.
 */
import { createHash } from 'node:crypto';
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { logger } from '../utils/logger.js';

/** Where the Major-Tom-private Claude config lives. */
export const MAJOR_TOM_CONFIG_DIR = join(homedir(), '.major-tom', 'claude-config');

/**
 * Find the bundled `hook-templates/` directory. Works in both:
 *   - tsx dev mode  : import.meta.url = relay/src/installer/install-hooks.ts
 *                     → ../../../scripts/hook-templates
 *   - bundled prod  : import.meta.url = relay/dist/server.js
 *                     → ../scripts/hook-templates
 *
 * We probe both candidates because esbuild bundling collapses the path
 * structure but tsx preserves it.
 */
function findTemplateDir(): string {
  const here = dirname(fileURLToPath(import.meta.url));
  const candidates = [
    // tsx dev mode (src/installer/install-hooks.ts)
    resolve(here, '..', '..', '..', 'scripts', 'hook-templates'),
    // bundled prod mode (dist/server.js)
    resolve(here, '..', 'scripts', 'hook-templates'),
    // belt-and-braces: relative to cwd in case relay was launched from its own dir
    resolve(process.cwd(), 'scripts', 'hook-templates'),
    resolve(process.cwd(), 'relay', 'scripts', 'hook-templates'),
  ];
  for (const path of candidates) {
    if (existsSync(join(path, 'pretooluse.sh'))) return path;
  }
  throw new Error(
    `install-hooks: could not locate hook-templates directory. Tried:\n  ${candidates.join('\n  ')}`,
  );
}

/**
 * Where the user's real Claude Code config lives. We READ from here to
 * pull their permission allowlist into Major Tom's private dir; we never
 * write to it.
 */
const USER_CLAUDE_SETTINGS_PATH = join(homedir(), '.claude', 'settings.json');

/**
 * Read the user's `permissions` block from their real `~/.claude/settings.json`.
 *
 * Returns `null` when the file is missing or can't be parsed. The installer
 * treats `null` as "no allowlist to merge" — equivalent to the pre-fix
 * behavior where every tool call prompted.
 *
 * This is read-only: the "never touch `~/.claude/`" constraint is about
 * writing, not reading. Pulling the allowlist in lets PTY-launched claude
 * inherit the same pre-approved tools the user already configured for the
 * SDK path.
 */
export function importUserPermissions(settingsPath = USER_CLAUDE_SETTINGS_PATH): unknown {
  if (!existsSync(settingsPath)) return null;
  try {
    const raw = readFileSync(settingsPath, 'utf-8');
    const parsed = JSON.parse(raw) as { permissions?: unknown };
    return parsed.permissions ?? null;
  } catch (err) {
    logger.warn(
      { path: settingsPath, err: err instanceof Error ? err.message : String(err) },
      'Could not read user Claude settings — PTY claude will prompt on every tool call',
    );
    return null;
  }
}

/**
 * Build the settings.json Major Tom drops into its private config dir.
 * Mirrors Claude Code's hook config schema. The 600s timeout matches the
 * `--max-time 600` in the remote-mode curl call inside pretooluse.sh.
 *
 * `$CLAUDE_CONFIG_DIR` is expanded by Claude Code at hook-invoke time,
 * NOT at install time, so we can leave the literal token in the file.
 *
 * `userPermissions`, when present, is merged as the top-level `permissions`
 * field so PTY-launched claude inherits the user's pre-approved tool
 * allowlist from `~/.claude/settings.json`.
 */
export function buildSettingsJson(userPermissions: unknown): string {
  const settings: Record<string, unknown> = {
    hooks: {
      PreToolUse: [
        {
          matcher: '*',
          hooks: [
            {
              type: 'command',
              command: '$CLAUDE_CONFIG_DIR/hooks/pretooluse.sh',
              timeout: 600,
            },
          ],
        },
      ],
      SubagentStart: [
        {
          hooks: [
            {
              type: 'command',
              command: '$CLAUDE_CONFIG_DIR/hooks/subagent-start.sh',
            },
          ],
        },
      ],
      // Phase 13 Wave 3 — SubagentStop dismisses the sprite when a
      // PTY-spawned subagent finishes. Mirrors SubagentStart in shape.
      SubagentStop: [
        {
          hooks: [
            {
              type: 'command',
              command: '$CLAUDE_CONFIG_DIR/hooks/subagent-stop.sh',
            },
          ],
        },
      ],
      // Tab-Keyed Offices — SessionStart registers the tab↔session
      // binding with the relay. Stop is Claude Code's session-end
      // hook (per docs/STREAM-EVENTS.md:252). Both are fire-and-forget,
      // no timeout needed — they never block.
      SessionStart: [
        {
          hooks: [
            {
              type: 'command',
              command: '$CLAUDE_CONFIG_DIR/hooks/session-start.sh',
            },
          ],
        },
      ],
      Stop: [
        {
          hooks: [
            {
              type: 'command',
              command: '$CLAUDE_CONFIG_DIR/hooks/stop.sh',
            },
          ],
        },
      ],
    },
  };
  if (userPermissions !== null && userPermissions !== undefined) {
    settings.permissions = userPermissions;
  }
  return JSON.stringify(settings, null, 2) + '\n';
}

/** Default approval-mode.json — only written if it doesn't already exist. */
const DEFAULT_APPROVAL_MODE_JSON =
  JSON.stringify({ mode: 'local', updatedAt: new Date(0).toISOString() }, null, 2) + '\n';

interface HookFileSpec {
  /** Path inside the config dir, relative. */
  relativePath: string;
  /** Filename inside the bundled `hook-templates/` directory. */
  templateFilename: string;
  /** Set executable bit (chmod 0o755) after writing. */
  executable: boolean;
}

const HOOK_FILES: HookFileSpec[] = [
  {
    relativePath: join('hooks', 'pretooluse.sh'),
    templateFilename: 'pretooluse.sh',
    executable: true,
  },
  {
    relativePath: join('hooks', 'subagent-start.sh'),
    templateFilename: 'subagent-start.sh',
    executable: true,
  },
  // Phase 13 Wave 3 — new SubagentStop hook template. `writeIfChanged`
  // is content-hashed, so existing installs from Wave 2 will detect
  // the settings.json hash mismatch on next startup and also pick up
  // the new subagent-stop.sh automatically — no manual reinstall.
  {
    relativePath: join('hooks', 'subagent-stop.sh'),
    templateFilename: 'subagent-stop.sh',
    executable: true,
  },
  // Tab-Keyed Offices — SessionStart / Stop hook scripts. The
  // content-hashed settings.json update above pulls these in on
  // any running relay's next startup; no manual reinstall.
  {
    relativePath: join('hooks', 'session-start.sh'),
    templateFilename: 'session-start.sh',
    executable: true,
  },
  {
    relativePath: join('hooks', 'stop.sh'),
    templateFilename: 'stop.sh',
    executable: true,
  },
];

function sha256(content: string): string {
  return createHash('sha256').update(content).digest('hex');
}

function ensureDir(path: string): void {
  if (!existsSync(path)) {
    mkdirSync(path, { recursive: true });
  }
}

/**
 * Write a file only if its content hash differs from the desired one.
 * Returns true if the file was (re)written, false if it was already up to date.
 */
function writeIfChanged(targetPath: string, desiredContent: string, executable: boolean): boolean {
  const desiredHash = sha256(desiredContent);
  if (existsSync(targetPath)) {
    const existingHash = sha256(readFileSync(targetPath, 'utf-8'));
    if (existingHash === desiredHash) {
      // Make sure perms are still right even if content is identical —
      // a previous install may have failed mid-chmod.
      if (executable) {
        try {
          chmodSync(targetPath, 0o755);
        } catch {
          // ignore — best-effort
        }
      }
      return false;
    }
    logger.warn(
      { path: targetPath, existingHash, desiredHash },
      'Hook file hash mismatch — restoring from template',
    );
  }
  writeFileSync(targetPath, desiredContent, 'utf-8');
  if (executable) {
    chmodSync(targetPath, 0o755);
  }
  return true;
}

interface InstallReport {
  configDir: string;
  installed: string[];
  skipped: string[];
  /** True if approval-mode.json was just created (not pre-existing). */
  createdApprovalMode: boolean;
}

/**
 * Idempotently install the Major-Tom-private Claude config and hook
 * scripts. Safe to call on every relay startup.
 */
export function installHooks(): InstallReport {
  ensureDir(MAJOR_TOM_CONFIG_DIR);
  ensureDir(join(MAJOR_TOM_CONFIG_DIR, 'hooks'));

  const templateDir = findTemplateDir();
  const installed: string[] = [];
  const skipped: string[] = [];

  // 1. settings.json — rebuilt on every install so the user's latest
  // permission allowlist is picked up. writeIfChanged's content-hash
  // guard keeps it a no-op when nothing changed.
  const settingsPath = join(MAJOR_TOM_CONFIG_DIR, 'settings.json');
  const userPermissions = importUserPermissions();
  const settingsJson = buildSettingsJson(userPermissions);
  if (writeIfChanged(settingsPath, settingsJson, false)) {
    installed.push(settingsPath);
    logger.info(
      {
        path: settingsPath,
        importedPermissions: userPermissions !== null,
      },
      userPermissions !== null
        ? 'settings.json updated — user permission allowlist imported'
        : 'settings.json updated — no user allowlist found, PTY claude will prompt on every tool call',
    );
  } else {
    skipped.push(settingsPath);
  }

  // 2. hook scripts
  for (const spec of HOOK_FILES) {
    const targetPath = join(MAJOR_TOM_CONFIG_DIR, spec.relativePath);
    const templatePath = join(templateDir, spec.templateFilename);
    if (!existsSync(templatePath)) {
      throw new Error(
        `Hook template missing: ${templatePath} — did you forget to bundle the templates?`,
      );
    }
    const templateContent = readFileSync(templatePath, 'utf-8');
    if (writeIfChanged(targetPath, templateContent, spec.executable)) {
      installed.push(targetPath);
    } else {
      skipped.push(targetPath);
    }
  }

  // 3. approval-mode.json — only created on first install. We don't
  //    overwrite the user's chosen mode on every relay restart.
  const approvalModePath = join(MAJOR_TOM_CONFIG_DIR, 'approval-mode.json');
  let createdApprovalMode = false;
  if (!existsSync(approvalModePath)) {
    writeFileSync(approvalModePath, DEFAULT_APPROVAL_MODE_JSON, 'utf-8');
    installed.push(approvalModePath);
    createdApprovalMode = true;
  } else {
    skipped.push(approvalModePath);
  }

  logger.info(
    {
      configDir: MAJOR_TOM_CONFIG_DIR,
      installedCount: installed.length,
      skippedCount: skipped.length,
      createdApprovalMode,
    },
    'Hook installer finished',
  );

  return {
    configDir: MAJOR_TOM_CONFIG_DIR,
    installed,
    skipped,
    createdApprovalMode,
  };
}
