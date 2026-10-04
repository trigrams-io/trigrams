#!/usr/bin/env node
import { closeSync, copyFileSync, lstatSync, openSync, readSync, readdirSync, renameSync, rmSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

const [root, ...options] = process.argv.slice(2);
if (!root || !options.length) throw new Error('Expected a runtime directory and codesign options.');
const magic = new Set([0xfeedface, 0xcefaedfe, 0xfeedfacf, 0xcffaedfe, 0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca]);
const header = Buffer.alloc(4);
function sign(directory) {
  for (const name of readdirSync(directory)) {
    const path = join(directory, name);
    const info = lstatSync(path);
    if (info.isDirectory()) { sign(path); continue; }
    if (!info.isFile() || info.size < 4) continue;
    const descriptor = openSync(path, 'r');
    let candidate;
    try { candidate = readSync(descriptor, header, 0, 4, 0) === 4 && magic.has(header.readUInt32BE()); }
    finally { closeSync(descriptor); }
    // Fat Mach-O shares a magic number with Java classes. Confirm candidates
    // before signing; ordinary dependency files need no subprocess per file.
    if (candidate && execFileSync('/usr/bin/file', ['-b', path], { encoding: 'utf8' }).includes('Mach-O')) {
      const staging = path + '.sign-' + randomUUID();
      try {
        copyFileSync(path, staging);
        execFileSync('/usr/bin/codesign', [...options, staging], { stdio: 'inherit' });
        renameSync(staging, path);
      } finally { rmSync(staging, { force: true }); }
    }
  }
}
sign(root);
