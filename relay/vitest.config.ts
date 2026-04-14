import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    globals: false,
    setupFiles: ['./src/__tests__/setup.ts'],
    include: ['src/**/__tests__/**/*.test.ts', 'src/**/*.test.ts'],
    pool: 'forks',
    testTimeout: 10_000,
    hookTimeout: 10_000,
  },
});
