'use strict';
const key = new URL(location.href).searchParams.get('key');
const $ = id => document.getElementById(id);
const message = (text, error = false) => {
  $('message').textContent = text;
  $('message').style.color = error ? '#ffb9ad' : '';
};
async function api(action, args = {}) {
  const response = await fetch('/api', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Crew-Token': key },
    body: JSON.stringify({ action, args }),
  });
  const parsed = await response.json();
  if (!response.ok || !parsed.ok) throw new Error(parsed.error || 'Launcher request failed');
  return parsed.result;
}
async function run(action, args = {}, label = action) {
  try {
    message('Working: ' + label + '…');
    const result = await api(action, args);
    message(label + ' completed.');
    return result;
  } catch (error) {
    message(error.message, true);
    throw error;
  }
}
async function runShow(action, args = {}) {
  try {
    const result = await run(action, args, action);
    $('addonResult').textContent = JSON.stringify(result, null, 2);
  } catch (error) {
    $('addonResult').textContent = error.message;
  }
}
function protect(button, task) {
  button.addEventListener('click', async () => {
    button.disabled = true;
    try { await task(); }
    catch { /* The status line already reports errors. */ }
    finally { button.disabled = false; }
  });
}
for (const button of document.querySelectorAll('.nav')) {
  button.addEventListener('click', () => {
    for (const nav of document.querySelectorAll('.nav')) nav.classList.toggle('active', nav === button);
    for (const panel of document.querySelectorAll('.panel'))
      panel.classList.toggle('active', panel.id === button.dataset.tab);
  });
}
async function updatePresence() {
  try {
    const { online } = await api('presence');
    $('players').replaceChildren();
    for (const user of ['MICHAEL', 'JAYKE', 'BERNARD', 'AUGUST']) {
      const div = document.createElement('div');
      div.className = 'player';
      const name = document.createElement('span'), status = document.createElement('span');
      name.textContent = user;
      status.textContent = online[user] ? '● Online' : '○ Offline';
      status.className = online[user] ? 'online' : '';
      div.append(name, status);
      $('players').append(div);
    }
  } catch { $('players').textContent = 'Status unknown'; }
}
function account() { return $('account').value; }
let savedAccountSet = new Set();
let accountPreferenceMap = {};
function applyAccountPreferences() {
  const prefs = accountPreferenceMap[account()] || {};
  const saved = savedAccountSet.has(account());
  $('remember').checked = prefs.remember ?? saved;
  $('useSaved').checked = saved && (prefs.useSaved ?? true);
  $('useSaved').disabled = !saved;
  $('closeOnPlay').checked = prefs.closeOnPlay !== false;
}
async function saveAccountPreferences() {
  const values = { remember: $('remember').checked,
    useSaved: $('useSaved').checked, closeOnPlay: $('closeOnPlay').checked };
  const result = await api('setPreferences', { account: account(), values });
  accountPreferenceMap[account()] = result.preferences;
}
for (const field of ['remember', 'useSaved', 'closeOnPlay'])
  $(field).addEventListener('change', () =>
    saveAccountPreferences().catch(error => message(error.message, true)));
protect($('refreshPresence'), updatePresence);
protect($('play'), async () => {
  await run('play', { username: account(), password: $('password').value,
    remember: $('remember').checked, useSaved: $('useSaved').checked,
    closeOnPlay: $('closeOnPlay').checked }, 'Game launch');
  $('password').value = '';
  if ($('remember').checked) {
    savedAccountSet.add(account());
    $('useSaved').disabled = false;
    $('useSaved').checked = true;
  }
  if ($('closeOnPlay').checked) window.close();
});
protect($('saveClient'), async () => {
  const saved = await run('setClient', { wowPath: $('wowPath').value }, 'Client verification');
  $('wowLocation').textContent = saved.settings.wowPath;
});
protect($('changePassword'), async () => {
  if (!confirm('Change the game password for ' + account() + '?')) return;
  await run('changePassword', { current: $('currentPassword').value,
    desired: $('newPassword').value }, 'Change account password');
  $('currentPassword').value = '';
  $('newPassword').value = '';
});
protect($('loadInstalled'), () => runShow('installed'));
protect($('missing'), () => runShow('missing'));
protect($('previewImport'), () => runShow('previewImport', { source: $('source').value }));
protect($('import'), async () => {
  if (confirm('Import compatible addons with backup? Close WoW first.')) {
    await runShow('import', { source: $('source').value });
  }
});
protect($('repair'), async () => {
  if (confirm('Back up Config.wtf, repair addon folder names and check dependencies?')) await runShow('repair');
});
// Catalog and installed-addon state live in the app. Only the addon collection
// scrolls; the realm and settings panes use the available window space.
const catalogView = {
  tab: 'discover', items: [], githubItems: [], installed: [],
  page: 0, loaded: false, busy: false, selected: null,
};
const PACKS = [
  { name: 'Comfy Atmosphere', description: 'Review local atmosphere and MPQ files. Client patches are not activated.', source: 'Local game patch' },
  { name: 'HD Switch / HD Pack', description: 'OctoWoW HD packs may be realm-specific; import only compatible addon files.', source: 'OctoWoW client patch' },
  { name: 'Nampower and client DLLs', description: 'Inventory local DLLs for review. Binary extensions are never automatically installed.', source: 'Native client extensions' },
  { name: 'VanillaFixes', description: 'Review local client fixes without copying or launching executable helpers.', source: 'Native client extensions' },
];
const addonNode = (tag, className, content) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (content !== undefined) node.textContent = String(content);
  return node;
};
function currentAddonItems() {
  if (catalogView.tab === 'installed') return catalogView.installed;
  if (catalogView.tab === 'packs') return PACKS;
  return $('addonProvider').value === 'github' ? catalogView.githubItems : catalogView.items;
}
function renderAddons() {
  const importVisible = catalogView.tab === 'import';
  $('addonToolbar').classList.toggle('hidden', importVisible || catalogView.tab === 'installed' || catalogView.tab === 'packs');
  $('addonList').classList.toggle('hidden', importVisible);
  $('addonBottom').classList.toggle('hidden', importVisible);
  $('addonImport').classList.toggle('active', importVisible);
  const query = $('addonSearch').value.toLowerCase().trim();
  let filtered = currentAddonItems().filter(entry => catalogView.tab !== 'discover' ||
    (entry.name + ' ' + entry.description + ' ' + entry.author).toLowerCase().includes(query));
  if (catalogView.tab === 'discover') {
    const sort = $('addonSort').value;
    filtered = [...filtered].sort((a, b) => {
      if (sort === 'downloads')
        return (b.downloads ?? -1) - (a.downloads ?? -1) || b.stars - a.stars;
      if (sort === 'recent')
        return (b.updated || '').localeCompare(a.updated || '') || b.stars - a.stars;
      if (sort === 'name') return a.name.localeCompare(b.name);
      if (sort === 'reverse') return b.name.localeCompare(a.name);
      return b.stars - a.stars || a.name.localeCompare(b.name);
    });
  }
  const pageSize = catalogView.tab === 'discover' ? Number($('addonPageSize').value) : 100;
  const pages = Math.max(1, Math.ceil(filtered.length / pageSize));
  catalogView.page = Math.min(catalogView.page, pages - 1);
  $('addonCount').textContent = filtered.length ?
    (catalogView.page * pageSize + 1) + '–' +
    Math.min((catalogView.page + 1) * pageSize, filtered.length) +
    ' of ' + filtered.length + ' addons' : 'No addons found';
  $('addonPrev').disabled = catalogView.page <= 0;
  $('addonNext').disabled = catalogView.page >= pages - 1;
  $('addonList').replaceChildren();
  for (const item of filtered.slice(catalogView.page * pageSize, (catalogView.page + 1) * pageSize)) {
    const card = addonNode('article', 'addon-card');
    const image = addonNode('img', 'addon-art');
    image.alt = '';
    image.loading = 'lazy';
    image.onerror = () => {
      image.replaceWith(addonNode('div', 'addon-art-fallback',
        (item.name || '?').slice(0, 1).toUpperCase()));
    };
    if (item.icon) image.src = imageProxy(item.icon);
    const info = addonNode('div', 'addon-info');
    info.append(addonNode('h3', 'addon-name', item.name),
      addonNode('p', 'addon-desc', item.description || item.skipped || 'Installed addon'));
    info.append(addonNode('div', 'addon-meta', catalogView.tab === 'installed' ?
      (item.version ? 'TOC ' + item.version : 'Check compatibility') :
      item.stars !== undefined ? '★ ' + (item.stars || 0) +
        (item.downloads !== null && item.downloads !== undefined ?
          ' · ↓ ' + item.downloads.toLocaleString() : '') : item.source));
    const controls = addonNode('div', 'addon-buttons');
    if (catalogView.tab === 'discover') {
      const details = addonNode('button', '', 'Details');
      details.addEventListener('click', () => showAddonDetails(item));
      controls.append(details);
      if (item.installable) {
        const install = addonNode('button', 'primary', 'Install');
        install.addEventListener('click', () => installAddon(item));
        controls.append(install);
      }
    } else if (catalogView.tab === 'packs') {
      const importButton = addonNode('button', '', 'Import local');
      importButton.addEventListener('click', () => selectAddonTab('import'));
      controls.append(importButton);
    }
    info.append(controls);
    card.append(item.icon ? image : addonNode('div', 'addon-art-fallback',
      (item.name || '?').slice(0, 1).toUpperCase()), info);
    $('addonList').append(card);
  }
}
function selectAddonTab(tab) {
  catalogView.tab = tab;
  catalogView.page = 0;
  for (const el of document.querySelectorAll('.addon-tab'))
    el.classList.toggle('active', el.dataset.addonTab === tab);
  renderAddons();
  if (tab === 'installed') {
    run('installed', {}, 'Installed addons').then(result => {
      catalogView.installed = result.installed;
      renderAddons();
    }).catch(() => {});
  } else if (tab === 'discover' && !catalogView.loaded) {
    void refreshCatalog(false);
  }
}
async function refreshCatalog(force) {
  if (catalogView.busy) return;
  catalogView.busy = true;
  $('refreshCatalog').disabled = true;
  $('addonStatus').textContent = 'Loading the Turtle WoW community registry…';
  try {
    const data = await api('catalog', { force });
    catalogView.items = data.items;
    catalogView.loaded = true;
    $('addonStatus').textContent = data.items.length + ' addons from Turtle WoW / GitHub' +
      (data.warning ? ' · ' + data.warning : '');
    if ($('addonProvider').value !== 'github') renderAddons();
  } catch (error) {
    $('addonStatus').textContent = error.message;
  } finally {
    $('refreshCatalog').disabled = false;
    catalogView.busy = false;
  }
}
function imageProxy(url) {
  return '/addon-image?key=' + encodeURIComponent(key) +
    '&url=' + encodeURIComponent(url);
}
function addReadmeInline(container, source) {
  const tokens = String(source || '').split(/(\*\*[^*]+\*\*|\[[^\]]+\]\(https?:\/\/[^)\s]+\))/g);
  for (const token of tokens) {
    const emphasis = token.match(/^\*\*([^*]+)\*\*$/);
    const link = token.match(/^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/);
    if (emphasis) container.append(addonNode('strong', '', emphasis[1]));
    else if (link) {
      const anchor = addonNode('a', '', link[1]);
      try {
        const url = new URL(link[2]);
        if (url.protocol === 'https:') {
          anchor.href = url.href;
          anchor.target = '_blank';
          anchor.rel = 'noopener noreferrer';
        }
      } catch { /* Invalid README hyperlinks display as ordinary text. */ }
      container.append(anchor);
    } else container.append(document.createTextNode(token));
  }
}
function renderReadme(markdown) {
  const host = $('detailReadme');
  host.replaceChildren();
  const lines = String(markdown || '').split(/\r?\n/);
  let list = null, code = null;
  for (const line of lines.slice(0, 3000)) {
    if (line.trim().startsWith(String.fromCharCode(96).repeat(3))) {
      if (code) { code = null; } else {
        code = addonNode('pre');
        host.append(code);
      }
      list = null;
      continue;
    }
    if (code) { code.textContent += line + '\n'; continue; }
    if (/^\s*<img\b/i.test(line) || /^\s*!\[/.test(line)) continue;
    if (!line.trim()) { list = null; continue; }
    const heading = line.match(/^(#{1,5})\s+(.+)$/);
    if (heading) {
      list = null;
      const h = addonNode('h' + Math.min(4, heading[1].length + 1));
      addReadmeInline(h, heading[2]);
      host.append(h);
      continue;
    }
    const li = line.match(/^\s*(?:[-*+]|\d+\.)\s+(.+)$/);
    if (li) {
      if (!list) { list = addonNode('ul'); host.append(list); }
      const item = addonNode('li');
      addReadmeInline(item, li[1]);
      list.append(item);
      continue;
    }
    list = null;
    const quote = line.match(/^\s*>\s*(.*)$/);
    const para = addonNode(quote ? 'blockquote' : 'p');
    addReadmeInline(para, quote ? quote[1] : line);
    host.append(para);
  }
  if (!host.childNodes.length) host.append(addonNode('p', 'footnote',
    'The author has not published a README. Open the source repository for details.'));
}
async function showAddonDetails(item) {
  catalogView.selected = item;
  $('detailTitle').textContent = item.name;
  $('detailDescription').textContent = item.description || 'No description provided.';
  $('detailMetadata').replaceChildren();
  $('detailGallery').replaceChildren();
  $('detailReadme').replaceChildren();
  $('detailGalleryMessage').textContent = 'Loading screenshots from GitHub…';
  $('detailReadmeStatus').textContent = 'Loading full README and project metadata…';
  $('detailSource').href = item.url;
  $('detailInstall').disabled = !item.installable;
  $('detailInstall').textContent = item.installable ? 'Install safely' : 'No compatible direct download';
  $('addonDetails').showModal();
  try {
    const result = await api('addonDetails', { url: item.url });
    // Guard against updates from an earlier details request after a new card
    // was selected, without ever inserting untrusted README HTML.
    if (catalogView.selected !== item || !$('addonDetails').open) return;
    for (const [label, value] of [
      ['Author', result.author || item.author || 'Community'],
      ['Stars', result.stars ?? item.stars], ['Forks', result.forks],
      ['Open issues', result.issues], ['License', result.license],
      ['Updated', result.updated?.slice(0, 10)], ['Branch', result.branch],
    ]) {
      if (value !== undefined && value !== '') {
        $('detailMetadata').append(addonNode('span', '', label + ': ' + value));
      }
    }
    $('detailReadmeStatus').textContent = result.warning || 'Complete project README';
    renderReadme(result.readme || result.description || item.description);
    for (const url of result.images || []) {
      const link = addonNode('a');
      link.href = url;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      const screenshot = addonNode('img');
      screenshot.alt = item.name + ' screenshot';
      screenshot.loading = 'lazy';
      screenshot.src = imageProxy(url);
      screenshot.onerror = () => link.replaceWith(addonNode('div', 'footnote',
        'Screenshot unavailable'));
      link.append(screenshot);
      $('detailGallery').append(link);
    }
    $('detailGalleryMessage').textContent = result.images?.length ?
      result.images.length + ' screenshots · click to view original' :
      'No screenshots are included in the project README.';
  } catch (error) {
    $('detailReadmeStatus').textContent = 'Could not load README: ' + error.message;
    $('detailGalleryMessage').textContent = 'Screenshots unavailable.';
    renderReadme(item.description);
  }
}
async function installAddon(item) {
  if (!item.installable) return;
  if (!confirm('Install ' + item.name + ' from ' + item.url +
    '?\n\nOnly compatible addon files are installed, with backups. Close WoW first.')) return;
  $('addonDetails').close();
  $('addonStatus').textContent = 'Downloading and checking ' + item.name + '…';
  try {
    const result = await api('installRepository', { url: item.url });
    $('addonStatus').textContent = 'Installed ' + result.imported +
      ' addon folder(s). Restart WoW to load them.';
    message('Addon installed. Backup saved at ' + result.backup);
  } catch (error) {
    $('addonStatus').textContent = 'Install failed: ' + error.message;
    message(error.message, true);
  }
}
for (const tab of document.querySelectorAll('.addon-tab'))
  tab.addEventListener('click', () => selectAddonTab(tab.dataset.addonTab));
for (const item of ['addonSearch', 'addonSort', 'addonPageSize']) {
  $(item).addEventListener(item === 'addonSearch' ? 'input' : 'change', () => {
    catalogView.page = 0; renderAddons();
  });
}
$('addonProvider').addEventListener('change', async () => {
  catalogView.page = 0;
  if ($('addonProvider').value === 'github') {
    const phrase = $('addonSearch').value.trim();
    if (!phrase) {
      $('addonStatus').textContent = 'Enter an addon name, then press Enter to search GitHub.';
    } else {
      try {
        const found = await run('githubSearch', { query: phrase }, 'GitHub search');
        catalogView.githubItems = found.items;
      } catch { catalogView.githubItems = []; }
    }
  }
  renderAddons();
});
$('addonSearch').addEventListener('keydown', async event => {
  if (event.key !== 'Enter' || $('addonProvider').value !== 'github') return;
  try {
    const found = await run('githubSearch', { query: $('addonSearch').value }, 'GitHub search');
    catalogView.githubItems = found.items;
    catalogView.page = 0;
    $('addonStatus').textContent = found.items.length +
      ' public repositories; compatibility is not verified.';
  } catch { catalogView.githubItems = []; }
  renderAddons();
});
$('addonPrev').addEventListener('click', () => { catalogView.page--; renderAddons(); });
$('addonNext').addEventListener('click', () => { catalogView.page++; renderAddons(); });
$('refreshCatalog').addEventListener('click', () => { void refreshCatalog(true); });
$('closeAddonDetails').addEventListener('click', () => $('addonDetails').close());
$('detailInstall').addEventListener('click', () => {
  if (catalogView.selected) void installAddon(catalogView.selected);
});
protect($('scanClients'), async () => {
  const result = await run('scanClients', {}, 'Find previous clients');
  $('addonResult').textContent = result.clients.length ? result.clients.join('\n') :
    'No common OctoWoW or Turtle client folders found. Enter a path manually.';
  if (result.clients.length) $('source').value = result.clients[0];
});
document.querySelector('[data-tab="addons"]').addEventListener('click', () => {
  if (!catalogView.loaded) void refreshCatalog(false);
});
protect($('checkUpdates'), async () => {
  const result = await run('updateStatus', {}, 'Check GitHub launcher updates');
  $('updateStatus').textContent = 'Installed: ' + result.current +
    ' · GitHub: ' + result.latest +
    (result.available ? ' · Restart to install the update.' : ' · Up to date.');
});
protect($('restartLauncher'), async () => {
  if (!confirm('Close this launcher window and restart to check GitHub for a new version? Close WoW first.')) return;
  await run('restartLauncher', {}, 'Restart launcher');
  window.close();
});
$('account').addEventListener('change', async () => {
  $('password').value = '';
  applyAccountPreferences();
  await run('setAccount', { username: account() }, 'Select account').catch(() => {});
});
async function initial() {
  if (!key || !/^[0-9a-f]{64}$/.test(key)) {
    message('Invalid localhost launcher session.', true);
    return;
  }
  const state = await run('state', {}, 'Load preferences');
  // Migration must see a real browser-to-backend handshake promptly.
  // Slow external realm-status requests must not cause a false rollback.
  await api('handshake');
  $('account').replaceChildren();
  for (const user of state.accounts) {
    const option = new Option(user, user, false, user === state.settings.username);
    $('account').add(option);
  }
  savedAccountSet = new Set(state.savedAccounts);
  accountPreferenceMap = state.preferences || {};
  applyAccountPreferences();
  $('wowPath').value = state.settings.wowPath;
  $('wowLocation').textContent = state.settings.wowPath || 'No WoW.exe selected';
  await run('refreshManifest', {}, 'Check server settings').catch(() => {});
  try {
    await api('status');
    $('serviceStatus').textContent = '● Realm service online';
  } catch {
    $('serviceStatus').textContent = '○ Realm service unavailable';
  }
  await updatePresence();
  message('Tortoise Crew Launcher ready.');
}
initial().catch(error => message(error.message, true));
