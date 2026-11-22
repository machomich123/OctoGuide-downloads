import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { importAddons } from './addons.mjs';

// A dedicated five-file release. Downloading the whole OctoGuide repository
// would also import unrelated addons and exceed the GitHub ZIP size limit.
export const PARTY_INVENTORY = Object.freeze({
  id: 'party-inventory',
  name: 'TortoiseBotsPartyInventory',
  title: 'TBM Party Inventory',
  source: 'Tortoise Crew · official addon',
  url: 'https://github.com/machomich123/OctoGuide-downloads/tree/main/tortoise-crew/addons/TortoiseBotsPartyInventory',
  description: 'View and manage party ALT equipment, bags and trading in-game. Requires TortoiseBotsManager and the matching Tortoise server commands.',
});

const RELEASE_ROOT = 'https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/addons/TortoiseBotsPartyInventory/';
const FILE_LIMITS = Object.freeze({
  'release.json': 16 * 1024,
  'TortoiseBotsPartyInventory.toc': 8 * 1024,
  'Inventory.lua': 3 * 1024 * 1024,
  'Assets/Refresh.tga': 128 * 1024,
  'Assets/Settings.tga': 128 * 1024,
  'Assets/SellMarked.tga': 128 * 1024,
});
const PAYLOAD_FILES = [
  'TortoiseBotsPartyInventory.toc', 'Inventory.lua',
  'Assets/Refresh.tga', 'Assets/Settings.tga', 'Assets/SellMarked.tga',
];

export function featuredAddon() {
  return {
    name: PARTY_INVENTORY.title,
    author: 'Tortoise Crew', description: PARTY_INVENTORY.description,
    url: PARTY_INVENTORY.url, source: PARTY_INVENTORY.source,
    stars: 0, downloads: null, updated: '', icon: '',
    installable: true, managedId: PARTY_INVENTORY.id,
  };
}

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

async function downloadReleaseFile(url, maxBytes) {
  const response = await fetch(url, {
    headers: { 'User-Agent': 'TortoiseCrewManagedAddon/1.0' },
    signal: AbortSignal.timeout(10000), cache: 'no-store',
    redirect: 'manual',
  });
  // Only the expected GitHub raw-content host may supply executable Lua.
  if (new URL(response.url).origin !== 'https://raw.githubusercontent.com' ||
      !response.ok) throw new Error('Party Inventory release unavailable (HTTP ' + response.status + ').');
  if (Number(response.headers.get('content-length') || 0) > maxBytes)
    throw new Error('Party Inventory release file exceeds its size limit.');
  const chunks = [];
  let bytes = 0;
  for await (const piece of response.body) {
    bytes += piece.byteLength;
    if (bytes > maxBytes) throw new Error('Party Inventory release file exceeds its size limit.');
    chunks.push(Buffer.from(piece));
  }
  return Buffer.concat(chunks);
}

export function validatePartyRelease(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      value.schema !== 1 || value.addon !== PARTY_INVENTORY.name ||
      typeof value.version !== 'string' ||
      !/^[0-9][A-Za-z0-9._-]{0,50}$/.test(value.version) ||
      !value.files || typeof value.files !== 'object' ||
      Array.isArray(value.files) ||
      Object.keys(value.files).sort().join('|') !== [...PAYLOAD_FILES].sort().join('|'))
    throw new Error('Invalid Party Inventory release manifest.');
  for (const name of PAYLOAD_FILES) {
    if (typeof value.files[name] !== 'string' || !/^[a-fA-F0-9]{64}$/.test(value.files[name]))
      throw new Error('Invalid SHA-256 in Party Inventory release manifest: ' + name);
  }
  return {
    schema: 1, addon: PARTY_INVENTORY.name, version: value.version,
    files: Object.fromEntries(PAYLOAD_FILES.map(name => [name, value.files[name].toLowerCase()])),
  };
}

function existingDirectory(game) {
  const root = path.resolve(game);
  const addons = path.join(root, 'Interface', 'AddOns');
  if (!fs.statSync(addons).isDirectory() || fs.lstatSync(addons).isSymbolicLink())
    throw new Error('Select a regular WoW game folder.');
  return path.join(addons, PARTY_INVENTORY.name);
}

function readLocalRelease(folder) {
  const releasePath = path.join(folder, 'release.json');
  if (!fs.existsSync(releasePath)) return null;
  if (fs.lstatSync(releasePath).isSymbolicLink() ||
      fs.statSync(releasePath).size > FILE_LIMITS['release.json']) return null;
  try { return validatePartyRelease(JSON.parse(fs.readFileSync(releasePath, 'utf8'))); }
  catch { return null; }
}

function matchesInstalled(folder, release) {
  return PAYLOAD_FILES.every(name => {
    const file = path.join(folder, ...name.split('/'));
    if (!fs.existsSync(file) || fs.lstatSync(file).isSymbolicLink() ||
        !fs.statSync(file).isFile() || fs.statSync(file).size > FILE_LIMITS[name]) return false;
    return sha256(fs.readFileSync(file)) === release.files[name];
  });
}

export function inspectPartyInventory(game) {
  const folder = existingDirectory(game);
  if (!fs.existsSync(folder)) return { installed: false, managed: false, modified: false, version: '' };
  if (!fs.statSync(folder).isDirectory() || fs.lstatSync(folder).isSymbolicLink())
    throw new Error('Party Inventory installation is not a regular directory.');
  const release = readLocalRelease(folder);
  return {
    installed: true, managed: Boolean(release),
    modified: Boolean(release && !matchesInstalled(folder, release)),
    version: release?.version || '', release,
  };
}

function sameRelease(left, right) {
  return Boolean(left && right && left.version === right.version &&
    PAYLOAD_FILES.every(name => left.files[name] === right.files[name]));
}

async function remoteRelease(download) {
  const bytes = await download(RELEASE_ROOT + 'release.json', FILE_LIMITS['release.json']);
  if (bytes.length > FILE_LIMITS['release.json']) throw new Error('Release manifest exceeds size limit.');
  return validatePartyRelease(JSON.parse(bytes.toString('utf8')));
}

export async function partyInventoryStatus(game, { download = downloadReleaseFile } = {}) {
  const installed = inspectPartyInventory(game);
  const latest = await remoteRelease(download);
  return {
    installed: installed.installed, managed: installed.managed,
    modified: installed.modified, current: installed.version, latest: latest.version,
    updateAvailable: !installed.managed || installed.modified ||
      !sameRelease(installed.release, latest),
  };
}

function checkClosed(isGameRunning) {
  if (isGameRunning?.()) throw new Error('Close WoW before changing Party Inventory.');
}

async function installOnce(game, {
  download = downloadReleaseFile, isGameRunning, auto = false,
} = {}) {
  checkClosed(isGameRunning);
  const previous = inspectPartyInventory(game);
  // Auto-updates only touch packages installed by this manager and still
  // matching their original, verified release. Manual installs make backups.
  if (auto && (!previous.managed || previous.modified))
    return { changed: false, skipped: previous.modified ? 'locally modified' : 'not managed' };
  const release = await remoteRelease(download);
  if (previous.managed && !previous.modified && sameRelease(previous.release, release))
    return { changed: false, version: release.version, upToDate: true };

  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-party-inventory-'));
  try {
    const unpacked = path.join(temp, 'AddOns');
    fs.mkdirSync(unpacked);
    const addonFolder = path.join(unpacked, 'TortoiseBotsPartyInventory');
    fs.mkdirSync(addonFolder);
    const payloads = await Promise.all(PAYLOAD_FILES.map(async name => {
      const bytes = await download(RELEASE_ROOT + name, FILE_LIMITS[name]);
      if (!Buffer.isBuffer(bytes) || bytes.length > FILE_LIMITS[name] ||
          sha256(bytes) !== release.files[name])
        throw new Error('Party Inventory checksum mismatch: ' + name);
      return [name, bytes];
    }));
    const toc = payloads.find(([name]) => name.endsWith('.toc'))[1].toString('utf8');
    const scripts = toc.split(/\r?\n/).map(s => s.trim())
      .filter(s => s && !s.startsWith('##') && !s.startsWith('#'));
    if (scripts.length !== 1 || scripts[0] !== 'Inventory.lua' ||
        !/^##\s*Dependencies:\s*TortoiseBotsManager\s*$/im.test(toc))
      throw new Error('Party Inventory TOC has unexpected dependencies or script entries.');
    for (const [name, bytes] of payloads) {
      const file = path.join(addonFolder, ...name.split('/'));
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, bytes);
    }
    fs.writeFileSync(path.join(addonFolder, 'release.json'),
      JSON.stringify(release, null, 2) + '\n');
    checkClosed(isGameRunning);
    const result = importAddons(unpacked, game, { isGameRunning });
    if (result.imported !== 1) throw new Error('Party Inventory import did not install one addon.');
    return { ...result, changed: true, version: release.version,
      source: PARTY_INVENTORY.url };
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

// The Play preflight and a manual Addons-tab click may overlap. Serialize
// imports to keep both operations from moving the same files concurrently.
let updateQueue = Promise.resolve();
export async function waitForPartyInventoryUpdates() {
  await updateQueue;
}
export function installPartyInventory(game, options = {}) {
  const pending = updateQueue.then(() => installOnce(game, options));
  updateQueue = pending.catch(() => {});
  return pending;
}
