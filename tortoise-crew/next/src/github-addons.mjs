import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { gitHubRepo } from './catalog.mjs';
import { safeName, importPlan, importAddons } from './addons.mjs';
import { unpackZip } from './safe-zip.mjs';

const FILE_TYPES = new Set(['.toc', '.lua', '.xml', '.tga', '.blp', '.dds',
  '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ttf', '.otf', '.wav', '.ogg',
  '.txt', '.md', '.ini', '.json', '.mp3']);

async function fetchLimited(url, limit, options = {}) {
  const response = await fetch(url, {
    headers: { 'User-Agent': 'TortoiseCrewAddonHub/1.1',
      Accept: 'application/vnd.github+json' },
    signal: AbortSignal.timeout(30000), redirect: 'follow',
  });
  const remote = new URL(response.url);
  if (remote.protocol !== 'https:' ||
      !['github.com', 'api.github.com', 'codeload.github.com'].includes(remote.hostname))
    throw new Error('Addon redirect was not an approved GitHub download.');
  if (!response.ok) throw new Error('GitHub download failed (HTTP ' + response.status + ').');
  if (Number(response.headers.get('content-length') || 0) > limit)
    throw new Error('GitHub addon exceeds the download limit.');
  const chunks = [];
  let size = 0;
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > limit) throw new Error('GitHub addon exceeds the download limit.');
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

export function collectAddonFolders(root, maxDepth = 7) {
  const results = [];
  const stack = [{ dir: path.resolve(root), depth: 0 }];
  let visited = 0;
  while (stack.length) {
    const { dir, depth } = stack.pop();
    if (++visited > 2500) throw new Error('Repository contains too many directories.');
    if (depth > maxDepth) continue;
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    const toc = entries.filter(x => x.isFile() && x.name.toLowerCase().endsWith('.toc'));
    if (toc.length) {
      // A repository subdirectory containing a TOC is one addon; avoid
      // copying nested packages a second time.
      results.push(dir);
      continue;
    }
    for (const item of entries) {
      if (!item.isDirectory() || item.isSymbolicLink() || !safeName(item.name) ||
          item.name.startsWith('.')) continue;
      stack.push({ dir: path.join(dir, item.name), depth: depth + 1 });
    }
  }
  return results;
}

export async function installFromGitHub(url, game, {
  isGameRunning, download = fetchLimited,
} = {}) {
  if (isGameRunning?.()) throw new Error('Close WoW before installing addons.');
  const repo = gitHubRepo(url);
  if (!repo) throw new Error('Select a supported GitHub repository URL.');
  const api = 'https://api.github.com/repos/' + encodeURIComponent(repo.owner) +
    '/' + encodeURIComponent(repo.repo);
  const metadata = JSON.parse((await download(api, 1024 * 1024)).toString('utf8'));
  const branch = String(metadata.default_branch || '');
  if (!branch || branch.length > 200) throw new Error('GitHub repository has no valid branch.');
  const zipUrl = api + '/zipball/' + encodeURIComponent(branch);
  const archive = await download(zipUrl, 65 * 1024 * 1024);
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'crew-github-addon-'));
  try {
    const expanded = path.join(temp, 'expanded'), flat = path.join(temp, 'addons');
    fs.mkdirSync(expanded);
    fs.mkdirSync(flat);
    unpackZip(archive, expanded, { extensions: FILE_TYPES });
    const folders = collectAddonFolders(expanded);
    const names = new Set();
    for (const folder of folders) {
      if (isGameRunning?.()) throw new Error('Close WoW before changing addons.');
      const tocs = fs.readdirSync(folder).filter(x => x.toLowerCase().endsWith('.toc'));
      if (tocs.length !== 1) continue; // Skip ambiguous addon folders.
      const name = path.basename(tocs[0], '.toc');
      if (!safeName(name) || names.has(name.toLowerCase()) ||
          /^blizzard[_-]|^turtle[_-]/i.test(name)) continue;
      names.add(name.toLowerCase());
      fs.cpSync(folder, path.join(flat, name), {
        recursive: true, force: false, errorOnExist: true, dereference: false,
      });
    }
    if (!names.size) throw new Error('No supported Vanilla/Turtle .toc addons found in this repository.');
    const plan = importPlan(flat, game);
    if (plan.planned.length === 0) throw new Error('No compatible addons found: ' +
      plan.warnings.join('; ').slice(0, 250));
    const result = importAddons(flat, game, { isGameRunning });
    return { ...result, repo: repo.url, selected: names.size };
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}
