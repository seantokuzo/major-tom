/**
 * QA-FIXES.md #10 — humanizeToolTask covers the short task-line shown on
 * the sprite inspector when a PTY-launched subagent transitions to
 * `.working`. Keep the assertions tight so future tweaks (new tools,
 * shorter truncation) surface as test failures instead of silent UX drift.
 */
import { describe, it, expect } from 'vitest';

import { humanizeToolTask } from '../hook-server.js';

describe('humanizeToolTask', () => {
  it('Read → basename of file_path', () => {
    expect(humanizeToolTask('Read', { file_path: '/Users/x/src/deep/foo.ts' })).toBe(
      'Reading foo.ts',
    );
    expect(humanizeToolTask('Read', {})).toBe('Reading a file');
  });

  it('Edit / MultiEdit → basename', () => {
    expect(humanizeToolTask('Edit', { file_path: '/a/b/c.swift' })).toBe('Editing c.swift');
    expect(humanizeToolTask('MultiEdit', { file_path: '/x/y.md' })).toBe('Editing y.md');
  });

  it('Write → basename', () => {
    expect(humanizeToolTask('Write', { file_path: '/tmp/out.log' })).toBe('Writing out.log');
  });

  it('Bash → first word of command', () => {
    expect(humanizeToolTask('Bash', { command: 'git status' })).toBe('Running git');
    expect(humanizeToolTask('Bash', { command: 'npm run test:ci' })).toBe('Running npm');
    expect(humanizeToolTask('Bash', {})).toBe('Running a shell command');
  });

  it('Grep / Glob → pattern', () => {
    expect(humanizeToolTask('Grep', { pattern: 'TODO' })).toBe('Searching: TODO');
    expect(humanizeToolTask('Glob', { pattern: '**/*.ts' })).toBe('Globbing **/*.ts');
  });

  it('WebFetch / WebSearch → url/query', () => {
    expect(humanizeToolTask('WebFetch', { url: 'https://claude.com' })).toBe(
      'Fetching https://claude.com',
    );
    expect(humanizeToolTask('WebSearch', { query: 'xcodebuild' })).toBe(
      'Searching web: xcodebuild',
    );
  });

  it('Agent / Task → subagent type', () => {
    expect(humanizeToolTask('Agent', { subagent_type: 'Explore' })).toBe('Spawning Explore');
    expect(humanizeToolTask('Task', { description: 'audit deps' })).toBe('Spawning audit deps');
  });

  it('falls back to the raw tool name', () => {
    expect(humanizeToolTask('MysteryTool', {})).toBe('MysteryTool');
  });

  it('truncates long descriptions with ellipsis', () => {
    const long = 'x'.repeat(200);
    const result = humanizeToolTask('WebSearch', { query: long });
    expect(result.length).toBeLessThanOrEqual(50);
    expect(result.endsWith('…')).toBe(true);
  });
});
