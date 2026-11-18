import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';

export const GAME_SHA256 = '97EA82AB7A82ED88BC5A155AB9BBF7E0BCDB5B9F892A47C6F8EDABE1496BFC75';
export const NEXT_VERSION = '0.3.9';
export const ACCOUNTS = Object.freeze(['MICHAEL', 'JAYKE', 'BERNARD', 'AUGUST']);
export const MANIFEST_URL = 'https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/manifest.json';

export function dataDir(env = process.env) {
  return path.join(env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'TortoiseCrewNext');
}

export function legacyDir(env = process.env) {
  return path.join(env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'TortoiseCrewLauncher');
}

export function readJson(file, fallback = {}) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  } catch (error) {
    if (error?.code === 'ENOENT') return fallback;
    throw error;
  }
}

export function writeJsonAtomic(file, obj) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = file + '.' + crypto.randomUUID() + '.new';
  try {
    fs.writeFileSync(temp, JSON.stringify(obj, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
    fs.renameSync(temp, file);
  } finally {
    try { fs.unlinkSync(temp); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  }
}

export function loadSettings(root = dataDir(), previous = legacyDir()) {
  const old = readJson(path.join(previous, 'settings.json'), {});
  const current = readJson(path.join(root, 'settings.json'), {});
  const merged = {
    username: old.Username || '',
    wowPath: old.WowPath || '',
    crewApiUrl: old.CrewApiUrl || '',
    ...current,
  };
  merged.username = String(merged.username).toUpperCase();
  if (!ACCOUNTS.includes(merged.username)) merged.username = '';
  if (typeof merged.wowPath !== 'string') merged.wowPath = '';
  if (typeof merged.crewApiUrl !== 'string') merged.crewApiUrl = '';
  return merged;
}

export function saveSettings(root, settings) {
  const safe = {
    username: ACCOUNTS.includes(settings.username) ? settings.username : '',
    wowPath: typeof settings.wowPath === 'string' ? settings.wowPath : '',
    crewApiUrl: typeof settings.crewApiUrl === 'string' ? settings.crewApiUrl : '',
  };
  writeJsonAtomic(path.join(root, 'settings.json'), safe);
  return safe;
}

export function sha256(file) {
  const digest = crypto.createHash('sha256');
  const fd = fs.openSync(file, 'r');
  const chunk = Buffer.allocUnsafe(64 * 1024);
  try {
    for (;;) {
      const n = fs.readSync(fd, chunk, 0, chunk.length, null);
      if (!n) break;
      digest.update(chunk.subarray(0, n));
    }
  } finally {
    fs.closeSync(fd);
  }
  return digest.digest('hex').toUpperCase();
}

export function validateGameExe(exe) {
  if (typeof exe !== 'string' || path.basename(exe).toLowerCase() !== 'wow.exe') {
    throw new Error('Select the verified 1.18.1 / build 7272 WoW.exe.');
  }
  if (sha256(exe) !== GAME_SHA256) {
    throw new Error('The chosen WoW.exe does not match the verified Turtle build 7272.');
  }
  return path.dirname(path.resolve(exe));
}

export const DIRECT_CREW_ORIGIN = 'https://vanilla-realm-lab.go.altare.global:25975';

export function crewBaseUrl(value) {
  const parsed = new URL(value);
  const host = parsed.hostname.toLowerCase();
  if (parsed.protocol !== 'https:' || (parsed.port && parsed.origin !== DIRECT_CREW_ORIGIN) || parsed.username || parsed.password ||
      parsed.pathname !== '/' || parsed.search || parsed.hash ||
      !['.trycloudflare.com', '.altare.global', '.go.altare.global'].some(suffix => host.endsWith(suffix))) {
    throw new Error('The Crew HTTPS service address is not approved.');
  }
  return parsed.origin;
}
