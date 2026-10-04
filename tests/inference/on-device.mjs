import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fixture, start } from '../runtime/peer.mjs';

const driver = process.argv[2];
if (!driver) throw new Error('Run scripts/test-on-device.sh on an Apple Intelligence-capable Mac.');
const f = await fixture();
const peer = await start(f);
try {
  await peer.request('session.create');
  async function prompt(text) {
    let after = peer.events.length;
    await peer.request('session.prompt', { text });
    for (let step = 0; step < 8; step++) {
      const generation = await peer.event('model.generate', () => true, after, 60000);
      after = peer.events.length;
      const path = join(f.dir, 'inference.json');
      await writeFile(path, JSON.stringify(generation));
      const result = spawnSync(driver, [path], { encoding: 'utf8', timeout: 120000, maxBuffer: 4 * 1024 * 1024 });
      assert.equal(result.status, 0, result.stderr || String(result.error));
      const response = JSON.parse(result.stdout);
      await peer.request('model.complete', { id: generation.id, response });
      if (!response.toolCalls.length) {
        await peer.event('session.snapshot', snapshot => snapshot.status === 'idle', after, 60000);
        return { text: response.text, steps: step + 1 };
      }
    }
    assert.fail('The real model did not finish within eight inference steps.');
  }

  const first = await prompt('你知道 ASD-STE100 吗？不确定就说不确定，请用中文回答。');
  const second = await prompt('你会说中文吗？请直接用中文回答当前问题。');
  assert.notEqual(first.text, second.text);
  assert.match(second.text, /[\p{Script=Han}]/u);
  assert.equal((await prompt('现在换一个问题：7 加 8 等于几？请只回答数字。')).text.trim(), '15');
  console.log('PASS: real AFM changes topic and answers the current Chinese question.');

  await peer.request('session.create');
  await writeFile(join(f.cwd, 'message.txt'), '42');
  const read = await prompt('Read message.txt and tell me its contents. Use the read tool to verify it.');
  assert(read.steps > 1 && read.text.includes('42'));
  console.log('PASS: real AFM calls pi read and answers from its result, with the discovered global skills enabled.');
} finally {
  await peer.stop();
  await f.dispose();
}
