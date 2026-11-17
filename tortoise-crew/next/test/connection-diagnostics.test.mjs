import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { once } from 'node:events';
import { createConnectionDiagnostics } from '../src/connection-diagnostics.mjs';
import { GameRelay, FrameDecoder, openRelayStream } from '../src/relay.mjs';

function fixture(t, options={}) {
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'crew-diagnostics-'));
  t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  return {root, diagnostics:createConnectionDiagnostics(root,{version:'0.3.7',...options})};
}
const records=root=>fs.readFileSync(path.join(root,'diagnostics/connections.jsonl'),'utf8')
  .trim().split('\n').filter(Boolean).map(JSON.parse);
async function tick() {await new Promise(r=>setTimeout(r,20));}
async function pair(t) {
  const server=net.createServer();server.listen(0,'127.0.0.1');await once(server,'listening');
  const accepted=once(server,'connection');
  const client=net.createConnection(server.address().port,'127.0.0.1');
  client.on('error',()=>{});const [remote]=await accepted;remote.on('error',()=>{});
  await once(client,'connect');
  t.after(()=>{client.destroy();remote.destroy();server.close();});return {client,remote};
}
function serverFrame(op,payload=Buffer.alloc(0)) {
  assert(payload.length<126);return Buffer.concat([Buffer.from([0x80|op,payload.length]),payload]);
}

test('first closure cause wins; only bounded allowlisted metadata reaches disk',async t=>{
  const {root,diagnostics}=fixture(t);const trace=diagnostics.begin('world','standard');
  trace.bind({bytesRead:80,bytesWritten:90},{bytesRead:40,bytesWritten:50});trace.connected();
  const secret='Bearer password-account-private-url';
  trace.end('remote_error',{code:'ECONNRESET',message:secret,stack:secret});
  trace.end('client_close');await diagnostics.flush();
  const data=records(root);assert.equal(data.length,2);assert.equal(data[1].reason,'remote_error');
  assert.equal(data[1].errorCode,'ECONNRESET');assert.equal(data[1].remoteBytesRead,80);
  assert(!JSON.stringify(data).includes(secret));assert.equal(data[0].id,data[1].id);
});
test('rotation is bounded and write failures do not interrupt a connection',async t=>{
  const {root,diagnostics}=fixture(t,{maxBytes:1800});
  for(let i=0;i<16;i++){diagnostics.begin('world','standard').end('client_end');await diagnostics.flush();}
  const files=fs.readdirSync(path.join(root,'diagnostics'));assert.deepEqual(files.sort(),['connections.jsonl','connections.jsonl.1']);
  for(const name of files)assert(fs.statSync(path.join(root,'diagnostics',name)).size<=1800);
  const bad=path.join(root,'not-a-folder');fs.writeFileSync(bad,'x');
  const fail=createConnectionDiagnostics(bad);fail.begin('world','standard').end('client_close');await fail.flush();
});
test('burst pressure drops diagnostics instead of building an unbounded queue',async t=>{
  const {root,diagnostics}=fixture(t,{maxPending:2});
  for(let i=0;i<1000;i++)diagnostics.begin('world','standard').end('client_close');
  await diagnostics.flush();const data=records(root);assert(data.length<=3);
  assert(data.some(r=>r.droppedRecords>0));
});
test('existing ping/pong frames expose RTT and close code without leaking reason text',async t=>{
  const {root,diagnostics}=fixture(t);const trace=diagnostics.begin('world','standard');
  const payload=Buffer.from([1,2,3,4]);trace.ping(payload);
  const decoder=new FrameDecoder(()=>{},()=>{},code=>trace.end('websocket_close',null,code),p=>trace.pong(p));
  decoder.push(serverFrame(10,payload));
  const close=Buffer.alloc(2);close.writeUInt16BE(1012);
  decoder.push(serverFrame(8,Buffer.concat([close,Buffer.from('private-close-text')])));
  await diagnostics.flush();const result=records(root)[1];
  assert.equal(result.closeCode,1012);assert.equal(result.pings,1);assert.equal(result.pongs,1);
  assert(!JSON.stringify(result).includes('private-close-text'));
});
test('standard game relay forwards bytes unchanged and reports remote WebSocket closure once',async t=>{
  const {root,diagnostics}=fixture(t);const local=await pair(t),upstream=await pair(t);
  const relay=new GameRelay('https://unused.invalid','0'.repeat(64),{diagnostics,
    connect:async()=>({socket:upstream.client,initial:Buffer.alloc(0)})});
  await relay.forward(local.remote,'world');
  const received=once(local.client,'data');upstream.remote.write(serverFrame(2,Buffer.from('game-bytes')));
  assert.equal((await received)[0].toString(),'game-bytes');
  const wire=once(upstream.remote,'data');local.client.write(Buffer.from('client-bytes'));
  const [encoded]=await wire;const n=encoded[1]&127;const key=encoded.subarray(2,6);
  const decoded=Buffer.from(encoded.subarray(6,6+n));for(let i=0;i<n;i++)decoded[i]^=key[i%4];
  assert.equal(decoded.toString(),'client-bytes');
  const close=Buffer.alloc(2);close.writeUInt16BE(1001);upstream.remote.write(serverFrame(8,close));
  await tick();await diagnostics.flush();const data=records(root);assert.equal(data.length,2);
  assert.equal(data[1].reason,'websocket_close');assert.equal(data[1].closeCode,1001);
});
test('local game ending and deliberate launcher stop are distinct',async t=>{
  const {root,diagnostics}=fixture(t);const local=await pair(t),upstream=await pair(t);
  const relay=new GameRelay('https://unused.invalid','0'.repeat(64),{diagnostics,
    connect:async()=>({socket:upstream.client,initial:Buffer.alloc(0)})});
  await relay.forward(local.remote,'world');local.client.end();await tick();await diagnostics.flush();
  assert.equal(records(root)[1].reason,'client_end');
  const l2=await pair(t),u2=await pair(t);
  const r2=new GameRelay('https://unused.invalid','0'.repeat(64),{diagnostics,
    connect:async()=>({socket:u2.client,initial:Buffer.alloc(0)})});
  await r2.forward(l2.remote,'world');await r2.stop();await tick();await diagnostics.flush();
  assert.equal(records(root).at(-1).reason,'launcher_stop');
});
test('prepared-session relay reports decode failure and handshake refusal',async t=>{
  const {root,diagnostics}=fixture(t);const upstream=await pair(t);
  const stream=await openRelayStream('https://unused.invalid','world','0'.repeat(64),{diagnostics,
    connect:async()=>({socket:upstream.client,initial:Buffer.alloc(0)})});
  stream.on('error',()=>{});stream.resume();upstream.remote.write(serverFrame(1,Buffer.from('unexpected')));
  await tick();await diagnostics.flush();assert.equal(records(root)[1].reason,'decode_error');
  await assert.rejects(openRelayStream('https://unused.invalid','auth','0'.repeat(64),{diagnostics,
    connect:async()=>{throw Object.assign(new Error('secret'),{code:'ECONNREFUSED'});}}));
  await diagnostics.flush();assert.equal(records(root).at(-1).reason,'handshake_error');
  assert.equal(records(root).at(-1).errorCode,'ECONNREFUSED');
});
