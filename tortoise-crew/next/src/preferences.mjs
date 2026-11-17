import path from 'node:path';
import { ACCOUNTS, readJson, writeJsonAtomic } from './config.mjs';

const KEYS = ['remember', 'useSaved', 'autoLogin', 'closeOnPlay'];
const DEFAULT = Object.freeze({
  remember: false, useSaved: false, autoLogin: false, closeOnPlay: true,
});

function preferenceFile(root) {
  return path.join(root, 'account-preferences.json');
}

export function accountPreferences(root, account, saved = false) {
  if (!ACCOUNTS.includes(account)) throw new Error('Unknown account.');
  const stored = readJson(preferenceFile(root), {});
  const value = stored[account] || {};
  const result = { ...DEFAULT };
  for (const key of KEYS) {
    if (typeof value[key] === 'boolean') result[key] = value[key];
  }
  // A saved password should be automatically selected on the next launch
  // unless the user has previously opted out.
  if (saved && typeof value.useSaved !== 'boolean') result.useSaved = true;
  if (saved && typeof value.remember !== 'boolean') result.remember = true;
  if (!saved) result.useSaved = false;
  return result;
}

export function setAccountPreferences(root, account, patch, saved = false) {
  if (!ACCOUNTS.includes(account)) throw new Error('Unknown account.');
  if (!patch || typeof patch !== 'object' || Array.isArray(patch) ||
      Object.keys(patch).some(key => !KEYS.includes(key) ||
        typeof patch[key] !== 'boolean')) {
    throw new Error('Invalid launcher login preference.');
  }
  const stored = readJson(preferenceFile(root), {});
  const base = accountPreferences(root, account, saved);
  stored[account] = { ...base, ...patch };
  writeJsonAtomic(preferenceFile(root), stored);
  return accountPreferences(root, account, saved);
}
