import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  ACCOUNTS, NEXT_VERSION, dataDir, legacyDir, loadSettings, saveSettings, validateGameExe,
  crewBaseUrl, readJson, writeJsonAtomic,
} from './config.mjs';
import { installedAddons, importPlan, importAddons, repairAddons, missingDependencies } from './addons.mjs';
import { manifest, crewRequest, crewLogin, crewPresence, changePassword } from './remote.mjs';
import { GameRelay } from './relay.mjs';
import { saveCredential, readCredential, storedAccounts } from './secrets.mjs';
import { openDesktopApp } from './desktop-window.mjs';
import { loadCatalog, searchGitHub, clientLocations } from './catalog.mjs';
import { installFromGitHub } from './github-addons.mjs';
import { accountPreferences, setAccountPreferences } from './preferences.mjs';
import { addonDetails, imageData } from './addon-details.mjs';
import { closeAppWindow } from './close-app.mjs';
import { startAutoLogin } from './wow-autologin.mjs';
import {
  inspectNativeInstant, installNativeInstant, uninstallNativeInstant,
  upgradeNativeInstant,
} from './native-instant.mjs';
import { saveNativeCredential } from './native-vault.mjs';
import { focusVerifiedGame, revealVerifiedGameSync } from './focus-wow.mjs';
import { LoginPreflight } from './login-preflight.mjs';
import { PreparedLogin } from './prepared-login.mjs';
import { createConnectionDiagnostics } from './connection-diagnostics.mjs';
import { launcherIconBytes, materializeLauncherIcon, ICON_SHA256 } from './launcher-icon.mjs';
import { installHiddenShortcuts } from './hidden-start.mjs';
import {
  clearReadyFile, readyFile, characterReady,
} from './character-ready.mjs';

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FILES = new Map([
  ['/', ['index.html', 'text/html; charset=utf-8']],
  ['/main.js', ['main.js', 'text/javascript; charset=utf-8']],
  ['/main.css', ['main.css', 'text/css; charset=utf-8']],
]);
const root = process.env.CREW_NEXT_DATA_DIR || dataDir();
const diagnostics = createConnectionDiagnostics(root, { version: NEXT_VERSION });
const previous = process.env.CREW_LEGACY_DATA_DIR || legacyDir();
const remembered = readJson(path.join(root, 'verified-account.json'), {});
const state = { settings: loadSettings(root, previous), game: null, relay: null,
  nativeWatch: null, nativeGuardian: null, nativeLastError: '',
  lastVerified: ACCOUNTS.includes(remembered.account) ? remembered.account : '',
  shuttingDown: false };
const preflight = new LoginPreflight({
  authenticate: crewLogin,
  provision: saveNativeCredential,
  validMs: 75000,
  prepareSession: async ({ account, password, url, token }) => {
    const presence = await crewPresence(url);
    if (presence[account] === true || presence[account]?.online)
      throw new Error('This account is already playing. Close its game before preparing another login.');
    return new PreparedLogin({ root, game: path.dirname(state.settings.wowPath),
      account, password, url, token, diagnostics,
      report: (stage, ms) => log('Prepared WoW: ' + stage +
        (ms === undefined ? '' : ' elapsedMs=' + ms)),
    }).prepare();
  },
});
const secret = crypto.randomBytes(32).toString('hex');

function redact(message) {
  return String(message || '').replace(/(Bearer\s+)[A-Za-z0-9]+/ig, '$1[hidden]');
}
function log(message) {
  fs.mkdirSync(root, { recursive: true });
  fs.appendFileSync(path.join(root, 'launcher.log'),
    new Date().toISOString() + ' ' + redact(message).substring(0, 400) + '\n');
}
function gameRunning() {
  if (state.game !== null && state.game.exitCode === null) return true;
  if (process.platform !== 'win32') return false;
  try {
    return /"WoW\.exe"/i.test(execFileSync('tasklist.exe',
      ['/FI', 'IMAGENAME eq WoW.exe', '/FO', 'CSV', '/NH'],
      { timeout: 3500, windowsHide: true, encoding: 'utf8' }));
  } catch {
    throw new Error('Could not verify that WoW is closed.');
  }
}
function observedWowPid() {
  if (process.platform !== 'win32') return null;
  const table = execFileSync('tasklist.exe',
    ['/FI', 'IMAGENAME eq WoW.exe', '/FO', 'CSV', '/NH'], {
      timeout: 3500, windowsHide: true, encoding: 'utf8',
    });
  const match = /"WoW[.]exe"\s*,\s*"([0-9]+)"/i.exec(table);
  return match ? Number(match[1]) : null;
}
function verifyPath() {
  if (!state.settings.wowPath) throw new Error('Choose a WoW.exe first.');
  return validateGameExe(state.settings.wowPath);
}
function addSetting(entry, value) {
  if (!['username', 'wowPath', 'crewApiUrl'].includes(entry)) throw new Error('Unknown setting.');
  const next = { ...state.settings, [entry]: value };
  if (entry === 'username' && !ACCOUNTS.includes(value)) throw new Error('Choose a known account.');
  if (entry === 'wowPath' && value) validateGameExe(value);
  if (entry === 'crewApiUrl' && value) crewBaseUrl(value);
  state.settings = saveSettings(root, next);
}

async function refreshCrewEndpoint() {
  const data = await manifest();
  const saved = state.settings.crewApiUrl;
  const retired = 'https://helmet-trunk-marie-jerry.trycloudflare.com';
  if (data.crewApiUrl && (!saved || saved === retired) && data.crewApiUrl !== saved) {
    addSetting('crewApiUrl', data.crewApiUrl);
    preflight.invalidate();
  }
  return data;
}

function prepareSavedAccount(force = false) {
  if (gameRunning()) return;
  if (!force && preflight.status(state.settings.username).status === 'verifying') return;
  state.lastPrepareAttempt = Date.now();
  const account = state.settings.username;
  preflight.invalidate();
  if (!ACCOUNTS.includes(account) || !state.settings.crewApiUrl ||
      !storedAccounts(root).includes(account)) return;
  const prefs = accountPreferences(root, account, true);
  if (!prefs.remember || !prefs.useSaved || !prefs.autoLogin) return;
  let password;
  try {
    password = readCredential(root, account);
  } catch (error) {
    log('Stored account verification unavailable: ' + error.name);
    return;
  }
  if (!password) return;
  let native = false;
  try {
    if (state.settings.wowPath) {
      native = inspectNativeInstant(
        path.dirname(state.settings.wowPath), root).installed;
      if (!native && !state.nativeInstallFailed) {
        if (!state.nativeInstall) {
          state.nativeInstall = installNativeInstant(verifyPath(), root, { gameRunning })
            .then(() => { state.nativeInstall = null; prepareSavedAccount(); })
            .catch(error => {
              state.nativeInstall = null; state.nativeInstallFailed = true;
              state.nativeLastError = error.message;
              log('Native preparation unavailable: ' + error.message);
              prepareSavedAccount();
            });
        }
        return;
      }
    }
  } catch (error) {
    log('Launcher preflight native inspection: ' + error.name);
  }
  // All work happens in the launcher; this never starts a game process.
  void preflight.prepare({
    account, password, url: state.settings.crewApiUrl, native, fromSaved: true,
  }).then(result => { if (result.verified) log('Launcher account verified and credentials prepared.'); })
    .catch(error => log('Launcher preflight unavailable: ' + error.message));
}

function backedUp(file, contents) {
  if (fs.existsSync(file)) {
    if (fs.lstatSync(file).isSymbolicLink()) throw new Error('Linked game configuration is not supported.');
    if (fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n') === contents.replace(/\r\n/g, '\n')) return;
    if (!fs.existsSync(file + '.crew-backup')) fs.copyFileSync(file, file + '.crew-backup');
  }
  fs.writeFileSync(file, contents, { encoding: 'utf8' });
}
export function configureGame(game, user, autoLogin = false, realmName = null) {
  if (!ACCOUNTS.includes(user)) throw new Error('Unknown account.');
  backedUp(path.join(game, 'realmlist.wtf'), 'set realmlist 127.0.0.1\r\n');
  const folder = path.join(game, 'WTF');
  fs.mkdirSync(folder, { recursive: true });
  const config = path.join(folder, 'Config.wtf');
  const previousText = fs.existsSync(config) ? fs.readFileSync(config, 'utf8') : '';
  // Preserve WoW's Remember Username setting. An empty accountName
  // disables the checkbox and removes the prefilled username.
  const newLine = 'SET accountName "' + user + '"';
  let text = /^\s*SET\s+accountName\s+.*$/im.test(previousText) ?
    previousText.replace(/^\s*SET\s+accountName\s+.*$/gim, newLine) :
    previousText.replace(/[\r\n]*$/, '\r\n') + newLine + '\r\n';
  if (realmName) {
    if (!/^[A-Za-z0-9 _.-]{1,100}$/.test(realmName)) throw new Error('Invalid prepared realm name.');
    const realmLine = 'SET realmName "' + realmName + '"';
    text = /^\s*SET\s+realmName\s+.*$/im.test(text) ?
      text.replace(/^\s*SET\s+realmName\s+.*$/gim, realmLine) : text + realmLine + '\r\n';
  }
  backedUp(config, text);
}
async function stopGame() {
  if (state.nativeGuardian) {
    // A user may close the launcher while WoW is booting off-screen.
    // Restore the game synchronously before ending the guard.
    try {
      const pid = observedWowPid();
      if (pid) revealVerifiedGameSync(pid);
    } catch (error) {
      log('Could not restore parked window during shutdown: ' + error.name);
    }
    state.nativeGuardian.kill();
    state.nativeGuardian = null;
  }
  if (state.nativeWatch) {
    clearInterval(state.nativeWatch);
    state.nativeWatch = null;
  }
  if (state.relay) {
    const relay = state.relay;
    state.relay = null;
    await relay.stop();
  }
}
async function play(account, password, remember, closeOnPlay = true, autoLogin = true) {
  if (gameRunning()) throw new Error('WoW is already running from this launcher.');
  if (!ACCOUNTS.includes(account) || !state.settings.crewApiUrl) throw new Error('Choose an account and Crew service.');
  const gameDir = verifyPath();
  if (typeof password !== 'string' || password.length < 1 || password.length > 16) {
    throw new Error('Enter the current WoW account password.');
  }
  let native = false;
  if (autoLogin) {
    if (state.nativeInstall) await state.nativeInstall;
    if (!inspectNativeInstant(gameDir, root).installed)
      await installNativeInstant(gameDir, root, { gameRunning });
    const status = inspectNativeInstant(gameDir, root);
    native = status.installed;
    if (native && status.upgradeAvailable) {
      upgradeNativeInstant(gameDir, root, { gameRunning });
    }
  }
  if (native && !remember) {
    throw new Error('Enable Remember password to use native instant login.');
  }
  // Reuse any account verification already completed while the launcher was
  // open. If Play wins the race, await the in-flight verification.
  const ticket = await preflight.takeTicket({
    account, password, url: state.settings.crewApiUrl, native,
  });
  // Save after Crew authentication, not after a later game launch succeeds:
  // clients that fail to start should still retain the verified credential.
  if (remember && !ticket.fromSaved) {
    saveCredential(root, account, password);
    setAccountPreferences(root, account, { remember: true, useSaved: true }, true);
  }
  const relay = ticket.prepared || new GameRelay(state.settings.crewApiUrl, ticket.token, { diagnostics });
  await relay.start();
  state.relay = relay;
  state.nativeLastError = '';
  try {
    configureGame(gameDir, account, autoLogin, ticket.prepared?.realm.name);
    if (native) {
      clearReadyFile(gameDir);
    }
    const executable = native ?
      path.join(gameDir, 'VanillaFixes.exe') : state.settings.wowPath;
    const child = spawn(executable, [], {
      // Play launches a normal visible game immediately. Authentication was
      // prepared by the launcher; no guardian, off-screen window, or reveal wait.
      cwd: gameDir, windowsHide: false, stdio: 'ignore',
    });
    await new Promise((resolve, reject) => {
      child.once('spawn', resolve);
      child.once('error', reject);
    });
    state.game = child;
    state.settings = saveSettings(root, { ...state.settings, username: account });
    state.lastVerified = account;
    // Verification is recorded only after a successful account login.
    const verifiedFile = path.join(root, 'verified-account.json');
    fs.writeFileSync(verifiedFile + '.new', JSON.stringify({ account, utc: new Date().toISOString() }));
    fs.renameSync(verifiedFile + '.new', verifiedFile);
    const migrated = path.join(root, 'migration.json');
    if (fs.existsSync(migrated)) {
      try {
        const record = readJson(migrated);
        if (record.cleanupPendingFirstVerifiedGameStart &&
            record.oldLauncher === path.join(previous, 'TortoiseCrewLauncher.exe')) {
          // Preserve user settings, DPAPI credentials and any recovery artifacts.
          // Delete only the obsolete executable after an authenticated game launch.
          fs.unlinkSync(record.oldLauncher);
          record.cleanupPendingFirstVerifiedGameStart = false;
          record.cleanupCompletedUtc = new Date().toISOString();
          const temp = migrated + '.new';
          fs.writeFileSync(temp, JSON.stringify(record, null, 2));
          fs.renameSync(temp, migrated);
          log('Old launcher executable retired after verified game launch.');
        }
      } catch (error) {
        log('Legacy executable retirement deferred: ' + error.name);
      }
    }
    if (native) {
      // VanillaFixes starts WoW suspended, attaches the already-installed
      // ClassicAPI DLL and exits. It does not remain alive for the game
      // session, so the relay must outlive its launcher process.
      child.once('exit', code => {
        state.game = null;
        if (code !== 0) {
          state.nativeLastError = 'Native loader exited with code ' + String(code);
          log(state.nativeLastError);
          void stopGame();
          return;
        }
        const startedAt = Date.now();
        const wait = setInterval(() => {
          let running;
          try { running = gameRunning(); } catch { running = false; }
          if (running) {
            clearInterval(wait);
            const pid = observedWowPid();
            if (pid) focusVerifiedGame(pid, focused => {
              log('Visible WoW startup focus confirmed: ' + focused);
              if (focused && closeOnPlay) closeAppWindow(root);
            });
            state.nativeWatch = setInterval(() => {
              try {
                if (!gameRunning()) {
                  log('Native WoW exited; releasing Crew relay.');
                  void stopGame();
                }
              } catch (error) {
                log('Native WoW status check unavailable: ' + error.name);
              }
            }, 1200);
            state.nativeWatch.unref();
          } else if (Date.now() - startedAt > 12000) {
            clearInterval(wait);
            state.nativeLastError = 'Native loader ended without a running WoW.exe';
            log(state.nativeLastError);
            void stopGame();
          }
        }, 350);
        wait.unref();
      });
    } else {
      child.once('exit', code => {
        log('WoW exited, code=' + String(code));
        state.game = null;
        void stopGame();
      });
    }
    if (autoLogin && !native) {
      // The signed Windows helper waits until *this* WoW process has an active
      // window. It never receives credentials via command-line arguments.
      // If focus cannot be verified, WoW stays open for manual login.
      try {
        const loginStartedAt = Date.now();
        const login = startAutoLogin({
          pid: child.pid, exe: state.settings.wowPath,
          account, password,
        }, outcome => log('WoW auto-login result: ' + outcome +
          ' elapsedMs=' + String(Date.now() - loginStartedAt)));
        child.once('exit', () => {
          if (login.exitCode === null) login.kill();
        });
      } catch (error) {
        log('WoW auto-login unavailable: ' + error.name);
      }
    }
    if (closeOnPlay && !native) {
      // Close only the dedicated Edge/Chrome app window. The backend and game
      // relay must remain running while WoW is open.
      setTimeout(() => {
        try { closeAppWindow(root, ok => {
          if (!ok) log('Could not close launcher app window after WoW startup.');
        }); } catch (error) { log('App window close deferred: ' + error.name); }
      }, 350);
    }
    return { started: true, autoLoginRequested: autoLogin,
      nativeInstant: native, gameSessionPrepared: !!ticket.prepared,
      nativeHiddenUntilCharacterReady: false };
  } catch (error) {
    await stopGame();
    await diagnostics.flush();
    throw error;
  }
}
function fail(error) {
  log('Request failed: ' + error?.name);
  return { ok: false, error: error?.message || 'Operation failed.' };
}
async function operate(action, args) {
  state.lastUiSeen = Date.now();
  switch (action) {
    case 'state': {
      const saved = storedAccounts(root);
      let native = { installed: false };
      try {
        if (state.settings.wowPath)
          native = inspectNativeInstant(path.dirname(state.settings.wowPath), root);
      } catch (error) {
        native = { installed: false, error: error.message };
      }
      return { accounts: ACCOUNTS, settings: state.settings,
        gameRunning: gameRunning(),
        nativeInstant: { ...native, lastError: state.nativeLastError },
        preAuth: preflight.status(state.settings.username),
        savedAccounts: saved,
        preferences: Object.fromEntries(ACCOUNTS.map(account =>
          [account, accountPreferences(root, account, saved.includes(account))])),
        version: NEXT_VERSION };
    }
    case 'handshake':
      fs.mkdirSync(root, { recursive: true });
      fs.writeFileSync(path.join(root, 'startup-proof.json'),
        JSON.stringify({ pid: process.pid, browserLoadedUtc: new Date().toISOString() }));
      return { browserLoaded: true };
    case 'setAccount':
      addSetting('username', String(args.username || '').toUpperCase());
      prepareSavedAccount(true);
      return { settings: state.settings };
    case 'setPreferences': {
      const account = String(args.account || '').toUpperCase();
      const preferences = setAccountPreferences(root, account, args.values,
        storedAccounts(root).includes(account));
      if (account === state.settings.username) prepareSavedAccount(true);
      return { preferences };
    }
    case 'setClient':
      addSetting('wowPath', String(args.wowPath || ''));
      prepareSavedAccount(true);
      return { settings: state.settings };
    case 'installNativeInstant':
      return installNativeInstant(verifyPath(), root, { gameRunning });
    case 'uninstallNativeInstant':
      return uninstallNativeInstant(verifyPath(), root, { gameRunning });
    case 'loginStatus':
      if (!preflight.status(state.settings.username).verified &&
          preflight.status(state.settings.username).status !== 'verifying' &&
          Date.now() - (state.lastPrepareAttempt || 0) > 10000)
        prepareSavedAccount();
      return { ...preflight.status(state.settings.username),
        nativeError: state.nativeLastError };
    case 'refreshManifest': {
      const data = await refreshCrewEndpoint();
      prepareSavedAccount();
      return { version: data.launcherVersion, updatesPaused: !!data.updatesPaused,
        crewApiUrl: state.settings.crewApiUrl };
    }
    case 'updateStatus': {
      const url = 'https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/next/update.json';
      const response = await fetch(url, { cache: 'no-store', signal: AbortSignal.timeout(10000) });
      if (!response.ok) throw new Error('GitHub launcher update metadata unavailable.');
      const contents = await response.text();
      if (contents.length > 8192) throw new Error('Unexpected update metadata size.');
      const release = JSON.parse(contents);
      if (!/^\d+\.\d+\.\d+$/.test(release.version || ''))
        throw new Error('Invalid launcher update version.');
      return { current: NEXT_VERSION, latest: release.version,
        available: release.version !== NEXT_VERSION };
    }
    case 'restartLauncher': {
      if (gameRunning()) throw new Error('Close WoW before restarting the launcher.');
      const script = path.join(root, 'start-hidden.vbs');
      if (!fs.existsSync(script)) throw new Error('Hidden launcher is not installed yet.');
      state.shuttingDown = true;
      preflight.invalidate();
      await stopGame();
      await diagnostics.flush();
      // Re-launch through the permanent Windows host; bootstrap performs the
      // verified download and rollback after this backend has exited.
      fs.writeFileSync(path.join(root, 'restart-pending.json'),
        JSON.stringify({ pid: process.pid, utc: new Date().toISOString() }));
      try { fs.unlinkSync(path.join(root, 'session.json')); } catch { }
      const child = spawn('wscript.exe', ['//B', '//Nologo', script],
        { cwd: root, detached: true, stdio: 'ignore', windowsHide: true });
      child.unref();
      setTimeout(() => process.exit(0), 850);
      return { restarting: true };
    }
    case 'status':
      return await crewRequest(state.settings.crewApiUrl, '/v1/health');
    case 'presence':
      return { online: await crewPresence(state.settings.crewApiUrl) };
    case 'play': {
      if (state.launching) throw new Error('WoW is already starting.');
      state.launching = true;
      try {
      const account = String(args.username || state.settings.username).toUpperCase();
      // Existing saved passwords can be used only for the selected account.
      let password = String(args.password || '');
      if (!password && account === state.settings.username &&
          args.useSaved === true)
        password = preflight.savedPassword(account, state.settings.crewApiUrl) || readCredential(root, account);
      const prefs = setAccountPreferences(root, account, {
        remember: args.remember === true,
        useSaved: args.useSaved === true,
        autoLogin: args.autoLogin !== false,
        closeOnPlay: args.closeOnPlay !== false,
      }, storedAccounts(root).includes(account));
      return await play(account, password, prefs.remember, prefs.closeOnPlay,
        prefs.autoLogin);
      } finally { state.launching = false; }
    }
    case 'changePassword': {
      const account = state.settings.username;
      if (!ACCOUNTS.includes(account)) throw new Error('Select an account.');
      await changePassword(state.settings.crewApiUrl, account,
        String(args.current || ''), String(args.desired || ''));
      saveCredential(root, account, String(args.desired));
      setAccountPreferences(root, account, { remember: true, useSaved: true }, true);
      prepareSavedAccount(true);
      return { changed: true };
    }
    case 'installed':
      return { installed: installedAddons(verifyPath()) };
    case 'catalog':
      return loadCatalog({ force: args.force === true, root, legacy: previous });
    case 'addonDetails':
      return addonDetails(String(args.url || ''));
    case 'githubSearch':
      return { items: await searchGitHub(String(args.query || '')) };
    case 'scanClients':
      return { clients: clientLocations() };
    case 'installRepository': {
      if (gameRunning()) throw new Error('Close WoW before installing an addon.');
      return installFromGitHub(String(args.url || ''), verifyPath(), {
        isGameRunning: gameRunning,
      });
    }
    case 'missing':
      return { missing: missingDependencies(verifyPath()) };
    case 'previewImport':
      return importPlan(String(args.source || ''), verifyPath());
    case 'import': {
      if (gameRunning()) throw new Error('Close WoW before importing addons.');
      const summary = importAddons(String(args.source || ''), verifyPath(), {
        isGameRunning: gameRunning,
      });
      return summary;
    }
    case 'repair': {
      if (gameRunning()) throw new Error('Close WoW before repairing addons.');
      return repairAddons(verifyPath(), { isGameRunning: gameRunning });
    }
    default:
      throw new Error('Unknown launcher operation.');
  }
}
function reply(response, status, obj) {
  const bytes = Buffer.from(JSON.stringify(obj));
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': bytes.length,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy': "default-src 'none'",
  });
  response.end(bytes);
}
export async function createServer() {
  const server = http.createServer(async (request, response) => {
    try {
      if (request.headers.host !== '127.0.0.1:' + server.address().port)
        return reply(response, 403, { ok: false, error: 'Invalid local hostname.' });
      const target = new URL(request.url, 'http://127.0.0.1/');
      if (request.method === 'POST' && target.pathname === '/api') {
        if (request.headers['x-crew-token'] !== secret ||
            request.headers.origin !== 'http://127.0.0.1:' + server.address().port ||
            !String(request.headers['content-type'] || '').startsWith('application/json')) {
          return reply(response, 403, { ok: false, error: 'Unauthorized browser request.' });
        }
        const chunks = [];
        let bytes = 0;
        for await (const chunk of request) {
          bytes += chunk.length;
          if (bytes > 128 * 1024) return reply(response, 413, { ok: false, error: 'Request too large.' });
          chunks.push(chunk);
        }
        const payload = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        const result = await operate(payload.action, payload.args || {});
        return reply(response, 200, { ok: true, result });
      }
      if (request.method === 'GET' && target.pathname === '/addon-image' &&
          target.searchParams.get('key') === secret) {
        const media = await imageData(target.searchParams.get('url') || '');
        response.writeHead(200, {
          'Content-Type': media.mime, 'Content-Length': media.bytes.length,
          'Cache-Control': 'private, max-age=600', 'X-Content-Type-Options': 'nosniff',
          'Referrer-Policy': 'no-referrer',
        });
        return response.end(media.bytes);
      }
      if (request.method === 'GET' && FILES.has(target.pathname) &&
          (target.pathname !== '/' || target.searchParams.get('key') === secret)) {
        const [file, type] = FILES.get(target.pathname);
        const contents = fs.readFileSync(path.join(APP, 'public', file));
        response.writeHead(200, {
          'Content-Type': type, 'Content-Length': contents.length, 'Cache-Control': 'no-store',
          'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data: https://github.com https://*.githubusercontent.com; connect-src 'self'",
          'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff',
        });
        return response.end(contents);
      }
      if (request.method === 'GET' && target.pathname === '/favicon.ico') {
          const contents = launcherIconBytes();
          response.writeHead(200, {
            'Content-Type': 'image/x-icon', 'Content-Length': contents.length,
            'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
          });
          return response.end(contents);
      }
      return reply(response, 404, { ok: false, error: 'Not found.' });
    } catch (error) {
      const result = fail(error);
      return reply(response, 400, result);
    }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  return { server, url: 'http://127.0.0.1:' + server.address().port + '/?key=' + secret };
}
async function main() {
  if (process.platform !== 'win32' && !process.argv.includes('--test-server'))
    throw new Error('The game launcher currently requires Windows.');
  const { server, url } = await createServer();
  if (process.argv.includes('--health-probe')) {
    try {
      const page = await fetch(url);
      if (page.status !== 200 || !(await page.text()).includes('Tortoise Crew')) {
        throw new Error('Local web UI did not respond.');
      }
      const probe = await fetch(new URL('/api', url), {
        method: 'POST',
        headers: { Origin: new URL(url).origin,
          'Content-Type': 'application/json',
          'X-Crew-Token': new URL(url).searchParams.get('key') },
        body: JSON.stringify({ action: 'state', args: {} }),
      });
      const data = await probe.json();
      if (!probe.ok || !data.ok) throw new Error('Local backend probe failed.');
      console.log('CREW_NEXT_PROBE_OK');
    } finally {
      await new Promise(resolve => server.close(resolve));
    }
    return;
  }
  try {
    const icon = materializeLauncherIcon(APP);
    const marker = path.join(root, 'launcher-icon.json');
    if (path.relative(root, APP).toLowerCase() === 'app' &&
        fs.existsSync(path.join(root, 'bootstrap.mjs')) && readJson(marker, {}).sha256 !== ICON_SHA256) {
      installHiddenShortcuts({ root, app: APP, icon });
      writeJsonAtomic(marker, { sha256: ICON_SHA256, installedUtc: new Date().toISOString() });
    }
  } catch (error) { log('Launcher icon refresh unavailable: ' + error.name); }
  log('Crew Next ' + NEXT_VERSION + ' started on loopback.');
  fs.writeFileSync(path.join(root, 'session.json'),
    JSON.stringify({ pid: process.pid, url, utc: new Date().toISOString() }),
    { mode: 0o600 });
  // Open an Edge/Chrome app window, never the default browser or a normal tab.
  // The existing desktop shortcut can continue to launch this Node entrypoint.
  if (!process.argv.includes('--no-browser')) {
    const browser = await openDesktopApp(url, root);
    log('Launched dedicated ' + browser + ' app window.');
  }
  // Start verifying the saved account only after the UI can connect.
  // No WoW.exe process is created until the user explicitly presses Play.
  setTimeout(() => {
    void refreshCrewEndpoint()
      .catch(error => log('Crew settings refresh unavailable: ' + error.message))
      .finally(() => prepareSavedAccount());
  }, 200).unref();
  const refresh = setInterval(() => {
    if (Date.now() - (state.lastUiSeen || 0) > 15000) {
      preflight.invalidate();
      return;
    }
    if (state.shuttingDown || gameRunning() ||
        preflight.status(state.settings.username).status === 'verifying') return;
    if (!preflight.status(state.settings.username).verified) prepareSavedAccount();
  }, 15000);
  refresh.unref();
  console.log('Tortoise Crew Next listening on localhost.');
  const shutdown = async () => {
    if (state.shuttingDown) return;
    state.shuttingDown = true;
    preflight.invalidate();
    try {
      const session = readJson(path.join(root, 'session.json'), {});
      if (session.pid === process.pid) fs.unlinkSync(path.join(root, 'session.json'));
    } catch { /* Stale session records are ignored by bootstrap. */ }
    server.close();
    await stopGame();
    if (!gameRunning()) process.exit(0);
  };
  process.on('SIGTERM', () => { void shutdown(); });
  process.on('SIGINT', () => { void shutdown(); });
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url))
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
