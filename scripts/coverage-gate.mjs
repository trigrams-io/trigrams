#!/usr/bin/env node
import { readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { relative, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const sourcePrefixes = ['apps/Trigrams/Sources/', 'agent/src/'];
const files = new Map();
const metadata = new Map();
for (const argument of process.argv.slice(2)) {
  const input = readFileSync(resolve(root, argument), 'utf8');
  for (const record of input.split('end_of_record')) {
    const source = /^SF:(.+)$/m.exec(record)?.[1];
    if (!source) continue;
    const path = relative(root, resolve(root, source)).replaceAll('\\', '/');
    if (!sourcePrefixes.some(prefix => path.startsWith(prefix))) {
      throw new Error(`Unexpected non-production coverage path: ${path}`);
    }
    if (files.has(path)) throw new Error(`Duplicate coverage source ${path}; merge executions with the coverage tool before running the gate.`);
    const lines = new Map();
    for (const match of record.matchAll(/^DA:(\d+),(\d+)/gm)) {
      const line = Number(match[1]);
      lines.set(line, Math.max(lines.get(line) ?? 0, Number(match[2])));
    }
    files.set(path, lines);
    metadata.set(path, record.split('\n').filter(line => /^(?:FN|FNDA|FNF|FNH|BRDA|BRF|BRH):/.test(line)));
  }
}

function sourceFiles(directory) {
  return readdirSync(directory).flatMap(name => {
    const path = resolve(directory, name);
    return statSync(path).isDirectory() ? sourceFiles(path) : /\.(swift|ts)$/.test(path) && !path.endsWith('.d.ts') ? [relative(root, path)] : [];
  });
}
const missing = sourcePrefixes.flatMap(prefix => sourceFiles(resolve(root, prefix))).filter(path => !files.has(path));
if (missing.length) throw new Error(`Production sources missing from coverage (never silently excluded):\n${missing.join('\n')}`);

const groups = [
  ['Native app', path => path.startsWith(sourcePrefixes[0])],
  ['pi runtime', path => path.startsWith(sourcePrefixes[1])],
  ['Combined production', () => true],
];
const summary = {};
let failed = false;
for (const [name, accepts] of groups) {
  const counts = [...files].filter(([path]) => accepts(path)).flatMap(([, lines]) => [...lines.values()]);
  const covered = counts.filter(count => count > 0).length;
  const total = counts.length;
  const percent = total ? covered / total * 100 : 0;
  summary[name] = { covered, total, percent };
  console.log(`${name}: ${percent.toFixed(2)}% (${covered}/${total} executed production lines; required >80%)`);
  if (!total || percent <= 80) failed = true;
}
const combined = [...files].sort(([a], [b]) => a.localeCompare(b)).map(([path, lines]) => {
  const covered = [...lines.values()].filter(count => count > 0).length;
  return `TN:Trigrams end-to-end\nSF:${path}\n${metadata.get(path).join('\n')}\n${[...lines].sort(([a], [b]) => a - b).map(([line, count]) => `DA:${line},${count}`).join('\n')}\nLF:${lines.size}\nLH:${covered}\nend_of_record\n`;
}).join('');
writeFileSync(resolve(root, 'build/coverage/production.lcov'), combined);
writeFileSync(resolve(root, 'build/coverage/summary.json'), JSON.stringify(summary, null, 2));
if (failed) {
  console.error('Coverage gate failed. Add an end-to-end scenario for the uncovered behavior; do not omit production source paths.');
  process.exitCode = 1;
}
