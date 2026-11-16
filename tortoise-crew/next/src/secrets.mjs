import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { ACCOUNTS, writeJsonAtomic, readJson } from './config.mjs';

// DPAPI keeps account secrets bound to the signed-in Windows user. The secret
// is sent on the helper's stdin, never in command-line arguments or logs.
const DPAPI = [
  'Add-Type -AssemblyName System.Security;',
  '$inputText = [Console]::In.ReadToEnd();',
  '$bytes = [Convert]::FromBase64String($inputText);',
  '$mode = [Security.Cryptography.DataProtectionScope]::CurrentUser;',
  '$out = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, $mode);',
  '[Console]::Out.Write([Convert]::ToBase64String($out));',
].join(' ');
const UNDPAPI = DPAPI.replace('::Protect($bytes, $null, $mode)', '::Unprotect($bytes, $null, $mode)');

function protect(value, operation) {
  if (process.platform !== 'win32') throw new Error('Windows DPAPI is required.');
  const encoded = operation === 'protect' ?
    Buffer.from(value, 'utf8').toString('base64') : value;
  return execFileSync('powershell.exe', [
    '-NoProfile', '-NonInteractive', '-Command', operation === 'protect' ? DPAPI : UNDPAPI,
  ], { input: encoded, encoding: 'utf8', timeout: 7000, maxBuffer: 512 * 1024,
    windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] }).trim();
}

function vaultFile(root) { return path.join(root, 'credentials.json'); }

export function saveCredential(root, user, password) {
  if (!ACCOUNTS.includes(user) || typeof password !== 'string' ||
      password.length < 1 || password.length > 16 || !/^[ -~]+$/.test(password)) {
    throw new Error('Choose a valid account and a 1–16 character game password.');
  }
  const credentials = readJson(vaultFile(root));
  credentials[user] = protect(password, 'protect');
  writeJsonAtomic(vaultFile(root), credentials);
}

export function readCredential(root, user) {
  if (!ACCOUNTS.includes(user)) return '';
  const encrypted = readJson(vaultFile(root))[user];
  if (typeof encrypted !== 'string' || !/^[A-Za-z0-9+/=]+$/.test(encrypted)) return '';
  try {
    return Buffer.from(protect(encrypted, 'unprotect'), 'base64').toString('utf8');
  } catch {
    return '';
  }
}

export function storedAccounts(root) {
  const credentials = readJson(vaultFile(root));
  return ACCOUNTS.filter(x => typeof credentials[x] === 'string');
}
