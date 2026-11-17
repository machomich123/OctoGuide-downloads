import fs from 'node:fs';
import path from 'node:path';
import { nativeShortcut, migrationPaths } from './migrate.mjs';

const wscript = path.join(process.env.WINDIR || 'C:\\Windows', 'System32', 'wscript.exe');

export function hiddenScript(node, entry) {
  for (const value of [node, entry]) {
    if (!path.isAbsolute(value) || value.includes('"') || value.includes('\r') ||
        value.includes('\n')) throw new Error('Invalid launcher path.');
  }
  // WScript is a standard, Microsoft-signed Windows component and starts
  // Node invisibly. It does not change any Windows application-control rule.
  const command = '"' + node + '" "' + entry + '"';
  return 'Option Explicit\r\n' +
    'Dim shell : Set shell = CreateObject("WScript.Shell")\r\n' +
    'shell.CurrentDirectory = "' + path.dirname(entry).replace(/"/g, '""') + '"\r\n' +
    'shell.Run "' + command.replace(/"/g, '""') + '", 0, False\r\n';
}

export function installHiddenShortcuts({
  root = migrationPaths().root, app = path.join(root, 'app'),
  node = process.execPath, shortcuts = migrationPaths(),
} = {}) {
  if (process.platform !== 'win32') throw new Error('Hidden launcher requires Windows.');
  if (!fs.existsSync(wscript)) throw new Error('Microsoft Windows Script Host is unavailable.');
  const launcher = path.join(root, 'bootstrap.mjs');
  if (!fs.existsSync(launcher)) throw new Error('Launcher bootstrap is not installed.');
  const script = path.join(root, 'start-hidden.vbs');
  fs.writeFileSync(script + '.new', hiddenScript(node, launcher), { mode: 0o600 });
  fs.renameSync(script + '.new', script);
  const originals = [];
  const targets = [shortcuts.desktop, shortcuts.start];
  try {
    for (const shortcut of targets) {
      fs.mkdirSync(path.dirname(shortcut), { recursive: true });
      const backup = shortcut + '.before-hidden-launch.lnk';
      if (fs.existsSync(shortcut)) {
        if (!fs.existsSync(backup)) fs.copyFileSync(shortcut, backup);
        originals.push({ shortcut, backup });
      } else {
        originals.push({ shortcut, backup: null });
      }
      nativeShortcut(shortcut, wscript, script, app, path.join(app, 'crew.ico'));
    }
    return { desktop: shortcuts.desktop, start: shortcuts.start,
      shellHost: wscript, script };
  } catch (error) {
    for (const { shortcut, backup } of originals.reverse()) {
      if (backup) fs.copyFileSync(backup, shortcut);
      else if (fs.existsSync(shortcut)) fs.unlinkSync(shortcut);
    }
    throw error;
  }
}
