import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import crypto from 'node:crypto';
import { interleave, fromLE, clientProof, clientSession, serverChallenge, worldProof } from '../src/wow-srp.mjs';
import { PreparedLogin, validateAddonBlob, addonFingerprint } from '../src/prepared-login.mjs';
import { authenticateWoW, WorldWire, OP, localAuth, authSessionPayload, addonInfoBlob, u32 } from '../src/wow-session.mjs';
import { LoginPreflight } from '../src/login-preflight.mjs';
const be = (hex,size) => Buffer.from(hex.padStart(size*2,'0'),'hex').reverse();

test('SRP interleave and M1 match independent wow_srp regression vectors',()=>{
  assert.deepEqual(interleave(fromLE(be('FCCC2DFFED3E8D0D77EAD3E230D9C12BFFA4F3D41BE507C0E534FC0DD6EB4C8F',32))),
    be('6C558DD116725AE527707A08C3E4BE3181B5E622343403807389BF42BC3AB61A89AC8DE01A4E14EE',40));
  assert.deepEqual(clientProof('7WG6SHZL33JMGPO4',
    be('00A4A09E0B5ACA438B8CD837D0816CA26043DBD1EAEF138EEF72DCF3F696D03D',32),
    be('0095FE039AFE5E1BADE9AC0CAEC3CB73D2D08BBF4CA8ADDBCDF0CE709ED5103F',32),
    be('00B0C41F58CCE894CFB816FA72CA344C9FE2ED7CE799452ADBA7ABDCD26EAE75',32),
    be('2F409C9AEC0FE203D3673202D57BEA19C931AACBD1FD75C539C34129BD70F83E37BFC0F99CD3A477',40)),
    be('7D07022B4064CCE633D679F61C6B212B6F8BC5C3',20));
});

test('SRP verifies both peers, fresh keys and rejection of tampered proofs',()=>{
  const keys=new Set();
  for(let i=0;i<12;i++) {
    const server=serverChallenge('TESTER','example-password');
    const client=clientSession('tester','example-password',server.salt,server.B);
    const accepted=server.verify(client.A,client.proof);
    assert.deepEqual(accepted.key,client.key);assert.deepEqual(accepted.proof,client.serverProof);
    keys.add(client.key.toString('hex'));
    const bad=Buffer.from(client.proof);bad[2]^=1;
    assert.throws(()=>server.verify(client.A,bad),/proof/);
    assert.throws(()=>server.verify(Buffer.alloc(32),client.proof),/key/);
  }
  assert.equal(keys.size,12);
});

async function listener(t,handler) {
  const sockets=new Set(),server=net.createServer(socket=>{
    sockets.add(socket);socket.on('error',()=>{});socket.once('close',()=>sockets.delete(socket));
    void Promise.resolve(handler(socket)).catch(()=>socket.destroy());
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>{for(const socket of sockets)socket.destroy();return new Promise(resolve=>server.close(resolve));});
  return server.address().port;
}
const connect=port=>new Promise((resolve,reject)=>{
  const socket=net.connect(port,'127.0.0.1',()=>resolve(socket));socket.once('error',reject);
});

test('world wire preserves cipher state across fragmented headers and coalesced packets',async t=>{
  const key=crypto.randomBytes(40),body=crypto.randomBytes(1024);
  const port=await listener(t,async socket=>{
    const wire=new WorldWire(socket,{server:true});wire.arm(key);
    const first=await wire.receive(),second=await wire.receive();
    assert.equal(first.opcode,0x123);assert.deepEqual(first.payload,body);
    assert.equal(second.opcode,0x456);assert.deepEqual(second.payload,Buffer.from('next'));
    wire.send(0x789,body);wire.send(0xabc,Buffer.from('reply'));
  });
  const socket=await connect(port),wire=new WorldWire(socket);t.after(()=>wire.destroy());wire.arm(key);
  // Fragment real encrypted bytes through a forwarding stream.
  const originalWrite=socket.write.bind(socket);
  socket.write=bytes=>{for(const byte of bytes)originalWrite(Buffer.from([byte]));return true;};
  wire.send(0x123,body);wire.send(0x456,Buffer.from('next'));
  assert.deepEqual(await wire.receive(),{opcode:0x789,payload:body});
  assert.deepEqual(await wire.receive(),{opcode:0xabc,payload:Buffer.from('reply')});
});

test('live session handoff preserves addon metadata and forwards traffic with different SRP keys',async t=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'crew-handoff-')),game=path.join(root,'game');
  fs.mkdirSync(game);t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  const account='TESTER',password='only-a-test';let remoteKey,remoteAuth=0,lastBlob;
  const realm={type:0,flags:0,name:'Test Realm',population:0,characters:2,category:1,id:0};
  const authPort=await listener(t,socket=>localAuth(socket,{account,password,realm,port:8085,onKey:key=>{remoteKey=Buffer.from(key);}}));
  const worldPort=await listener(t,async socket=>{
    const wire=new WorldWire(socket,{server:true});const seed=u32(123);wire.send(OP.AUTH_CHALLENGE,seed);
    const auth=await wire.receive();assert.equal(auth.opcode,OP.AUTH_SESSION);
    assert.equal(auth.payload.readUInt32LE(0),7272);
    const end=auth.payload.indexOf(0,8),clientSeed=auth.payload.subarray(end+1,end+5);
    assert.deepEqual(auth.payload.subarray(end+5,end+25),worldProof(account,clientSeed,seed,remoteKey));
    lastBlob=Buffer.from(auth.payload.subarray(end+25));remoteAuth++;
    wire.arm(remoteKey);wire.send(OP.AUTH_RESPONSE,Buffer.concat([Buffer.from([12]),Buffer.alloc(9)]));
    wire.send(OP.ADDON_INFO,Buffer.from([1,0,0]));
    while(true) {
      const packet=await wire.receive();
      if(packet.opcode===OP.CHAR_ENUM)wire.send(OP.CHAR_LIST,Buffer.from([2,1,2,3,4]));
      else if(packet.opcode===OP.PING)wire.send(OP.PONG,packet.payload.subarray(0,4));
      else wire.send(0x555,packet.payload);
    }
  });
  const prepare=()=>new PreparedLogin({root,game,account,password,open:mode=>connect(mode==='auth'?authPort:worldPort)}).prepare();
  const stages=[];
  async function handoff(prepared,blob) {
    t.after(()=>prepared.stop());await prepared.start({authPort:0,worldPort:0});
    const start=performance.now();
    const auth=await authenticateWoW(await connect(prepared.authPort),account,password);
    assert.notDeepEqual(auth.key,remoteKey,'local SRP must not replace the upstream key');
    const wire=new WorldWire(await connect(prepared.worldPort));
    const challenge=await wire.receive();
    wire.send(OP.AUTH_SESSION,authSessionPayload(account,5875,u32(7),challenge.payload,auth.key,blob));wire.arm(auth.key);
    let packet;
    do {packet=await wire.receive();}while(packet.opcode!==OP.AUTH_RESPONSE);
    assert.equal(packet.payload[0],12);wire.send(OP.CHAR_ENUM);
    do {packet=await wire.receive();}while(packet.opcode!==OP.CHAR_LIST);
    assert.deepEqual(packet.payload,Buffer.from([2,1,2,3,4]));
    stages.push(performance.now()-start);
    wire.send(OP.PING,Buffer.concat([u32(998),u32(0)]));
    do {packet=await wire.receive();}while(packet.opcode!==OP.PONG);
    assert.equal(packet.payload.readUInt32LE(0),998);
    wire.send(0x444,Buffer.from('payload remains intact'));
    packet=await wire.receive();assert.equal(packet.opcode,0x555);assert.equal(packet.payload.toString(),'payload remains intact');
    wire.destroy();auth.key.fill(0);await prepared.stop();
  }
  const blob=addonInfoBlob(['Blizzard_AuctionUI','MyCustomAddon']);
  const first=await prepare();assert.equal(remoteAuth,0,'first run must await exact client addon data');
  await handoff(first,blob);assert.deepEqual(lastBlob,blob);
  const second=await prepare();assert.equal(second.world.characterList.payload[0],2,'repeat run must prefetch before Play');
  const count=remoteAuth;await handoff(second,blob);assert.equal(remoteAuth,count,'cached handoff must not authenticate upstream again');
  const changed=addonInfoBlob(['Blizzard_AuctionUI','ChangedAddon']);
  const third=await prepare();await handoff(third,changed);
  assert.deepEqual(lastBlob,changed,'addon changes must reach the real server unchanged');
  assert.equal(remoteAuth,count+2,'changed metadata must replace the prepared upstream world session');
  assert.equal(stages.length,3);
  const recovery=await prepare();t.after(()=>recovery.stop());
  await recovery.start({authPort:0,worldPort:0});recovery.world.destroy();
  assert.equal(recovery.fallback,true,'failed preparation must preserve ordinary login');
  const ordinaryAuth=await authenticateWoW(await connect(recovery.authPort),account,password);
  assert.deepEqual(ordinaryAuth.key,remoteKey,'recovery must use the real server SRP session');
  const ordinaryWorld=new WorldWire(await connect(recovery.worldPort));
  const challenge=await ordinaryWorld.receive();
  ordinaryWorld.send(OP.AUTH_SESSION,authSessionPayload(account,7272,u32(99),challenge.payload,ordinaryAuth.key,changed));
  ordinaryWorld.arm(ordinaryAuth.key);
  let packet;do{packet=await ordinaryWorld.receive();}while(packet.opcode!==OP.AUTH_RESPONSE);
  assert.equal(packet.payload[0],12);ordinaryWorld.send(OP.CHAR_ENUM);
  do{packet=await ordinaryWorld.receive();}while(packet.opcode!==OP.CHAR_LIST);
  assert.equal(packet.payload[0],2);ordinaryWorld.destroy();ordinaryAuth.key.fill(0);await recovery.stop();
});

test('expired preparation closes its upstream connection and cannot bind game ports',async t=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'crew-expire-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  let key;
  const realm={type:0,flags:0,name:'Test',population:0,characters:0,category:0,id:0};
  const auth=await listener(t,socket=>localAuth(socket,{account:'TESTER',password:'example',realm,port:8085,onKey:k=>{key=k;}}));
  const world=await listener(t,socket=>{const wire=new WorldWire(socket,{server:true});wire.send(OP.AUTH_CHALLENGE,u32(1));});
  const prepared=await new PreparedLogin({root,game:root,account:'TESTER',password:'example',ttlMs:30,open:mode=>connect(mode==='auth'?auth:world)}).prepare();
  t.after(()=>prepared.stop());await new Promise(resolve=>setTimeout(resolve,60));
  assert.equal(prepared.usable(),false);assert.equal(prepared.disposed,true);
  assert.equal(prepared.password,'');assert.ok(prepared.world.key.every(byte=>byte===0));
  await assert.rejects(()=>prepared.start({authPort:0,worldPort:0}),/expired/);
});

test('addon cache validates compressed length and invalidates installation changes',t=>{
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'crew-addons-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  const dir=path.join(root,'Interface','AddOns','Test');fs.mkdirSync(dir,{recursive:true});
  const file=path.join(dir,'Test.toc');fs.writeFileSync(file,'test');
  const before=addonFingerprint(root,'TESTER');fs.writeFileSync(file,'changed');
  assert.notEqual(addonFingerprint(root,'TESTER'),before);
  const stable=addonFingerprint(root,'TESTER');fs.utimesSync(file,new Date(),new Date(Date.now()+1000));
  assert.equal(addonFingerprint(root,'TESTER'),stable,'rewriting identical metadata must not discard the prepared session');
  const blob=addonInfoBlob(['Test']);assert.equal(validateAddonBlob(blob),blob);
  const bad=Buffer.from(blob);bad.writeUInt32LE(12345,0);assert.throws(()=>validateAddonBlob(bad),/size mismatch/);
  assert.throws(()=>validateAddonBlob(Buffer.alloc(8)),/size/);
});

test('preflight disposes superseded sessions and reuses saved credentials only for their account and URL',async()=>{
  let stopCount=0;
  const preflight=new LoginPreflight({authenticate:async()=> 'a'.repeat(64),provision:async()=>{},prepareSession:async({password})=>({password,usable:()=>true,stop:async()=>{stopCount++;}})});
  const input={account:'TESTER',password:'example',url:'https://example.test',native:true,fromSaved:true};
  await preflight.prepare(input);
  assert.equal(preflight.savedPassword(input.account,input.url),'example');
  assert.equal(preflight.savedPassword('OTHER',input.url),'');assert.equal(preflight.savedPassword(input.account,'https://other.test'),'');
  preflight.invalidate();assert.equal(stopCount,1);assert.equal(preflight.savedPassword(input.account,input.url),'');
  await preflight.prepare(input);const ticket=await preflight.takeTicket(input);
  preflight.invalidate();assert.equal(stopCount,1,'consumed session belongs to the game until it exits');
  await ticket.prepared.stop();assert.equal(stopCount,2);
});
