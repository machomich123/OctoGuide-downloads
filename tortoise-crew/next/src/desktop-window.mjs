import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';

// Chromium's app mode creates a dedicated window without tabs or an address bar.
// This is not a native Win32 UI; it uses the installed, Windows-managed browser.
// Never use the user's default-browser setting to choose the app host.
export function browserCandidates(env = process.env) {
  const pf86 = env['ProgramFiles(x86)'] || '';
  const pf = env.ProgramFiles || '';
  const local = env.LOCALAPPDATA || '';
  return [
    ['Microsoft Edge', path.join(pf86, 'Microsoft', 'Edge', 'Application', 'msedge.exe')],
    ['Microsoft Edge', path.join(pf, 'Microsoft', 'Edge', 'Application', 'msedge.exe')],
    ['Microsoft Edge', path.join(local, 'Microsoft', 'Edge', 'Application', 'msedge.exe')],
    ['Google Chrome', path.join(pf, 'Google', 'Chrome', 'Application', 'chrome.exe')],
    ['Google Chrome', path.join(pf86, 'Google', 'Chrome', 'Application', 'chrome.exe')],
    ['Google Chrome', path.join(local, 'Google', 'Chrome', 'Application', 'chrome.exe')],
  ].filter(([, exe]) => path.isAbsolute(exe));
}

export function selectAppBrowser(env = process.env, exists = fs.existsSync) {
  for (const [name, exe] of browserCandidates(env)) {
    if (exists(exe)) return { name, exe };
  }
  throw new Error(
    'Tortoise Crew needs Microsoft Edge or Google Chrome to open its dedicated app window. ' +
    'Install Edge and try the desktop shortcut again.'
  );
}

export function desktopAppArguments(url, dataRoot) {
  const parsed = new URL(url);
  if (parsed.protocol !== 'http:' || parsed.hostname !== '127.0.0.1' ||
      !/^\d+$/.test(parsed.port) || parsed.pathname !== '/' ||
      !/^[a-f0-9]{64}$/.test(parsed.searchParams.get('key') || '') ||
      !path.isAbsolute(dataRoot)) {
    throw new Error('Refusing to open an unexpected desktop app URL.');
  }
  // An isolated profile keeps the app independent of the default browser and
  // avoids modifying the user's normal Edge/Chrome profile or open tabs.
  return [
    '--app=' + url,
    '--user-data-dir=' + path.join(dataRoot, 'desktop-window-profile'),
    '--no-first-run',
    '--no-default-browser-check',
    '--window-size=1100,760',
  ];
}

export async function openDesktopApp(url, dataRoot, env = process.env) {
  const browser = selectAppBrowser(env);
  const args = desktopAppArguments(url, dataRoot);
  // A fixed profile is reused across launches. No web download or installation
  // of another executable is necessary, and no Windows security setting changes.
  fs.mkdirSync(path.join(dataRoot, 'desktop-window-profile'), { recursive: true });
  const child = spawn(browser.exe, args, {
    detached: true, stdio: 'ignore', windowsHide: false,
  });
  await new Promise((resolve, reject) => {
    child.once('spawn', resolve);
    child.once('error', reject);
  });
  child.unref();
  return browser.name;
}
