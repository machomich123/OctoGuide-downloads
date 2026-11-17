import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  loadSettings, saveSettings, crewBaseUrl, ACCOUNTS,
} from '../src/config.mjs';
import {
  safeName, installedAddons, importPlan, importAddons, repairAddons,
} from '../src/addons.mjs';
import { encodeFrame, FrameDecoder } from '../src/relay.mjs';
import { planMigration, migrate, nativeShortcut } from '../src/migrate.mjs';
import { createServer } from '../src/main.mjs';
import {
  browserCandidates, selectAppBrowser, desktopAppArguments,
} from '../src/desktop-window.mjs';
import { saveCredential, readCredential } from '../src/secrets.mjs';
import { gitHubRepo, parseRegistry, loadCatalog } from '../src/catalog.mjs';
import { unpackZip } from '../src/safe-zip.mjs';
import { collectAddonFolders, installFromGitHub } from '../src/github-addons.mjs';
import { hiddenScript, installHiddenShortcuts } from '../src/hidden-start.mjs';
import { compareVersion, validateUpdateManifest, applyUpdate } from '../bootstrap.mjs';
import { installOnce } from '../install-once.mjs';
const RELEASE_VERSION = JSON.parse(fs.readFileSync(
  path.resolve('tortoise-crew', 'next', 'package.json'), 'utf8')).version;

function fixture(t) {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-next-test-'));
  t.after(() => fs.rmSync(base, { recursive: true, force: true }));
  return base;
}
function game(base) {
  fs.mkdirSync(path.join(base, 'Interface', 'AddOns'), { recursive: true });
  fs.mkdirSync(path.join(base, 'WTF'), { recursive: true });
  fs.writeFileSync(path.join(base, 'WTF', 'Config.wtf'), 'SET scriptMemory "48"\r\nSET other "yes"\r\n');
  return base;
}
function addon(gameDir, folder, tocName = folder, extra = null) {
  const dst = path.join(gameDir, 'Interface', 'AddOns', folder);
  fs.mkdirSync(dst, { recursive: true });
  fs.writeFileSync(path.join(dst, tocName + '.toc'), '## Interface: 11800\n## Dependencies: MissingAddon\n');
  fs.writeFileSync(path.join(dst, 'Main.lua'), '-- normal addon code');
  if (extra) fs.writeFileSync(path.join(dst, extra), 'disabled');
  return dst;
}

test('settings migrate case-sensitive old fields without changing legacy files', t => {
  const root = fixture(t), legacy = path.join(root, 'old'), next = path.join(root, 'next');
  fs.mkdirSync(legacy);
  const before = JSON.stringify({ Username: 'MICHAEL', WowPath: 'C:\\Games\\WoW.exe', CrewApiUrl: 'https://secure.trycloudflare.com' });
  fs.writeFileSync(path.join(legacy, 'settings.json'), before);
  const settings = loadSettings(next, legacy);
  assert.equal(settings.username, 'MICHAEL');
  saveSettings(next, settings);
  assert.equal(fs.readFileSync(path.join(legacy, 'settings.json'), 'utf8'), before);
  assert.deepEqual(ACCOUNTS, ['MICHAEL', 'JAYKE', 'BERNARD', 'AUGUST']);
});

test('untrusted Crew URLs, reserved names and paths are rejected', () => {
  for (const url of ['http://test.trycloudflare.com', 'https://eviltrycloudflare.com',
    'https://evil.example.com', 'https://user:pwd@abc.trycloudflare.com',
    'https://abc.trycloudflare.com/hack']) {
    assert.throws(() => crewBaseUrl(url));
  }
  assert.equal(crewBaseUrl('https://abc.trycloudflare.com'), 'https://abc.trycloudflare.com');
  for (const name of ['..', 'CON', 'AUX.txt', '../bad', 'bad\\folder', 'a?.toc']) {
    assert.equal(safeName(name), false);
  }
  assert.equal(safeName('!OctoScope.toc'), true);
});

test('addon import preserves old versions and excludes executables', t => {
  const root = fixture(t), src = game(path.join(root, 'source')), dst = game(path.join(root, 'dest'));
  const old = addon(dst, 'OctoScope', 'OctoScope');
  fs.writeFileSync(path.join(old, 'Old.lua'), 'original');
  addon(src, 'wrong-folder', 'OctoScope', 'native-helper.dll');
  addon(src, 'Blizzard_Unit', 'Blizzard_Unit');
  const plan = importPlan(src, dst);
  assert.equal(plan.planned.length, 1);
  const result = importAddons(src, dst, { isGameRunning: () => false });
  assert.equal(result.imported, 1);
  assert.equal(fs.existsSync(path.join(dst, 'Interface', 'AddOns', 'OctoScope', 'native-helper.dll')), false);
  assert.equal(fs.readFileSync(path.join(result.backup, 'OctoScope', 'Old.lua'), 'utf8'), 'original');
  assert.ok(result.missingDependencies.some(x => x.dependency === 'MissingAddon'));
});

test('repair preserves original configuration, old SavedVariables and names', t => {
  const root = fixture(t), dst = game(path.join(root, 'client'));
  addon(dst, 'incorrect', '!OctoScope');
  fs.mkdirSync(path.join(dst, 'WTF', 'Account'));
  fs.writeFileSync(path.join(dst, 'WTF', 'Account', 'SavedVariables.lua'), 'keep me');
  const result = repairAddons(dst, { isGameRunning: () => false });
  assert.equal(result.renamed, 1);
  assert.equal(installedAddons(dst)[0].name, '!OctoScope');
  assert.match(fs.readFileSync(path.join(dst, 'WTF', 'Config.wtf'), 'utf8'), /SET scriptMemory "0"/);
  assert.match(fs.readFileSync(path.join(result.backup, 'Config.wtf'), 'utf8'), /scriptMemory "48"/);
  assert.equal(fs.readFileSync(path.join(dst, 'WTF', 'Account', 'SavedVariables.lua'), 'utf8'), 'keep me');
});

test('WebSocket decoder supports split packets, ping and unmasked binary frames', () => {
  const received = [], pings = [];
  const decoder = new FrameDecoder(x => received.push(x.toString('utf8')),
    x => pings.push(x.toString('utf8')), () => {});
  decoder.push(Buffer.from([0x82, 0x05, 72]));
  decoder.push(Buffer.from([101, 108, 108, 111, 0x89, 0x02, 79, 75]));
  assert.deepEqual(received, ['Hello']);
  assert.deepEqual(pings, ['OK']);
  const sent = encodeFrame(2, Buffer.from('Hello'));
  assert.equal(sent[1] & 0x80, 0x80); // Client packets must be masked.
  assert.throws(() => new FrameDecoder(() => {}, () => {}, () => {}).push(sent));
});

test('local API rejects wrong-origin requests; browser UI and handshake work', async t => {
  const { server, url } = await createServer();
  t.after(() => new Promise(resolve => server.close(resolve)));
  const origin = new URL(url).origin;
  const token = new URL(url).searchParams.get('key');
  const html = await fetch(url);
  assert.equal(html.status, 200);
  assert.match(await html.text(), /Tortoise Crew/);
  const bad = await fetch(origin + '/api', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: 'https://evil.example',
      'X-Crew-Token': token },
    body: '{"action":"state"}',
  });
  assert.equal(bad.status, 403);
  const good = await fetch(origin + '/api', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: origin, 'X-Crew-Token': token },
    body: '{"action":"state"}',
  });
  assert.equal((await good.json()).ok, true);
});

test('migration dry-run never replaces old launcher or shortcuts', t => {
  const base = fixture(t), home = path.join(base, 'home');
  const oldRoot = path.join(base, 'old'), nextRoot = path.join(base, 'next');
  fs.mkdirSync(oldRoot);
  fs.mkdirSync(home);
  const oldExe = path.join(oldRoot, 'TortoiseCrewLauncher.exe');
  fs.writeFileSync(oldExe, 'old launcher');
  const paths = { root: nextRoot, oldRoot, app: path.join(nextRoot, 'app'),
    desktop: path.join(home, 'Tortoise Crew Launcher.lnk'),
    start: path.join(home, 'Start Menu', 'Tortoise Crew Launcher.lnk') };
  assert.equal(planMigration({ paths, node: process.execPath, allowNonWindows: true }).existingDesktop, false);
  const plan = migrate({ paths, node: process.execPath, allowNonWindows: true });
  assert.equal(plan.dryRun, true);
  assert.equal(fs.readFileSync(oldExe, 'utf8'), 'old launcher');
  assert.equal(fs.existsSync(nextRoot), false);
});

test('Windows DPAPI encryption round-trip when available', t => {
  if (process.platform !== 'win32') return t.skip('Windows-only encrypted credential vault');
  const root = fixture(t);
  saveCredential(root, 'MICHAEL', 'aB!34*%?');
  assert.equal(readCredential(root, 'MICHAEL'), 'aB!34*%?');
  const file = fs.readFileSync(path.join(root, 'credentials.json'), 'utf8');
  assert.doesNotMatch(file, /aB!34/);
});

test('Windows creates a real .lnk pointing at signed Node and launcher entrypoint', t => {
  if (process.platform !== 'win32') return t.skip('Windows shell shortcut test');
  const root = fixture(t);
  const file = path.join(root, 'Tortoise Crew Launcher.lnk');
  const main = path.resolve('src', 'main.mjs');
  nativeShortcut(file, process.execPath, main, root, '');
  assert.ok(fs.existsSync(file));
  const output = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
    '$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:CREW_TEST_LINK); ' +
    '[Console]::Out.Write($s.TargetPath + "|" + $s.Arguments)'], {
    env: { ...process.env, CREW_TEST_LINK: file },
    windowsHide: true, encoding: 'utf8',
  });
  assert.equal(output.status, 0, output.stderr);
  assert.ok(output.stdout.toLowerCase().includes(process.execPath.toLowerCase()));
  assert.ok(output.stdout.includes('main.mjs'));
});

test('app-window selects Edge independent of default browser, with Chrome fallback', () => {
  const env = {
    'ProgramFiles(x86)': 'C:\\Program Files (x86)',
    ProgramFiles: 'C:\\Program Files',
    LOCALAPPDATA: 'C:\\Users\\Example\\AppData\\Local',
  };
  // Use platform-appropriate paths to exercise the selector on CI and locally.
  const all = browserCandidates(env);
  const edge = all.find(([name]) => name === 'Microsoft Edge');
  const chrome = all.find(([name]) => name === 'Google Chrome');
  assert.ok(edge);
  assert.ok(chrome);
  assert.equal(selectAppBrowser(env, file => file === edge[1]).name, 'Microsoft Edge');
  assert.equal(selectAppBrowser(env, file => file === chrome[1]).name, 'Google Chrome');
  assert.throws(() => selectAppBrowser(env, () => false), /Install Edge/);
});

test('app-window uses a local, isolated profile and no browser security overrides', () => {
  const home = path.resolve('crew-next-test');
  const url = 'http://127.0.0.1:38493/?key=' + 'a'.repeat(64);
  const args = desktopAppArguments(url, home);
  assert.equal(args[0], '--app=' + url);
  assert.ok(args.some(x => x.startsWith('--user-data-dir=')));
  assert.ok(args.includes('--no-first-run'));
  assert.ok(args.every(x => !/disable-web-security|allow-running-insecure|ignore-certificate-errors/i.test(x)));
  for (const bad of ['https://google.com/', 'http://localhost:38493/?key=' + 'a'.repeat(64),
    'http://127.0.0.1:38493/?key=invalid', 'http://127.0.0.1:38493/api?key=' + 'a'.repeat(64)]) {
    assert.throws(() => desktopAppArguments(bad, home));
  }
});

test('old Turtle catalog parses all valid GitHub and GitLab listings', async t => {
  const root = fixture(t);
  const legacy = path.join(root, 'legacy');
  fs.mkdirSync(legacy);
  const input = { addons: [
    { name: 'Octoscope', url: 'https://github.com/author/Octoscope', stars: 15 },
    { name: 'Legacy GitLab', url: 'https://gitlab.com/author/legacy', stars: 2 },
    { name: 'Wrong source', url: 'http://example.com/unsafe', stars: 500 },
  ] };
  const text = JSON.stringify(input);
  fs.writeFileSync(path.join(legacy, 'addon-registry.json'), text);
  const { items } = await loadCatalog({ root: path.join(root, 'next'), legacy,
    fetchText: async () => { throw new Error('Offline fixture'); } });
  assert.equal(items.length, 2);
  assert.equal(items[0].name, 'Octoscope');
  assert.equal(items[1].installable, false);
  assert.equal(parseRegistry(text).length, 2);
  assert.deepEqual(gitHubRepo('https://github.com/author/Octoscope'),
    { owner: 'author', repo: 'Octoscope', url: 'https://github.com/author/Octoscope' });
  assert.equal(gitHubRepo('https://evil.com/a/b'), null);
});

test('safe ZIP and GitHub addon importer skip executables and preserve existing addon', async t => {
  if (process.platform !== 'win32') return t.skip('PowerShell ZIP fixture');
  const root = fixture(t);
  const input = path.join(root, 'archive-src'), repo = path.join(input, 'some-github-repo');
  const folder = path.join(repo, 'Octoscope');
  fs.mkdirSync(folder, { recursive: true });
  fs.writeFileSync(path.join(folder, 'Octoscope.toc'), '## Interface: 11800\n');
  fs.writeFileSync(path.join(folder, 'Octoscope-tbc.toc'), '## Interface: 20500\n');
  fs.writeFileSync(path.join(folder, 'Core.lua'), '-- compatible addon');
  fs.writeFileSync(path.join(folder, 'addon.dll'), 'no native binaries');
  const zip = path.join(root, 'addon.zip');
  const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
    'Compress-Archive -LiteralPath $env:CREW_ZIP_SRC -DestinationPath $env:CREW_ZIP_FILE'], {
    windowsHide: true, encoding: 'utf8',
    env: { ...process.env, CREW_ZIP_SRC: repo, CREW_ZIP_FILE: zip },
  });
  assert.equal(result.status, 0, result.stderr);
  const extracted = path.join(root, 'extracted');
  const archive = fs.readFileSync(zip);
  assert.ok(unpackZip(archive, extracted, { extensions: new Set(['.lua', '.toc']) }).files >= 2);
  assert.equal(collectAddonFolders(extracted).length, 1);
  const client = game(path.join(root, 'client'));
  const old = addon(client, 'Octoscope');
  fs.writeFileSync(path.join(old, 'Old.lua'), '-- old');
  let fetchCount = 0;
  const installed = await installFromGitHub('https://github.com/author/Octoscope', client, {
    isGameRunning: () => false,
    download: async (url) => ++fetchCount === 1 ?
      Buffer.from('{"default_branch":"main"}') : archive,
  });
  assert.equal(installed.imported, 1);
  assert.ok(fs.existsSync(path.join(client, 'Interface', 'AddOns', 'Octoscope', 'Core.lua')));
  assert.equal(fs.existsSync(path.join(client, 'Interface', 'AddOns', 'Octoscope', 'addon.dll')), false);
  assert.equal(fs.existsSync(path.join(client, 'Interface', 'AddOns', 'Octoscope', 'Octoscope-tbc.toc')), false);
  assert.ok(fs.existsSync(path.join(installed.backup, 'Octoscope', 'Old.lua')));
  assert.throws(() => unpackZip(Buffer.from('not-zip'), path.join(root, 'unsafe')), /ZIP/);
});

test('launcher update validates GitHub URL, version ordering and sha256', () => {
  assert.equal(compareVersion('0.2.0', '0.1.9') > 0, true);
  assert.equal(compareVersion('0.2.0', '0.2.0'), 0);
  assert.equal(compareVersion('0.1.9', '0.2.0') < 0, true);
  const release = {
    version: '0.2.0',
    bundleUrl: 'https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/next/crew-next-0.2.0.zip',
    sha256: 'A'.repeat(64),
  };
  assert.deepEqual(validateUpdateManifest(release), release);
  assert.throws(() => validateUpdateManifest({ ...release, bundleUrl: 'https://evil.test/payload.zip' }));
  assert.throws(() => validateUpdateManifest({ ...release, sha256: 'bad' }));
});

test('verified GitHub package applies atomically and keeps an app backup', async t => {
  const root = fixture(t), app = path.join(root, 'app');
  const current = path.resolve('tortoise-crew', 'next');
  fs.mkdirSync(app);
  for (const part of ['src', 'public']) {
    fs.cpSync(path.join(current, part), path.join(app, part), { recursive: true });
  }
  fs.writeFileSync(path.join(app, 'package.json'), JSON.stringify({ version: '0.1.9' }));
  const archive = fs.readFileSync(path.join(current, 'crew-next-' + RELEASE_VERSION + '.zip'));
  const sha256 = (await import('node:crypto')).createHash('sha256').update(archive).digest('hex');
  const release = {
    version: RELEASE_VERSION,
    bundleUrl: 'https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/next/crew-next-' + RELEASE_VERSION + '.zip',
    sha256,
  };
  await assert.rejects(() => applyUpdate(root, { ...release, sha256: 'f'.repeat(64) },
    { allowRunningGame: true, download: async () => archive }), /checksum mismatch/);
  assert.equal(JSON.parse(fs.readFileSync(path.join(app, 'package.json'), 'utf8')).version, '0.1.9');
  const result = await applyUpdate(root, release,
    { allowRunningGame: true, download: async () => archive });
  assert.equal(result.updated, true);
  assert.equal(JSON.parse(fs.readFileSync(path.join(app, 'package.json'), 'utf8')).version, RELEASE_VERSION);
  assert.equal(JSON.parse(fs.readFileSync(path.join(result.oldApp, 'package.json'), 'utf8')).version, '0.1.9');
});

test('hidden Windows launcher uses wscript and preserves a recovery shortcut', t => {
  if (process.platform !== 'win32') return t.skip('Windows desktop shortcut integration');
  const root = fixture(t), app = path.join(root, 'app');
  fs.mkdirSync(app);
  fs.writeFileSync(path.join(root, 'bootstrap.mjs'), '// test entrypoint');
  const first = path.join(root, 'desktop.lnk'), second = path.join(root, 'start.lnk');
  nativeShortcut(first, process.execPath, path.join(root, 'bootstrap.mjs'), root, '');
  const result = installHiddenShortcuts({ root, app,
    shortcuts: { desktop: first, start: second } });
  const readLink = file => spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive',
    '-Command', '$w=New-Object -ComObject WScript.Shell;' +
      '$s=$w.CreateShortcut($env:CREW_LINK);[Console]::Out.Write($s.TargetPath)'], {
    windowsHide: true, encoding: 'utf8', env: { ...process.env, CREW_LINK: file },
  }).stdout;
  assert.match(readLink(first), /wscript.exe$/i);
  assert.match(readLink(second), /wscript.exe$/i);
  assert.ok(fs.existsSync(first + '.before-hidden-launch.lnk'));
  assert.match(fs.readFileSync(result.script, 'utf8'), /shell\.Run/i);
  assert.ok(hiddenScript(process.execPath, path.join(root, 'bootstrap.mjs')).includes(', 0, False'));
});

test('one-time migration delivers a hidden launcher to a disconnected crew fixture', async t => {
  if (process.platform !== 'win32') return t.skip('Windows app migration fixture');
  const root = fixture(t), app = path.join(root, 'app');
  fs.mkdirSync(app);
  fs.writeFileSync(path.join(app, 'package.json'), '{"version":"0.1.0-preview"}');
  fs.mkdirSync(path.join(app, 'src'));
  fs.writeFileSync(path.join(app, 'src', 'main.mjs'), '// previous launcher');
  const dir = path.resolve('tortoise-crew', 'next');
  const archive = fs.readFileSync(path.join(dir, 'crew-next-' + RELEASE_VERSION + '.zip'));
  const boot = fs.readFileSync(path.join(dir, 'bootstrap.mjs'));
  const extractor = fs.readFileSync(path.join(dir, 'src', 'safe-zip.mjs'));
  const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
  const manifest = {
    version: RELEASE_VERSION,
    bundleUrl: 'https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/next/crew-next-' + RELEASE_VERSION + '.zip',
    sha256: digest(archive),
    bootstrapSha256: digest(boot),
    extractorSha256: digest(extractor),
  };
  const d = path.join(root, 'desk.lnk'), s = path.join(root, 'start.lnk');
  nativeShortcut(d, process.execPath, path.join(root, 'app', 'src', 'main.mjs'), root, '');
  const result = await installOnce({
    root, start: false, shortcuts: { desktop: d, start: s },
    download: async url => {
      if (url.endsWith('update.json')) return Buffer.from(JSON.stringify(manifest));
      if (url.endsWith('bootstrap.mjs')) return boot;
      if (url.endsWith('/safe-zip.mjs')) return extractor;
      if (url.endsWith('.zip')) return archive;
      throw new Error('Unexpected fixture URL.');
    },
  });
  assert.equal(result.installed, RELEASE_VERSION);
  assert.ok(fs.existsSync(path.join(root, 'bootstrap.mjs')));
  assert.ok(fs.existsSync(path.join(root, 'start-hidden.vbs')));
  assert.equal(JSON.parse(fs.readFileSync(path.join(app, 'package.json'), 'utf8')).version, RELEASE_VERSION);
  assert.ok(fs.existsSync(path.join(result.backup, 'src', 'main.mjs')));
});
