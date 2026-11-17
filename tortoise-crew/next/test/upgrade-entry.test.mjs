import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
test('one-file upgrader reuses the bundled runtime when Node is not on PATH',t=>{
 if(process.platform!=='win32')return t.skip('Windows CMD entrypoint');
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'crew-portable-runtime-'));
 t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const local=path.join(root,'profile'),app=path.join(local,'TortoiseCrewNext');
 fs.mkdirSync(path.join(app,'app/src'),{recursive:true});fs.mkdirSync(path.join(app,'runtime'),{recursive:true});
 fs.writeFileSync(path.join(app,'app/src/main.mjs'),'// old launcher fixture');
 fs.copyFileSync(process.execPath,path.join(app,'runtime/node.exe'));
 const script=path.resolve('tortoise-crew/next/TortoiseCrew-Upgrade.cmd');
 const result=spawnSync('cmd.exe',['/d','/s','/c','call "'+script+'" --check'],{
  encoding:'utf8',windowsHide:true,windowsVerbatimArguments:true,timeout:15000,
  env:{...process.env,LOCALAPPDATA:local,ProgramFiles:path.join(root,'no-global-node'),PATH:path.join(process.env.WINDIR,'System32')},
 });
 assert.equal(result.status,0,result.stdout+'\n'+result.stderr);
 assert.match(result.stdout,/CREW_UPGRADE_READY/);
 assert(!fs.existsSync(path.join(app,'bootstrap.mjs')),'Check mode must not install, download or launch anything');
});
