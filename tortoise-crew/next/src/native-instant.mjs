import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import { unpackZip } from './safe-zip.mjs';
import { GAME_SHA256, readJson, writeJsonAtomic, sha256 } from './config.mjs';
import { nativeAssetText } from './native-assets-bundled.mjs';

// Experimental native GlueXML/ClassicAPI integration for the user's verified
// Vanilla 1.12.1 client. The 1.18.1 Turtle content uses this base executable.
// No modification to WoW.exe, passwords in game files, or hidden DLL injection.
const ASSETS = [
  'GlueXML.toc', 'CrewInstantLogin.lua', 'CrewInstantLogin.xml',
  'CrewLegacyGlobals.lua',
];
const MARKER = 'crew-native-instant-v1.json';
export const VF_EXE_HASH = '228D7BB5E3B5B0C2062D6C5F40C38C2A173E4C80D8A5D9E4077BE800431B48A3';
export const VF_DLL_HASH = 'F283B6B5AD8042E7995EFF9768C150042DD47DE6E5F00FFE530D2E67743DF81D';
export const CLASSICAPI_HASH = 'E34886FB9725B9059375A5C37BFF81CE220633C4E2C39719EF3223A6B8FC703D';
const UPSTREAM_ZIP_URL = 'https://github.com/hannesmann/vanillafixes/releases/download/v1.5.3/vanillafixes-1.5.3.zip';
const UPSTREAM_ZIP_HASH = '72EA02AA34B61675D6F9FFC99FC64BC3D0C3E68E139F3F885EB04CAC5167BC07';

function digest(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex').toUpperCase();
}
const fileMarker = root => path.join(root, MARKER);
const glueRoot = game => path.join(game, 'Data', 'Interface', 'GlueXML');
function verifyPath(game, file) {
  const rel = path.relative(game, file);
  if (rel.startsWith('..') || path.isAbsolute(rel)) throw new Error('Native file outside WoW folder.');
  let current = game;
  for (const segment of rel.split(path.sep)) {
    current = path.join(current, segment);
    if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink())
      throw new Error('Native instant login refuses linked files.');
  }
}
export function nativeFiles() {
  return Object.fromEntries(ASSETS.map(name =>
    [name, Buffer.from(nativeAssetText[name], 'utf8')]));
}
export function verifyNativeClient(game, { requireLoader = true } = {}) {
  if (!fs.existsSync(path.join(game, 'WoW.exe')) ||
      sha256(path.join(game, 'WoW.exe')) !== GAME_SHA256)
    throw new Error('Native test requires the verified Tortoise WoW.exe.');
  // Already installed on the user's client; do not rewrite executable bytes.
  const exe = fs.readFileSync(path.join(game, 'WoW.exe'));
  for (const [offset, byte] of [
    [0x2f113a, 0xeb], [0x2f113b, 0x19], [0x2f1158, 0x03],
    [0x2f11a7, 0x03], [0x2f11f0, 0xeb], [0x2f11f1, 0xb2],
  ]) {
    if (exe[offset] !== byte) throw new Error('Custom GlueXML has not been enabled.');
  }
  if (!fs.existsSync(path.join(game, 'ClassicAPI.dll')) ||
      sha256(path.join(game, 'ClassicAPI.dll')) !== CLASSICAPI_HASH)
    throw new Error('This test requires the verified ClassicAPI.dll.');
  if (requireLoader && (!fs.existsSync(path.join(game, 'VanillaFixes.exe')) ||
      sha256(path.join(game, 'VanillaFixes.exe')) !== VF_EXE_HASH ||
      !fs.existsSync(path.join(game, 'VfPatcher.dll')) ||
      sha256(path.join(game, 'VfPatcher.dll')) !== VF_DLL_HASH))
    throw new Error('Verified VanillaFixes 1.5.3 loader files are missing.');
}

export function inspectNativeInstant(game, root) {
  const marker = readJson(fileMarker(root), null);
  if (!marker || ![1, 2].includes(marker.version) || marker.game !== path.resolve(game) ||
      !Array.isArray(marker.files)) return { installed: false };
  verifyNativeClient(game);
  for (const record of marker.files) {
    const file = path.join(game, record.relative);
    verifyPath(game, file);
    if (!fs.existsSync(file) || sha256(file) !== record.sha256)
      throw new Error('Native login files changed. Existing installation will not be altered.');
  }
  return {
    installed: true, nativeLauncher: path.join(game, 'VanillaFixes.exe'),
    firstLoginRequiresVaultProvisioning: true,
    protocol: marker.version,
    upgradeAvailable: ASSETS.some(name => {
      const target = path.join(glueRoot(game), name);
      return !fs.existsSync(target) ||
        digest(fs.readFileSync(target)) !== digest(nativeFiles()[name]);
    }),
  };
}

// Migrate an owned v1 installation to the no-splash, character-ready v2
// protocol. This backs up only our files and preserves other modifications.
export function upgradeNativeInstant(game, root, { gameRunning = () => false } = {}) {
  if (gameRunning()) throw new Error('Close WoW before upgrading its native UI.');
  game = path.resolve(game);
  const status = inspectNativeInstant(game, root);
  if (!status.installed) throw new Error('Native login is not installed.');
  if (!status.upgradeAvailable && status.protocol === 2) return { upgraded: false };
  const oldMarker = readJson(fileMarker(root));
  const entries = new Map(oldMarker.files.map(record => [record.relative, record]));
  const assets = nativeFiles();
  const changes = [];
  for (const [name, source] of Object.entries(assets)) {
    const target = path.join(glueRoot(game), name);
    const relative = path.relative(game, target);
    verifyPath(game, target);
    if (!entries.has(relative) && fs.existsSync(target))
      throw new Error('An unowned native GlueXML file already exists: ' + name);
    changes.push({ relative, target, source, existed: fs.existsSync(target) });
  }
  const backupDir = path.join(root, 'backups',
    'native-ready-v2-' + new Date().toISOString().replace(/[:.]/g, '-'));
  fs.mkdirSync(backupDir, { recursive: true });
  const previousFiles = new Map();
  for (const change of changes) {
    if (!change.existed) continue;
    const old = fs.readFileSync(change.target);
    previousFiles.set(change.target, old);
    fs.writeFileSync(path.join(backupDir, path.basename(change.target) + '.before'), old);
  }
  fs.copyFileSync(fileMarker(root), path.join(backupDir, 'manifest.before.json'));
  const applied = [];
  try {
    for (const change of changes) {
      fs.mkdirSync(path.dirname(change.target), { recursive: true });
      const staging = change.target + '.crew-v2-stage';
      if (fs.existsSync(staging)) throw new Error('Concurrent native upgrade detected.');
      fs.writeFileSync(staging, change.source, { flag: 'wx' });
      try {
        fs.renameSync(staging, change.target);
      } finally {
        if (fs.existsSync(staging)) fs.unlinkSync(staging);
      }
      applied.push(change);
      entries.set(change.relative, {
        relative: change.relative, sha256: sha256(change.target),
      });
    }
    writeJsonAtomic(fileMarker(root), {
      ...oldMarker, version: 2, files: [...entries.values()],
      updatedUtc: new Date().toISOString(),
    });
    const verified = inspectNativeInstant(game, root);
    if (!verified.installed || verified.upgradeAvailable)
      throw new Error('Native v2 upgrade verification failed.');
    return { upgraded: true, backupDir };
  } catch (error) {
    for (const change of applied.reverse()) {
      if (previousFiles.has(change.target)) {
        fs.writeFileSync(change.target, previousFiles.get(change.target));
      } else if (fs.existsSync(change.target)) {
        fs.unlinkSync(change.target);
      }
    }
    fs.copyFileSync(path.join(backupDir, 'manifest.before.json'), fileMarker(root));
    throw error;
  }
}

// An official, verified zip may be used when the patcher is not yet present.
// The developer's test installation can pass its verified DLL directly.
export async function nativePatcherBytes({ fetcher = fetch, sourceFile = null } = {}) {
  if (sourceFile) {
    const data = fs.readFileSync(sourceFile);
    if (digest(data) !== VF_DLL_HASH) throw new Error('Local VF patcher checksum mismatch.');
    return data;
  }
  const response = await fetcher(UPSTREAM_ZIP_URL, {
    redirect: 'follow', signal: AbortSignal.timeout(20000),
  });
  if (!response.ok || Number(response.headers.get('content-length') || 0) > 300000)
    throw new Error('Official VanillaFixes release unavailable.');
  const zip = Buffer.from(await response.arrayBuffer());
  if (zip.length > 300000 || digest(zip) !== UPSTREAM_ZIP_HASH)
    throw new Error('Official VanillaFixes release checksum mismatch.');
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-vf-'));
  try {
    unpackZip(zip, temp, { maxFiles: 10, maxBytes: 500000,
      extensions: new Set(['.dll']) });
    const file = path.join(temp, 'VfPatcher.dll');
    const bytes = fs.readFileSync(file);
    if (digest(bytes) !== VF_DLL_HASH) throw new Error('Official VF DLL checksum mismatch.');
    return bytes;
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

export async function installNativeInstant(game, root, {
  fetcher = fetch, patcherSource = null, gameRunning = () => false,
} = {}) {
  game = path.resolve(game);
  if (gameRunning()) throw new Error('Close World of Warcraft before installing.');
  if (inspectNativeInstant(game, root).installed) return { installed: true, existing: true };
  verifyNativeClient(game, { requireLoader: false });
  const loader = path.join(game, 'VanillaFixes.exe');
  if (!fs.existsSync(loader) || sha256(loader) !== VF_EXE_HASH)
    throw new Error('The supported VanillaFixes.exe is missing.');
  const patcher = path.join(game, 'VfPatcher.dll');
  const addPatcher = !fs.existsSync(patcher);
  if (!addPatcher && sha256(patcher) !== VF_DLL_HASH)
    throw new Error('An unknown VfPatcher.dll already exists.');
  const files = nativeFiles();
  const locations = [
    ...Object.entries(files).map(([name, content]) => ({
      path: path.join(glueRoot(game), name), content,
    })),
    { path: path.join(game, 'dlls.txt'), content: Buffer.from('ClassicAPI.dll\r\n') },
  ];
  if (addPatcher) locations.push({ path: patcher,
    content: await nativePatcherBytes({ fetcher, sourceFile: patcherSource }) });
  for (const entry of locations) {
    verifyPath(game, entry.path);
    if (fs.existsSync(entry.path))
      throw new Error('Custom game file already exists: ' + path.basename(entry.path));
  }
  const created = [];
  try {
    for (const entry of locations) {
      fs.mkdirSync(path.dirname(entry.path), { recursive: true });
      fs.writeFileSync(entry.path, entry.content, { flag: 'wx' });
      created.push(entry.path);
    }
    writeJsonAtomic(fileMarker(root), {
      version: 2, game,
      files: created.map(file => ({
        relative: path.relative(game, file), sha256: sha256(file),
      })), installedUtc: new Date().toISOString(),
    });
    return inspectNativeInstant(game, root);
  } catch (error) {
    for (const file of created.reverse()) {
      try { fs.unlinkSync(file); } catch {}
    }
    throw error;
  }
}

export function uninstallNativeInstant(game, root, { gameRunning = () => false } = {}) {
  if (gameRunning()) throw new Error('Close World of Warcraft before restoring login.');
  const ready = inspectNativeInstant(game, root);
  if (!ready.installed) return { removed: false };
  const marker = readJson(fileMarker(root));
  for (const record of marker.files) {
    const file = path.join(game, record.relative);
    verifyPath(game, file);
    if (sha256(file) !== record.sha256)
      throw new Error('The native file changed. Refusing to remove an unknown modification.');
  }
  for (const record of marker.files) fs.unlinkSync(path.join(game, record.relative));
  fs.unlinkSync(fileMarker(root));
  return { removed: true };
}
