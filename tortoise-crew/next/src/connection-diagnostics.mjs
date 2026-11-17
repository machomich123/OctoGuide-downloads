import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

// Two records per connection. No payloads, account names, URLs, messages or
// credentials are accepted. Disk writes are serialized outside the data path.
export function createConnectionDiagnostics(root, { version = '', maxBytes = 262144,
  maxPending = 32 } = {}) {
  const file = path.join(root, 'diagnostics', 'connections.jsonl');
  let queue = [], running = null, size = null, dropped = 0, disabled = false;
  const write = record => {
    if (disabled) return;
    if (queue.length >= maxPending) { dropped++; return; }
    queue.push(record);
    if (!running) running = drain();
  };
  async function drain() {
    try {
      await fs.mkdir(path.dirname(file), { recursive: true });
      if (size === null) size = await fs.stat(file).then(s => s.size, () => 0);
      while (queue.length) {
        const record = queue.shift();
        if (dropped) { record.droppedRecords = dropped; dropped = 0; }
        const line = JSON.stringify(record) + '\n';
        if (size + Buffer.byteLength(line) > maxBytes) {
          await fs.rm(file + '.1', { force: true });
          await fs.rename(file, file + '.1').catch(e => { if (e.code !== 'ENOENT') throw e; });
          size = 0;
        }
        await fs.appendFile(file, line, { mode: 0o600 });
        size += Buffer.byteLength(line);
      }
    } catch { disabled = true; queue = []; } // Diagnostics must never break gameplay.
    finally { running = null; }
  }
  return {
    file,
    async flush() { while (running) await running; },
    begin(mode, transport) {
      const id = crypto.randomUUID(), start = performance.now();
      const base = { schema: 1, version: /^\d+\.\d+\.\d+(?:[-.][a-zA-Z0-9]+)*$/.test(version) ? version.slice(0,40) : '', id,
        mode: mode === 'auth' ? 'auth' : 'world',
        transport: transport === 'prepared' ? 'prepared' : 'standard' };
      let socket, local, done = false, connected = false;
      let lastRead = 0, lastWrite = 0, lastActivity = start, lastTick = null;
      let pingAt = null, pingBytes = null, pings = 0, pongs = 0;
      let lastPong = null, rttMax = 0, driftMax = 0;
      const codes = new Set(['ECONNRESET','ECONNREFUSED','ECONNABORTED','ETIMEDOUT','EPIPE',
        'ENETUNREACH','EHOSTUNREACH','ENOTFOUND','EAI_AGAIN','ERR_STREAM_DESTROYED',
        'ERR_SSL_WRONG_VERSION_NUMBER','ERR_TLS_CERT_ALTNAME_INVALID',
        'UNABLE_TO_VERIFY_LEAF_SIGNATURE','CERT_HAS_EXPIRED','UNABLE_TO_GET_ISSUER_CERT_LOCALLY']);
      const safeCode = e => codes.has(e?.code) ? e.code : undefined;
      const sample = () => {
        const now = performance.now(), read = socket?.bytesRead || 0, written = socket?.bytesWritten || 0;
        if (read !== lastRead || written !== lastWrite) lastActivity = now;
        lastRead = read; lastWrite = written;
        return now;
      };
      write({ ...base, event: 'open', utc: new Date().toISOString() });
      return {
        id,
        bind(remote, client = null) { socket = remote; local = client; sample(); },
        connected() { connected = true; },
        // Called by the pre-existing 20-second heartbeat; no additional timer.
        ping(payload) {
          const now = sample();
          if (lastTick !== null) driftMax = Math.max(driftMax, Math.max(0, now - lastTick - 20000));
          lastTick = now; pingAt = now; pingBytes = payload; pings++;
        },
        pong(payload) {
          if (done) return;
          pongs++;lastPong = performance.now();
          if (pingAt !== null && pingBytes?.equals(payload))
            rttMax = Math.max(rttMax, lastPong - pingAt);
        },
        end(reason, error = null, closeCode = undefined) {
          if (done) return; done = true;
          // Last-activity age is heartbeat-sampled, not a precise packet timer.
          const now = performance.now();
          const allowed = new Set(['handshake_error','handshake_timeout','client_end','client_close',
            'client_error','remote_end','remote_close','remote_error','websocket_close',
            'decode_error','launcher_stop','stream_destroy']);
          write({ ...base, event: 'close', utc: new Date().toISOString(),
            reason: allowed.has(reason) ? reason : 'stream_destroy',
            connected, errorCode: safeCode(error),
            closeCode: Number.isInteger(closeCode) && closeCode >= 1000 && closeCode <= 4999 ? closeCode : undefined,
            durationMs: Math.round(now-start), remoteBytesRead: socket?.bytesRead || 0,
            remoteBytesWritten: socket?.bytesWritten || 0,
            clientBytesRead: local?.bytesRead || 0, clientBytesWritten: local?.bytesWritten || 0,
            heartbeatSampleAgeMs: Math.round(Math.max(0,now-lastActivity)),
            pings, pongs, lastPongAgeMs: lastPong === null ? null : Math.round(now-lastPong),
            maxPongRttMs: Math.round(rttMax), maxHeartbeatDriftMs: Math.round(driftMax) });
        },
      };
    },
  };
}
