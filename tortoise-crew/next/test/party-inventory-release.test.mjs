import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

// The on-disk release manifest is itself the only source of truth for the
// launcher. Check the bytes checked into GitHub instead of trusting a version
// number, a mock download, or the older test client currently installed.
test('published Party Inventory release has all five exact file hashes', () => {
  const addon = path.resolve('tortoise-crew/addons/TortoiseBotsPartyInventory');
  const manifest = JSON.parse(fs.readFileSync(path.join(addon, 'release.json'), 'utf8'));
  assert.equal(manifest.schema, 1);
  assert.equal(manifest.addon, 'TortoiseBotsPartyInventory');
  assert.equal(manifest.version, '2026.11.22.6');
  const expected = [
    'Inventory.lua', 'TortoiseBotsPartyInventory.toc',
    'Assets/Refresh.tga', 'Assets/Settings.tga', 'Assets/SellMarked.tga',
  ];
  assert.deepEqual(Object.keys(manifest.files).sort(), [...expected].sort());
  for (const name of expected) {
    const data = fs.readFileSync(path.join(addon, name));
    assert.equal(crypto.createHash('sha256').update(data).digest('hex'),
      manifest.files[name], `${name} must be exactly the QA-approved release bytes`);
  }
});
