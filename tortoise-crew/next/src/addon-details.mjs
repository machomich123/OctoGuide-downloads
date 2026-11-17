import { gitHubRepo } from './catalog.mjs';

const GITHUB_API = 'https://api.github.com/repos/';
const MAX_README = 350 * 1024;
const MAX_IMAGE = 8 * 1024 * 1024;
const mediaCache = new Map();

export function allowedImageUrl(value) {
  try {
    const url = new URL(String(value));
    if (url.protocol !== 'https:' || url.username || url.password || url.port ||
        url.href.length > 1600 || url.hash ||
        !['github.com', 'raw.githubusercontent.com', 'user-images.githubusercontent.com',
          'avatars.githubusercontent.com', 'i.imgur.com'].some(host =>
            url.hostname === host) &&
        !url.hostname.endsWith('.githubusercontent.com')) return null;
    return url.href;
  } catch { return null; }
}

export function githubReadmeImages(markdown, repo, branch) {
  const base = 'https://raw.githubusercontent.com/' +
    encodeURIComponent(repo.owner) + '/' + encodeURIComponent(repo.repo) + '/' +
    branch.split('/').map(encodeURIComponent).join('/') + '/';
  const definitions = new Map();
  for (const [, id, url] of markdown.matchAll(/^\s*\[([^\]\r\n]+)\]:\s*<?([^\s>]+)>?/gm)) {
    definitions.set(id.toLowerCase(), url);
  }
  const candidates = [];
  for (const [, image] of markdown.matchAll(/!\[[^\]\r\n]*\]\(\s*<?([^\s)>]+)>?(?:\s+[^)]*)?\)/g))
    candidates.push(image);
  for (const [, id] of markdown.matchAll(/!\[[^\]]*\]\[([^\]]+)\]/g))
    if (definitions.has(id.toLowerCase())) candidates.push(definitions.get(id.toLowerCase()));
  for (const [, , image] of markdown.matchAll(/<img\b[^>]*\bsrc\s*=\s*(["'])(.*?)\1[^>]*>/gim))
    candidates.push(image);
  const result = [];
  for (let candidate of candidates) {
    candidate = candidate.replace(/&amp;/gi, '&');
    let resolved;
    try {
      if (candidate.startsWith('//')) candidate = 'https:' + candidate;
      resolved = new URL(candidate, base);
      if (resolved.hostname === 'github.com' && /\/blob\//.test(resolved.pathname)) {
        const parts = resolved.pathname.split('/');
        const blob = parts.indexOf('blob');
        resolved = new URL('https://raw.githubusercontent.com/' +
          parts.slice(1, blob).join('/') + '/' + parts.slice(blob + 1).join('/'));
      }
    } catch { continue; }
    const valid = allowedImageUrl(resolved.href);
    if (valid && !result.includes(valid)) result.push(valid);
    if (result.length >= 120) break;
  }
  return result;
}

async function fetchGithubJSON(url, fetcher = fetch) {
  const response = await fetcher(url, {
    headers: { 'User-Agent': 'TortoiseCrewLauncher/0.3',
      Accept: 'application/vnd.github+json' },
    signal: AbortSignal.timeout(14000), cache: 'no-store',
  });
  if (!response.ok) throw new Error('GitHub documentation unavailable (HTTP ' + response.status + ').');
  const text = await response.text();
  if (text.length > 1024 * 1024) throw new Error('GitHub documentation exceeds size limit.');
  return JSON.parse(text);
}

export async function addonDetails(repoUrl, fetcher = fetch) {
  const repo = gitHubRepo(repoUrl);
  if (!repo) return { readme: '', images: [], description: '',
    warning: 'Full documentation is available from the source website.' };
  const url = GITHUB_API + encodeURIComponent(repo.owner) + '/' + encodeURIComponent(repo.repo);
  const metadata = await fetchGithubJSON(url, fetcher);
  const branch = String(metadata.default_branch || 'main');
  if (!branch || branch.length > 180 || /[\r\n\0]/.test(branch))
    throw new Error('GitHub repository returned an invalid branch.');
  let readme = '';
  let warning = '';
  try {
    const body = await fetchGithubJSON(url + '/readme', fetcher);
    if (body.encoding !== 'base64' || typeof body.content !== 'string')
      throw new Error('Unexpected GitHub README representation.');
    const decoded = Buffer.from(body.content.replace(/\s/g, ''), 'base64');
    if (decoded.length > MAX_README) throw new Error('README is too large.');
    readme = decoded.toString('utf8');
  } catch (error) {
    warning = 'README unavailable: ' + error.message;
  }
  const images = githubReadmeImages(readme, repo, branch);
  return {
    name: String(metadata.name || repo.repo).slice(0, 160),
    description: String(metadata.description || '').slice(0, 1200),
    author: String(metadata.owner?.login || repo.owner).slice(0, 120),
    stars: Number(metadata.stargazers_count || 0),
    forks: Number(metadata.forks_count || 0),
    issues: Number(metadata.open_issues_count || 0),
    updated: String(metadata.pushed_at || ''),
    homepage: /^https:\/\//i.test(metadata.homepage || '') ?
      String(metadata.homepage).slice(0, 800) : '',
    license: String(metadata.license?.spdx_id || metadata.license?.name || 'Not specified').slice(0, 120),
    topics: Array.isArray(metadata.topics) ?
      metadata.topics.filter(x => typeof x === 'string').slice(0, 25) : [],
    branch, url: repo.url, readme, images, warning,
  };
}

// Fetch only remote image media from known hosts; never forward cookies,
// passwords or launcher session tokens. Block redirects outside the allowlist.
export async function imageData(original, fetcher = fetch) {
  const valid = allowedImageUrl(original);
  if (!valid) throw new Error('Unapproved addon image URL.');
  const cached = mediaCache.get(valid);
  if (cached && Date.now() - cached.time < 15 * 60 * 1000) return cached;
  let current = valid, response;
  for (let redirect = 0; redirect <= 4; redirect++) {
    response = await fetcher(current, { redirect: 'manual',
      headers: { 'User-Agent': 'TortoiseCrewLauncher/0.3' },
      signal: AbortSignal.timeout(15000) });
    if (![301, 302, 303, 307, 308].includes(response.status)) break;
    const location = response.headers.get('location');
    current = allowedImageUrl(new URL(location, current).href);
    if (!current) throw new Error('Addon image redirected to an unapproved host.');
  }
  if (!response?.ok || [301, 302, 303, 307, 308].includes(response.status))
    throw new Error('Addon image is unavailable.');
  if (Number(response.headers.get('content-length') || 0) > MAX_IMAGE)
    throw new Error('Addon image exceeds size limit.');
  const mime = String(response.headers.get('content-type') || '').split(';')[0].toLowerCase();
  if (!['image/png', 'image/jpeg', 'image/gif', 'image/webp'].includes(mime))
    throw new Error('Addon image is not a supported raster image.');
  const chunks = [];
  let size = 0;
  for await (const chunk of response.body) {
    size += chunk.byteLength;
    if (size > MAX_IMAGE) throw new Error('Addon image exceeds size limit.');
    chunks.push(Buffer.from(chunk));
  }
  const bytes = Buffer.concat(chunks);
  const validType = mime === 'image/png' ? bytes.subarray(0, 8).equals(
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) :
    mime === 'image/jpeg' ? bytes[0] === 0xff && bytes[1] === 0xd8 :
    mime === 'image/gif' ? ['GIF87a', 'GIF89a'].includes(bytes.toString('ascii', 0, 6)) :
    bytes.toString('ascii', 0, 4) === 'RIFF' &&
      bytes.toString('ascii', 8, 12) === 'WEBP';
  if (!validType) throw new Error('Addon image content does not match its media type.');
  const result = { bytes, mime, time: Date.now() };
  if (mediaCache.size >= 32) mediaCache.delete(mediaCache.keys().next().value);
  mediaCache.set(valid, result);
  return result;
}
