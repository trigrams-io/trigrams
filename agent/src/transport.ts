import { chmod, lstat, mkdir, unlink } from 'node:fs/promises';
import { createServer, type Server, type Socket } from 'node:net';
import { dirname } from 'node:path';
import { timingSafeEqual } from 'node:crypto';

export class ProtocolError extends Error {
  constructor(public code: string, message: string) { super(message); }
}
export type Params = Record<string, unknown>;
export type Handler = (method: string, params: Params) => Promise<unknown>;
const MAX_FRAME = 4 * 1024 * 1024;
const MAX_BUFFER = 16 * 1024 * 1024;

/** One authenticated app connection; stdout is intentionally outside the protocol. */
export class Transport {
  private server?: Server;
  private peer?: Socket;
  private sockets = new Set<Socket>();
  onDisconnect?: () => void;
  constructor(private path: string, private token: string, private handler: Handler) {}
  async start() {
    await mkdir(dirname(this.path), { recursive: true, mode: 0o700 });
    const directory = await lstat(dirname(this.path));
    if (!directory.isDirectory() || directory.isSymbolicLink() || directory.uid !== process.getuid?.()) {
      throw new ProtocolError('transport.directory', 'Socket directory must be owned by the current user.');
    }
    await chmod(dirname(this.path), 0o700);
    try { await lstat(this.path); throw new ProtocolError('transport.exists', 'Socket path already exists.'); }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
    this.server = createServer(socket => this.connect(socket));
    await new Promise<void>((resolve, reject) => {
      this.server!.once('error', reject);
      this.server!.listen(this.path, () => { this.server!.off('error', reject); resolve(); });
    });
    await chmod(this.path, 0o600);
  }
  private connect(socket: Socket) {
    this.sockets.add(socket);
    let buffer = Buffer.alloc(0);
    let authenticated = false;
    const helloTimeout = setTimeout(() => socket.destroy(), 5000);
    socket.on('error', () => socket.destroy());
    socket.on('close', () => {
      clearTimeout(helloTimeout);
      this.sockets.delete(socket);
      if (this.peer === socket) { this.peer = undefined; this.onDisconnect?.(); }
    });
    socket.on('data', chunk => {
      buffer = Buffer.concat([buffer, chunk]);
      let newline: number;
      while ((newline = buffer.indexOf(10)) !== -1) {
        if (newline > MAX_FRAME) { socket.destroy(); return; }
        const line = buffer.subarray(0, newline); buffer = buffer.subarray(newline + 1);
        let request: unknown;
        try { request = JSON.parse(line.toString('utf8')); }
        catch { this.send(socket, { id: '', error: { code: 'protocol.json', message: 'Invalid JSON frame.' } }); continue; }
        const r = request as { id?: unknown; method?: unknown; params?: unknown };
        if (!r || typeof r.id !== 'string' || r.id.length > 256 || typeof r.method !== 'string' ||
            !r.params || typeof r.params !== 'object' || Array.isArray(r.params)) {
          this.send(socket, { id: typeof r?.id === 'string' ? r.id : '', error: { code: 'protocol.request', message: 'Expected {id,method,params}.' } }); continue;
        }
        const params = r.params as Params;
        if (!authenticated) {
          const supplied = typeof params.token === 'string' ? Buffer.from(params.token) : Buffer.alloc(0);
          const expected = Buffer.from(this.token);
          if (r.method !== 'hello' || params.version !== 1 || supplied.length !== expected.length || !timingSafeEqual(supplied, expected) || this.peer) {
            this.send(socket, { id: r.id, error: { code: 'protocol.authentication', message: 'Handshake rejected.' } }); socket.end(); return;
          }
          authenticated = true; clearTimeout(helloTimeout); this.peer = socket;
        } else if (r.method === 'hello') {
          this.send(socket, { id: r.id, error: { code: 'protocol.handshake', message: 'Already authenticated.' } }); continue;
        }
        const id = r.id; const method = r.method;
        void this.handler(method, params).then(result => this.send(socket, { id, result }), error => {
          this.send(socket, { id, error: { code: error instanceof ProtocolError ? error.code : 'runtime.error', message: error instanceof Error ? error.message : String(error) } });
        });
      }
      if (buffer.length > MAX_FRAME) socket.destroy();
    });
  }
  private send(socket: Socket, value: unknown) {
    if (socket.destroyed || !socket.writable) return;
    const frame = JSON.stringify(value) + '\n';
    if (Buffer.byteLength(frame) > MAX_FRAME || socket.writableLength + Buffer.byteLength(frame) > MAX_BUFFER) { socket.destroy(new Error('Protocol backpressure limit exceeded.')); return; }
    socket.write(frame);
  }
  emit(event: string, params: unknown) {
    if (!this.peer) throw new ProtocolError('transport.disconnected', 'The native model/UI connection is unavailable.');
    this.send(this.peer, { event, params });
  }
  async close() {
    this.onDisconnect = undefined;
    for (const socket of this.sockets) socket.destroy();
    if (this.server?.listening) await new Promise<void>(resolve => this.server!.close(() => resolve()));
    await unlink(this.path).catch(error => { if (error.code !== 'ENOENT') throw error; });
  }
}
export function stringParam(params: Params, key: string): string {
  if (typeof params[key] !== 'string') throw new ProtocolError('protocol.params', `${key} must be a string.`);
  return params[key];
}
