import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { launcherIconBytes, materializeLauncherIcon, ICON_SHA256 } from '../src/launcher-icon.mjs';
import { createServer } from '../src/main.mjs';
test('selected B3 icon contains seven Windows sizes, is hash checked and writes only once',t=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'crew-icon-'));
  t.after(()=>fs.rmSync(root,{recursive:true,force:true}));const bytes=launcherIconBytes();
  assert.equal(bytes.readUInt16LE(2),1);assert.equal(bytes.readUInt16LE(4),7);
  const sizes=[];for(let i=0;i<7;i++)sizes.push(bytes[6+i*16]||256);
  assert.deepEqual(sizes,[16,24,32,48,64,128,256]);
  assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),ICON_SHA256);
  const file=materializeLauncherIcon(root),at=fs.statSync(file).mtimeMs;
  assert.equal(materializeLauncherIcon(root),file);assert.equal(fs.statSync(file).mtimeMs,at);
  assert(fs.readFileSync(file).equals(bytes));
});
test('app window favicon serves the selected embedded B3 even with an old installer icon',async t=>{
  const {server,url}=await createServer();t.after(()=>new Promise(r=>server.close(r)));
  const response=await fetch(new URL('/favicon.ico?v=b3',url));
  assert.equal(response.status,200);assert.equal(response.headers.get('content-type'),'image/x-icon');
  assert(Buffer.from(await response.arrayBuffer()).equals(launcherIconBytes()));
});
