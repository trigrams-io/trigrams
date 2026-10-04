#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const resultBundle = resolve(process.argv[2] ?? 'build/UITests.xcresult');
const output = resolve(process.argv[3] ?? 'build/coverage/swift.lcov');
const report = JSON.parse(execFileSync('xcrun', ['xccov', 'view', '--report', '--json', resultBundle], { encoding: 'utf8' }));
const targets = report.targets.filter(target => target.name === 'Trigrams.app');
if (targets.length !== 1) throw new Error('Expected exactly one instrumented Trigrams.app target.');
const records = [];
const seen = new Set();
for (const file of targets[0].files) {
  const path = relative(root, file.path);
  if (!path.startsWith('apps/Trigrams/Sources/') || !path.endsWith('.swift')) continue;
  if (seen.has(path)) throw new Error(`Duplicate Swift coverage source: ${path}`);
  seen.add(path);
  const raw = execFileSync('xcrun', ['xccov', 'view', '--archive', '--file', file.path, resultBundle], { encoding: 'utf8' });
  const lines = [...raw.matchAll(/^\s*(\d+):\s*(\d+)(?:\s|$)/gm)].map(match => [Number(match[1]), Number(match[2])]);
  const covered = lines.filter(([, count]) => count > 0).length;
  if (lines.length !== file.executableLines || covered !== file.coveredLines) {
    throw new Error(`xccov report/archive line counts disagree for ${path}: report ${file.coveredLines}/${file.executableLines}; archive ${covered}/${lines.length}`);
  }
  records.push(`TN:macOS end-to-end\nSF:${path}\n${lines.map(([line, count]) => `DA:${line},${count}`).join('\n')}\nLF:${lines.length}\nLH:${covered}\nend_of_record\n`);
}
if (!records.length) throw new Error('No production Swift coverage was collected.');
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, records.join(''));
writeFileSync(resolve(dirname(output), 'xccov.json'), JSON.stringify(report, null, 2));
console.log(`Wrote measured Swift coverage for ${seen.size} source files to ${relative(root, output)}.`);
