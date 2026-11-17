import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
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
