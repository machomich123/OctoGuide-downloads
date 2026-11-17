import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Native GlueXML assets must be embedded inside an .mjs file: the existing
// secure launcher ZIP extractor intentionally allows JS, but not arbitrary
// .lua/.xml/.toc files. Keeping the restrictive extractor unchanged allows
// older launchers to install this update without a migration bootstrap.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const src = path.join(root, 'src', 'native-assets');
const files = [
  'GlueXML.toc', 'CrewInstantLogin.lua', 'CrewInstantLogin.xml',
  'CrewLegacyGlobals.lua',
];
const content = Object.fromEntries(files.map(name => [
  name, fs.readFileSync(path.join(src, name), 'utf8').replace(/\r\n/g, '\n'),
]));
const output = [
  '// Generated from src/native-assets by scripts/Generate-Native-Asset-Bundle.mjs.',
  '// Edit source .lua/.xml/.toc files, then regenerate this file before release.',
  'export const nativeAssetText = Object.freeze(' + JSON.stringify(content, null, 2) + ');',
  '',
].join('\n');
fs.writeFileSync(path.join(root, 'src', 'native-assets-bundled.mjs'), output);
console.log('CREW_NATIVE_ASSETS_BUNDLED=' + files.length);
