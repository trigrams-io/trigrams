import { resolve } from 'node:path';
import { Transport, ProtocolError } from './transport.js';
import { Runtime } from './runtime.js';

const args = new Map<string, string>();
for (let i = 2; i < process.argv.length; i += 2) {
  const key = process.argv[i]; const value = process.argv[i + 1];
  if (!key?.startsWith('--') || !value) throw new ProtocolError('startup.arguments', 'Expected --socket PATH --token TOKEN --agent-dir DIR --cwd DIR [--profile community|store].');
  args.set(key, value);
}
function required(key: string) { const value = args.get(key); if (!value) throw new ProtocolError('startup.arguments', `Missing ${key}.`); return value; }
const profile = args.get('--profile') ?? 'community';
if (profile !== 'community' && profile !== 'store') throw new ProtocolError('startup.profile', 'profile must be community or store.');
const token = required('--token');
if (Buffer.byteLength(token) < 32) throw new ProtocolError('startup.token', 'Handshake token must contain at least 32 bytes.');
const socketPath = resolve(required('--socket'));
// Upstream built-in extensions consult this supported process-wide override.
process.env.PI_CODING_AGENT_DIR = resolve(required('--agent-dir'));
let transport: Transport;
const runtime = new Runtime({ cwd: resolve(required('--cwd')), agentDir: resolve(required('--agent-dir')), profile }, (event, params) => transport.emit(event, params));
transport = new Transport(socketPath, token, (method, params) => runtime.handle(method, params));
transport.onDisconnect = () => {
  runtime.disconnect();
  void shutdown().then(() => process.exit(0), error => { console.error(error); process.exit(1); });
};
let closing = false;
async function shutdown() {
  if (closing) return; closing = true;
  await runtime.dispose(); await transport.close();
}
process.once('SIGTERM', () => { void shutdown().then(() => process.exit(0), error => { console.error(error); process.exit(1); }); });
process.once('SIGINT', () => { void shutdown().then(() => process.exit(0), error => { console.error(error); process.exit(1); }); });
try { await runtime.initialize(); await transport.start(); console.error('Trigrams pi runtime ready.'); }
catch (error) { console.error(error); process.exitCode = 1; }
