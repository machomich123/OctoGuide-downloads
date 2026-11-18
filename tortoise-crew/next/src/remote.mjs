import https from 'node:https';
import { crewBaseUrl, DIRECT_CREW_ORIGIN, MANIFEST_URL } from './config.mjs';

const directCertificate = `-----BEGIN CERTIFICATE-----
MIIBqzCCAVKgAwIBAgIUDQMCIPe1mIfiWBOvf7JxzYdbczowCgYIKoZIzj0EAwIw
LTErMCkGA1UEAwwidmFuaWxsYS1yZWFsbS1sYWIuZ28uYWx0YXJlLmdsb2JhbDAe
Fw0yNjExMTgxMjU3NDdaFw0zNjExMTUxMjU3NDdaMC0xKzApBgNVBAMMInZhbmls
bGEtcmVhbG0tbGFiLmdvLmFsdGFyZS5nbG9iYWwwWTATBgcqhkjOPQIBBggqhkjO
PQMBBwNCAAT23g/Et14HaXNuSVe+EU6iPQm9mxmU3IpKLnz3VudOTROY5P0RrtD+
Eox591pJkdJFF0LJNx47hU3fE4kv5/tFo1AwTjAtBgNVHREEJjAkgiJ2YW5pbGxh
LXJlYWxtLWxhYi5nby5hbHRhcmUuZ2xvYmFsMB0GA1UdDgQWBBRS4RbY5SRHxPya
FYDvS4sEooHRrTAKBggqhkjOPQQDAgNHADBEAiB6ZtC0QRpXnBumXTEZ7Wa5rS3l
to1C9H+CmJopmmIu1QIgKB2Y236HbFH/gMhbfU70qiM7KUGlPQuR5h8/74xYPgs=
-----END CERTIFICATE-----
`;

export function crewTrustOptions(origin) {
  return origin === DIRECT_CREW_ORIGIN ? { ca: directCertificate } : {};
}

function directRequest(url, { method, headers, body, signal }) {
  return new Promise((resolve, reject) => {
    const request = https.request(url, { method, headers, signal, ...crewTrustOptions(url.origin) }, response => {
      const chunks = [];
      let size = 0;
      response.on('error', reject);
      response.on('data', chunk => {
        size += chunk.length;
        if (size > 8192) {
          response.destroy(new Error('Unexpected oversized service response.'));
          return;
        }
        chunks.push(chunk);
      });
      response.on('end', () => resolve({
        ok: response.statusCode >= 200 && response.statusCode < 300,
        text: async () => Buffer.concat(chunks).toString('utf8'),
      }));
    });
    request.on('error', reject);
    request.end(body);
  });
}

async function jsonFromResponse(response, limit = 8192) {
  const text = await response.text();
  if (text.length > limit) throw new Error('Unexpected oversized service response.');
  try { return JSON.parse(text); }
  catch { throw new Error('Crew service returned invalid JSON.'); }
}

export async function manifest() {
  const response = await fetch(MANIFEST_URL, {
    headers: { 'User-Agent': 'TortoiseCrewNext/0.1' },
    signal: AbortSignal.timeout(10000),
    cache: 'no-store',
  });
  if (!response.ok) throw new Error('Could not load the official Crew manifest.');
  const data = await jsonFromResponse(response, 32000);
  if (!/^\d+\.\d+\.\d+$/.test(data.launcherVersion || '') ||
      !/^[a-z0-9-]+\.altare\.global$/i.test(data.host || '') ||
      !Number.isInteger(data.sshPort) || data.sshPort < 1 || data.sshPort > 65535) {
    throw new Error('The official Crew manifest is invalid.');
  }
  if (data.crewApiUrl) crewBaseUrl(data.crewApiUrl);
  if (data.crewDirectApiUrl && crewBaseUrl(data.crewDirectApiUrl) !== DIRECT_CREW_ORIGIN) {
    throw new Error('The official Crew direct address is invalid.');
  }
  return data;
}

export async function crewRequest(base, route, body = undefined) {
  const origin = crewBaseUrl(base);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 9000);
  try {
    const url = new URL(route, origin);
    if (url.origin !== origin) throw new Error('Invalid Crew service route.');
    const request = origin === DIRECT_CREW_ORIGIN ? directRequest : fetch;
    const response = await request(url, {
      method: body === undefined ? 'GET' : 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: controller.signal,
    });
    const result = await jsonFromResponse(response);
    if (!response.ok || !result.ok) throw new Error(
      typeof result.code === 'string' ? result.code : 'Crew service unavailable.');
    return result;
  } catch (error) {
    if (error.name === 'AbortError') throw new Error('Crew service did not respond.');
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

export async function crewLogin(base, username, password) {
  const result = await crewRequest(base, '/v1/session', { username, password });
  if (typeof result.token !== 'string' || !/^[0-9a-f]{64}$/i.test(result.token)) {
    throw new Error('Crew service returned an invalid session token.');
  }
  return result.token;
}

export async function crewPresence(base) {
  const result = await crewRequest(base, '/v1/presence');
  return result.online || {};
}

export async function changePassword(base, username, currentPassword, newPassword) {
  const result = await crewRequest(base, '/v1/password', { username, currentPassword, newPassword });
  if (result.code !== 'PASSWORD_UPDATED') throw new Error('Password change not confirmed.');
}
