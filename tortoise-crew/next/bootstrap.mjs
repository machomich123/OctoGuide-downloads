import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn, execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const UPDATE_URL = 'https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/next/update.json';
const APP_SOURCE = 'https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/next/';

function note(root, message) {
  fs.mkdirSync(root, { recursive: true });
  fs.appendFileSync(path.join(root, 'updater.log'), new Date().toISOString() + ' ' +
    String(message).slice(0, 350) + '\n');
}

export function compareVersion(a, b) {
  if (!/^\d+\.\d+\.\d+$/.test(a) || !/^\d+\.\d+\.\d+$/.test(b))
    throw new Error('Invalid updater version.');
  const left = a.split('.').map(Number), right = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) if (left[i] !== right[i]) return left[i] - right[i];
  return 0;
}

export function validateUpdateManifest(manifest) {
  if (!manifest || typeof manifest !== 'object' ||
      !/^\d+\.\d+\.\d+$/.test(manifest.version || '') ||
      !/^[a-f0-9]{64}$/i.test(manifest.sha256 || '') ||
      manifest.bundleUrl !== APP_SOURCE + 'crew-next-' + manifest.version + '.zip')
    throw new Error('Untrusted launcher update manifest.');
  return manifest;
}

async function fetchBytes(url, limit, timeoutMs = 12000) {
  const response = await fetch(url, { cache: 'no-store',
    signal: AbortSignal.timeout(timeoutMs) });
  if (!response.ok || response.url !== url) throw new Error('GitHub update unavailable.');
  if (Number(response.headers.get('content-length') || 0) > limit)
    throw new Error('Launcher update exceeds expected size.');
  const chunks = [];
  let total = 0;
  for await (const piece of response.body) {
    total += piece.length;
    if (total > limit) throw new Error('Launcher update exceeds expected size.');
    chunks.push(Buffer.from(piece));
  }
  return Buffer.concat(chunks);
}

export async function checkForUpdate(app, download = fetchBytes) {
  const current = JSON.parse(fs.readFileSync(path.join(app, 'package.json'), 'utf8')).version;
  const remote = validateUpdateManifest(JSON.parse(
    (await download(UPDATE_URL, 8192)).toString('utf8')));
  return compareVersion(remote.version, current) > 0 ? remote : null;
}

function probe(entry, dataRoot) {
  const env = { ...process.env,
    CREW_NEXT_DATA_DIR: path.join(dataRoot, '.crew-probe-data'),
    CREW_LEGACY_DATA_DIR: path.join(dataRoot, '.crew-probe-legacy') };
  const output = execFileSync(process.execPath,
    [path.join(entry, 'src', 'main.mjs'), '--health-probe'],
    { env, timeout: 20000, encoding: 'utf8', windowsHide: true });
  if (!output.includes('CREW_NEXT_PROBE_OK'))
    throw new Error('Updated launcher did not pass its startup probe.');
  fs.rmSync(env.CREW_NEXT_DATA_DIR, { recursive: true, force: true });
}

export async function applyUpdate(root, remote, {
  download = fetchBytes, allowRunningGame = false,
} = {}) {
  validateUpdateManifest(remote);
  const app = path.join(root, 'app');
  if (!fs.existsSync(path.join(app, 'src', 'main.mjs')))
    throw new Error('Existing launcher is missing.');
  if (!allowRunningGame && process.platform === 'win32' &&
      /"WoW\.exe"/i.test(execFileSync('tasklist.exe',
        ['/FI', 'IMAGENAME eq WoW.exe', '/FO', 'CSV', '/NH'],
        { timeout: 3500, encoding: 'utf8', windowsHide: true })))
    throw new Error('Close WoW before installing a launcher update.');
  const bytes = await download(remote.bundleUrl, 12 * 1024 * 1024, 30000);
  if (crypto.createHash('sha256').update(bytes).digest('hex').toLowerCase() !== remote.sha256.toLowerCase())
    throw new Error('GitHub launcher update checksum mismatch.');
  const temp = path.join(root, 'staging-' + crypto.randomUUID());
  fs.mkdirSync(temp);
  let previous = null, installed = false;
  try {
    const { unpackZip } = await import(pathToFileURL(path.join(app, 'src', 'safe-zip.mjs')).href);
    unpackZip(bytes, temp, { maxFiles: 90, maxBytes: 7 * 1024 * 1024,
      extensions: new Set(['.mjs', '.js', '.json', '.html', '.css']) });
    const pkg = JSON.parse(fs.readFileSync(path.join(temp, 'package.json'), 'utf8'));
    if (pkg.version !== remote.version || !fs.existsSync(path.join(temp, 'public', 'index.html')) ||
        !fs.existsSync(path.join(temp, 'src', 'main.mjs')) ||
        !fs.existsSync(path.join(temp, 'src', 'safe-zip.mjs'))) {
      throw new Error('Updated launcher bundle is missing required files.');
    }
    probe(temp, root);
    const existingIcon = path.join(app, 'crew.ico');
    if (fs.existsSync(existingIcon)) fs.copyFileSync(existingIcon, path.join(temp, 'crew.ico'));
    const backups = path.join(root, 'backups');
    fs.mkdirSync(backups, { recursive: true });
    previous = path.join(backups, 'app-before-' + Date.now() + '-' + crypto.randomUUID());
    fs.renameSync(app, previous);
    fs.renameSync(temp, app);
    installed = true;
    return { updated: true, oldApp: previous, newVersion: remote.version };
  } catch (error) {
    if (!installed && previous && fs.existsSync(previous) && !fs.existsSync(app))
      fs.renameSync(previous, app);
    throw error;
  } finally {
    if (fs.existsSync(temp)) fs.rmSync(temp, { recursive: true, force: true });
  }
}

function pidRunning(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; }
  catch { return false; }
}

async function reuseExisting(root, app) {
  const file = path.join(root, 'session.json');
  if (!fs.existsSync(file)) return false;
  try {
    const session = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (!pidRunning(session.pid) ||
        !/^http:\/\/127\.0\.0\.1:\d+\/\?key=[0-9a-f]{64}$/.test(session.url))
      return false;
    const response = await fetch(session.url, { signal: AbortSignal.timeout(1200) });
    if (!response.ok) return false;
    const { openDesktopApp } = await import(pathToFileURL(path.join(app, 'src', 'desktop-window.mjs')).href);
    await openDesktopApp(session.url, root);
    return true;
  } catch { return false; }
}

async function startApp(root) {
  const app = path.join(root, 'app');
  const marker = path.join(root, 'startup-proof.json');
  if (fs.existsSync(marker)) fs.unlinkSync(marker);
  const child = spawn(process.execPath, [path.join(app, 'src', 'main.mjs')], {
    cwd: app, detached: true, stdio: 'ignore', windowsHide: true,
  });
  await new Promise((resolve, reject) => {
    child.once('spawn', resolve);
    child.once('error', reject);
  });
  child.unref();
  const until = Date.now() + 25000;
  while (Date.now() < until) {
    if (fs.existsSync(marker)) {
      try {
        const proof = JSON.parse(fs.readFileSync(marker, 'utf8'));
        if (proof.pid === child.pid) return child.pid;
      } catch { /* File may still be in the process of being written. */ }
    }
    if (!pidRunning(child.pid)) break;
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  if (pidRunning(child.pid)) child.kill();
  throw new Error('Launcher did not open successfully.');
}

export async function boot(root = ROOT, { download = fetchBytes } = {}) {
  const app = path.join(root, 'app');
  const restarting = path.join(root, 'restart-pending.json');
  if (fs.existsSync(restarting)) {
    try {
      const marker = JSON.parse(fs.readFileSync(restarting, 'utf8'));
      if (Date.now() - Date.parse(marker.utc) < 60000) {
        const until = Date.now() + 15000;
        while (Date.now() < until && pidRunning(marker.pid))
          await new Promise(resolve => setTimeout(resolve, 200));
      }
    } catch { /* Ignore malformed/stale restart requests. */ }
    try { fs.unlinkSync(restarting); } catch { }
  }
  if (await reuseExisting(root, app)) return { reused: true };
  let replaced = null;
  try {
    const remote = await checkForUpdate(app, download);
    if (remote) {
      replaced = await applyUpdate(root, remote, { download });
      note(root, 'Installed Node launcher ' + remote.version + ' from GitHub.');
    }
  } catch (error) {
    note(root, 'Update deferred; keeping installed launcher: ' + error.message);
  }
  try {
    const pid = await startApp(root);
    return { pid, updated: !!replaced };
  } catch (error) {
    if (!replaced) throw error;
    const old = path.join(root, 'app');
    const broken = path.join(root, 'backups', 'failed-app-' + Date.now());
    fs.renameSync(old, broken);
    fs.renameSync(replaced.oldApp, old);
    note(root, 'Rolled back update after failed app startup.');
    return { pid: await startApp(root), rolledBack: true };
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  boot().catch(error => { note(ROOT, 'Unable to open launcher: ' + error.message);
    console.error(error.message); process.exitCode = 1; });
}
