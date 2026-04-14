import { beforeEach, afterEach } from 'vitest';

// Keep pino quiet unless a test overrides LOG_LEVEL explicitly.
if (!process.env['LOG_LEVEL']) {
  process.env['LOG_LEVEL'] = 'silent';
}

const ORIG_SHELL = process.env['SHELL'];

beforeEach(() => {
  process.env['SHELL'] = '/bin/bash';
});

afterEach(() => {
  if (ORIG_SHELL === undefined) {
    delete process.env['SHELL'];
  } else {
    process.env['SHELL'] = ORIG_SHELL;
  }
});
