#!/usr/bin/env node
// Trusted local runner. Remote Git content is DATA ONLY, never imported or executed.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const ID=/^[a-z0-9][a-z0-9-]{0,63}$/;
const SHA=/^[a-f0-9]{64}$/;
const COMMIT=/^[a-f0-9]{40}$/;
const matches=(pattern,value)=>typeof value==='string'&&pattern.test(value);
export const digest=b=>crypto.createHash('sha256').update(b).digest('hex');
const json=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const insist=(ok,msg)=>{if(!ok)throw new Error(msg);};
function keys(o,allowed){insist(o&&typeof o==='object'&&!Array.isArray(o),'Expected object'); for(const k of Object.keys(o))insist(allowed.includes(k),'Unknown field: '+k);}
function safeFile(root,rel){
  insist(typeof rel==='string'&&rel.length>0&&!rel.includes('\\')&&!rel.includes(':')&&!rel.startsWith('/')&&rel.split('/').every(p=>p&&p!=='.'&&p!=='..'),'Unsafe relative path');
  let p=path.resolve(root); for(const part of rel.split('/')){p=path.join(p,part); if(fs.existsSync(p))insist(!fs.lstatSync(p).isSymbolicLink(),'Symlink/reparse link rejected');}
  return p;
}
export function validateTask(t){
  keys(t,['schemaVersion','id','machine','kind','package','checks','instructions','expiresAt']);
  insist(t.schemaVersion===1&&matches(ID,t.id)&&matches(ID,t.machine),'Invalid task identity');
  insist(['verify-package','manual-test'].includes(t.kind),'Unsupported task kind');
  insist(typeof t.instructions==='string'&&t.instructions.length<=12000,'Invalid instructions');
  insist(Array.isArray(t.checks)&&t.checks.length>0&&t.checks.length<=30&&new Set(t.checks).size===t.checks.length&&t.checks.every(x=>matches(ID,x)),'Invalid checks');
  insist(typeof t.expiresAt==='string'&&Number.isFinite(Date.parse(t.expiresAt)),'Invalid expiry');
  const p=t.package; keys(p,['key','architecture','sourceCommit','runID','artifactID','zipSHA256','zipBytes','manifestSHA256','executableSHA256','payloadCount']);
  insist(matches(ID,p.key)&&['amd64','arm64'].includes(p.architecture)&&matches(COMMIT,p.sourceCommit),'Invalid package identity');
  for(const f of ['zipSHA256','manifestSHA256','executableSHA256'])insist(matches(SHA,p[f]),'Invalid digest: '+f);
  for(const f of ['runID','artifactID','zipBytes','payloadCount'])insist(Number.isSafeInteger(p[f])&&p[f]>0,'Invalid package number');
  return t;
}
export function verifyPackage(t,location){
  insist(location&&typeof location.directory==='string'&&typeof location.zip==='string','Package not mapped in local configuration');
  const root=path.resolve(location.directory); insist(!fs.lstatSync(root).isSymbolicLink(),'Linked package root rejected');
  const zip=fs.readFileSync(location.zip); insist(zip.length===t.package.zipBytes&&digest(zip)===t.package.zipSHA256,'ZIP size/hash mismatch');
  const raw=fs.readFileSync(safeFile(root,'manifest.json')); insist(digest(raw)===t.package.manifestSHA256,'Manifest hash mismatch');
  const m=JSON.parse(raw.toString('utf8').replace(/^\uFEFF/,''));
  insist(m.sourceCommit===t.package.sourceCommit&&m.sourceChanges===false&&m.architecture==='windows-'+t.package.architecture,'Manifest source/architecture mismatch');
  insist(m.scope==='uninstalled-desktop-touch-keyboard-chinese-experiment'&&m.completeChineseResources===true,'Not a complete isolated keyboard package');
  insist(m.files&&Object.keys(m.files).length===t.package.payloadCount,'Payload count mismatch');
  for(const [name,hash] of Object.entries(m.files)){insist(matches(SHA,hash),'Invalid payload digest'); insist(digest(fs.readFileSync(safeFile(root,name)))===hash,'Payload hash mismatch: '+name);}
  const exe=fs.readFileSync(safeFile(root,'YimeTouchKeyboard.exe'));
  insist(digest(exe)===t.package.executableSHA256,'Executable hash mismatch');
  insist(exe.length>=64&&exe.toString('ascii',0,2)==='MZ','Not a PE executable');
  const offset=exe.readUInt32LE(60); insist(offset+6<=exe.length&&exe.toString('ascii',offset,offset+4)==='PE\0\0','Invalid PE header');
  insist(exe.readUInt16LE(offset+4)===(t.package.architecture==='amd64'?0x8664:0xaa64),'PE architecture mismatch');
  return {zipSHA256:t.package.zipSHA256,manifestSHA256:t.package.manifestSHA256,executableSHA256:t.package.executableSHA256,payloadFiles:Object.keys(m.files).length,packageArchitecture:t.package.architecture,executableStarted:false,hardwareAcceptance:false};
}
function writeNew(p,value){fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,JSON.stringify(value,null,2)+'\n',{flag:'wx'});}
function git(repo,args,input){
  const r=spawnSync('git',['-c','core.hooksPath=',...args],{cwd:repo,input,encoding:'utf8',timeout:120000,maxBuffer:8*1024*1024,env:{...process.env,GIT_TERMINAL_PROMPT:'0'}});
  if(r.error||r.status!==0)throw new Error('Git operation failed: '+args[0]+' (inspect credentials/network locally; no automatic settings changes)');
  return r.stdout.trim();
}
function configCheck(c){
  keys(c,['schemaVersion','machine','hostname','architecture','remote','queueBranch','stateDir','packages','authorName','authorEmail']);
  insist(c.schemaVersion===1&&matches(ID,c.machine)&&typeof c.hostname==='string'&&['amd64','arm64'].includes(c.architecture),'Invalid local config');
  insist(c.hostname.toLowerCase()===os.hostname().toLowerCase(),'Wrong host: configure on intended machine');
  // OS architecture, not Node process architecture: x64 Node may run under ARM emulation.
  const native={x86_64:'amd64',AMD64:'amd64',amd64:'amd64',aarch64:'arm64',ARM64:'arm64',arm64:'arm64'}[os.machine()];
  insist(native===c.architecture,'Native OS architecture differs from local enrollment');
  insist(typeof c.remote==='string'&&c.remote.length>0&&!c.remote.startsWith('-'),'Invalid remote');
  insist(typeof c.queueBranch==='string'&&/^[a-zA-Z0-9][a-zA-Z0-9/_-]*$/.test(c.queueBranch)&&!c.queueBranch.includes('..'),'Invalid queue branch');
  insist(path.isAbsolute(c.stateDir),'stateDir must be absolute');
  insist(c.packages&&typeof c.packages==='object','Missing local package mapping');
}
function setup(c){
  configCheck(c); const state=path.resolve(c.stateDir); fs.mkdirSync(state,{recursive:true});
  insist(!fs.lstatSync(state).isSymbolicLink(),'Linked state directory rejected');
  const repo=path.join(state,'transport.git');
  if(!fs.existsSync(repo)){fs.mkdirSync(repo);git(repo,['init','--bare']);git(repo,['remote','add','origin',c.remote]);}
  insist(git(repo,['rev-parse','--is-bare-repository'])==='true'&&git(repo,['remote','get-url','origin'])===c.remote,'Transport identity mismatch');
  return {state,repo};
}
function lock(state,fn){const p=path.join(state,'runner.lock');let fd;try{fd=fs.openSync(p,'wx');}catch{throw new Error('Runner lock exists; stop other runner first. Do not auto-steal a stale lock.');}try{fs.writeFileSync(fd,String(process.pid));return fn();}finally{fs.closeSync(fd);fs.unlinkSync(p);}}
export function receive(c,{now=Date.now()}={}){
  const {state,repo}=setup(c); return lock(state,()=>{
    git(repo,['fetch','--no-tags','origin',`refs/heads/${c.queueBranch}:refs/heads/incoming`]);
    const commit=git(repo,['rev-parse','refs/heads/incoming']);
    const paths=git(repo,['ls-tree','-r','--name-only',commit,'--',`tasks/queue/${c.machine}/`]).split('\n').filter(Boolean);
    const outcomes=[];
    for(const file of paths){
      insist(new RegExp(`^tasks/queue/${c.machine}/[a-z0-9][a-z0-9-]{0,63}\\.json$`).test(file),'Unexpected queue file');
      const raw=git(repo,['show',`${commit}:${file}`]); insist(Buffer.byteLength(raw)<32768,'Task too large');
      const t=validateTask(JSON.parse(raw)); insist(t.machine===c.machine&&file.endsWith('/'+t.id+'.json'),'Task routing mismatch');
      insist(t.package.architecture===c.architecture,'Task architecture differs from local enrollment');
      const hash=digest(raw);const dir=path.join(state,'tasks',t.id), receipt=path.join(dir,'receipt.json');
      if(fs.existsSync(receipt)){insist(json(receipt).taskSHA256===hash,'Task ID reused with different data: '+t.id);outcomes.push({id:t.id,status:'already-received'});continue;}
      const base={schemaVersion:1,taskID:t.id,machine:c.machine,queueCommit:commit,taskSHA256:hash,receivedAt:new Date(now).toISOString(),package:t.package,host:{hostname:os.hostname(),platform:os.platform(),nodeArchitecture:process.arch,osMachine:os.machine()},physicalAcceptance:false};
      let status='awaiting-human',verification=null,reason=null;
      if(Date.parse(t.expiresAt)<=now){status='expired';reason='Task expired; publish a new task ID after review';}
      else try{verification=verifyPackage(t,c.packages[t.package.key]);status=t.kind==='verify-package'?'static-verified':'awaiting-human';}catch(e){status='blocked';reason=e.message;}
      // A receipt survives interruption. Repeats never auto-run or overwrite evidence.
      const staged=path.join(state,'tasks','.staging-'+t.id+'-'+crypto.randomUUID());
      writeNew(path.join(staged,'receipt.json'),{...base,status,verification,reason});fs.writeFileSync(path.join(staged,'task.json'),raw+'\n',{flag:'wx'});
      writeNew(path.join(staged,'result.json'),{...base,status,verification,reason,checks:t.checks.map(id=>({id,status:'not-run',inputMethod:null,actualText:null,observation:null})),humanEvidence:false});
      fs.writeFileSync(path.join(staged,'NEXT.zh-CN.txt'),`任务 ${t.id}\n状态 ${status}\n${t.instructions}\n\n只填写 result.json 的 checks；未执行保留 not-run。静态通过不是实机验收。先 review，再明确 publish 回传。\n`,{flag:'wx'});
      fs.renameSync(staged,dir);
      outcomes.push({id:t.id,status});
    }
    return {queueCommit:commit,outcomes};
  });
}
function resultForPublish(c,id,state){
  insist(matches(ID,id),'Invalid task ID');const dir=path.join(state,'tasks',id);const receipt=json(path.join(dir,'receipt.json'));const taskRaw=fs.readFileSync(path.join(dir,'task.json'),'utf8').trim();insist(digest(taskRaw)===receipt.taskSHA256,'Stored task changed');const task=validateTask(JSON.parse(taskRaw));insist(task.id===id&&task.machine===c.machine&&receipt.machine===c.machine,'Stored routing changed');const result=json(path.join(dir,'result.json'));
  keys(result,['schemaVersion','taskID','machine','queueCommit','taskSHA256','receivedAt','package','host','physicalAcceptance','status','verification','reason','checks','humanEvidence']);
  for(const field of ['schemaVersion','taskID','machine','queueCommit','taskSHA256','receivedAt','package','host','verification','reason'])insist(JSON.stringify(result[field])===JSON.stringify(receipt[field]),'Immutable receipt field changed: '+field);
  insist(result.physicalAcceptance===false,'Do not claim complete physical acceptance in task transport');
  insist(result.status===receipt.status,'Transport status cannot be rewritten as test pass');
  insist(Array.isArray(result.checks)&&result.checks.length===task.checks.length,'Check set changed');
  result.checks.forEach((r,i)=>{keys(r,['id','status','inputMethod','actualText','observation']);insist(r.id===task.checks[i]&&['not-run','pass','fail','blocked','skipped'].includes(r.status),'Invalid check');for(const k of ['inputMethod','actualText','observation'])insist(r[k]===null||(typeof r[k]==='string'&&r[k].length<=4000),'Invalid evidence text');if(r.status!=='not-run')insist(typeof r.observation==='string'&&r.observation.trim().length>0,'Executed/skipped check requires observation');if(['pass','fail'].includes(r.status))insist(['mouse','finger','pen','keyboard','observation','automated'].includes(r.inputMethod),'Input method required');});
  insist(typeof result.humanEvidence==='boolean','Invalid humanEvidence');
  if(['blocked','expired'].includes(receipt.status))insist(result.checks.every(r=>r.status==='not-run')&&!result.humanEvidence,'Blocked/expired tasks cannot report execution; publish a new task ID');
  if(task.kind==='manual-test'&&result.checks.some(r=>['pass','fail'].includes(r.status))){
    insist(result.humanEvidence===true,'Manual checks require human evidence');
    insist(result.checks.every(r=>!['pass','fail'].includes(r.status)||r.inputMethod!=='automated'),'Manual acceptance cannot use simulated/automated input');
  }
  const encoded=JSON.stringify(result,null,2)+'\n';insist(encoded.length<=100000,'Result too large');return encoded;
}
export function publish(c,id,{confirm=false}={}){
  const {state,repo}=setup(c);return lock(state,()=>{
    const body=resultForPublish(c,id,state);const branch=`task-results/${c.machine}`;const relative=`results/${c.machine}/${id}/${digest(body)}.json`;
    if(!confirm)return {branch,path:relative,body,action:'review-only; use --confirm to push this result'};
    insist(typeof c.authorName==='string'&&c.authorName.trim()&&typeof c.authorEmail==='string'&&c.authorEmail.includes('@'),'Set result commit author locally');
    // A fresh temporary index builds only a result tree, never stages the user's checkout.
    const refs=git(repo,['ls-remote','--heads','origin',`refs/heads/${branch}`]);let parent=null;
    if(refs){git(repo,['fetch','--no-tags','origin',`refs/heads/${branch}:refs/heads/results`]);parent=git(repo,['rev-parse','refs/heads/results']);}
    const index=path.join(state,'publish-index-'+crypto.randomUUID());const env={...process.env,GIT_INDEX_FILE:index,GIT_AUTHOR_NAME:c.authorName,GIT_AUTHOR_EMAIL:c.authorEmail,GIT_COMMITTER_NAME:c.authorName,GIT_COMMITTER_EMAIL:c.authorEmail,GIT_TERMINAL_PROMPT:'0'};
    function plumbing(args,input){const r=spawnSync('git',['-c','core.hooksPath=',...args],{cwd:repo,input,encoding:'utf8',env,timeout:120000});if(r.error||r.status!==0)throw new Error('Result Git operation failed; local evidence retained, never force-push');return r.stdout.trim();}
    try{
      if(parent)plumbing(['read-tree',parent]);else plumbing(['read-tree','--empty']);
      const blob=plumbing(['hash-object','-w','--stdin'],body);plumbing(['update-index','--add','--cacheinfo',`100644,${blob},${relative}`]);const tree=plumbing(['write-tree']);
      if(parent&&git(repo,['rev-parse',`${parent}^{tree}`])===tree)return {status:'already-published',branch,path:relative};
      const commit=plumbing(['commit-tree',tree,...(parent?['-p',parent]:[])],`test(exchange): record ${c.machine} ${id}\n`);
      plumbing(['push','origin',`${commit}:refs/heads/${branch}`]);
      insist(git(repo,['ls-remote','--heads','origin',`refs/heads/${branch}`]).split(/\s/)[0]===commit,'Push outcome needs verification');
      return {status:'published',branch,commit,path:relative};
    }finally{if(fs.existsSync(index))fs.unlinkSync(index);}
  });
}
export async function main(argv){
  const [command,configPath,...rest]=argv;insist(['once','watch','publish'].includes(command)&&configPath,'Usage: node runner.mjs once|watch|publish LOCAL-CONFIG.json [TASK-ID --confirm | --interval 60 --minutes 30]');
  const c=json(configPath);
  if(command==='publish'){insist(rest.length>=1&&rest.every((x,i)=>i===0||x==='--confirm'),'Unknown publish option');console.log(JSON.stringify(publish(c,rest[0],{confirm:rest.includes('--confirm')}),null,2));return;}
  if(command==='once'){insist(rest.length===0,'Unknown once option');console.log(JSON.stringify(receive(c),null,2));return;}
  const opts=Object.fromEntries(Array.from({length:rest.length/2},(_,i)=>[rest[i*2],Number(rest[i*2+1])]));insist(rest.length%2===0&&Object.keys(opts).every(k=>['--interval','--minutes'].includes(k)),'Unknown watch options');
  const interval=opts['--interval']??60, minutes=opts['--minutes']??30;insist(Number.isInteger(interval)&&interval>=30&&interval<=3600&&Number.isInteger(minutes)&&minutes>=1&&minutes<=480,'Watch bounds: interval 30–3600 seconds, duration 1–480 minutes');
  const until=Date.now()+minutes*60000;do{console.log(JSON.stringify(receive(c)));if(Date.now()+interval*1000>=until)break;await new Promise(r=>setTimeout(r,interval*1000));}while(Date.now()<until);
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2)).catch(e=>{console.error(e.message);process.exitCode=1;});
