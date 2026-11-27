import { installedAddons } from './addons.mjs';
import { loadCatalog, repositoryAddonVersion } from './catalog.mjs';
import { installFromGitHub } from './github-addons.mjs';
import { installPartyInventory, partyInventoryStatus } from './managed-addons.mjs';

const key = value => String(value || '').toLowerCase().replace(/[^a-z0-9]/g, '');
const PARTY_INVENTORY = 'TortoiseBotsPartyInventory';

export function isNewerAddonVersion(current, candidate) {
  const parts = value => /^v?\d+(?:\.\d+){1,5}$/i.test(value || '') ?
    value.replace(/^v/i, '').split('.').map(Number) : null;
  const a = parts(current), b = parts(candidate);
  if (!a || !b || [...a, ...b].some(n => !Number.isSafeInteger(n))) return false;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const difference = (b[i] ?? 0) - (a[i] ?? 0);
    if (difference) return difference > 0;
  }
  return false;
}

export async function availableAddonUpdates(game, options = {}) {
  const {items} = await loadCatalog(options);
  const installed = installedAddons(game).filter(addon => !addon.skipped);
  const sources = new Map();
  for (const local of installed) {
    if (local.name === PARTY_INVENTORY || !local.version) continue;
    const repos = new Map(items.filter(item => item.installable && !item.managedId &&
      (key(item.name) === key(local.name) ||
        key(new URL(item.url).pathname.split('/').filter(Boolean).pop()) === key(local.name)))
      .map(item => [item.url.toLowerCase().replace(/\/$/, ''), item]));
    if (repos.size === 1) {
      const [id, repo] = repos.entries().next().value;
      if (!sources.has(id)) sources.set(id, { local, repo });
    }
  }
  const updates = [];
  if (installed.some(addon => addon.name === PARTY_INVENTORY)) {
    try {
      const party = await partyInventoryStatus(game);
      if (party.updateAvailable && !party.modified && isNewerAddonVersion(party.current, party.latest))
        updates.push({name: PARTY_INVENTORY, managed: true});
    } catch { /* Other verified sources remain eligible offline. */ }
  }
  const entries = [...sources.values()];
  for (let i = 0; i < entries.length; i += 5) {
    const batch = await Promise.all(entries.slice(i, i + 5).map(async ({local, repo}) => {
      const latest = await repositoryAddonVersion(repo.url, repo.name);
      return isNewerAddonVersion(local.version, latest?.version) ?
        {name: local.name, url: repo.url} : null;
    }));
    updates.push(...batch.filter(Boolean));
  }
  return updates;
}

export async function applyAddonUpdates(game, updates, {isGameRunning} = {}) {
  const result = {updated: [], failed: []};
  for (const item of updates) {
    try {
      if (isGameRunning?.()) throw new Error('Close WoW before updating addons.');
      const install = item.managed ? await installPartyInventory(game, {auto: true, isGameRunning}) :
        await installFromGitHub(item.url, game, {isGameRunning});
      if (install.skipped) throw new Error('Managed addon files changed. Update it individually.');
      if (!install.upToDate) result.updated.push(item.name);
    } catch (error) {
      result.failed.push({name: item.name, error: error.message});
    }
  }
  return result;
}
