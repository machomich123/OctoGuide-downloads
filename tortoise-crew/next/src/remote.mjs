import { crewBaseUrl, MANIFEST_URL } from './config.mjs';

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
  return data;
}

export async function crewRequest(base, route, body = undefined) {
  const origin = crewBaseUrl(base);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 9000);
  try {
    const response = await fetch(origin + route, {
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
