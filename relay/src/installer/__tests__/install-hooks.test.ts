import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { buildSettingsJson, importUserPermissions } from '../install-hooks.js';

describe('installer: importUserPermissions', () => {
  let baseDir: string;

  beforeEach(async () => {
    baseDir = await mkdtemp(join(tmpdir(), 'installer-perms-'));
  });

  afterEach(async () => {
    await rm(baseDir, { recursive: true, force: true });
  });

  it('returns null when settings.json is missing', () => {
    expect(importUserPermissions(join(baseDir, 'missing.json'))).toBeNull();
  });

  it('returns null when settings.json has no permissions block', async () => {
    const path = join(baseDir, 'settings.json');
    await writeFile(path, JSON.stringify({ hooks: {} }));
    expect(importUserPermissions(path)).toBeNull();
  });

  it('returns the permissions block when present', async () => {
    const path = join(baseDir, 'settings.json');
    const permissions = {
      allow: ['Bash(*)', 'mcp__github__*'],
      ask: ['Bash(rm:*)'],
    };
    await writeFile(path, JSON.stringify({ permissions, hooks: {} }));
    expect(importUserPermissions(path)).toEqual(permissions);
  });

  it('returns null on malformed JSON (does not throw)', async () => {
    const path = join(baseDir, 'settings.json');
    await writeFile(path, '{ not valid json');
    expect(importUserPermissions(path)).toBeNull();
  });
});

describe('installer: buildSettingsJson', () => {
  it('emits only hooks when userPermissions is null', () => {
    const raw = buildSettingsJson(null);
    const parsed = JSON.parse(raw);
    expect(parsed.hooks).toBeDefined();
    expect(parsed.permissions).toBeUndefined();
  });

  it('emits only hooks when userPermissions is undefined', () => {
    const raw = buildSettingsJson(undefined);
    const parsed = JSON.parse(raw);
    expect(parsed.permissions).toBeUndefined();
  });

  it('merges userPermissions into the top-level permissions field', () => {
    const perms = { allow: ['Bash(*)'], ask: ['Bash(rm:*)'] };
    const raw = buildSettingsJson(perms);
    const parsed = JSON.parse(raw);
    expect(parsed.permissions).toEqual(perms);
    expect(parsed.hooks).toBeDefined();
  });

  it('preserves all hook entries (PreToolUse, SubagentStart/Stop, SessionStart, Stop)', () => {
    const parsed = JSON.parse(buildSettingsJson(null));
    expect(parsed.hooks.PreToolUse).toHaveLength(1);
    expect(parsed.hooks.SubagentStart).toHaveLength(1);
    expect(parsed.hooks.SubagentStop).toHaveLength(1);
    expect(parsed.hooks.SessionStart).toHaveLength(1);
    expect(parsed.hooks.Stop).toHaveLength(1);
  });

  it('keeps PreToolUse timeout at 600s', () => {
    const parsed = JSON.parse(buildSettingsJson(null));
    expect(parsed.hooks.PreToolUse[0].hooks[0].timeout).toBe(600);
  });
});
