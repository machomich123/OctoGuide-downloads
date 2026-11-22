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
import { createServer, configureGame } from '../src/main.mjs';
import {
  browserCandidates, selectAppBrowser, desktopAppArguments,
} from '../src/desktop-window.mjs';
import { saveCredential, readCredential } from '../src/secrets.mjs';
import { gitHubRepo, parseRegistry, loadCatalog } from '../src/catalog.mjs';
import { unpackZip } from '../src/safe-zip.mjs';
import { collectAddonFolders, installFromGitHub } from '../src/github-addons.mjs';
import { PARTY_INVENTORY, featuredAddon, validatePartyRelease,
  inspectPartyInventory, partyInventoryStatus, installPartyInventory,
} from '../src/managed-addons.mjs';
import { hiddenScript, installHiddenShortcuts } from '../src/hidden-start.mjs';
import { compareVersion, validateUpdateManifest, applyUpdate } from '../bootstrap.mjs';
import { installOnce } from '../install-once.mjs';
import { accountPreferences, setAccountPreferences } from '../src/preferences.mjs';
import { addonDetails, githubReadmeImages, allowedImageUrl, imageData } from '../src/addon-details.mjs';
import { validateAutoLoginRequest, loginHelperSource } from '../src/wow-autologin.mjs';
import {
  nativeFiles, inspectNativeInstant, uninstallNativeInstant, nativePatcherBytes,
  upgradeNativeInstant,
} from '../src/native-instant.mjs';
import { nativeAssetText } from '../src/native-assets-bundled.mjs';
import { nativeVaultScript } from '../src/native-vault.mjs';
import { focusScript } from '../src/focus-wow.mjs';
import { guardianScript } from '../src/window-guardian.mjs';
import { LoginPreflight } from '../src/login-preflight.mjs';
import { readyFile, clearReadyFile, characterReady,
  waitForCharacterSelection } from '../src/character-ready.mjs';
const RELEASE_VERSION = JSON.parse(fs.readFileSync(
  path.resolve('tortoise-crew', 'next', 'package.json'), 'utf8')).version;

test('installed launcher version appears on all screens and matches the backend version', () => {
  const root = path.resolve('tortoise-crew', 'next');
  const html = fs.readFileSync(path.join(root, 'public', 'index.html'), 'utf8');
  const client = fs.readFileSync(path.join(root, 'public', 'main.js'), 'utf8');
  const settings = fs.readFileSync(path.join(root, 'src', 'config.mjs'), 'utf8');
  for (const id of ['launcherVersion', 'sidebarVersion', 'settingsVersion']) {
    assert.match(html, new RegExp('id="' + id + '"'));
    assert.match(client, new RegExp("\\$\\('" + id + "'\\)\\.textContent = installedVersion|\\$\\('" +
      id + "'\\)\\.textContent = 'Installed launcher version: ' \\+ installedVersion"));
  }
  assert.match(client, /state[.]version/);
  assert.match(settings, new RegExp("NEXT_VERSION = '" + RELEASE_VERSION.replaceAll('.', '[.]') + "'"));
});

function fixture(t) {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-next-test-'));
  t.after(() => fs.rmSync(base, { recursive: true, force: true }));
  return base;
}

test('native instant login ships as loose GlueXML without changing WoW.exe', t => {
  const files = nativeFiles();
  assert.deepEqual(Object.keys(files).sort(),
    ['GlueXML.toc', 'CrewInstantLogin.lua', 'CrewInstantLogin.xml',
      'CrewLegacyGlobals.lua'].sort());
  const toc = files['GlueXML.toc'].toString('utf8');
  assert.match(toc, /^CrewLegacyGlobals[.]lua\r?\nGlueConstants[.]lua/m);
  assert.match(toc, /AccountLogin[.]xml/);
  assert.match(toc, /CharacterSelect[.]xml/);
  assert.match(toc, /CrewInstantLogin[.]xml/);
  const lua = files['CrewInstantLogin.lua'].toString('utf8');
  assert.match(lua, /LoginWithSavedAccount/);
  assert.match(lua, /GetSavedAccounts/);
  assert.match(lua, /CharacterSelect_OnEvent/);
  assert.match(lua, /CHARACTER_LIST_UPDATE/);
  assert.match(lua, /AppendToFile/);
  assert.match(lua, /CrewCharacterReady[.]flag/);
  assert.match(lua, /SaveAccount/);
  assert.doesNotMatch(lua, /Authenticating securely|CrewInstantSplash/);
  assert.match(files['CrewLegacyGlobals.lua'].toString('utf8'), /_G = getfenv\(0\)/);
  assert.doesNotMatch(lua, /SetCVar[^(]*[(]"password"|ImportFile|EncryptPassword|password[ \t]*=[ \t]*["']\w+/);
  const dir = fixture(t);
  assert.deepEqual(inspectNativeInstant(dir, dir), { installed: false });
  assert.deepEqual(uninstallNativeInstant(dir, dir), { removed: false });
});

test('native source assets are embedded in the secure updater-compatible JavaScript bundle', () => {
  const originals = path.resolve('tortoise-crew', 'next', 'src', 'native-assets');
  for (const [name, source] of Object.entries(nativeAssetText)) {
    const original = fs.readFileSync(path.join(originals, name), 'utf8')
      .replace(/\r\n/g, '\n');
    assert.equal(source, original, 'Regenerate the asset bundle after editing ' + name);
    assert.deepEqual(nativeFiles()[name], Buffer.from(original, 'utf8'));
  }
});

test('native integration refuses untrusted VfPatcher DLL and avoids game mutation', async t => {
  const dir = fixture(t);
  const payload = path.join(dir, 'VfPatcher.dll');
  fs.writeFileSync(payload, 'not the official loader');
  await assert.rejects(() => nativePatcherBytes({ sourceFile: payload }),
    /checksum mismatch/i);
});

test('native Windows vault script scopes credentials and never uses command-line passwords', () => {
  const script = nativeVaultScript();
  assert.match(script, /CredWriteW/);
  assert.match(script, /ClassicAPI\/WoW\//);
  assert.match(script, /127[.]0[.]0[.]1/);
  assert.match(script, /Console\]::In[.]ReadToEnd/);
  assert.match(script, /Marshal\]::FreeHGlobal/);
  assert.doesNotMatch(script, /Set-Content|Out-File|Invoke-WebRequest|clipboard|Write-Host/);
});

test('native vault PowerShell is parseable without sending any credentials', () => {
  if (process.platform !== 'win32') return;
  const script = nativeVaultScript();
  const run = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive',
    '-Command', '$tokens=$null;$errors=$null;' +
    '[void][System.Management.Automation.Language.Parser]::ParseInput(' +
    '[Console]::In.ReadToEnd(),[ref]$tokens,[ref]$errors);' +
    'if($errors.Count){$errors|%{$_.Message};exit 2};"VAULT_SYNTAX_OK"'], {
    input: script, encoding: 'utf8', windowsHide: true, timeout: 9000,
  });
  assert.equal(run.status, 0, run.stdout + run.stderr);
  assert.match(run.stdout, /VAULT_SYNTAX_OK/);
});

test('native focus helper targets only the WoW window without keystrokes', () => {
  const source = focusScript();
  assert.match(source, /ProcessName -ne "WoW"/);
  assert.match(source, /SetForegroundWindow/);
  assert.match(source, /EnumWindows/);
  assert.match(source, /GetWindowThreadProcessId/);
  assert.match(source, /ShowWindowAsync/);
  assert.doesNotMatch(source, /SendKeys|SendInput|password|Inject|Set-ExecutionPolicy/);
});

test('readiness signal distinguishes real character list from stale/missing data', async t => {
  const folder = fixture(t);
  fs.mkdirSync(path.join(folder, 'WTF'), { recursive: true });
  const flag = readyFile(folder);
  assert.equal(characterReady(folder), false);
  fs.writeFileSync(flag, 'not ready');
  assert.equal(characterReady(folder), false);
  clearReadyFile(folder);
  assert.equal(fs.existsSync(flag), false);
  setTimeout(() => fs.writeFileSync(flag, 'CREW_CHARACTER_LIST_READY\n'), 80);
  const result = await waitForCharacterSelection(folder, {
    intervalMs: 20, timeoutMs: 1000,
  });
  assert.equal(result.status, 'ready');
  assert.equal(characterReady(folder), true);
  clearReadyFile(folder);
  const exited = await waitForCharacterSelection(folder, {
    intervalMs: 20, timeoutMs: 1000,
    isGameRunning: () => false,
  });
  assert.equal(exited.status, 'exited');
  const timeout = await waitForCharacterSelection(folder, {
    intervalMs: 10, timeoutMs: 35,
  });
  assert.equal(timeout.status, 'timeout');
});

test('launcher pre-verifies once, reuses token and awaits in-flight verification', async () => {
  let calls = 0, provisioned = 0, now = 1000;
  let finish;
  const preflight = new LoginPreflight({
    authenticate: () => {
      calls++;
      return new Promise(resolve => { finish = resolve; });
    },
    provision: () => { provisioned++; },
    now: () => now, validMs: 20000,
  });
  const payload = { account: 'MICHAEL', password: 'example-only',
    url: 'https://crew.example.test', native: true };
  const preparing = preflight.prepare(payload);
  assert.equal(preflight.status('MICHAEL').status, 'verifying');
  const consuming = preflight.take(payload);
  finish('a'.repeat(64));
  assert.equal((await preparing).verified, true);
  assert.equal(await consuming, 'a'.repeat(64));
  assert.equal(calls, 1);
  assert.equal(provisioned, 1);
  now += 21000;
  const second = preflight.prepare(payload);
  finish('b'.repeat(64));
  await second;
  assert.equal(await preflight.take(payload), 'b'.repeat(64));
  assert.equal(calls, 2);
  assert.equal(provisioned, 2);
  preflight.invalidate();
  assert.equal(preflight.status('MICHAEL').verified, false);
});

test('Win32 hidden-window enumerator compiles using signed Windows PowerShell', () => {
  if (process.platform !== 'win32') return;
  // A non-WoW PID exits safely without touching any window, but the full
  // Win32 helper must compile before its PID guard runs.
  const processResult = spawnSync('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command', focusScript()], {
      input: JSON.stringify({ pid: process.pid, mode: 'inspect' }),
      windowsHide: true, encoding: 'utf8', timeout: 16000,
    });
  assert.equal(processResult.status, 3, processResult.stderr + processResult.stdout);
  assert.equal(processResult.stderr.trim(), '');
});

test('guardian parks the real WoW window and reveals it only after character readiness', () => {
  const script = guardianScript();
  assert.match(script, /SetWinEventHook/);
  assert.match(script, /SetWindowPos/);
  assert.match(script, /-30000/);
  assert.match(script, /CREW_CHARACTER_LIST_READY/);
  assert.match(script, /CHARACTER_VISIBLE/);
  assert.match(script, /FALLBACK_VISIBLE/);
  assert.match(script, /Stop\(\)/);
  assert.doesNotMatch(script, /SendKeys|SendInput|Set-ExecutionPolicy|CredWrite|password/i);
});

test('Win32 window guardian parses cleanly without launching WoW', () => {
  if (process.platform !== 'win32') return;
  const result = spawnSync('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Command',
      '$t=$null;$e=$null;' +
      '[void][System.Management.Automation.Language.Parser]::ParseInput(' +
      '[Console]::In.ReadToEnd(),[ref]$t,[ref]$e);' +
      'if($e.Count){$e|%{$_.Message};exit 2};"GUARDIAN_SYNTAX_OK"'], {
      input: guardianScript(), encoding: 'utf8', windowsHide: true, timeout: 9000,
    });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /GUARDIAN_SYNTAX_OK/);
});
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
  assert.equal(items.length, 4);
  assert.equal(items[0].name, 'TortoiseBotsManager');
  assert.equal(items[1].name, 'TBM Party Inventory');
  assert.equal(items[1].managedId, 'party-inventory');
  assert.equal(items[2].name, 'Octoscope');
  assert.equal(items[3].installable, false);
  assert.equal(parseRegistry(text).length, 2);
  assert.deepEqual(gitHubRepo('https://github.com/author/Octoscope'),
    { owner: 'author', repo: 'Octoscope', url: 'https://github.com/author/Octoscope' });
  assert.equal(gitHubRepo('https://evil.com/a/b'), null);
});

test('managed Party Inventory can be installed and updated safely from verified release files', async t => {
  const root = fixture(t), client = game(path.join(root, 'client'));
  const toc = Buffer.from('## Interface: 11200\n## Title: TBM Party Inventory\n' +
    '## Dependencies: TortoiseBotsManager\nInventory.lua\n');
  const source = (version, lua) => {
    const inventory = Buffer.from(lua);
    const assets = {
      'Assets/Refresh.tga': Buffer.from('refresh texture fixture'),
      'Assets/Settings.tga': Buffer.from('settings texture fixture'),
      'Assets/SellMarked.tga': Buffer.from('sell texture fixture'),
    };
    const release = { schema: 1, addon: PARTY_INVENTORY.name, version,
      files: { 'TortoiseBotsPartyInventory.toc': crypto.createHash('sha256').update(toc).digest('hex'),
        'Inventory.lua': crypto.createHash('sha256').update(inventory).digest('hex'),
        ...Object.fromEntries(Object.entries(assets).map(([name, bytes]) =>
          [name, crypto.createHash('sha256').update(bytes).digest('hex')])) } };
    const bytes = { 'release.json': Buffer.from(JSON.stringify(release)),
      'TortoiseBotsPartyInventory.toc': toc, 'Inventory.lua': inventory, ...assets };
    return { release, download: async (url, limit) => {
      assert.ok(url.startsWith('https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/'));
      const filename = Object.keys(bytes).find(name => url.endsWith('/' + name));
      const result = bytes[filename];
      assert.ok(result && result.length <= limit);
      return result;
    } };
  };
  assert.ok(featuredAddon().installable);
  assert.throws(() => validatePartyRelease({ addon: PARTY_INVENTORY.name, schema: 1,
    version: '1', files: { '../unsafe.lua': '0'.repeat(64) } }), /manifest/);
  const old = addon(client, PARTY_INVENTORY.name);
  fs.writeFileSync(path.join(old, 'PersonalNote.lua'), '-- preserved by backup');
  const first = source('2026.11.22.1', '-- verified inventory v1');
  assert.equal(inspectPartyInventory(client).managed, false);
  const autoBeforeInstall = await installPartyInventory(client, { download: first.download, auto: true });
  assert.equal(autoBeforeInstall.changed, false);
  assert.ok(fs.existsSync(path.join(old, 'PersonalNote.lua')));
  const installed = await installPartyInventory(client, { download: first.download });
  assert.equal(installed.imported, 1);
  assert.equal(installed.changed, true);
  assert.ok(fs.existsSync(path.join(old, 'Assets', 'Settings.tga')));
  assert.ok(fs.existsSync(path.join(installed.backup, PARTY_INVENTORY.name, 'PersonalNote.lua')));
  assert.equal(inspectPartyInventory(client).managed, true);
  assert.equal((await partyInventoryStatus(client, { download: first.download })).updateAvailable, false);
  const unchanged = await installPartyInventory(client, { download: first.download });
  assert.equal(unchanged.changed, false);
  assert.equal(unchanged.upToDate, true);

  const next = source('2026.11.22.2', '-- verified inventory v2');
  assert.equal((await partyInventoryStatus(client, { download: next.download })).updateAvailable, true);
  const upgraded = await installPartyInventory(client, { download: next.download, auto: true });
  assert.equal(upgraded.changed, true);
  assert.equal(fs.readFileSync(path.join(old, 'Inventory.lua'), 'utf8'), '-- verified inventory v2');
  assert.ok(fs.existsSync(path.join(upgraded.backup, PARTY_INVENTORY.name, 'Inventory.lua')));
  fs.writeFileSync(path.join(old, 'Inventory.lua'), '-- local customization');
  const guarded = await installPartyInventory(client, { download: next.download, auto: true });
  assert.equal(guarded.skipped, 'locally modified');
  assert.equal(fs.readFileSync(path.join(old, 'Inventory.lua'), 'utf8'), '-- local customization');
  const repaired = await installPartyInventory(client, { download: next.download });
  assert.equal(repaired.changed, true);
  assert.equal(fs.readFileSync(path.join(repaired.backup, PARTY_INVENTORY.name, 'Inventory.lua'), 'utf8'),
    '-- local customization');

  const broken = source('2026.11.22.3', '-- valid release v3');
  const sabotage = async (url, limit) => url.endsWith('/Inventory.lua') ?
    Buffer.from('-- malicious or truncated') : broken.download(url, limit);
  await assert.rejects(() => installPartyInventory(client, { download: sabotage }), /checksum mismatch/);
  assert.equal(fs.readFileSync(path.join(old, 'Inventory.lua'), 'utf8'), '-- verified inventory v2');
  await assert.rejects(() => installPartyInventory(client, { download: broken.download,
    isGameRunning: () => true }), /Close WoW/);
  assert.equal(fs.readFileSync(path.join(old, 'Inventory.lua'), 'utf8'), '-- verified inventory v2');
});

test('Party Inventory release builder stages exactly the approved Lua, TOC and TGA assets', t => {
  const root = fixture(t), output = path.join(root, 'release');
  const toc = path.join(root, 'approved.toc'), lua = path.join(root, 'approved.lua');
  const assets = path.join(root, 'Assets');
  fs.mkdirSync(assets);
  for (const name of ['Refresh.tga', 'Settings.tga', 'SellMarked.tga'])
    fs.writeFileSync(path.join(assets, name), 'approved-' + name);
  fs.writeFileSync(toc, '## Interface: 11200\n## Dependencies: TortoiseBotsManager\nInventory.lua\n');
  fs.writeFileSync(lua, '-- frozen QA-approved addon\n');
  const builder = path.resolve('tortoise-crew', 'next', 'scripts', 'Prepare-Party-Inventory.mjs');
  const invoke = version => spawnSync(process.execPath,
    [builder, '--lua', lua, '--toc', toc, '--assets', assets,
      '--version', version, '--output', output],
    { encoding: 'utf8', windowsHide: true, timeout: 10000 });
  const first = invoke('2026.11.22.1');
  assert.equal(first.status, 0, first.stderr);
  const release = validatePartyRelease(JSON.parse(fs.readFileSync(path.join(output, 'release.json'), 'utf8')));
  for (const [name, hash] of Object.entries(release.files))
    assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(output, ...name.split('/'))))
      .digest('hex'), hash);
  const previous = invoke('2026.11.22.1');
  assert.notEqual(previous.status, 0);
  assert.match(previous.stderr, /newer/);
  assert.equal(fs.readFileSync(path.join(output, 'Inventory.lua'), 'utf8'), '-- frozen QA-approved addon\n');
  fs.writeFileSync(lua, '-- next QA-approved addon\n');
  const next = invoke('2026.11.22.2');
  assert.equal(next.status, 0, next.stderr);
  assert.equal(fs.readFileSync(path.join(output, 'Inventory.lua'), 'utf8'), '-- next QA-approved addon\n');
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
    'Add-Type -AssemblyName System.IO.Compression.FileSystem; ' +
    '[IO.Compression.ZipFile]::CreateFromDirectory($env:CREW_ZIP_SRC,$env:CREW_ZIP_FILE,' +
    '[IO.Compression.CompressionLevel]::Optimal,$true)'], {
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
  assert.match(fs.readFileSync(result.script, 'utf8'), /shell\.CurrentDirectory/i);
  assert.ok(hiddenScript(process.execPath, path.join(root, 'bootstrap.mjs')).includes(', 0, False'));
});

test('one-time migration delivers a hidden launcher to a disconnected crew fixture', async t => {
  if (process.platform !== 'win32') return t.skip('Windows app migration fixture');
  const root = fixture(t), app = path.join(root, 'app');
  fs.mkdirSync(app);
  fs.writeFileSync(path.join(app, 'package.json'), '{"version":"0.1.0-preview"}');
  fs.mkdirSync(path.join(app, 'src'));
  fs.writeFileSync(path.join(app, 'src', 'main.mjs'), '// previous launcher');
  fs.writeFileSync(path.join(root, 'settings.json'), JSON.stringify({ username:'BERNARD', wowPath:'C:\\ExistingClient\\WoW.exe' }));
  fs.writeFileSync(path.join(root, 'credentials.json'), '{"fixture":"preserved"}');
  const settingsBefore=fs.readFileSync(path.join(root,'settings.json'));
  const vaultBefore=fs.readFileSync(path.join(root,'credentials.json'));
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
  const desktop=path.join(root,'OneDrive','Desktop');fs.mkdirSync(desktop,{recursive:true});
  const d = path.join(desktop, 'Tortoise Crew Launcher.lnk'), s = path.join(root, 'start.lnk');
  nativeShortcut(d, process.execPath, path.join(root, 'app', 'src', 'main.mjs'), root, '');
  const result = await installOnce({
    root, start: false, shortcuts: { desktop: d, start: s },
    download: async url => {
      if (url.includes('update.json?nonce=')) return Buffer.from(JSON.stringify(manifest));
      if (url.includes('bootstrap.mjs?nonce=')) return boot;
      if (url.includes('/safe-zip.mjs?nonce=')) return extractor;
      if (url.endsWith('.zip')) return archive;
      throw new Error('Unexpected fixture URL.');
    },
  });
  assert.equal(result.installed, RELEASE_VERSION);
  assert.ok(fs.existsSync(path.join(root, 'bootstrap.mjs')));
  assert.ok(fs.existsSync(path.join(root, 'start-hidden.vbs')));
  assert.equal(JSON.parse(fs.readFileSync(path.join(app, 'package.json'), 'utf8')).version, RELEASE_VERSION);
  assert.ok(fs.existsSync(path.join(result.backup, 'src', 'main.mjs')));
  assert(fs.readFileSync(path.join(root,'settings.json')).equals(settingsBefore));
  assert(fs.readFileSync(path.join(root,'credentials.json')).equals(vaultBefore));
  const marker=JSON.parse(fs.readFileSync(path.join(root,'launcher-icon.json'),'utf8'));
  assert.match(marker.sha256,/^[a-f0-9]{64}$/);
  const iconFiles=fs.readdirSync(app).filter(n=>/^crew-b3-.*\.ico$/.test(n));
  assert.equal(iconFiles.length,1);
  assert.equal(d,result.shortcuts.desktop);
  assert(fs.existsSync(path.join(root,'backups')));
});

test('saved-password and close-on-play choices persist by account across restarts', t => {
  const root = fixture(t);
  assert.equal(accountPreferences(root, 'MICHAEL', false).closeOnPlay, true);
  assert.equal(accountPreferences(root, 'MICHAEL', true).useSaved, true);
  setAccountPreferences(root, 'MICHAEL', {
    remember: true, useSaved: true, closeOnPlay: true,
  }, true);
  assert.deepEqual(accountPreferences(root, 'MICHAEL', true),
    { remember: true, useSaved: true, autoLogin: true, closeOnPlay: true });
  assert.equal(accountPreferences(root, 'BERNARD', false).remember, false);
  assert.equal(accountPreferences(root, 'MICHAEL', false).useSaved, false);
  const json = fs.readFileSync(path.join(root, 'account-preferences.json'), 'utf8');
  assert.doesNotMatch(json, /password|token|secret/i);
  assert.throws(() => setAccountPreferences(root, 'MICHAEL', { unexpected: true }));
});

test('auto-login defaults on, migrates legacy placeholder false and honors later opt-out', t => {
  const root = fixture(t);
  fs.writeFileSync(path.join(root, 'account-preferences.json'),
    JSON.stringify({ MICHAEL: { remember: true, useSaved: true, autoLogin: false } }));
  assert.equal(accountPreferences(root, 'MICHAEL', true).autoLogin, true);
  setAccountPreferences(root, 'MICHAEL', { autoLogin: false }, true);
  assert.equal(accountPreferences(root, 'MICHAEL', true).autoLogin, false);
  setAccountPreferences(root, 'MICHAEL', { autoLogin: true }, true);
  assert.equal(accountPreferences(root, 'MICHAEL', true).autoLogin, true);
  assert.equal(accountPreferences(root, 'BERNARD', false).autoLogin, true);
});

test('Windows auto-login checks the exact game process and keeps secrets off argv', () => {
  const request = {
    pid: 1234, exe: path.resolve('test', 'WoW.exe'),
    account: 'BERNARD', password: 'A+b^c%{ }',
  };
  if (process.platform === 'win32') {
    assert.doesNotThrow(() => validateAutoLoginRequest(request));
  }
  assert.throws(() => validateAutoLoginRequest({ ...request, account: 'STRANGER' }));
  assert.throws(() => validateAutoLoginRequest({ ...request, exe: 'not-wow.exe' }));
  assert.throws(() => validateAutoLoginRequest({ ...request, password: 'a\nb' }));
  assert.throws(() => validateAutoLoginRequest({ ...request, password: 'x'.repeat(17) }));
  const script = loginHelperSource();
  assert.match(script, /GetWindowThreadProcessId/);
  assert.match(script, /GetForegroundWindow/);
  assert.match(script, /GameHasFocus/);
  assert.match(script, /SetForegroundWindow/);
  assert.match(script, /AttachThreadInput/);
  assert.match(script, /BringWindowToTop/);
  assert.match(script, /ProcessName -ne "WoW"/);
  assert.match(script, /\$resolvedPath -and/);
  assert.match(script, /AppActivate/);
  assert.match(script, /\{ENTER\}/);
  assert.doesNotMatch(script, /\$account\.ToCharArray\(\)/);
  assert.doesNotMatch(script, /Set-Content|Out-File|Add-Content|Clipboard|CredWrite|Invoke-WebRequest/);
});

test('fast login focuses the verified game and submits the password as one sequence', () => {
  const script = loginHelperSource();
  assert.match(script, /CrewFocus\]::Activate\(\$window\)/);
  assert.match(script, /GameHasFocus/);
  assert.match(script, /WaitForInputIdle\(900\)/);
  assert.match(script, /Start-Sleep -Milliseconds 1050/);
  assert.match(script, /\$sequence[.]Append\(\(EncodeKey \$letter\)\)/);
  assert.match(script, /\$sequence[.]Append\("\{ENTER\}"\)/);
  assert.match(script, /SendWait\(\$sequence[.]ToString\(\)\)/);
  assert.doesNotMatch(script, /Start-Sleep -Milliseconds 4700/);
  assert.doesNotMatch(script, /SendWait\(\(EncodeKey \$letter\)\)/);
});

test('auto-login PowerShell syntax parses without opening a game or window', () => {
  if (process.platform !== 'win32') return;
  const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive',
    '-Command', [
      '$tokens=$null; $errors=$null;',
      '[void][System.Management.Automation.Language.Parser]::ParseInput(',
      '[Console]::In.ReadToEnd(),[ref]$tokens,[ref]$errors);',
      'if($errors.Count) { $errors|ForEach-Object{$_.Message};exit 1 }',
      '"PS_SCRIPT_SYNTAX_OK"',
    ].join(' ')], {
      input: loginHelperSource(), encoding: 'utf8', windowsHide: true, timeout: 9000,
    });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.match(result.stdout, /PS_SCRIPT_SYNTAX_OK/);
});

test('signed Windows host accepts auto-login helper without sending input', () => {
  if (process.platform !== 'win32') return;
  const result = spawnSync('powershell.exe',
    ['-NoProfile', '-NonInteractive', '-Sta', '-Command', loginHelperSource()], {
      input: JSON.stringify({ probe: true }),
      encoding: 'utf8', windowsHide: true, timeout: 18000,
    });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  assert.match(result.stdout, /HELPER_PROBE_OK/);
});

test('auto-login preserves Remember Username and never puts password in game config', t => {
  const root = fixture(t), gameDir = path.join(root, 'client');
  const folder = path.join(gameDir, 'WTF');
  fs.mkdirSync(folder, { recursive: true });
  const config = path.join(folder, 'Config.wtf');
  fs.writeFileSync(config, 'SET accountName "AUGUST"\r\nSET screenshotQuality "8"\r\n');
  configureGame(gameDir, 'MICHAEL', true);
  const contents = fs.readFileSync(config, 'utf8');
  assert.match(contents, /SET accountName "MICHAEL"/);
  assert.match(contents, /SET screenshotQuality "8"/);
  assert.doesNotMatch(contents, /password|secret/i);
  assert.match(fs.readFileSync(config + '.crew-backup', 'utf8'), /AUGUST/);
  configureGame(gameDir, 'JAYKE', false);
  assert.match(fs.readFileSync(config, 'utf8'), /SET accountName "JAYKE"/);
});

test('README extracts Markdown and HTML screenshot links without unsafe hosts', () => {
  const repo = gitHubRepo('https://github.com/shagu/ShaguTweaks');
  const markdown = '# Tweak\n![Settings](screenshots/settings.jpg)\n' +
    '<img src="screenshots/menu.jpg">\n![external](https://evil.example/img.png)\n' +
    '![other][screen]\n[screen]: screenshots/other.png';
  const urls = githubReadmeImages(markdown, repo, 'master');
  assert.equal(urls.length, 3);
  assert.equal(urls[0], 'https://raw.githubusercontent.com/shagu/ShaguTweaks/master/screenshots/settings.jpg');
  assert.ok(urls.some(x => x.endsWith('/screenshots/menu.jpg')));
  assert.equal(allowedImageUrl('http://127.0.0.1/secret.png'), null);
  assert.equal(allowedImageUrl('https://evil.example/screen.png'), null);
});

test('full addon details contain metadata, README, screenshots and safe image data', async () => {
  const body = Buffer.from('# Demo\n![Screen](screenshots/a.png)').toString('base64');
  const fetcher = async url => ({
    ok: true, status: 200,
    text: async () => JSON.stringify(url.endsWith('/readme') ?
      { encoding: 'base64', content: body } : {
        name: 'Demo', description: 'Complete description',
        default_branch: 'main', owner: { login: 'example' },
        stargazers_count: 17, forks_count: 5, topics: ['vanilla'],
        license: { spdx_id: 'MIT' },
      }),
  });
  const result = await addonDetails('https://github.com/example/Demo', fetcher);
  assert.equal(result.readme, '# Demo\n![Screen](screenshots/a.png)');
  assert.equal(result.license, 'MIT');
  assert.equal(result.stars, 17);
  assert.equal(result.images.length, 1);
  const png = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 1, 2]);
  const media = await imageData('https://raw.githubusercontent.com/example/Demo/main/a.png',
    async () => ({
      ok: true, status: 200,
      headers: new Headers({ 'Content-Type': 'image/png' }),
      body: [png],
    }));
  assert.equal(media.mime, 'image/png');
  assert.deepEqual(media.bytes, png);
  await assert.rejects(() => imageData('http://localhost/secret'));
});
