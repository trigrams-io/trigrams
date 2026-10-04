import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { createConnection } from 'node:net';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { once } from 'node:events';
export const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
export const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
export async function fixture() {
  const base = process.env.GITHUB_ACTIONS === 'true' ? process.env.TMPDIR || process.env.RUNNER_TEMP : '/Volumes/SSD/Developer/Codex/tmp';
  if (!base) throw new Error('CI must configure its temporary directory.');
  if (process.env.GITHUB_ACTIONS !== 'true') await stat('/Volumes/SSD');
  await mkdir(base, { recursive: true });
  const dir = await mkdtemp(join(base, 'tri-'));
  const agentDir = join(dir, 'a'); const cwd = join(dir, 'w');
  await mkdir(agentDir); await mkdir(cwd);
  return { dir, agentDir, cwd, async dispose() { await rm(dir, { recursive: true, force: true }); } };
}
export async function start(f, { profile = 'community', capabilities = ['terminal-v1'] } = {}) {
  const path = join(f.dir, `s${Math.random().toString(36).slice(2, 7)}`);
  const token = 'integration-private-token-0123456789';
  const child = spawn(process.execPath, [join(root, 'agent/dist/main.js'), '--socket', path, '--token', token, '--agent-dir', f.agentDir, '--cwd', f.cwd, '--profile', profile], { cwd: root, env: { ...process.env, TMPDIR: process.env.GITHUB_ACTIONS === 'true' ? process.env.TMPDIR || process.env.RUNNER_TEMP : '/Volumes/SSD/Developer/Codex/tmp' }, stdio: ['ignore', 'pipe', 'pipe'] });
  let logs = ''; child.stderr.on('data', data => logs += data); child.stdout.on('data', data => logs += data);
  for (let i = 0; i < 400; i++) {
    if (child.exitCode !== null) throw new Error(`Runtime exited: ${logs}`);
    if (await stat(path).then(() => true).catch(() => false)) break;
    await pause(10);
  }
  const socket = createConnection(path); await once(socket, 'connect');
  let buffer = ''; let nextID = 0; const pending = new Map(); const events = [];
  const waiters = new Set();
  socket.setEncoding('utf8');
  socket.on('data', data => {
    buffer += data;
    let i;
    while ((i = buffer.indexOf('\n')) >= 0) {
      const message = JSON.parse(buffer.slice(0, i)); buffer = buffer.slice(i + 1);
      if (message.id !== undefined) {
        const p = pending.get(message.id); pending.delete(message.id);
        if (message.error) p?.reject(Object.assign(new Error(message.error.message), { code: message.error.code })); else p?.resolve(message.result);
      } else { events.push(message); for (const waiter of waiters) waiter(); }
    }
  });
  socket.on('error', error => { for (const p of pending.values()) p.reject(error); pending.clear(); });
  const request = (method, params = {}) => new Promise((resolve, reject) => { const id = String(++nextID); pending.set(id, { resolve, reject }); socket.write(JSON.stringify({ id, method, params }) + '\n'); });
  const event = (name, predicate = () => true, after = 0, timeout = 8000) => new Promise((resolve, reject) => {
    const find = () => { const value = events.slice(after).find(e => e.event === name && predicate(e.params)); if (value) { clearTimeout(timer); waiters.delete(find); resolve(value.params); } };
    const timer = setTimeout(() => { waiters.delete(find); reject(new Error(`Timed out on ${name}. Logs: ${logs}\nEvents: ${JSON.stringify(events.slice(-5))}`)); }, timeout);
    waiters.add(find); find();
  });
  const hello = await request('hello', { version: 1, token, capabilities });
  return { child, path, socket, request, event, events, hello, logs: () => logs,
    async stop() { socket.end(); if (child.exitCode === null) { child.kill('SIGTERM'); await Promise.race([once(child, 'exit'), pause(5000).then(() => { child.kill('SIGKILL'); throw new Error(`Runtime failed to stop: ${logs}`); })]); } }
  };
}
export async function respond(peer, after, response) {
  const generation = await peer.event('model.generate', () => true, after);
  await peer.request('model.complete', { id: generation.id, response });
  return generation;
}
export async function answer(peer, text) {
  const after = peer.events.length; await peer.request('session.prompt', { text });
  await respond(peer, after, { text: `Answer: ${text}`, toolCalls: [] });
  return peer.event('session.snapshot', p => p.status === 'idle', after);
}
export async function save(path, content) { await mkdir(resolve(path, '..'), { recursive: true }); await writeFile(path, content); }
