// One-time migration for crew members who already installed the v1.0.13
// browser-based Node launcher. Thereafter bootstrap.mjs updates automatically.
// Download this source only from the canonical owner-controlled GitHub repo.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import { execFileSync, spawn } from 'node:child_process';
import { pathToFileURL, fileURLToPath } from 'node:url';

const BASE = 'https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/next/';
const DEFAULT_ROOT = path.join(process.env.LOCALAPPDATA || path.join(os.homedir(),
  'AppData', 'Local'), 'TortoiseCrewNext');

async function getBytes(url, max) {
  const prefix = BASE + 'update.json?nonce=';
  const freshManifest = url.startsWith(prefix) && /^[a-f0-9]{16}$/.test(url.slice(prefix.length));
  if (!url.startsWith(BASE) || url.includes('#') || (url.includes('?') && !freshManifest))
    throw new Error('Unexpected GitHub launcher URL.');
  const response = await fetch(url, { cache: 'no-store', signal: AbortSignal.timeout(25000) });
  if (!response.ok || response.url !== url) throw new Error('Official GitHub resource unavailable.');
  const chunks = [];
  let size = 0;
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > max) throw new Error('Unexpectedly large launcher resource.');
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

function requireDigest(data, sha256) {
  if (!/^[a-f0-9]{64}$/i.test(sha256 || '') ||
      crypto.createHash('sha256').update(data).digest('hex').toLowerCase() !== sha256.toLowerCase())
    throw new Error('The downloaded launcher file failed SHA-256 verification.');
}

function assertManifest(update) {
  if (!update || !/^\d+\.\d+\.\d+$/.test(update.version || '') ||
      update.bundleUrl !== BASE + 'crew-next-' + update.version + '.zip' ||
      !/^[0-9a-f]{64}$/i.test(update.sha256 || '') ||
      !/^[0-9a-f]{64}$/i.test(update.bootstrapSha256 || '') ||
      !/^[0-9a-f]{64}$/i.test(update.extractorSha256 || ''))
    throw new Error('Official update metadata is incomplete.');
}

function locateShortcuts(root) {
  const command = '[Environment]::GetFolderPath("DesktopDirectory")';
  const desktop = execFileSync('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', command],
    { windowsHide: true, encoding: 'utf8', timeout: 7000 }).trim();
  const start = path.join(process.env.APPDATA || path.join(os.homedir(),
    'AppData', 'Roaming'), 'Microsoft', 'Windows', 'Start Menu', 'Programs');
  return {
    desktop: path.join(desktop, 'Tortoise Crew Launcher.lnk'),
    start: path.join(start, 'Tortoise Crew Launcher.lnk'),
  };
}

async function closeOldNode(root) {
  const game = execFileSync('tasklist.exe',
    ['/FI', 'IMAGENAME eq WoW.exe', '/FO', 'CSV', '/NH'],
    { windowsHide: true, encoding: 'utf8', timeout: 5000 });
  if (/"WoW\.exe"/i.test(game)) throw new Error('Close WoW before upgrading the launcher.');
  const script = "$p=Get-CimInstance Win32_Process -Filter \"Name = 'node.exe'\";" +
    '$base=$env:CREW_NEXT_APP; ' +
    '$p|Where-Object { $_.CommandLine -and $_.CommandLine.Contains($base) -and ' +
    '$_.CommandLine.Contains("main.mjs") }|Select-Object -ExpandProperty ProcessId';
  const listed = execFileSync('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', script],
    { windowsHide: true, encoding: 'utf8', timeout: 7000,
      env: { ...process.env, CREW_NEXT_APP: path.join(root, 'app', 'src') } });
  for (const raw of listed.trim().split(/\s+/)) {
    const pid = Number(raw);
    if (!Number.isInteger(pid) || pid <= 0 || pid === process.pid) continue;
    try { process.kill(pid, 'SIGTERM'); } catch { }
  }
  await new Promise(resolve => setTimeout(resolve, 750));
}

export async function installOnce({
  root = DEFAULT_ROOT, download = getBytes, start = true, shortcuts,
} = {}) {
  if (process.platform !== 'win32') throw new Error('Tortoise Crew requires Windows.');
  const oldApp = path.join(root, 'app');
  if (!fs.existsSync(path.join(oldApp, 'src', 'main.mjs')))
    throw new Error('Install the existing Tortoise Crew v1.0.13 launcher first.');
  const manifest = JSON.parse((await download(BASE + 'update.json?nonce=' +
    crypto.randomBytes(8).toString('hex'), 8192)).toString('utf8'));
  assertManifest(manifest);
  const [zip, bootstrap, extractor] = await Promise.all([
    download(manifest.bundleUrl, 12 * 1024 * 1024),
    download(BASE + 'bootstrap.mjs', 150 * 1024),
    download(BASE + 'src/safe-zip.mjs', 100 * 1024),
  ]);
  requireDigest(zip, manifest.sha256);
  requireDigest(bootstrap, manifest.bootstrapSha256);
  requireDigest(extractor, manifest.extractorSha256);
  const stage = path.join(root, 'first-install-' + crypto.randomUUID());
  const loader = path.join(root, '.trusted-zip-' + crypto.randomUUID() + '.mjs');
  fs.mkdirSync(stage);
  fs.writeFileSync(loader, extractor, { mode: 0o600 });
  let previous = null, priorBootstrap = null;
  const bootstrapPath = path.join(root, 'bootstrap.mjs');
  const links = shortcuts || locateShortcuts(root);
  try {
    const { unpackZip } = await import(pathToFileURL(loader).href);
    unpackZip(zip, stage, { maxFiles: 90, maxBytes: 7 * 1024 * 1024,
      extensions: new Set(['.mjs', '.js', '.json', '.html', '.css']) });
    const pkg = JSON.parse(fs.readFileSync(path.join(stage, 'package.json'), 'utf8'));
    if (pkg.version !== manifest.version || !fs.existsSync(path.join(stage, 'src', 'hidden-start.mjs')))
      throw new Error('The new launcher bundle is incomplete.');
    const env = { ...process.env,
      CREW_NEXT_DATA_DIR: path.join(stage, '.probe-data'),
      CREW_LEGACY_DATA_DIR: path.join(stage, '.probe-legacy') };
    const test = execFileSync(process.execPath, [path.join(stage, 'src', 'main.mjs'), '--health-probe'],
      { env, windowsHide: true, encoding: 'utf8', timeout: 18000 });
    if (!test.includes('CREW_NEXT_PROBE_OK')) throw new Error('Updated app failed its probe.');
    fs.rmSync(env.CREW_NEXT_DATA_DIR, { recursive: true, force: true });
    const ico = path.join(oldApp, 'crew.ico');
    if (fs.existsSync(ico)) fs.copyFileSync(ico, path.join(stage, 'crew.ico'));
    if (start) await closeOldNode(root);
    const backups = path.join(root, 'backups');
    fs.mkdirSync(backups, { recursive: true });
    previous = path.join(backups, 'app-before-onboarding-' + Date.now());
    fs.renameSync(oldApp, previous);
    fs.renameSync(stage, oldApp);
    if (fs.existsSync(bootstrapPath)) {
      priorBootstrap = bootstrapPath + '.previous-' + Date.now();
      fs.copyFileSync(bootstrapPath, priorBootstrap);
    }
    fs.writeFileSync(bootstrapPath, bootstrap);
    const { installHiddenShortcuts } = await import(
      pathToFileURL(path.join(oldApp, 'src', 'hidden-start.mjs')).href);
    const result = installHiddenShortcuts({
      root, app: oldApp, node: process.execPath, shortcuts: links,
    });
    if (start) {
      const proof = path.join(root, 'startup-proof.json');
      if (fs.existsSync(proof)) fs.unlinkSync(proof);
      const child = spawn(result.shellHost, ['//B', '//Nologo', result.script],
        { detached: true, stdio: 'ignore', windowsHide: true });
      child.unref();
      let ready = false;
      for (let i = 0; i < 125; i++) {
        if (fs.existsSync(proof)) {
          const p = JSON.parse(fs.readFileSync(proof, 'utf8'));
          if (p.browserLoadedUtc && Date.now() - Date.parse(p.browserLoadedUtc) < 30000) {
            ready = true; break;
          }
        }
        await new Promise(resolve => setTimeout(resolve, 200));
      }
      if (!ready) throw new Error('Updated app did not open. Restore the previous version.');
    }
    return { installed: manifest.version, shortcuts: links, backup: previous };
  } catch (error) {
    if (previous && fs.existsSync(previous)) {
      if (fs.existsSync(oldApp)) {
        const failed = path.join(root, 'backups', 'failed-first-install-' + Date.now());
        fs.renameSync(oldApp, failed);
      }
      fs.renameSync(previous, oldApp);
      if (priorBootstrap && fs.existsSync(priorBootstrap))
        fs.copyFileSync(priorBootstrap, bootstrapPath);
      for (const target of [links.desktop, links.start]) {
        const backup = target + '.before-hidden-launch.lnk';
        if (fs.existsSync(backup)) fs.copyFileSync(backup, target);
      }
    }
    throw error;
  } finally {
    try { fs.unlinkSync(loader); } catch { }
    if (fs.existsSync(stage)) fs.rmSync(stage, { recursive: true, force: true });
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  installOnce().then(result => console.log('Tortoise Crew updated:', result.installed,
    'Desktop app ready.')).catch(error => { console.error('Crew install:', error.message);
    process.exitCode = 1; });
}
