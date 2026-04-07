#!/usr/bin/env node
/**
 * Ensure node-pty's prebuilt `spawn-helper` binary is executable.
 *
 * `spawn-helper` ships inside the node-pty tarball, but some npm versions
 * strip the execute bit during install — which silently breaks `pty.spawn`
 * on macOS with a cryptic `posix_spawnp failed` error. We chmod +x any
 * `spawn-helper` we find under node-pty/prebuilds/*.
 *
 * Idempotent. Safe on platforms without node-pty (e.g. CI skipping deps).
 */
import { chmodSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const prebuildsDir = join(__dirname, '..', 'node_modules', 'node-pty', 'prebuilds');

if (!existsSync(prebuildsDir)) {
  // node-pty not installed (optional dep or CI skip) — nothing to do.
  process.exit(0);
}

let fixed = 0;
for (const entry of readdirSync(prebuildsDir)) {
  const helper = join(prebuildsDir, entry, 'spawn-helper');
  if (!existsSync(helper)) continue;
  try {
    const mode = statSync(helper).mode;
    // Add user/group/other execute bits (0o111).
    chmodSync(helper, mode | 0o111);
    fixed++;
  } catch (err) {
    console.warn(`[fix-node-pty-perms] failed to chmod ${helper}:`, err.message);
  }
}

if (fixed > 0) {
  console.log(`[fix-node-pty-perms] ensured +x on ${fixed} spawn-helper binary(ies)`);
}
