import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadCatalog, withCrewAddons, repositoryAddonVersion } from '../src/catalog.mjs';
import { isNewerAddonVersion } from '../src/addon-updates.mjs';

test('bulk addon updates count only strictly newer comparable releases', () => {
  assert.equal(isNewerAddonVersion('v8.9.0', '8.10.0'), true);
  assert.equal(isNewerAddonVersion('2026.11.27.3', '2026.11.27.4'), true);
  assert.equal(isNewerAddonVersion('8.3.0', '5.5.4'), false);
  assert.equal(isNewerAddonVersion('1.0', 'v1.0.0'), false);
  assert.equal(isNewerAddonVersion('GIT', '2.0.0'), false);
  assert.equal(isNewerAddonVersion('1.0', 'Unknown'), false);
});

test('repository addon version uses the default branch TOC and detects Git builds', async () => {
  const repo = 'https://github.com/example/ExampleAddon';
  const version = await repositoryAddonVersion(repo, 'ExampleAddon', async url => {
    assert.equal(url, 'https://raw.githubusercontent.com/example/ExampleAddon/HEAD/ExampleAddon.toc');
    return '## Interface: 11200\n## Version: 3.1.5\n';
  });
  assert.deepEqual(version, { version: '3.1.5', development: false });
  assert.deepEqual(await repositoryAddonVersion(repo, 'ExampleAddon', async () =>
    '## Interface: 11200\n## Version: GIT\n'), { version: '', development: true });
  assert.deepEqual(await repositoryAddonVersion(repo, 'ExampleAddon', async () => {
    throw Error('Addon source unavailable (HTTP 404).');
  }), { unavailable: true });
});
test('TortoiseBotsManager is installable even with a fresh offline profile and no registry requests added',async t=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'crew-catalog-'));
  t.after(()=>fs.rmSync(root,{recursive:true,force:true}));let requests=0;
  const result=await loadCatalog({root,legacy:path.join(root,'legacy'),fetchText:async()=>{requests++;throw Error('offline');}});
  assert.equal(requests,1);assert.equal(result.items.length,2);
  const item=result.items[0];assert.equal(item.name,'TortoiseBotsManager');
  assert.equal(item.url,'https://github.com/Sagiroth/TortoiseBotsManager');
  assert.equal(item.installable,true);assert.match(item.description,/Requires the server-side/);
  assert.equal(result.items[1].name,'TBM Party Inventory');
  assert.equal(result.items[1].managedId,'party-inventory');
});
test('TortoiseBotsManager is merged once into fresh and already-cached catalogs',async t=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'crew-catalog-'));
  t.after(()=>fs.rmSync(root,{recursive:true,force:true}));let requests=0;
  const input=JSON.stringify({addons:[{name:'Community alias',url:'https://github.com/sagiroth/TortoiseBotsManager/'}]});
  const fetchText=async()=>{requests++;return input;};
  const online=await loadCatalog({root,fetchText});assert.equal(online.items.length,2);
  const cached=await loadCatalog({root,fetchText});assert.equal(cached.items.length,2);assert.equal(requests,1);
  assert.equal(cached.items[0].source,'Tortoise Crew');
  assert.equal(cached.items[1].managedId,'party-inventory');
  assert.equal(withCrewAddons([]).length,2);
});
