import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import {spawnSync} from 'node:child_process';
import {digest,validateTask,verifyPackage,receive,publish,gitFailureSummary} from './runner.mjs';
const exec=(cwd,...args)=>{const r=spawnSync('git',['-c','core.hooksPath=','-c','commit.gpgSign=false','-c','core.autocrlf=false','-c','init.templateDir=',...args],{cwd,encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
function fixture(){
 const arch=/^(aarch64|arm64)$/i.test(os.machine())?'arm64':'amd64';
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'yime-exchange-'));const remote=path.join(root,'remote.git'),src=path.join(root,'src'),pkg=path.join(root,'package');fs.mkdirSync(src);fs.mkdirSync(pkg);exec(root,'init','--bare',remote);exec(remote,'config','uploadpack.allowFilter','true');exec(remote,'config','uploadpack.allowAnySHA1InWant','true');exec(src,'init','-b','queue');exec(src,'config','user.name','Test');exec(src,'config','user.email','test@example.invalid');exec(src,'remote','add','origin',remote);
 const exe=Buffer.alloc(128);exe.write('MZ');exe.writeUInt32LE(64,60);exe.write('PE\0\0',64);exe.writeUInt16LE(arch==='arm64'?0xaa64:0x8664,68);fs.writeFileSync(path.join(pkg,'YimeTouchKeyboard.exe'),exe);
 const manifest={sourceCommit:'a'.repeat(40),sourceChanges:false,architecture:'windows-'+arch,scope:'uninstalled-desktop-touch-keyboard-chinese-experiment',completeChineseResources:true,files:{'YimeTouchKeyboard.exe':digest(exe)}};const mb=JSON.stringify(manifest);fs.writeFileSync(path.join(pkg,'manifest.json'),mb);const zip=path.join(root,'fixture.zip');fs.writeFileSync(zip,'fixture-only-archive');
 const task={schemaVersion:1,id:'test-one',machine:'desktop',kind:'manual-test',expiresAt:'2099-01-01T00:00:00Z',package:{key:'fixture',architecture:arch,sourceCommit:'a'.repeat(40),runID:1,artifactID:2,zipSHA256:digest('fixture-only-archive'),zipBytes:20,manifestSHA256:digest(mb),executableSHA256:digest(exe),payloadCount:1},checks:['word-ni'],instructions:'Use a disposable document only.'};
 const q=path.join(src,'tasks/queue/desktop');fs.mkdirSync(q,{recursive:true});const taskFile=path.join(q,'test-one.json');fs.writeFileSync(taskFile,JSON.stringify(task));exec(src,'add','.');exec(src,'commit','-m','queue');exec(src,'push','origin','queue');
 const config={schemaVersion:1,machine:'desktop',hostname:os.hostname(),architecture:arch,remote,queueBranch:'queue',stateDir:path.join(root,'state'),packages:{fixture:{directory:pkg,zip}},authorName:'Test',authorEmail:'test@example.invalid'};
 return {root,remote,src,pkg,zip,task,taskFile,config,cleanup:()=>fs.rmSync(root,{recursive:true,force:true})};
}
test('reject arbitrary commands, paths, unsupported identity and duplicate cases',()=>{const f=fixture();try{assert.equal(validateTask(f.task),f.task);for(const mutation of [{command:'calc.exe'},{kind:'shell'},{id:'../oops'},{checks:['a','a']}])assert.throws(()=>validateTask({...f.task,...mutation}));}finally{f.cleanup();}});
test('static hashes and PE checked without launching anything',()=>{const f=fixture();try{assert.equal(verifyPackage(f.task,f.config.packages.fixture).executableStarted,false);fs.appendFileSync(path.join(f.pkg,'YimeTouchKeyboard.exe'),'x');assert.throws(()=>verifyPackage(f.task,f.config.packages.fixture),/Payload hash mismatch/);}finally{f.cleanup();}});
test('fetch, await human, review, append-only publish, idempotence',()=>{const f=fixture();try{
 const first=receive(f.config);assert.equal(first.outcomes[0].status,'awaiting-human');assert.equal(receive(f.config).outcomes[0].status,'already-received');
 const review=publish(f.config,'test-one');assert.equal(review.branch,'task-results/desktop');assert.equal(exec(f.src,'ls-remote','--heads','origin','refs/heads/task-results/desktop'),'');
 const p=publish(f.config,'test-one',{confirm:true});assert.equal(p.status,'published');assert.equal(publish(f.config,'test-one',{confirm:true}).status,'already-published');
 const file=path.join(f.config.stateDir,'tasks/test-one/result.json'),result=JSON.parse(fs.readFileSync(file));result.checks[0]={id:'word-ni',status:'pass',inputMethod:'mouse',actualText:'你',observation:'Disposable Word document, explicit binding. Manual observation.'};result.humanEvidence=true;fs.writeFileSync(file,JSON.stringify(result));assert.equal(publish(f.config,'test-one',{confirm:true}).status,'published');
 const names=exec(f.remote,'ls-tree','-r','--name-only','refs/heads/task-results/desktop').split('\n');assert.equal(names.length,2);assert.ok(names.every(n=>n.startsWith('results/desktop/test-one/')));
 result.package.sourceCommit='b'.repeat(40);fs.writeFileSync(file,JSON.stringify(result));assert.throws(()=>publish(f.config,'test-one'),/Immutable/);
 }finally{f.cleanup();}});
test('queue reusing same task ID with different content fails closed',()=>{const f=fixture();try{receive(f.config);f.task.instructions='Changed';fs.writeFileSync(f.taskFile,JSON.stringify(f.task));exec(f.src,'commit','-am','change');exec(f.src,'push','origin','queue');assert.throws(()=>receive(f.config),/reused/);}finally{f.cleanup();}});
test('wrong host and architecture are rejected',()=>{const f=fixture();try{assert.throws(()=>receive({...f.config,hostname:'not-this-machine'}),/Wrong host/);assert.throws(()=>receive({...f.config,architecture:f.config.architecture==='amd64'?'arm64':'amd64'}),/architecture/);}finally{f.cleanup();}});
test('missing package is blocked, expiry never verifies package',()=>{const f=fixture();try{const blocked=receive({...f.config,packages:{}});assert.equal(blocked.outcomes[0].status,'blocked');const expired=receive({...f.config,stateDir:path.join(f.root,'expired')},{now:Date.parse('2100-01-01')});assert.equal(expired.outcomes[0].status,'expired');}finally{f.cleanup();}});
test('lock is not stolen',()=>{const f=fixture();try{fs.mkdirSync(f.config.stateDir);fs.writeFileSync(path.join(f.config.stateDir,'runner.lock'),'unrelated');assert.throws(()=>receive(f.config),/lock exists/);assert.equal(fs.readFileSync(path.join(f.config.stateDir,'runner.lock'),'utf8'),'unrelated');}finally{f.cleanup();}});
test('static verify task does not claim physical pass',()=>{const f=fixture();try{f.task.kind='verify-package';fs.writeFileSync(f.taskFile,JSON.stringify(f.task));exec(f.src,'commit','-am','kind');exec(f.src,'push','origin','queue');assert.equal(receive(f.config).outcomes[0].status,'static-verified');const r=JSON.parse(fs.readFileSync(path.join(f.config.stateDir,'tasks/test-one/result.json')));assert.equal(r.physicalAcceptance,false);assert.equal(r.checks[0].status,'not-run');}finally{f.cleanup();}});
test('string schema rejects coercible arrays',()=>{const f=fixture();try{assert.throws(()=>validateTask({...f.task,id:['test-one']}));assert.throws(()=>validateTask({...f.task,package:{...f.task.package,zipSHA256:[f.task.package.zipSHA256]}}));}finally{f.cleanup();}});
test('blocked receipt cannot be promoted and manual pass needs human evidence',()=>{const f=fixture();try{
 receive({...f.config,packages:{}});let file=path.join(f.config.stateDir,'tasks/test-one/result.json'),r=JSON.parse(fs.readFileSync(file));r.checks[0]={id:'word-ni',status:'pass',inputMethod:'automated',actualText:'你',observation:'synthetic'};fs.writeFileSync(file,JSON.stringify(r));assert.throws(()=>publish(f.config,'test-one'),/Blocked\/expired/);
 const c={...f.config,stateDir:path.join(f.root,'second')};receive(c);file=path.join(c.stateDir,'tasks/test-one/result.json');r=JSON.parse(fs.readFileSync(file));r.checks[0]={id:'word-ni',status:'pass',inputMethod:'mouse',actualText:'你',observation:'manual'};fs.writeFileSync(file,JSON.stringify(r));assert.throws(()=>publish(c,'test-one'),/human evidence/);r.humanEvidence=true;r.checks[0].inputMethod='automated';fs.writeFileSync(file,JSON.stringify(r));assert.throws(()=>publish(c,'test-one'),/automated input/);
 }finally{f.cleanup();}});
test('abandoned staging directory does not mark task as received',()=>{const f=fixture();try{const abandoned=path.join(f.config.stateDir,'tasks/.staging-test-one-interrupted');fs.mkdirSync(abandoned,{recursive:true});fs.writeFileSync(path.join(abandoned,'receipt.json'),'partial');assert.equal(receive(f.config).outcomes[0].status,'awaiting-human');assert.equal(fs.readFileSync(path.join(abandoned,'receipt.json'),'utf8'),'partial');for(const file of ['receipt.json','task.json','result.json','NEXT.zh-CN.txt'])assert.ok(fs.existsSync(path.join(f.config.stateDir,'tasks/test-one',file)));}finally{f.cleanup();}});
test('manifest traversal and payload symlinks fail closed',()=>{const f=fixture();try{let p=path.join(f.pkg,'manifest.json');let m=JSON.parse(fs.readFileSync(p));m.files={'../outside':digest('x')};fs.writeFileSync(p,JSON.stringify(m));f.task.package.manifestSHA256=digest(fs.readFileSync(p));assert.throws(()=>verifyPackage(f.task,f.config.packages.fixture),/Unsafe relative path/);
 if(process.platform!=='win32'){m.files={'linked':digest('x')};fs.writeFileSync(p,JSON.stringify(m));f.task.package.manifestSHA256=digest(fs.readFileSync(p));fs.writeFileSync(path.join(f.root,'outside'),'x');fs.symlinkSync(path.join(f.root,'outside'),path.join(f.pkg,'linked'));assert.throws(()=>verifyPackage(f.task,f.config.packages.fixture),/Symlink/);}
 }finally{f.cleanup();}});
test('stored task tampering is rejected before publish',()=>{const f=fixture();try{receive(f.config);const p=path.join(f.config.stateDir,'tasks/test-one/task.json');const t=JSON.parse(fs.readFileSync(p));t.checks=['another-check'];fs.writeFileSync(p,JSON.stringify(t));assert.throws(()=>publish(f.config,'test-one'),/Stored task changed/);}finally{f.cleanup();}});

test('Git failures classify without disclosing raw stderr or credentials',()=>{
 const samples=[
  [{status:128,stderr:"fatal: could not read Username for 'https://alice:SECRET@github.com/x?token=SECRET': terminal prompts disabled"},'authentication'],
  [{status:null,error:{code:'ETIMEDOUT'},stderr:'private path SECRET'},'timeout'],
  [{status:128,stderr:'Could not resolve proxy: SECRET.proxy.invalid'},'proxy'],
  [{status:128,stderr:'SSL certificate problem for https://SECRET'},'tls-certificate'],
  [{status:128,stderr:"couldn't find remote ref SECRET"},'remote-ref-missing'],
  [{status:128,stderr:'Authorization: Bearer SECRET'},'unclassified']
 ];
 for(const [result,category] of samples){const message=gitFailureSummary('fetch',result);assert.ok(message.includes('category='+category));assert.ok(!message.includes('SECRET'));assert.ok(!message.includes('https://'));}
});

test('partial transport keeps history without unrelated blobs and preserves v1 state',()=>{const f=fixture();try{
 const big=Buffer.alloc(4*1024*1024,71);fs.writeFileSync(path.join(f.src,'unrelated-product.bin'),big);exec(f.src,'add','unrelated-product.bin');exec(f.src,'commit','-m','product blob');const blob=exec(f.src,'rev-parse','HEAD:unrelated-product.bin');exec(f.src,'push','origin','queue');
 const old=path.join(f.config.stateDir,'transport.git');fs.mkdirSync(old,{recursive:true});exec(old,'init','--bare');exec(old,'remote','add','origin',f.remote);fs.writeFileSync(path.join(old,'failed-evidence.txt'),'preserve');
 assert.equal(receive(f.config).outcomes[0].status,'awaiting-human');const repo=path.join(f.config.stateDir,'transport-partial-v2.git');
 assert.equal(exec(repo,'rev-parse','--is-shallow-repository'),'false');assert.equal(exec(repo,'config','--get','remote.origin.promisor'),'true');
 assert.ok(exec(repo,'rev-list','--objects','--all','--missing=print').split('\n').includes('?'+blob));assert.equal(fs.readFileSync(path.join(old,'failed-evidence.txt'),'utf8'),'preserve');
 }finally{f.cleanup();}});
test('partial transport rejects remote rewind without rewriting incoming',()=>{const f=fixture();try{
 const original=exec(f.src,'rev-parse','HEAD');receive(f.config);fs.writeFileSync(path.join(f.src,'note.txt'),'next');exec(f.src,'add','note.txt');exec(f.src,'commit','-m','next');exec(f.src,'push','origin','queue');receive(f.config);const repo=path.join(f.config.stateDir,'transport-partial-v2.git'),latest=exec(repo,'rev-parse','incoming');
 exec(f.src,'push','--force','origin',original+':refs/heads/queue');assert.throws(()=>receive(f.config),/Git operation failed: fetch/);assert.equal(exec(repo,'rev-parse','incoming'),latest);
 }finally{f.cleanup();}});
test('unsupported filtering never consumes queue tasks',()=>{const f=fixture();try{exec(f.remote,'config','uploadpack.allowFilter','false');assert.throws(()=>receive(f.config),/did not advertise protocol-v2 blob filtering/);assert.ok(!fs.existsSync(path.join(f.config.stateDir,'tasks/test-one/receipt.json')));assert.match(exec(path.join(f.config.stateDir,'transport-partial-v2.git'),'count-objects','-v'),/in-pack: 0/);}finally{f.cleanup();}});

test('migration requires previous v1 tip ancestry',()=>{const f=fixture();try{
 const old=path.join(f.config.stateDir,'transport.git');fs.mkdirSync(old,{recursive:true});exec(old,'init','--bare');exec(old,'remote','add','origin',f.remote);exec(old,'fetch','origin','queue:incoming');
 exec(f.src,'checkout','--orphan','replacement');exec(f.src,'commit','-am','new unrelated root');exec(f.src,'push','--force','origin','replacement:queue');
 assert.throws(()=>receive(f.config),/previous transport\/receipt anchor/);assert.ok(!fs.existsSync(path.join(f.config.stateDir,'tasks/test-one/receipt.json')));assert.ok(exec(old,'rev-parse','incoming'));
 }finally{f.cleanup();}});

test('result migration refuses missing previous remote result history',()=>{const f=fixture();try{
 receive(f.config);publish(f.config,'test-one',{confirm:true});const old=path.join(f.config.stateDir,'transport.git');fs.mkdirSync(old);exec(old,'init','--bare');exec(old,'remote','add','origin',f.remote);exec(old,'fetch','origin','refs/heads/task-results/desktop:refs/heads/results');
 exec(f.remote,'update-ref','-d','refs/heads/task-results/desktop');assert.throws(()=>publish(f.config,'test-one',{confirm:true}),/Previous results branch missing/);
 }finally{f.cleanup();}});
