import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
  evaluatePermission,
  mergePermissionSettings,
  readPermissionSettings,
  readPermissionSettingsForCwd,
  type PermissionSettings,
} from '../permission-matcher.js';
import { mkdir } from 'node:fs/promises';

const empty: PermissionSettings = { allow: [], ask: [] };

describe('evaluatePermission — tool name matching', () => {
  it('returns "ask" for tools not in any list', () => {
    expect(evaluatePermission('Bash', { command: 'ls' }, empty)).toBe('ask');
  });

  it('allows when rule is the exact tool name (no parens)', () => {
    const s: PermissionSettings = { allow: ['WebSearch'], ask: [] };
    expect(evaluatePermission('WebSearch', undefined, s)).toBe('allow');
  });

  it('allows when rule is `ToolName(*)`', () => {
    const s: PermissionSettings = { allow: ['Bash(*)'], ask: [] };
    expect(evaluatePermission('Bash', { command: 'echo hi' }, s)).toBe('allow');
  });

  it('allows mcp__github__* prefix for any mcp__github__ tool', () => {
    const s: PermissionSettings = { allow: ['mcp__github__*'], ask: [] };
    expect(evaluatePermission('mcp__github__create_pull_request', {}, s)).toBe('allow');
    expect(evaluatePermission('mcp__github__get_issue', {}, s)).toBe('allow');
    expect(evaluatePermission('mcp__slack__send_message', {}, s)).toBe('ask');
  });

  it('does not allow when tool name does not match', () => {
    const s: PermissionSettings = { allow: ['Bash(*)'], ask: [] };
    expect(evaluatePermission('Read', { file_path: '/tmp/x' }, s)).toBe('ask');
  });
});

describe('evaluatePermission — Bash command prefix matching', () => {
  const s: PermissionSettings = { allow: ['Bash(xcrun simctl:*)', 'Bash(git checkout:*)'], ask: [] };

  it('allows when command starts with prefix + space', () => {
    expect(evaluatePermission('Bash', { command: 'xcrun simctl list' }, s)).toBe('allow');
    expect(evaluatePermission('Bash', { command: 'git checkout main' }, s)).toBe('allow');
  });

  it('allows exact prefix with no trailing argument', () => {
    expect(evaluatePermission('Bash', { command: 'xcrun simctl' }, s)).toBe('allow');
  });

  it('does not allow when command does not match prefix', () => {
    expect(evaluatePermission('Bash', { command: 'rm -rf /' }, s)).toBe('ask');
    expect(evaluatePermission('Bash', { command: 'cat file' }, s)).toBe('ask');
  });
});

describe('evaluatePermission — ask precedence', () => {
  it('returns "ask" when ask-rule matches even if broader allow exists', () => {
    const s: PermissionSettings = { allow: ['Bash(*)'], ask: ['Bash(rm:*)'] };
    expect(evaluatePermission('Bash', { command: 'rm -rf node_modules' }, s)).toBe('ask');
    expect(evaluatePermission('Bash', { command: 'ls -la' }, s)).toBe('allow');
  });
});

describe('evaluatePermission — malformed rules are ignored', () => {
  it('ignores empty strings, returns default', () => {
    const s: PermissionSettings = { allow: [''], ask: [] };
    expect(evaluatePermission('Bash', { command: 'x' }, s)).toBe('ask');
  });

  it('ignores non-matching rule (e.g. missing close paren) silently', () => {
    const s: PermissionSettings = { allow: ['Bash(*', 'Bash(*)'], ask: [] };
    expect(evaluatePermission('Bash', { command: 'x' }, s)).toBe('allow');
  });
});

describe('readPermissionSettings', () => {
  let baseDir: string;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'perm-matcher-'));
  });

  afterEach(async () => {
    await rm(baseDir, { recursive: true, force: true });
  });

  it('returns empty lists when file is missing', () => {
    expect(readPermissionSettings(join(baseDir, 'missing.json'))).toEqual({
      allow: [],
      ask: [],
    });
  });

  it('returns empty lists when file has no permissions block', async () => {
    const path = join(baseDir, 'settings.json');
    await writeFile(path, JSON.stringify({ hooks: {} }));
    expect(readPermissionSettings(path)).toEqual({ allow: [], ask: [] });
  });

  it('reads allow and ask arrays when present', async () => {
    const path = join(baseDir, 'settings.json');
    await writeFile(
      path,
      JSON.stringify({
        permissions: {
          allow: ['Bash(*)', 'mcp__github__*'],
          ask: ['Bash(rm:*)'],
        },
      }),
    );
    expect(readPermissionSettings(path)).toEqual({
      allow: ['Bash(*)', 'mcp__github__*'],
      ask: ['Bash(rm:*)'],
    });
  });

  it('filters out non-string entries silently', async () => {
    const path = join(baseDir, 'settings.json');
    await writeFile(
      path,
      JSON.stringify({
        permissions: { allow: ['Bash(*)', 42, null], ask: [true, 'Bash(rm:*)'] },
      }),
    );
    expect(readPermissionSettings(path)).toEqual({
      allow: ['Bash(*)'],
      ask: ['Bash(rm:*)'],
    });
  });

  it('returns empty lists on malformed JSON', async () => {
    const path = join(baseDir, 'settings.json');
    await writeFile(path, '{ not valid');
    expect(readPermissionSettings(path)).toEqual({ allow: [], ask: [] });
  });
});

describe('mergePermissionSettings', () => {
  it('concatenates both lists', () => {
    const a: PermissionSettings = { allow: ['Bash(*)'], ask: ['Bash(rm:*)'] };
    const b: PermissionSettings = { allow: ['Read'], ask: [] };
    expect(mergePermissionSettings(a, b)).toEqual({
      allow: ['Bash(*)', 'Read'],
      ask: ['Bash(rm:*)'],
    });
  });
});

describe('readPermissionSettingsForCwd', () => {
  let baseDir: string;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'perm-cwd-'));
    await mkdir(join(baseDir, '.claude'), { recursive: true });
  });

  afterEach(async () => {
    await rm(baseDir, { recursive: true, force: true });
  });

  it('merges shared settings.json and settings.local.json', async () => {
    await writeFile(
      join(baseDir, '.claude', 'settings.json'),
      JSON.stringify({ permissions: { allow: ['Read'], ask: [] } }),
    );
    await writeFile(
      join(baseDir, '.claude', 'settings.local.json'),
      JSON.stringify({ permissions: { allow: ['Bash(*)'], ask: ['Bash(rm:*)'] } }),
    );
    expect(readPermissionSettingsForCwd(baseDir)).toEqual({
      allow: ['Read', 'Bash(*)'],
      ask: ['Bash(rm:*)'],
    });
  });

  it('returns empty sets when neither file exists', () => {
    expect(readPermissionSettingsForCwd(baseDir)).toEqual({ allow: [], ask: [] });
  });

  it('works when only settings.local.json exists', async () => {
    await writeFile(
      join(baseDir, '.claude', 'settings.local.json'),
      JSON.stringify({ permissions: { allow: ['Glob'] } }),
    );
    expect(readPermissionSettingsForCwd(baseDir)).toEqual({ allow: ['Glob'], ask: [] });
  });
});
