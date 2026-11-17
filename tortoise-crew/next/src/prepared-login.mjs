import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import crypto from 'node:crypto';
import { inflateSync } from 'node:zlib';
import { readJson, writeJsonAtomic } from './config.mjs';
import { openRelayStream } from './relay.mjs';
import { authenticateWoW, PreparedWorld, localAuth } from './wow-session.mjs';

export function addonFingerprint(game, account) {
  const hash = crypto.createHash('sha256');
  const base = path.join(game, 'Interface', 'AddOns');
  let entries = 0;
  function walk(folder) {
    if (!fs.existsSync(folder)) return;
    for (const entry of fs.readdirSync(folder, { withFileTypes: true }).sort((a,b)=>a.name.localeCompare(b.name))) {
      if (++entries > 100000) throw new Error('Addon fingerprint limit.');
      const file = path.join(folder, entry.name);
      if (entry.isSymbolicLink()) throw new Error('Linked addon files cannot be prefetched.');
      if (entry.isDirectory()) { if (entry.name !== '.git') walk(file); }
      else if (entry.isFile()) {
        const stat = fs.statSync(file);
        const contentMetadata=/\.(toc|pub)$/i.test(entry.name);
        // WoW rewrites addon .pub keys at every login, often byte-for-byte.
        // Their content matters; a timestamp touch must not invalidate prefetch.
        hash.update(JSON.stringify([path.relative(base,file),stat.size,contentMetadata?null:stat.mtimeMs]));
        if (contentMetadata) hash.update(fs.readFileSync(file));
      }
    }
  }
  walk(base);
  const enabled = path.join(game,'WTF','Account',account,'AddOns.txt');
  if (fs.existsSync(enabled)) hash.update(fs.readFileSync(enabled));
  return hash.digest('hex');
}
export function validateAddonBlob(blob) {
  if (!Buffer.isBuffer(blob) || blob.length < 5 || blob.length > 65500) throw new Error('Invalid cached addon metadata.');
  const size = blob.readUInt32LE(0);
  if (size < 1 || size > 1024*1024) throw new Error('Invalid addon data size.');
  const raw = inflateSync(blob.subarray(4), { maxOutputLength: 1024*1024 });
  if (raw.length !== size) throw new Error('Addon metadata size mismatch.');
  let offset=0, count=0;
  while (offset < raw.length) {
    const end = raw.indexOf(0, offset);
    if (end <= offset || end-offset > 255 || end+10 > raw.length || ++count > 2000) throw new Error('Malformed addon metadata.');
    offset=end+10;
  }
  return blob;
}

// All account/session state is per launcher instance and per Windows profile.
// No session keys or passwords are serialized. The only cache is the client's
// exact, non-secret addon handshake, invalidated when its installation changes.
export class PreparedLogin {
  constructor({ root, game, account, password, url, token, report = () => {},
    open = mode => openRelayStream(url, mode, token), ttlMs = 90000 }) {
    this.root=root; this.game=game; this.account=account; this.password=password;
    this.url=url; this.token=token; this.report=report; this.open=open; this.ttlMs=ttlMs;
    this.listeners=[]; this.clients=new Set(); this.localKey=null; this.disposed=false;
    this.attached=false; this.expires=0; this.ready=false; this.world=null;
    this.fallback=false;this.fallbackStreams=new Set();this.started=false;
  }
  async prepare() {
    const began=performance.now();
    try {
      const auth = await authenticateWoW(await this.open('auth'), this.account, this.password);
      this.report('srp-verified', Math.round(performance.now()-began));
      const realm = auth.realms.find(r=>!(r.flags&3));
      if (!realm) { auth.key.fill(0); throw new Error('No ready realm.'); }
      this.realm=realm;
      this.fingerprint=addonFingerprint(this.game,this.account);
      let blob=null;
      try {
        const cache=readJson(path.join(this.root,'prepared-addon-info.json'),null);
        if (cache?.version===1 && cache.fingerprint===this.fingerprint && cache.game===this.game)
          blob=validateAddonBlob(Buffer.from(cache.blob,'base64'));
      } catch { /* Missing, malformed, or changed cache uses live addon data. */ }
      let worldStream;
      try { worldStream=await this.open('world'); }
      catch (error) { auth.key.fill(0); throw error; }
      this.world = new PreparedWorld({ account:this.account,key:auth.key,stream:worldStream,
        addons:blob, reopen:()=>this.open('world'),
        report:stage=>this.report(stage,Math.round(performance.now()-began)),
        saveAddonInfo:bytes=>{
          try {
            validateAddonBlob(bytes);
            writeJsonAtomic(path.join(this.root,'prepared-addon-info.json'),{
              version:1,game:this.game,fingerprint:this.fingerprint,blob:bytes.toString('base64'),
            });
          } catch { this.report('addon-cache-unavailable'); }
        },
      });
      this.world.once('disposed',()=>{
        if (this.ready && !this.attached) this.ready=false;
        if (this.started && !this.disposed) this.enableFallback();
      });
      await this.world.prepare();
      if (this.disposed) throw new Error('Prepared login cancelled.');
      this.expires=Date.now()+this.ttlMs; this.ready=true;
      this.expiry=setTimeout(()=>{ if (!this.attached) this.stop(); },this.ttlMs); this.expiry.unref();
      this.report(this.world.characterList?'session-and-characters-ready':'session-and-connection-ready',Math.round(performance.now()-began));
      return this;
    } catch (error) { await this.stop(); throw error; }
  }
  usable() { return this.ready && !this.disposed && !this.world?.disposed &&
    !this.world?.wire.io.failure && Date.now()<this.expires && !this.attached; }
  async start({ authPort=3724,worldPort=8085 }={}) {
    if (!this.usable()) throw new Error('Prepared login expired.');
    // Binding occurs only after Play. Opening the launcher never reserves the
    // game's local ports and never starts a WoW process.
    try {
      this.started=true;clearTimeout(this.expiry);this.expires=Date.now()+45000;
      this.expiry=setTimeout(()=>this.enableFallback(),45000);this.expiry.unref();
      const listen=async handler=>{
        const server=net.createServer(client=>{
          client.setNoDelay(true); this.clients.add(client);
          client.once('close',()=>this.clients.delete(client));
          client.on('error',()=>{}); handler(client);
        });
        this.listeners.push(server);
        return server;
      };
      const bind=(server,port)=>new Promise((resolve,reject)=>{
        server.once('error',reject); server.listen(port,'127.0.0.1',()=>{server.off('error',reject);resolve(server.address().port);});
      });
      const world=await listen(client=>{
        if(this.fallback){void this.forward(client,'world');return;}
        if (!this.localKey || this.attached || this.world.disposed) { client.destroy(); return; }
        this.attached=true; clearTimeout(this.expiry);
        void this.world.attach(client,this.localKey).catch(error=>this.report('client-session-ended: '+error.message))
          .finally(()=>{ if(!this.disposed)this.enableFallback(); });
      });
      this.worldPort=await bind(world,worldPort);
      let authBusy=false;
      const auth=await listen(client=>{
        if(this.fallback){void this.forward(client,'auth');return;}
        if (authBusy || this.attached || !this.usable()) {client.destroy();return;}
        authBusy=true;
        void localAuth(client,{ account:this.account,password:this.password,realm:this.realm,port:this.worldPort,
          onKey:key=>{ this.localKey?.fill(0);this.localKey=key; } })
          .catch(()=>{}).finally(()=>{authBusy=false;});
      });
      this.authPort=await bind(auth,authPort);
      return this;
    } catch(error) { await this.stop(); throw error; }
  }
  enableFallback() {
    if(this.disposed || this.fallback)return;
    this.fallback=true;this.ready=false;clearTimeout(this.expiry);
    this.world?.destroy();this.localKey?.fill(0);this.localKey=null;this.password='';
    for(const client of this.clients)client.destroy();
    this.report('standard-login-available');
  }
  async forward(client,mode) {
    client.pause();let remote;
    const close=()=>{client.destroy();remote?.destroy();if(remote)this.fallbackStreams.delete(remote);};
    client.once('error',close);client.once('close',close);
    try {
      remote=await this.open(mode);
      if(this.disposed || client.destroyed){remote.destroy();return;}
      this.fallbackStreams.add(remote);remote.once('error',close);remote.once('close',close);
      client.pipe(remote).pipe(client);
    }catch{close();}
  }
  async stop() {
    if (this.disposed) return; this.disposed=true;this.ready=false;clearTimeout(this.expiry);
    this.world?.destroy();this.localKey?.fill(0);this.localKey=null;this.password='';this.token='';
    for (const client of this.clients) client.destroy();this.clients.clear();
    for (const stream of this.fallbackStreams) stream.destroy();this.fallbackStreams.clear();
    await Promise.all(this.listeners.map(server=>new Promise(resolve=>{
      if (server.listening) server.close(resolve);else resolve();
    })));
    this.listeners=[];
  }
}
