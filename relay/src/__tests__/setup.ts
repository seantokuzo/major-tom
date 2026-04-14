import { beforeEach, afterEach } from 'vitest';

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
