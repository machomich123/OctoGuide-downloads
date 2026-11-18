import net from 'node:net';
import tls from 'node:tls';
import crypto from 'node:crypto';
import { Duplex } from 'node:stream';
import { crewBaseUrl } from './config.mjs';
import { crewTrustOptions } from './remote.mjs';

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const LIMIT = 2 * 1024 * 1024;

export function encodeFrame(opcode, data = Buffer.alloc(0)) {
  const payload = Buffer.isBuffer(data) ? data : Buffer.from(data);
  if (payload.length > LIMIT) throw new Error('Game frame is too large.');
  const extension = payload.length < 126 ? 0 : payload.length < 65536 ? 2 : 8;
  const header = Buffer.alloc(2 + extension + 4);
  header[0] = 0x80 | opcode;
  header[1] = 0x80 | (extension === 0 ? payload.length : extension === 2 ? 126 : 127);
  if (extension === 2) header.writeUInt16BE(payload.length, 2);
  if (extension === 8) header.writeBigUInt64BE(BigInt(payload.length), 2);
  const start = 2 + extension;
  crypto.randomFillSync(header, start, 4);
  const masked = Buffer.from(payload);
  for (let i = 0; i < masked.length; i++) masked[i] ^= header[start + i % 4];
  return Buffer.concat([header, masked]);
}

// Strict RFC 6455 decoder for unmasked server frames (with fragmentation).
export class FrameDecoder {
  constructor(onBinary, onPing, onClose, onPong = () => {}) {
    this.buffer = Buffer.alloc(0);
    this.fragment = false;
    this.onBinary = onBinary;
    this.onPing = onPing;
    this.onClose = onClose;
    this.onPong = onPong;
  }
  push(data) {
    this.buffer = Buffer.concat([this.buffer, data]);
    if (this.buffer.length > LIMIT + 12) throw new Error('Game frame exceeds limit.');
    while (this.buffer.length >= 2) {
      const b0 = this.buffer[0], b1 = this.buffer[1];
      const fin = (b0 & 0x80) !== 0, opcode = b0 & 0x0f;
      if ((b0 & 0x70) !== 0 || (b1 & 0x80) !== 0) throw new Error('Invalid server WebSocket frame.');
      let n = b1 & 0x7f, offset = 2;
      if (n === 126) {
        if (this.buffer.length < 4) return;
        n = this.buffer.readUInt16BE(2);
        offset = 4;
      } else if (n === 127) {
        if (this.buffer.length < 10) return;
        const wide = this.buffer.readBigUInt64BE(2);
        if (wide > BigInt(LIMIT)) throw new Error('Oversized WebSocket frame.');
        n = Number(wide);
        offset = 10;
      }
      if (n > LIMIT || (opcode >= 8 && (!fin || n > 125))) throw new Error('Invalid frame length.');
      if (this.buffer.length < offset + n) return;
      const payload = this.buffer.subarray(offset, offset + n);
      this.buffer = this.buffer.subarray(offset + n);
      if (opcode === 8) { this.onClose(payload.length >= 2 ? payload.readUInt16BE(0) : 1005); return; }
      if (opcode === 9) { this.onPing(payload); continue; }
      if (opcode === 10) { this.onPong(payload); continue; }
      if (opcode === 2) {
        if (this.fragment) throw new Error('Nested WebSocket frames.');
        this.fragment = !fin;
      } else if (opcode === 0) {
        if (!this.fragment) throw new Error('Unexpected continuation.');
        this.fragment = !fin;
      } else throw new Error('Unexpected text frame on binary relay.');
      if (payload.length) this.onBinary(payload);
    }
  }
}

export async function connectWebSocket(base, mode, token, { trace = null } = {}) {
  if (!/^[0-9a-f]{64}$/i.test(token) || !['auth', 'world'].includes(mode)) {
    throw new Error('Invalid relay session.');
  }
  const endpoint = new URL(crewBaseUrl(base));
  const host = endpoint.hostname;
  return new Promise((resolve, reject) => {
    const key = crypto.randomBytes(16).toString('base64');
    const accept = crypto.createHash('sha1').update(key + GUID).digest('base64');
    const socket = tls.connect({
      host, port: Number(endpoint.port || 443), servername: host,
      rejectUnauthorized: true, ...crewTrustOptions(endpoint.origin),
    });
    socket.setNoDelay(true);
    socket.setKeepAlive(true, 30000);
    trace?.bind(socket);
    socket.setTimeout(12000);
    let pending = Buffer.alloc(0), finished = false;
    const fail = error => {
      trace?.end(error?.code === 'ETIMEDOUT' ? 'handshake_timeout' : 'handshake_error', error);
      if (!finished) { finished = true; reject(error); }
      socket.destroy();
    };
    socket.once('error', fail);
    socket.once('timeout', () => fail(Object.assign(new Error('Relay handshake timed out.'), { code: 'ETIMEDOUT' })));
    socket.once('secureConnect', () => socket.write([
      'GET /v1/relay/' + mode + ' HTTP/1.1',
      'Host: ' + endpoint.host, 'Upgrade: websocket', 'Connection: Upgrade',
      'Sec-WebSocket-Version: 13', 'Sec-WebSocket-Key: ' + key,
      'Authorization: Bearer ' + token, '', '',
    ].join('\r\n')));
    function receive(bytes) {
      pending = Buffer.concat([pending, bytes]);
      if (pending.length > 16 * 1024) return fail(new Error('Oversized relay response.'));
      const end = pending.indexOf('\r\n\r\n');
      if (end < 0) return;
      const header = pending.subarray(0, end).toString('latin1');
      const match = /^sec-websocket-accept:\s*(.+)$/im.exec(header);
      if (!/^HTTP\/1\.[01] 101\b/.test(header) || !match || match[1].trim() !== accept) {
        return fail(new Error('Crew relay rejected its WebSocket handshake.'));
      }
      socket.off('data', receive);
      socket.off('error', fail);
      socket.setTimeout(0);
      finished = true;
      trace?.connected();
      resolve({ socket, initial: pending.subarray(end + 4) });
    }
    socket.on('data', receive);
    socket.once('close', () => { if (!finished) fail(new Error('Relay closed during handshake.')); });
  });
}

// A binary stream over the existing authenticated TLS relay. No listener or
// WoW process is needed to prepare a session through this stream.
export async function openRelayStream(base, mode, token, { diagnostics = null,
  connect = connectWebSocket } = {}) {
  const trace = diagnostics?.begin(mode, 'prepared');
  let connection;
  try { connection = await connect(base, mode, token, { trace }); }
  catch (error) { trace?.end('handshake_error', error); throw error; }
  const { socket, initial } = connection;
  trace?.bind(socket);trace?.connected();
  const stream = new Duplex({
    read() { socket.resume(); },
    write(bytes, encoding, done) { socket.write(encodeFrame(2, bytes), done); },
    destroy(error, done) { trace?.end('stream_destroy', error); clearInterval(ping); socket.destroy(); done(error); },
  });
  const decoder = new FrameDecoder(
    bytes => { if (!stream.push(bytes)) socket.pause(); },
    bytes => socket.write(encodeFrame(10, bytes)),
    code => { trace?.end('websocket_close', null, code); stream.destroy(); },
    payload => trace?.pong(payload),
  );
  const receive = bytes => { try { decoder.push(bytes); } catch (error) { trace?.end('decode_error', error); stream.destroy(error); } };
  socket.on('data', receive);
  socket.on('error', error => { trace?.end('remote_error', error); stream.destroy(error); });
  socket.on('end', () => { trace?.end('remote_end'); });
  socket.on('close', () => { trace?.end('remote_close'); stream.push(null); stream.destroy(); });
  let sequence = 0;
  const ping = setInterval(() => {
    if (!socket.destroyed) {
      const payload = Buffer.allocUnsafe(4);payload.writeUInt32BE(++sequence >>> 0);
      trace?.ping(payload);socket.write(encodeFrame(9, payload));
    }
  }, 20000);
  ping.unref();
  stream.endDiagnostics = (reason, error = null) => trace?.end(reason, error);
  stream.bindDiagnosticsClient = client => trace?.bind(socket, client);
  if (initial.length) queueMicrotask(() => receive(initial));
  return stream;
}

export class GameRelay {
  constructor(baseUrl, token, { diagnostics = null, connect = connectWebSocket } = {}) {
    this.baseUrl = baseUrl;
    this.token = token;
    this.listeners = [];
    this.clients = new Set();
    this.diagnostics = diagnostics;this.connect = connect;this.traces = new Map();
  }
  async start() {
    try {
      for (const [mode, port] of [['auth', 3724], ['world', 8085]]) {
        const listener = net.createServer(client => this.forward(client, mode));
        await new Promise((resolve, reject) => {
          listener.once('error', reject);
          listener.listen({ host: '127.0.0.1', port, exclusive: true }, () => {
            listener.off('error', reject);
            resolve();
          });
        });
        this.listeners.push(listener);
      }
    } catch (error) {
      await this.stop();
      throw error;
    }
  }
  async forward(client, mode) {
    this.clients.add(client);
    client.setNoDelay?.(true);
    const trace = this.diagnostics?.begin(mode, 'standard');
    this.traces.set(client, trace);
    client.pause();
    let remote, ping, closed = false;
    const close = (reason = 'stream_destroy', error = null, code = undefined) => {
      if (closed) return;closed = true;
      trace?.end(reason, error, code);
      if (ping) clearInterval(ping);
      client.destroy();
      remote?.destroy();
      this.clients.delete(client);
      this.traces.delete(client);
    };
    client.once('end', () => trace?.end('client_end'));
    client.once('close', () => close('client_close'));
    client.once('error', error => close('client_error', error));
    try {
      const connection = await this.connect(this.baseUrl, mode, this.token, { trace });
      remote = connection.socket;
      trace?.bind(remote, client);trace?.connected();
      if (closed || client.destroyed) { remote.destroy();close('client_close');return; }
      const decoder = new FrameDecoder(
        data => { if (!client.write(data)) remote.pause(); },
        data => remote.write(encodeFrame(10, data)),
        code => close('websocket_close', null, code),
        payload => trace?.pong(payload),
      );
      client.on('data', bytes => { if (!remote.write(encodeFrame(2, bytes))) client.pause(); });
      client.on('drain', () => remote.resume());
      remote.on('drain', () => client.resume());
      remote.on('data', bytes => { try { decoder.push(bytes); } catch (error) { close('decode_error', error); } });
      remote.once('end', () => trace?.end('remote_end'));
      remote.once('close', () => close('remote_close'));
      remote.once('error', error => close('remote_error', error));
      let sequence = 0;
      ping = setInterval(() => {
        if (!remote.destroyed) {
          const payload = Buffer.allocUnsafe(4);payload.writeUInt32BE(++sequence >>> 0);
          trace?.ping(payload);remote.write(encodeFrame(9, payload));
        }
      }, 20000);
      ping.unref();
      if (connection.initial.length) decoder.push(connection.initial);
      client.resume();
    } catch (error) { close('handshake_error', error); }
  }
  async stop() {
    for (const trace of this.traces.values()) trace?.end('launcher_stop');
    for (const client of [...this.clients]) client.destroy();
    this.clients.clear();
    await Promise.all(this.listeners.map(s => new Promise(done => s.close(done))));
    this.listeners = [];
  }
}
