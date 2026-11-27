import fs from 'node:fs';
import path from 'node:path';
import { dataDir, legacyDir } from './config.mjs';
import { featuredAddon } from './managed-addons.mjs';
import { readTocMetadata } from './addons.mjs';

const REGISTRY = 'https://raw.githubusercontent.com/bnema/turtlectl/main/data/addons.json';
const MAX_REGISTRY_BYTES = 16 * 1024 * 1024;
const CREW_ADDONS = [{ name: 'TortoiseBotsManager', author: 'Sagiroth',
  url: 'https://github.com/Sagiroth/TortoiseBotsManager',
  description: 'In-game TortoiseBots control panel (/tbm) for Tortoise WoW 1.18.1. Requires the server-side TortoiseBots module. Install as Interface/AddOns/TortoiseBotsManager.',
}];

export function withCrewAddons(items) {
  const curated = CREW_ADDONS.map(row => normalizeEntry(row, 'Tortoise Crew'));
  const urls = new Set(curated.map(row => row.url.toLowerCase().replace(/\/$/, '')));
  const managed = featuredAddon();
  return [...curated, managed, ...items.filter(row =>
    row.name !== managed.name && !urls.has(row.url.toLowerCase().replace(/\/$/, '')))];
}

function clipped(value, length = 500) {
  return typeof value === 'string' ? value.slice(0, length) : '';
}

// A source must explicitly publish a release version. GitHub stars, commit
// timestamps and WoW Interface numbers cannot serve as version substitutes.
export function publishedAddonVersion(value) {
  const version = clipped(value, 48).trim();
  return /^(?:v?\d+(?:\.\d+){1,5}(?:[-+][A-Za-z0-9._-]+)?|r\d+)$/i.test(version) ?
    version : '';
}

export function gitHubRepo(url) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || parsed.hostname !== 'github.com' ||
        parsed.username || parsed.password || parsed.port || parsed.search || parsed.hash)
      return null;
    const matches = parsed.pathname.match(/^\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+?)(?:\.git)?\/?$/);
    if (!matches || ['.', '..'].includes(matches[1]) || ['.', '..'].includes(matches[2]))
      return null;
    return { owner: matches[1], repo: matches[2], url: 'https://github.com/' +
      matches[1] + '/' + matches[2] };
  } catch { return null; }
}

export function normalizeEntry(row, source = 'Turtle WoW catalog') {
  if (!row || typeof row !== 'object' || Array.isArray(row)) return null;
  const name = clipped(row.name, 120).trim();
  const rawUrl = clipped(row.url || row.html_url, 500);
  let url = '';
  try {
    const parsed = new URL(rawUrl);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password ||
        !['github.com', 'gitlab.com', 'turtle-wow.fandom.com', 'turtle-wow.org'].includes(parsed.hostname))
      return null;
    url = parsed.href;
  } catch { return null; }
  if (!name) return null;
  const repo = gitHubRepo(url);
  const stars = Number(row.stars ?? row.stargazers_count);
  const downloads = row.downloads === null || row.downloads === undefined ? null :
    Number(row.downloads);
  const updated = clipped(row.last_commit || row.pushed_at, 50);
  const latestVersion = publishedAddonVersion(row.latest_version || row.latestVersion ||
    row.release?.tag_name || row.version);
  return {
    name,
    description: clipped(row.description || 'Community addon for Vanilla / Turtle WoW.', 550),
    author: clipped(row.author || row.full_name, 160),
    url,
    source,
    stars: Number.isFinite(stars) && stars >= 0 ? Math.floor(stars) : 0,
    downloads: Number.isFinite(downloads) && downloads >= 0 ? Math.floor(downloads) : null,
    updated: Number.isFinite(Date.parse(updated)) ? updated : '',
    latestVersion,
    icon: repo ? 'https://github.com/' + repo.owner + '.png?size=96' : '',
    installable: Boolean(repo),
  };
}

export function parseRegistry(raw) {
  if (raw.length > MAX_REGISTRY_BYTES) throw new Error('Turtle addon registry is oversized.');
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed.addons)) throw new Error('Invalid Turtle addon registry.');
  return parsed.addons.map(x => normalizeEntry(x)).filter(Boolean)
    .sort((a, b) => b.stars - a.stars || a.name.localeCompare(b.name));
}

async function fetchTextLimited(url, maxBytes, timeout = 16000) {
  const response = await fetch(url, {
    headers: { 'User-Agent': 'TortoiseCrewAddonHub/1.1',
      Accept: 'application/vnd.github+json' },
    signal: AbortSignal.timeout(timeout), cache: 'no-store',
  });
  if (!response.ok) throw new Error('Addon source unavailable (HTTP ' + response.status + ').');
  if (Number(response.headers.get('content-length') || 0) > maxBytes)
    throw new Error('Addon source is too large.');
  const chunks = [];
  let bytes = 0;
  for await (const piece of response.body) {
    bytes += piece.byteLength;
    if (bytes > maxBytes) throw new Error('Addon source is too large.');
    chunks.push(Buffer.from(piece));
  }
  return Buffer.concat(chunks).toString('utf8');
}

// The repository installer downloads the default branch. Read the version
// from that same branch's Classic TOC, since catalog rows often omit it.
export async function repositoryAddonVersion(url, name, fetchText = fetchTextLimited) {
  const repo = gitHubRepo(url);
  if (!repo) return null;
  const names = [...new Set([repo.repo, name])].filter(entry =>
    typeof entry === 'string' && /^[A-Za-z0-9_!. -]{1,100}$/.test(entry));
  const root = 'https://raw.githubusercontent.com/' + encodeURIComponent(repo.owner) +
    '/' + encodeURIComponent(repo.repo) + '/HEAD/';
  for (const toc of names) {
    try {
      const metadata = readTocMetadata(await fetchText(root + encodeURIComponent(toc + '.toc'), 64 * 1024, 5000));
      if (metadata.interfaceVersion && !/^(11\d\d\d|12\d\d\d)$/.test(metadata.interfaceVersion)) continue;
      if (metadata.version || metadata.development)
        return { version: metadata.version, development: metadata.development };
    } catch { /* Optional metadata may be missing or temporarily unavailable. */ }
  }
  try {
    await fetchText('https://api.github.com/repos/' + encodeURIComponent(repo.owner) +
      '/' + encodeURIComponent(repo.repo), 128 * 1024, 5000);
  } catch (error) {
    if (/\(HTTP 404\)/.test(error.message)) return { unavailable: true };
  }
  return null;
}

export async function loadCatalog({ force = false, root = dataDir(),
  legacy = legacyDir(), fetchText = fetchTextLimited } = {}) {
  const currentCache = path.join(root, 'addon-registry.json');
  const oldCache = path.join(legacy, 'addon-registry.json');
  if (!force && fs.existsSync(currentCache) &&
      Date.now() - fs.statSync(currentCache).mtimeMs < 24 * 3600 * 1000)
    return { items: withCrewAddons(parseRegistry(fs.readFileSync(currentCache, 'utf8'))), cached: true };
  try {
    const contents = await fetchText(REGISTRY, MAX_REGISTRY_BYTES);
    const items = parseRegistry(contents);
    fs.mkdirSync(root, { recursive: true });
    fs.writeFileSync(currentCache + '.new', contents, { mode: 0o600 });
    fs.renameSync(currentCache + '.new', currentCache);
    return { items: withCrewAddons(items), cached: false };
  } catch (error) {
    for (const old of [currentCache, oldCache]) {
      if (!fs.existsSync(old)) continue;
      try { return { items: withCrewAddons(parseRegistry(fs.readFileSync(old, 'utf8'))),
        cached: true, warning: 'Offline: showing the most recent saved catalog.' }; }
      catch { /* Continue to the other saved registry. */ }
    }
    return { items: withCrewAddons([]), cached: true,
      warning: 'Offline: showing bundled Tortoise Crew addons. Refresh to load the community catalog.' };
  }
}

export async function searchGitHub(query, fetchText = fetchTextLimited) {
  const term = String(query || '').trim();
  if (!term || term.length > 100) throw new Error('Enter an addon search phrase.');
  const url = 'https://api.github.com/search/repositories?per_page=40&sort=stars&q=' +
    encodeURIComponent(term + ' turtle wow addon');
  const data = JSON.parse(await fetchText(url, 4 * 1024 * 1024));
  if (!Array.isArray(data.items)) throw new Error('GitHub addon search returned invalid results.');
  return data.items.map(x => normalizeEntry(x, 'GitHub search (compatibility unverified)'))
    .filter(Boolean);
}

export function clientLocations({ home = process.env.USERPROFILE || '',
  drives = ['C:\\', 'D:\\', 'E:\\'] } = {}) {
  const known = ['OctoWoW', 'client-octo', 'client-turtle', 'Turtle WoW',
    'Tortoise WoW', 'WoW', 'World of Warcraft', 'Games\\OctoWoW',
    'Games\\Turtle WoW', 'Downloads\\OctoWoW'];
  const result = [];
  for (const dir of [home, path.join(home, 'Desktop'), path.join(home, 'Downloads'),
    ...drives]) {
    for (const name of known) {
      const target = path.join(dir, name);
      if (result.length >= 25) return result;
      try {
        if (fs.statSync(path.join(target, 'Interface', 'AddOns')).isDirectory() &&
            !fs.lstatSync(target).isSymbolicLink()) result.push(target);
      } catch { /* Typical candidate path is absent. */ }
    }
  }
  return [...new Set(result)];
}
