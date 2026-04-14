import { describe, it, expect } from 'vitest';

describe('vitest harness', () => {
  it('arithmetic still works', () => {
    expect(1 + 1).toBe(2);
  });

  it('SHELL is overridden by setup', () => {
    expect(process.env['SHELL']).toBe('/bin/bash');
  });
});
