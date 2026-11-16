import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { execFileSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dataDir, legacyDir, writeJsonAtomic } from './config.mjs';

const APP_SRC = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WINDOW_SCRIPT = [
  '$ErrorActionPreference = "Stop"',
  '$inputData = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:CREW_SHORTCUT_DATA)) | ConvertFrom-Json',
  '$shell = New-Object -ComObject WScript.Shell',
  '$shortcut = $shell.CreateShortcut($inputData.Shortcut)',
  '$shortcut.TargetPath = $inputData.NodeExe',
  '$shortcut.Arguments = [string]::Concat(\'"\', $inputData.Main, \'"\' )',
  '$shortcut.WorkingDirectory = $inputData.WorkingDir',
  '$shortcut.Description = "Tortoise Crew Next"',
  '$shortcut.WindowStyle = 7',
  'if ($inputData.Icon -and (Test-Path -LiteralPath $inputData.Icon)) { $shortcut.IconLocation = $inputData.Icon }',
  '$shortcut.Save()',
].join('; ');

export function nativeShortcut(file, node, main, work, icon) {
  const data = { Shortcut: file, NodeExe: node, Main: main, WorkingDir: work, Icon: icon };
  const payload = Buffer.from(JSON.stringify(data)).toString('base64');
  execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', WINDOW_SCRIPT], {
    windowsHide: true, timeout: 10000, maxBuffer: 100000,
    env: { ...process.env, CREW_SHORTCUT_DATA: payload },
  });
}

function extractIcon(exe, dest) {
  const script = [
    'Add-Type -AssemblyName System.Drawing',
    '$icon = [Drawing.Icon]::ExtractAssociatedIcon($env:CREW_OLD_EXE)',
    'if ($null -eq $icon) { throw "No launcher icon in existing application" }',
    '$stream = [IO.File]::Open($env:CREW_NEW_ICON, [IO.FileMode]::CreateNew)',
    'try { $icon.Save($stream) } finally { $stream.Dispose(); $icon.Dispose() }',
  ].join('; ');
  execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], {
    env: { ...process.env, CREW_OLD_EXE: exe, CREW_NEW_ICON: dest },
    timeout: 10000, windowsHide: true,
  });
}

export function migrationPaths(env = process.env, home = os.homedir()) {
  const root = dataDir(env);
  return {
    root,
    oldRoot: legacyDir(env),
    app: path.join(root, 'app'),
    desktop: path.join(home, 'Desktop', 'Tortoise Crew Launcher.lnk'),
    classicDesktop: path.join(home, 'Desktop', 'Tortoise Crew Classic.lnk'),
    start: path.join(env.APPDATA || path.join(home, 'AppData', 'Roaming'),
      'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Tortoise Crew Launcher.lnk'),
    classicStart: path.join(env.APPDATA || path.join(home, 'AppData', 'Roaming'),
      'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Tortoise Crew Classic.lnk'),
  };
}

export function planMigration(options = {}) {
  const paths = options.paths || migrationPaths();
  const node = options.node || process.execPath;
  if (process.platform !== 'win32' && !options.allowNonWindows)
    throw new Error('This migration is supported only on Windows.');
  if (!fs.existsSync(node)) throw new Error('The official Node.js runtime is missing.');
  if (!fs.existsSync(path.join(paths.oldRoot, 'TortoiseCrewLauncher.exe')))
    throw new Error('Existing Tortoise Crew Launcher not found. Nothing changed.');
  if (path.resolve(paths.app).toLowerCase() === path.resolve(APP_SRC).toLowerCase())
    throw new Error('Cannot overwrite the source directory.');
  return {
    node, ...paths,
    oldLauncher: path.join(paths.oldRoot, 'TortoiseCrewLauncher.exe'),
    existingDesktop: fs.existsSync(paths.desktop),
    existingStartMenu: fs.existsSync(paths.start),
    source: APP_SRC,
  };
}

function probe(app, node) {
  const child = execFileSync(node, [path.join(app, 'src', 'main.mjs'), '--health-probe'], {
    timeout: 18000, windowsHide: true, encoding: 'utf8',
    env: { ...process.env, CREW_NEXT_DATA_DIR: path.join(app, '.probe-data'),
      CREW_LEGACY_DATA_DIR: path.join(app, '.probe-legacy') },
  });
  if (!child.includes('CREW_NEXT_PROBE_OK')) throw new Error('New backend failed its health probe.');
}

export function migrate(options = {}) {
  const plan = planMigration(options);
  if (!options.apply) return { ...plan, dryRun: true, oldLauncherPreserved: true };
  const stamp = crypto.randomUUID();
  const staging = path.join(plan.root, 'app-staging-' + stamp);
  const oldApp = path.join(plan.root, 'app-previous-' + stamp);
  const shortcutBackups = [];
  let replaced = false;
  let newAppInstalled = false;
  fs.mkdirSync(plan.root, { recursive: true });
  try {
    fs.mkdirSync(staging);
    for (const item of ['package.json', 'public', 'src']) {
      fs.cpSync(path.join(plan.source, item), path.join(staging, item), { recursive: true, errorOnExist: true });
    }
    try { extractIcon(plan.oldLauncher, path.join(staging, 'crew.ico')); }
    catch { /* Fall back to the standard runtime icon, never block migration for artwork. */ }
    probe(staging, plan.node);
    if (fs.existsSync(plan.app)) {
      fs.renameSync(plan.app, oldApp);
      replaced = true;
    }
    fs.renameSync(staging, plan.app);
    newAppInstalled = true;
    probe(plan.app, plan.node);
    for (const shortcut of [plan.desktop, plan.start]) {
      fs.mkdirSync(path.dirname(shortcut), { recursive: true });
      const backup = path.join(plan.root,
        (shortcut === plan.desktop ? 'desktop' : 'startmenu') + '-previous-' + stamp + '.lnk');
      if (fs.existsSync(shortcut)) {
        fs.copyFileSync(shortcut, backup);
        shortcutBackups.push({ shortcut, backup });
      } else shortcutBackups.push({ shortcut, backup: null });
      if (options.pilot) {
        // Keep a usable shortcut to the existing launcher for the first actual
        // realm test. Revert these files as well if the migration fails.
        const classic = shortcut === plan.desktop ? plan.classicDesktop : plan.classicStart;
        const classicBackup = path.join(plan.root,
          (shortcut === plan.desktop ? 'classic-desktop' : 'classic-start') +
          '-previous-' + stamp + '.lnk');
        if (fs.existsSync(classic)) {
          fs.copyFileSync(classic, classicBackup);
          shortcutBackups.push({ shortcut: classic, backup: classicBackup });
        } else shortcutBackups.push({ shortcut: classic, backup: null });
        if (fs.existsSync(shortcut)) fs.copyFileSync(shortcut, classic);
        else nativeShortcut(classic, plan.oldLauncher, '', plan.oldRoot, plan.oldLauncher);
      }
      nativeShortcut(shortcut, plan.node, path.join(plan.app, 'src', 'main.mjs'), plan.app,
        path.join(plan.app, 'crew.ico'));
    }
    const marker = path.join(plan.root, 'startup-proof.json');
    if (fs.existsSync(marker)) fs.unlinkSync(marker);
    const child = spawn(plan.node, [path.join(plan.app, 'src', 'main.mjs')], {
      cwd: plan.app, windowsHide: true, detached: true, stdio: 'ignore',
    });
    child.unref();
    // A first-start browser or a slow Windows user profile may need more than
    // nine seconds. The handshake still must come from the real local UI.
    const until = Date.now() + 25000;
    let ready = false;
    while (Date.now() < until) {
      if (fs.existsSync(marker)) {
        const proof = JSON.parse(fs.readFileSync(marker, 'utf8'));
        if (proof.pid === child.pid) { ready = true; break; }
      }
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
    }
    if (!ready) throw new Error('New launcher did not start; restoring shortcuts.');
    writeJsonAtomic(path.join(plan.root, 'migration.json'), {
      completedUtc: new Date().toISOString(), oldLauncher: plan.oldLauncher,
      previousApp: replaced ? oldApp : null, oldShortcutBackups: shortcutBackups,
      cleanupPendingFirstVerifiedGameStart: !options.pilot,
      pilot: options.pilot === true,
    });
    return { migrated: true, startedPid: child.pid,
      oldLauncherPreservedUntilGameWorks: true, desktop: plan.desktop, start: plan.start,
      pilot: options.pilot === true };
  } catch (error) {
    for (const { shortcut, backup } of shortcutBackups.reverse()) {
      if (backup) fs.copyFileSync(backup, shortcut);
      else if (fs.existsSync(shortcut)) fs.unlinkSync(shortcut);
    }
    if (newAppInstalled && fs.existsSync(plan.app)) fs.rmSync(plan.app, { recursive: true, force: true });
    if (replaced && fs.existsSync(oldApp)) fs.renameSync(oldApp, plan.app);
    throw error;
  } finally {
    if (fs.existsSync(staging)) fs.rmSync(staging, { recursive: true, force: true });
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = migrate({ apply: process.argv.includes('--apply'),
      pilot: process.argv.includes('--pilot') });
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
