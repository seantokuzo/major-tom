import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    globals: false,
    setupFiles: ['./src/__tests__/setup.ts'],
    include: ['src/**/__tests__/**/*.test.ts', 'src/**/*.test.ts'],
    // Stray git worktrees from prior agents (and their stale builds) live
    // under `.claude/worktrees/`. Without this exclude, vitest discovers
    // their `src/**` and runs old/broken copies of these tests.
    exclude: ['**/node_modules/**', '**/dist/**', '**/.claude/**'],
    pool: 'forks',
    testTimeout: 10_000,
    hookTimeout: 10_000,
  },
});
