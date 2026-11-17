// WoW 1.12 SRP6 (not RFC5054 SRP6a): k=3, little endian, SHA1 interleave.
// Reference: gtker/wow_srp; all secrets stay in this process.
import crypto from 'node:crypto';
export const N_BYTES = Buffer.from('b79b3e2a87823cab8f5ebfbf8eb10108535006298b5badbd5b53e1895e644b89', 'hex');
export const fromLE = b => BigInt('0x' + (Buffer.from(b).reverse().toString('hex') || '0'));
export function toLE(n, size = 32) {
  if (n < 0n || n >= 1n << BigInt(size * 8)) throw new Error('Integer out of range.');
  return Buffer.from(n.toString(16).padStart(size * 2, '0'), 'hex').reverse();
}
export const N = fromLE(N_BYTES);
export const hash = (...parts) => crypto.createHash('sha1').update(Buffer.concat(parts.map(p => Buffer.isBuffer(p) ? p : Buffer.from(p)))).digest();
export function pow(base, exp, mod = N) {
  let result = 1n; base = ((base % mod) + mod) % mod;
  while (exp) { if (exp & 1n) result = result * base % mod; base = base * base % mod; exp >>= 1n; }
  return result;
}
export function interleave(s) {
  const bytes = toLE(s); let start = 0;
  while (start < bytes.length && bytes[start] === 0) start++;
  if (start % 2) start++;
  const trimmed = bytes.subarray(start);
  const even = Buffer.from([...trimmed].filter((_, i) => i % 2 === 0));
  const odd = Buffer.from([...trimmed].filter((_, i) => i % 2 === 1));
  const a = hash(even), b = hash(odd), key = Buffer.alloc(40);
  for (let i = 0; i < 20; i++) { key[2*i] = a[i]; key[2*i+1] = b[i]; }
  bytes.fill(0); even.fill(0); odd.fill(0);
  return key;
}
function identity(account, password, salt) {
  const inner = hash(account.toUpperCase() + ':' + password.toUpperCase());
  const x = fromLE(hash(salt, inner)); inner.fill(0); return x;
}
export function clientProof(account, salt, A, B, key) {
  const ng = hash(N_BYTES), g = hash(Buffer.from([7]));
  for (let i = 0; i < 20; i++) ng[i] ^= g[i];
  return hash(ng, hash(account.toUpperCase()), salt, A, B, key);
}
export function clientSession(account, password, salt, B, privateBytes = crypto.randomBytes(32)) {
  if (B.length !== 32 || salt.length !== 32 || fromLE(B) % N === 0n) throw new Error('Invalid SRP challenge.');
  const a = fromLE(privateBytes), A = toLE(pow(7n, a));
  const x = identity(account, password, salt), u = fromLE(hash(A, B));
  const s = pow(fromLE(B) - 3n * pow(7n, x), a + u * x);
  const key = interleave(s), proof = clientProof(account, salt, A, B, key);
  return { A, key, proof, serverProof: hash(A, proof, key) };
}
export function serverChallenge(account, password, { salt = crypto.randomBytes(32), privateBytes = crypto.randomBytes(32) } = {}) {
  const v = pow(7n, identity(account, password, salt)), b = fromLE(privateBytes);
  const B = toLE((3n * v + pow(7n, b)) % N);
  return { salt, B, verify(A, proof) {
    if (A.length !== 32 || proof.length !== 20 || fromLE(A) % N === 0n) throw new Error('Invalid client SRP key.');
    const u = fromLE(hash(A, B));
    const key = interleave(pow(fromLE(A) * pow(v, u), b));
    const expected = clientProof(account, salt, A, B, key);
    if (!crypto.timingSafeEqual(expected, proof)) { key.fill(0); throw new Error('Invalid client SRP proof.'); }
    return { key, proof: hash(A, proof, key) };
  } };
}
export const worldProof = (account, clientSeed, serverSeed, key) => hash(Buffer.from(account.toUpperCase()), Buffer.alloc(4), clientSeed, serverSeed, key);

// Each direction owns independent state. Only headers, never payloads, use this.
export class HeaderCipher {
  constructor(key) { this.key = Buffer.from(key); this.index = 0; this.previous = 0; }
  encrypt(header) {
    const out = Buffer.alloc(header.length);
    for (let i = 0; i < out.length; i++) {
      out[i] = ((header[i] ^ this.key[this.index]) + this.previous) & 255;
      this.index = (this.index + 1) % 40; this.previous = out[i];
    }
    return out;
  }
  decrypt(header) {
    const out = Buffer.alloc(header.length);
    for (let i = 0; i < out.length; i++) {
      out[i] = ((header[i] - this.previous) & 255) ^ this.key[this.index];
      this.index = (this.index + 1) % 40; this.previous = header[i];
    }
    return out;
  }
  destroy() { this.key.fill(0); }
}
