import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const MAX_FILES = 6000;
const MAX_BYTES = 450 * 1024 * 1024;
const RESERVED = /^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)/i;

export function safeName(name) {
  return typeof name === 'string' && name.length > 0 && name.length <= 100 &&
    !/[/\\<>:"|?*\x00-\x1f]/.test(name) &&
    !name.endsWith(' ') && !name.endsWith('.') && name !== '.' &&
    name !== '..' && !RESERVED.test(name);
}

function assertPlainDirectory(dir) {
  const abs = path.resolve(dir);
  for (let current = abs; current !== path.dirname(current); current = path.dirname(current)) {
    if (fs.lstatSync(current).isSymbolicLink()) throw new Error('Linked folders are not supported: ' + current);
  }
  if (!fs.statSync(abs).isDirectory()) throw new Error('Not a directory: ' + abs);
  return abs;
}

function isProtected(name) {
  return /^blizzard[_-]|^turtle[_-]/i.test(name);
}

function tocMetadata(file) {
  const contents = fs.readFileSync(file, 'utf8');
  const version = contents.match(/^##\s*Interface\s*:\s*(\d+)/im)?.[1] || '';
  const required = [...contents.matchAll(/^##\s*(?:Dependencies|RequiredDeps)\s*:\s*(.+)$/gim)]
    .flatMap(([, text]) => text.split(',').map(x => x.trim()).filter(Boolean));
  return { version, required };
}

function selectToc(dir) {
  const files = fs.readdirSync(dir, { withFileTypes: true })
    .filter(x => x.isFile() && x.name.toLowerCase().endsWith('.toc') && safeName(x.name))
    .map(x => path.join(dir, x.name));
  const valid = files.map(file => ({ file, ...tocMetadata(file) }))
    .filter(x => !x.version || /^(11\d\d\d|12\d\d\d)$/.test(x.version));
  if (valid.length === 1) return valid[0];
  if (valid.length > 1) {
    const exact = valid.filter(x => path.basename(x.file, '.toc').toLowerCase() === path.basename(dir).toLowerCase());
    if (exact.length === 1) return exact[0];
  }
  if (valid.length === 0) throw new Error('No compatible Vanilla/Turtle TOC found in ' + path.basename(dir));
  throw new Error('Ambiguous addon manifests in ' + path.basename(dir));
}

function addonDir(root) {
  const resolved = path.resolve(root);
  for (const candidate of [path.join(resolved, 'Interface', 'AddOns'), resolved]) {
    if (!fs.existsSync(candidate)) continue;
    const dir = assertPlainDirectory(candidate);
    if (path.basename(dir).toLowerCase() === 'addons') return dir;
  }
  throw new Error('Select a WoW game folder or Interface/AddOns folder.');
}

export function installedAddons(game) {
  const root = addonDir(game);
  return fs.readdirSync(root, { withFileTypes: true }).filter(x => x.isDirectory() &&
    safeName(x.name) && !x.name.startsWith('.')).map(x => {
    const full = path.join(root, x.name);
    if (fs.lstatSync(full).isSymbolicLink()) return { name: x.name, skipped: 'linked folder' };
    try {
      const toc = selectToc(full);
      return { name: x.name, manifest: path.basename(toc.file),
        version: toc.version, dependencies: toc.required };
    } catch (e) {
      return { name: x.name, skipped: e.message };
    }
  });
}

function scanTree(dir, totals) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (!safeName(entry.name) || entry.isSymbolicLink()) throw new Error('Unsafe addon entry: ' + entry.name);
    const current = path.join(dir, entry.name);
    if (entry.isDirectory()) scanTree(current, totals);
    else if (entry.isFile()) {
      totals.files++;
      totals.bytes += fs.statSync(current).size;
      if (totals.files > MAX_FILES || totals.bytes > MAX_BYTES) throw new Error('Addon import exceeds safety limits.');
    } else throw new Error('Unexpected file type in addon: ' + entry.name);
  }
}

function newBackup(game, prefix) {
  const root = path.join(path.resolve(game), 'WTF');
  if (!fs.existsSync(root)) throw new Error('Game WTF folder is missing. No files were changed.');
  assertPlainDirectory(root);
  const location = path.join(root, prefix + '-' + crypto.randomUUID());
  fs.mkdirSync(location, { recursive: false });
  return location;
}

function checkGameIdle(isGameRunning) {
  if (isGameRunning?.()) throw new Error('Close WoW before changing addons.');
}

export function importPlan(source, game) {
  const src = addonDir(source);
  const dst = addonDir(game);
  if (src.toLowerCase() === dst.toLowerCase() ||
      src.toLowerCase().startsWith(dst.toLowerCase() + path.sep) ||
      dst.toLowerCase().startsWith(src.toLowerCase() + path.sep)) {
    throw new Error('Cannot import a client into itself.');
  }
  const installed = new Set(fs.readdirSync(dst).map(x => x.toLowerCase()));
  const planned = [];
  const warnings = [];
  const totals = { files: 0, bytes: 0 };
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    if (!entry.isDirectory() || !safeName(entry.name) || entry.name.startsWith('.')) continue;
    if (isProtected(entry.name)) { warnings.push('Built-in addon skipped: ' + entry.name); continue; }
    const location = path.join(src, entry.name);
    if (fs.lstatSync(location).isSymbolicLink()) { warnings.push('Linked folder skipped: ' + entry.name); continue; }
    let toc;
    try { toc = selectToc(location); }
    catch (e) { warnings.push(e.message); continue; }
    const canonical = path.basename(toc.file, '.toc');
    if (!safeName(canonical) || isProtected(canonical)) {
      warnings.push('Unsafe/protected addon skipped: ' + canonical); continue;
    }
    const destEntry = fs.readdirSync(dst).find(x => x.toLowerCase() === canonical.toLowerCase());
    if (planned.some(x => x.name.toLowerCase() === canonical.toLowerCase())) {
      warnings.push('Ambiguous duplicate addon skipped: ' + canonical); continue;
    }
    if (destEntry && (fs.lstatSync(path.join(dst, destEntry)).isSymbolicLink() ||
                      !fs.statSync(path.join(dst, destEntry)).isDirectory() || isProtected(destEntry))) {
      warnings.push('Conflicting protected target skipped: ' + canonical); continue;
    }
    scanTree(location, totals);
    planned.push({ name: canonical, from: location, to: path.join(dst, destEntry || canonical),
      exists: installed.has(canonical.toLowerCase()), dependencies: toc.required });
    if (planned.length > 1000) throw new Error('Too many addons in one import.');
  }
  return { planned, warnings, files: totals.files, bytes: totals.bytes, target: dst };
}

export function missingDependencies(game) {
  const entries = installedAddons(game);
  const names = new Set(entries.filter(x => !x.skipped).map(x => x.name.toLowerCase()));
  return entries.flatMap(x => (x.dependencies || []).filter(dep => !names.has(dep.toLowerCase()))
    .map(dep => ({ addon: x.name, dependency: dep })));
}

export function importAddons(source, game, { isGameRunning } = {}) {
  checkGameIdle(isGameRunning);
  const plan = importPlan(source, game);
  if (plan.planned.length === 0) return { imported: 0, backup: null, warnings: plan.warnings };
  const backup = newBackup(game, 'CrewNextImport');
  const staging = path.join(plan.target, '.crew-next-' + crypto.randomUUID());
  const applied = [];
  fs.mkdirSync(staging);
  try {
    for (const item of plan.planned) {
      checkGameIdle(isGameRunning);
      const prepared = path.join(staging, item.name);
      // Copy only addon UI files; never activate binary client patches or helper programs.
      const blocked = new Set(['.exe', '.dll', '.asi', '.mpq', '.bat', '.cmd',
        '.ps1', '.vbs', '.js', '.msi', '.com', '.scr']);
      fs.cpSync(item.from, prepared, {
        recursive: true, force: false, errorOnExist: true, dereference: false,
        filter: source => {
          if (path.basename(source).toLowerCase() === '.git') return false;
          if (fs.lstatSync(source).isSymbolicLink()) return false;
          return !blocked.has(path.extname(source).toLowerCase());
        },
      });
      scanTree(prepared, { files: 0, bytes: 0 });
    }
    for (const item of plan.planned) {
      checkGameIdle(isGameRunning);
      const original = item.to;
      const old = path.join(backup, item.name);
      const stage = path.join(staging, item.name);
      let movedOld = false;
      if (fs.existsSync(original)) {
        fs.renameSync(original, old);
        movedOld = true;
      }
      applied.push({ original, old, movedOld, stage });
      fs.renameSync(stage, original);
    }
    fs.writeFileSync(path.join(backup, 'import-summary.json'),
      JSON.stringify({ addons: plan.planned.map(x => x.name), warnings: plan.warnings }, null, 2));
    return { imported: plan.planned.length, backup, warnings: plan.warnings,
      missingDependencies: missingDependencies(game) };
  } catch (e) {
    for (const item of applied.reverse()) {
      if (fs.existsSync(item.original)) fs.rmSync(item.original, { recursive: true, force: false });
      if (item.movedOld && fs.existsSync(item.old)) fs.renameSync(item.old, item.original);
    }
    throw e;
  } finally {
    if (fs.existsSync(staging)) fs.rmSync(staging, { recursive: true, force: true });
  }
}

export function repairAddons(game, { isGameRunning } = {}) {
  checkGameIdle(isGameRunning);
  const root = addonDir(game);
  const config = path.join(path.resolve(game), 'WTF', 'Config.wtf');
  if (!fs.existsSync(config) || fs.lstatSync(config).isSymbolicLink()) {
    throw new Error('WTF/Config.wtf must be a regular file.');
  }
  const moves = [];
  const warnings = [];
  for (const item of installedAddons(game)) {
    if (!item.manifest || isProtected(item.name)) continue;
    const desired = path.basename(item.manifest, '.toc');
    if (desired.toLowerCase() === item.name.toLowerCase()) continue;
    if (!safeName(desired) || isProtected(desired)) continue;
    const original = path.join(root, item.name), target = path.join(root, desired);
    if (fs.existsSync(target) || moves.some(x => x.target.toLowerCase() === target.toLowerCase())) {
      warnings.push('Name conflict: ' + item.name + ' -> ' + desired); continue;
    }
    moves.push({ original, target });
  }
  const backup = newBackup(game, 'CrewNextRepair');
  fs.copyFileSync(config, path.join(backup, 'Config.wtf'));
  fs.writeFileSync(path.join(backup, 'renames.json'), JSON.stringify(moves, null, 2));
  const done = [];
  const stagedConfig = path.join(backup, 'Config.new');
  try {
    checkGameIdle(isGameRunning);
    for (const move of moves) {
      fs.renameSync(move.original, move.target);
      done.push(move);
    }
    const before = fs.readFileSync(config, 'utf8');
    const updated = before.replace(/^\s*SET\s+scriptMemory\s+[^\r\n]*(?:\r?\n|$)/gim, '')
      .replace(/[\r\n]+$/, '') + '\r\nSET scriptMemory "0"\r\n';
    fs.writeFileSync(stagedConfig, updated);
    fs.copyFileSync(stagedConfig, config);
  } catch (e) {
    fs.copyFileSync(path.join(backup, 'Config.wtf'), config);
    for (const move of done.reverse()) fs.renameSync(move.target, move.original);
    throw e;
  }
  return { renamed: moves.length, backup, warnings,
    missingDependencies: missingDependencies(game) };
}
