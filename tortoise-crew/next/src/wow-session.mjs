import crypto from 'node:crypto';
import { deflateSync } from 'node:zlib';
import { EventEmitter } from 'node:events';
import { N_BYTES, hash, clientSession, serverChallenge, worldProof, HeaderCipher } from './wow-srp.mjs';

export const OP = Object.freeze({ AUTH_CHALLENGE: 0x1ec, AUTH_SESSION: 0x1ed,
  AUTH_RESPONSE: 0x1ee, CHAR_ENUM: 0x37, CHAR_LIST: 0x3b, PING: 0x1dc,
  PONG: 0x1dd, ADDON_INFO: 0x2ef, WARDEN: 0x2e6 });
export function u32(value) { const b = Buffer.alloc(4); b.writeUInt32LE(value); return b; }
const cstring = value => Buffer.from(value + '\0');
const equal = (a, b) => a.length === b.length && crypto.timingSafeEqual(a, b);

// A bounded, cancellable reader; TCP/WebSocket chunks are not packet boundaries.
export class Bytes {
  constructor(stream, timeoutMs = 12000) {
    this.stream = stream; this.timeoutMs = timeoutMs; this.buffer = Buffer.alloc(0);
    this.pending = null; this.failure = null;
    stream.on('data', bytes => {
      this.buffer = Buffer.concat([this.buffer, bytes]);
      if (this.buffer.length > 2 * 1024 * 1024) return this.fail(new Error('Protocol buffer limit.'));
      this.drain();
    });
    stream.on('error', error => this.fail(error));
    stream.on('close', () => this.fail(new Error('Session stream closed.')));
    stream.on('end', () => this.fail(new Error('Session stream ended.')));
  }
  fail(error) {
    this.failure ||= error;
    if (this.pending) { const p = this.pending; this.pending = null; clearTimeout(p.timer); p.reject(this.failure); }
  }
  drain() {
    if (!this.pending || this.buffer.length < this.pending.size) return;
    const p = this.pending; this.pending = null; clearTimeout(p.timer);
    const result = this.buffer.subarray(0, p.size); this.buffer = this.buffer.subarray(p.size); p.resolve(result);
  }
  read(size) {
    if (!Number.isInteger(size) || size < 0 || size > 1024*1024) return Promise.reject(new Error('Invalid read size.'));
    if (this.pending) return Promise.reject(new Error('Concurrent protocol read.'));
    if (this.failure) return Promise.reject(this.failure);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => this.fail(new Error('Session protocol timed out.')), this.timeoutMs);
      this.pending = { size, resolve, reject, timer }; this.drain();
    });
  }
  write(bytes) { if (this.failure) throw this.failure; this.stream.write(bytes); }
  destroy() { this.fail(new Error('Session disposed.')); this.stream.destroy(); this.buffer.fill(0); }
}

export function loginChallenge(account, build = 7272) {
  const name = Buffer.from(account.toUpperCase()), out = Buffer.alloc(34 + name.length);
  out[0] = 0; out[1] = 3; out.writeUInt16LE(out.length - 4, 2);
  out.write('WoW\0', 4, 'ascii'); out.set([1, 18, 1], 8); out.writeUInt16LE(build, 11);
  out.write('68x\0', 13, 'ascii'); out.write('niW\0', 17, 'ascii'); out.write('SUne', 21, 'ascii');
  out.set([127, 0, 0, 1], 29); out[33] = name.length; return Buffer.concat([out.subarray(0, 34), name]);
}
export async function authenticateWoW(stream, account, password, build = 7272) {
  const io = new Bytes(stream);
  try {
    io.write(loginChallenge(account, build));
    const status = await io.read(3);
    if (status[0] !== 0 || status[2] !== 0) throw new Error('WoW authentication challenge rejected: ' + status[2]);
    const B = await io.read(32), gl = (await io.read(1))[0], g = await io.read(gl);
    const nl = (await io.read(1))[0], n = await io.read(nl);
    if (!equal(g, Buffer.from([7])) || !equal(n, N_BYTES)) throw new Error('Unsupported SRP parameters.');
    const salt = await io.read(32); await io.read(16);
    const flags = (await io.read(1))[0];
    if (flags !== 0) throw new Error('Additional account authentication required.');
    const srp = clientSession(account, password, salt, B);
    try {
      // Turtle 1.18.1 is build 7272 using the Vanilla wire layout.
      if (build !== 7272) throw new Error('Unsupported prepared-login client build.');
      const versionProof = hash(srp.A, Buffer.alloc(20));
      io.write(Buffer.concat([Buffer.from([1]), srp.A, srp.proof, versionProof, Buffer.from([0, 0])]));
      const response = await io.read(2);
      if (response[0] !== 1 || response[1] !== 0) throw new Error('WoW authentication proof rejected: opcode=' + response[0] + ' result=' + response[1] + ' buffered=' + io.buffer.length + ' status=' + [...io.buffer.subarray(0, 1)]);
      const proof = await io.read(20); await io.read(4);
      if (!equal(proof, srp.serverProof)) throw new Error('WoW server proof mismatch.');
      io.write(Buffer.from([0x10, 0, 0, 0, 0]));
      const header = await io.read(3);
      if (header[0] !== 0x10) throw new Error('Unexpected realm response.');
      const realms = await io.read(header.readUInt16LE(1));
      const parsed = parseRealms(realms);
      return { key: Buffer.from(srp.key), realms: parsed, build };
    } finally { srp.key.fill(0); }
  } finally { io.destroy(); }
}

export function parseRealms(body) {
  if (body.length < 7) throw new Error('Truncated realm list.');
  const count = body[4]; let offset = 5; const realms = [];
  const string = () => { const end = body.indexOf(0, offset); if (end < 0 || end - offset > 255) throw new Error('Invalid realm string.');
    const text = body.toString('utf8', offset, end); offset = end + 1; return text; };
  for (let i = 0; i < count; i++) {
    if (offset + 5 > body.length) throw new Error('Truncated realm.');
    const type = body.readUInt32LE(offset), flags = body[offset+4]; offset += 5;
    const name = string(), address = string();
    if (offset + 7 > body.length) throw new Error('Truncated realm metadata.');
    const population = body.readFloatLE(offset), characters = body[offset+4], category = body[offset+5], id = body[offset+6]; offset += 7;
    realms.push({ type, flags, name, address, population, characters, category, id });
  }
  return realms;
}
export function realmResponse(realm, port) {
  const population = Buffer.alloc(4); population.writeFloatLE(realm.population);
  const body = Buffer.concat([Buffer.alloc(4), Buffer.from([1]), u32(realm.type), Buffer.from([realm.flags & ~3]),
    cstring(realm.name), cstring('127.0.0.1:' + port), population,
    Buffer.from([realm.characters, realm.category, realm.id]), Buffer.alloc(2)]);
  const header = Buffer.alloc(3); header[0] = 0x10; header.writeUInt16LE(body.length, 1);
  return Buffer.concat([header, body]);
}

export class WorldWire {
  constructor(stream, { server = false, timeoutMs = 12000 } = {}) {
    this.io = new Bytes(stream, timeoutMs); this.server = server; this.encrypt = null; this.decrypt = null;
  }
  arm(key) { this.encrypt = new HeaderCipher(key); this.decrypt = new HeaderCipher(key); }
  send(opcode, payload = Buffer.alloc(0)) {
    const header = Buffer.alloc(this.server ? 4 : 6);
    if (payload.length > 65529) throw new Error('World packet too large.');
    header.writeUInt16BE(payload.length + header.length - 2);
    if (this.server) header.writeUInt16LE(opcode, 2); else header.writeUInt32LE(opcode, 2);
    this.io.write(Buffer.concat([this.encrypt ? this.encrypt.encrypt(header) : header, payload]));
  }
  async receive() {
    const length = this.server ? 6 : 4;
    let header = await this.io.read(length);
    if (this.decrypt) header = this.decrypt.decrypt(header);
    const size = header.readUInt16BE(0) - (length-2);
    if (size < 0) throw new Error('Invalid world packet length.');
    return { opcode: this.server ? header.readUInt32LE(2) : header.readUInt16LE(2), payload: await this.io.read(size) };
  }
  destroy() { this.io.destroy(); this.encrypt?.destroy(); this.decrypt?.destroy(); }
}

export function addonInfoBlob(addons) {
  const entries = addons.map(name => Buffer.concat([cstring(name), Buffer.from([1]), u32(0x4c1c776d), u32(0)]));
  const raw = Buffer.concat(entries), compressed = deflateSync(raw);
  return Buffer.concat([u32(raw.length), compressed]);
}
export function authSessionPayload(account, build, clientSeed, serverSeed, key, addons = []) {
  const blob = Buffer.isBuffer(addons) ? addons : addonInfoBlob(addons);
  return Buffer.concat([u32(build), u32(0), cstring(account.toUpperCase()), clientSeed,
    worldProof(account, clientSeed, serverSeed, key), blob]);
}

// The upstream session is real: authenticated world socket and live character
// list, prepared without WoW.exe. Local SRP is independent and never reaches
// the remote auth server, so it cannot replace the upstream session key.
export class PreparedWorld extends EventEmitter {
  constructor({ account, key, stream, build = 7272, addons = null, report = () => {}, reopen = null, saveAddonInfo = () => {} }) {
    super(); this.account = account.toUpperCase(); this.key = key; this.build = build; this.addons = addons;
    this.wire = new WorldWire(stream, { timeoutMs: 12000 }); this.report = report;
    this.before = []; this.characterList = null; this.client = null; this.disposed = false; this.attached = false;
    this.pendingPings = new Set(); this.pingSequence = 0xf0000000;
    this.reopen = reopen; this.saveAddonInfo = saveAddonInfo;
    this.addonBlob = addons === null ? null : Buffer.isBuffer(addons) ? addons : addonInfoBlob(addons);
  }
  async prepare() {
    try {
      const challenge = await this.wire.receive();
      if (challenge.opcode !== OP.AUTH_CHALLENGE || challenge.payload.length !== 4) throw new Error('Unsupported world challenge.');
      this.serverSeed = challenge.payload;
      this.report('world-connection-ready');
      if (this.addonBlob === null) return this;
      return await this.authenticate(this.addonBlob);
    } catch (error) { this.destroy(); throw error; }
  }
  async authenticate(blob) {
    try {
      this.wire.send(OP.AUTH_SESSION, authSessionPayload(this.account, this.build, crypto.randomBytes(4), this.serverSeed, this.key, blob));
      this.wire.arm(this.key);
      const deadline = Date.now() + 15000;
      let accepted = false;
      while (!this.characterList) {
        if (Date.now() > deadline) throw new Error('World preparation timed out.');
        const packet = await this.wire.receive();
        this.check(packet);
        if (packet.opcode === OP.AUTH_RESPONSE) {
          if (packet.payload[0] !== 0x0c) throw new Error('World login not ready: ' + packet.payload[0]);
          accepted = true; this.report('world-authenticated'); this.wire.send(OP.CHAR_ENUM);
        }
        if (packet.opcode === OP.CHAR_LIST) {
          if (!accepted || !packet.payload.length) throw new Error('Unexpected character list.');
          this.characterList = packet;
        } else this.before.push(packet);
        if (this.before.reduce((n, p) => n+p.payload.length, 0) > 1024*1024) throw new Error('World prefetch limit.');
      }
      this.report('character-list-prefetched');
      this.wire.io.timeoutMs = 120000;
      this.ping = setInterval(() => {
        if (this.attached || this.disposed) return;
        const id = this.pingSequence++ >>> 0; this.pendingPings.add(id);
        try { this.wire.send(OP.PING, Buffer.concat([u32(id), u32(0)])); } catch { this.destroy(); }
      }, 15000); this.ping.unref();
      this.pump = this.readUpstream(this.wire);
      return this;
    } catch (error) { this.destroy(); throw error; }
  }
  check(packet) {
    // Warden binds payload crypto to K as well. This version supports servers
    // without Warden only; never pretend translating headers handles Warden.
    if (packet.opcode === OP.WARDEN) throw new Error('Prepared sessions do not support Warden.');
  }
  async readUpstream(wire) {
    try {
      while (!this.disposed && wire === this.wire) {
        const packet = await wire.receive(); this.check(packet);
        if (packet.opcode === OP.PONG && packet.payload.length >= 4 && this.pendingPings.delete(packet.payload.readUInt32LE(0))) continue;
        if (this.client) this.client.send(packet.opcode, packet.payload);
        else {
          this.before.push(packet);
          if (this.before.reduce((n, p) => n+p.payload.length, 0) > 1024*1024) throw new Error('World prefetch limit.');
        }
      }
    } catch (error) { if (!this.disposed && wire === this.wire) { this.report('upstream-closed'); this.emit('unavailable', error); this.destroy(); } }
  }
  async attach(stream, localKey) {
    if (this.attached || this.disposed || !this.serverSeed) throw new Error('Prepared session unavailable.');
    this.attached = true; clearInterval(this.ping);
    const client = new WorldWire(stream, { server: true, timeoutMs: 120000 });
    const seed = crypto.randomBytes(4); client.send(OP.AUTH_CHALLENGE, seed);
    try {
      const auth = await client.receive();
      if (auth.opcode !== OP.AUTH_SESSION || auth.payload.length < 33) throw new Error('Expected client auth session.');
      const nameEnd = auth.payload.indexOf(0, 8);
      if (nameEnd < 8 || nameEnd > 24 || auth.payload.length < nameEnd + 25) throw new Error('Malformed client auth session.');
      const name = auth.payload.toString('ascii', 8, nameEnd);
      const clientSeed = auth.payload.subarray(nameEnd+1, nameEnd+5);
      const proof = auth.payload.subarray(nameEnd+5, nameEnd+25);
      this.report('client-world-proof build=' + auth.payload.readUInt32LE(0) +
        ' accountMatch=' + (name === this.account) +
        ' digestMatch=' + equal(proof, worldProof(this.account, clientSeed, seed, localKey)));
      // The pinned Turtle exe advertises 7272 to realmd but retains 5875 in
      // its Vanilla world handshake. Both are known layouts, not arbitrary builds.
      if (name !== this.account || ![5875, this.build].includes(auth.payload.readUInt32LE(0)) || !equal(proof, worldProof(this.account, clientSeed, seed, localKey)))
        throw new Error('Client world proof mismatch.');
      // Preserve the client's EXACT addon metadata. A first run, or changed
      // addons, finishes world authentication here; future launches prefetch
      // using this non-secret blob plus an addon-directory fingerprint.
      const blob = auth.payload.subarray(nameEnd+25);
      if (blob.length < 4 || blob.length > 65500) throw new Error('Invalid addon metadata.');
      if (this.addonBlob !== null && !equal(blob, this.addonBlob)) {
        if (!this.reopen) throw new Error('Addon metadata changed; reopen required.');
        clearInterval(this.ping);
        const old = this.wire;
        this.wire = new WorldWire(await this.reopen(), { timeoutMs: 12000 });
        old.destroy(); this.characterList = null; this.before = [];
        const challenge = await this.wire.receive();
        if (challenge.opcode !== OP.AUTH_CHALLENGE || challenge.payload.length !== 4) throw new Error('Unsupported replacement world challenge.');
        this.serverSeed = challenge.payload;
      }
      if (!this.characterList) await this.authenticate(blob);
      this.addonBlob = Buffer.from(blob); this.saveAddonInfo(this.addonBlob);
      client.arm(localKey); this.client = client;
      for (const packet of this.before) client.send(packet.opcode, packet.payload);
      this.before = []; this.report('client-attached');
      let initialEnum = true;
      while (!this.disposed) {
        const packet = await client.receive();
        if (packet.opcode === OP.AUTH_SESSION) throw new Error('Unexpected repeated world authentication.');
        if (initialEnum && packet.opcode === OP.CHAR_ENUM) {
          initialEnum = false; client.send(OP.CHAR_LIST, this.characterList.payload); this.report('prefetched-list-delivered');
        } else this.wire.send(packet.opcode, packet.payload);
      }
    } finally { client.destroy(); this.destroy(); }
  }
  destroy() {
    if (this.disposed) return; this.disposed = true; clearInterval(this.ping);
    this.wire.destroy(); this.client?.destroy(); this.key.fill(0);
    this.characterList?.payload.fill(0); this.before = [];
    this.emit('disposed');
  }
}

// The local frontend verifies the real password using SRP before exposing the
// prepared world session. It listens on loopback only (see prepared-login).
export async function localAuth(stream, { account, password, realm, port, onKey }) {
  const io = new Bytes(stream); let key;
  try {
    const header = await io.read(4);
    if (header[0] !== 0 || header[1] !== 3) throw new Error('Unsupported local login protocol.');
    const size = header.readUInt16LE(2);
    if (size < 31 || size > 46) throw new Error('Invalid local login challenge.');
    const body = await io.read(size);
    if (body.toString('ascii',0,4) !== 'WoW\0' || body.readUInt16LE(7) !== 7272) throw new Error('Local client build mismatch.');
    if (body[29] < 1 || body.length !== 30 + body[29] || body.toString('ascii', 30) !== account) throw new Error('Local login account mismatch.');
    const challenge = serverChallenge(account, password);
    io.write(Buffer.concat([Buffer.from([0,0,0]), challenge.B, Buffer.from([1,7,32]), N_BYTES, challenge.salt, Buffer.alloc(16), Buffer.from([0])]));
    const proof = await io.read(75);
    if (proof[0] !== 1 || proof[73] !== 0 || proof[74] !== 0) throw new Error('Unsupported local proof.');
    const accepted = challenge.verify(proof.subarray(1,33), proof.subarray(33,53)); key = accepted.key;
    onKey(key); io.write(Buffer.concat([Buffer.from([1,0]), accepted.proof, Buffer.alloc(4)]));
    while (true) {
      const opcode = (await io.read(1))[0];
      if (opcode !== 0x10) throw new Error('Unexpected local auth command.');
      await io.read(4); io.write(realmResponse(realm, port));
    }
  } finally { io.destroy(); }
}
