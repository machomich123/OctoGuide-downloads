import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { validatePartyRelease } from '../src/managed-addons.mjs';

const args = process.argv.slice(2);
function argument(name) {
  const index = args.indexOf(name);
  if (index < 0 || !args[index + 1] || args[index + 1].startsWith('--'))
    throw new Error('Required argument missing: ' + name);
  return args[index + 1];
}

function inputBytes(file, maxBytes) {
  const location = path.resolve(file);
  if (fs.lstatSync(location).isSymbolicLink() || !fs.statSync(location).isFile() ||
      fs.statSync(location).size > maxBytes)
    throw new Error('Expected a regular release file under ' + maxBytes + ' bytes: ' + location);
  return fs.readFileSync(location);
}

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function numericVersionCompare(a, b) {
  const left = a.split('.').map(Number), right = b.split('.').map(Number);
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const diff = (left[i] || 0) - (right[i] || 0);
    if (diff !== 0) return diff;
  }
  return 0;
}

const lua = inputBytes(argument('--lua'), 3 * 1024 * 1024);
const toc = inputBytes(argument('--toc'), 8 * 1024);
const assetsRoot = path.resolve(argument('--assets'));
const assets = Object.fromEntries(['Refresh.tga', 'Settings.tga', 'SellMarked.tga']
  .map(name => ['Assets/' + name, inputBytes(path.join(assetsRoot, name), 128 * 1024)]));
const version = argument('--version');
if (!/^\d+(?:\.\d+){2,4}$/.test(version))
  throw new Error('Release version must be numeric, e.g. 2026.11.22.1.');
const tocText = toc.toString('utf8');
const scripts = tocText.split(/\r?\n/).map(s => s.trim())
  .filter(s => s && !s.startsWith('#'));
if (scripts.length !== 1 || scripts[0] !== 'Inventory.lua' ||
    !/^##\s*Dependencies:\s*TortoiseBotsManager\s*$/im.test(tocText) ||
    !/^##\s*Interface:\s*11\d\d\d\s*$/im.test(tocText))
  throw new Error('TOC must target Vanilla, load only Inventory.lua and require TortoiseBotsManager.');

const release = validatePartyRelease({
  schema: 1, addon: 'TortoiseBotsPartyInventory', version,
  files: { 'TortoiseBotsPartyInventory.toc': sha256(toc), 'Inventory.lua': sha256(lua),
    ...Object.fromEntries(Object.entries(assets).map(([name, bytes]) => [name, sha256(bytes)])) },
});
const next = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repository = path.resolve(next, '..', '..');
const destination = args.includes('--output') ? path.resolve(argument('--output')) :
  path.join(repository, 'tortoise-crew', 'addons', 'TortoiseBotsPartyInventory');
const staging = path.join(path.dirname(destination), '.party-release-' + crypto.randomUUID());
fs.mkdirSync(staging, { recursive: true });
let previous = null;
try {
  if (fs.existsSync(destination)) {
    const priorRelease = path.join(destination, 'release.json');
    if (fs.existsSync(priorRelease)) {
      const prior = validatePartyRelease(JSON.parse(fs.readFileSync(priorRelease, 'utf8')));
      if (numericVersionCompare(version, prior.version) <= 0)
        throw new Error('New release version must be newer than ' + prior.version);
    }
  }
  fs.writeFileSync(path.join(staging, 'Inventory.lua'), lua);
  fs.writeFileSync(path.join(staging, 'TortoiseBotsPartyInventory.toc'), toc);
  fs.mkdirSync(path.join(staging, 'Assets'));
  for (const [name, bytes] of Object.entries(assets))
    fs.writeFileSync(path.join(staging, ...name.split('/')), bytes);
  fs.writeFileSync(path.join(staging, 'release.json'), JSON.stringify(release, null, 2) + '\n');
  fs.writeFileSync(path.join(staging, 'README.md'),
    '# TBM Party Inventory\n\n' +
    'Separate Lua addon for the Tortoise WoW 1.18.1 family realm. Requires the ' +
    '**TortoiseBotsManager** addon and matching server-side ALT inventory commands.\n\n' +
    'Install or update from **Tortoise Crew Launcher → Addons → Discover**. ' +
    'The launcher verifies all five file SHA-256 hashes from `release.json`, keeps backups ' +
    'in the client WTF folder and automatically checks for an update before Play.\n' +
    'Local modifications are never overwritten automatically.\n\n' +
    '**Release:** ' + version + '\n');
  if (fs.existsSync(destination)) {
    // A caller's --output may be on a different volume from the repository.
    // Rename is atomic only within one filesystem: keep custom-output backups
    // beside that output. The normal repo release retains its ignored out/ dir.
    const repositoryRelease = path.join(repository, 'tortoise-crew', 'addons',
      'TortoiseBotsPartyInventory');
    const backupParent = path.resolve(destination) === path.resolve(repositoryRelease)
      ? path.join(repository, 'out') : path.dirname(destination);
    const backups = path.join(backupParent, 'party-inventory-release-backups');
    fs.mkdirSync(backups, { recursive: true });
    previous = path.join(backups, 'before-' + version + '-' + crypto.randomUUID());
    fs.renameSync(destination, previous);
  }
  try { fs.renameSync(staging, destination); }
  catch (error) {
    if (previous && fs.existsSync(previous)) fs.renameSync(previous, destination);
    throw error;
  }
  for (const [name, expected] of Object.entries(release.files)) {
    if (sha256(fs.readFileSync(path.join(destination, ...name.split('/')))) !== expected)
      throw new Error('Release verification failed: ' + name);
  }
  process.stdout.write('Prepared Party Inventory ' + version + '\n' + destination + '\n');
} finally {
  if (fs.existsSync(staging)) fs.rmSync(staging, { recursive: true, force: true });
}
