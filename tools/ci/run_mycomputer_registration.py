"""Explicit, bounded stage-3 orchestration; no automatic recovery or replay.

This file is only a developer implementation. Shipping it does not authorize
registration. Hash-bound local evidence is not protection from a malicious peer
already operating as the same Windows user.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys

V2='mycomputer-activation-development-package-v2'
REGISTER_CONFIRM='once-mycomputer-register-and-cleanup'
RECOVER_CONFIRM='once-mycomputer-recover-owned-registration'
HEX=re.compile(r'[0-9a-f]{64}\Z')
EXE='YimeMyComputerActivationStage1.exe'
DLL='YimeTextService18u.dll'


def require(ok,reason):
    if not ok: raise ValueError(reason)


def unique(pairs):
    out={}
    for key,value in pairs:
        require(key not in out,'duplicate JSON key');out[key]=value
    return out


def read_bytes(path,limit=1024*1024):
    require(not path.is_symlink() and not getattr(path.stat(),'st_file_attributes',0)&0x400,'reparse evidence rejected')
    with path.open('rb') as stream: data=stream.read(limit+1)
    require(len(data)<=limit,'evidence size limit')
    return data


def read_json(path):return json.loads(read_bytes(path).decode('utf-8-sig'),object_pairs_hook=unique)
def sha(data):return hashlib.sha256(data).hexdigest()


def save(path,value):
    temporary=path.with_name(path.name+'.tmp')
    with temporary.open('x',encoding='utf-8') as stream:
        json.dump(value,stream,ensure_ascii=True,indent=2);stream.write('\n');stream.flush();os.fsync(stream.fileno())
    os.replace(temporary,path)


def load_module(path,name):
    sys.dont_write_bytecode=True
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def package_context(package,anchor):
    package=Path(package).absolute()
    require(isinstance(anchor,str) and HEX.fullmatch(anchor),'independent manifest SHA required')
    raw=read_bytes(package/'manifest.json');require(sha(raw)==anchor,'manifest hash mismatch')
    manifest=json.loads(raw.decode('utf-8'),object_pairs_hook=unique)
    require(manifest.get('schema')==V2,'stage3 requires v2 package')
    # Check bytes before importing any adjacent helper, not merely afterwards.
    rows=manifest.get('files');require(isinstance(rows,list) and len(rows)==7,'v2 payload count')
    files={}
    for row in rows:
        require(isinstance(row,dict),'payload row')
        name=row.get('path');require(isinstance(name,str) and re.fullmatch(r'[A-Za-z0-9_.-]+',name) and name not in files,'payload name')
        data=read_bytes(package/name,128*1024*1024)
        require(type(row.get('bytes')) is int and len(data)==row['bytes'] and sha(data)==row.get('sha256'),'payload hash mismatch')
        files[name]=row
    require(set(files)=={EXE,DLL,'README.zh-CN.md','collect_mycomputer_preflight.py','windows_job_once.py','run_mycomputer_registration.py','validate_local_activation_evidence.py'},'fixed v2 payload set')
    package=package.resolve(strict=True)
    require(Path(__file__).resolve()==package/'run_mycomputer_registration.py','run the pinned package orchestrator')
    collector=load_module(package/'collect_mycomputer_preflight.py','stage3_pinned_collector')
    collector.validate_package(package,anchor)
    return package,manifest,files,load_module(package/'windows_job_once.py','stage3_pinned_job'),load_module(package/'validate_local_activation_evidence.py','stage3_pinned_gate')


def fresh_directory(path,excluded):
    path=Path(path).absolute();require(not path.is_symlink(),'evidence symlink')
    resolved=path.resolve(strict=False)
    for root in excluded:
        require(resolved!=root and root not in resolved.parents,'evidence must be outside protected directory')
    resolved.mkdir(parents=False,exist_ok=False)
    return resolved


def valid_root(root):
    return isinstance(root,dict) and set(root)=={'pid','creationFileTime'} and type(root['pid']) is int and 0<root['pid']<=0xffffffff and isinstance(root['creationFileTime'],str) and re.fullmatch(r'[1-9][0-9]{0,19}',root['creationFileTime']) and int(root['creationFileTime'])<=0xffffffffffffffff


def completed(process,exit_code):
    return isinstance(process,dict) and process.get('started') is True and process.get('treeStopped') is True and process.get('timedOut') is False and process.get('errorCode') is None and type(process.get('exitCode')) is int and process['exitCode']==exit_code


def evidence_file(path):
    data=read_bytes(path,4*1024*1024)
    return {'path':path.name,'bytes':len(data),'sha256':sha(data)}


def invoke(runner,command,directory,prefix,timeout,callback=None):
    kwargs={'on_root_created':callback} if callback is not None else {}
    state=runner(command,directory,directory/(prefix+'-stdout.txt'),directory/(prefix+'-stderr.txt'),timeout,**kwargs)
    save(directory/(prefix+'-process.json'),state)
    return state


def register(package,evidence,anchor,confirmation,timeout=30,runner=None):
    require(confirmation==REGISTER_CONFIRM,'explicit register confirmation required')
    require(type(timeout) is int and 1<=timeout<=120,'timeout must be 1..120')
    package,manifest,files,job,gate=package_context(package,anchor)
    directory=fresh_directory(evidence,[package]);ledger_dir=directory/'ledger';ledger_dir.mkdir()
    ledger=ledger_dir/'registration-ledger.dpapi'
    receipt={'schema':'mycomputer-registration-run-v1','mode':'register-once','status':'incomplete',
             'manifestSha256':anchor,'sourceCommit':manifest['sourceCommit'],'exeSha256':files[EXE]['sha256'],
             'dllSha256':files[DLL]['sha256'],'ledgerPath':str(ledger),'rootIdentity':None,'process':None,
             'stdout':None,'stderr':None,'ledgerSha256':None,'automaticRecoveryAttempted':False,
             'activationEvidenceConsistent':False,'sourceAuthenticityVerified':False}
    receipt_path=directory/'registration.json';save(receipt_path,receipt)
    def root_created(root):
        require(valid_root(root) and receipt['rootIdentity'] is None,'invalid/repeated root identity')
        receipt['rootIdentity']=dict(root);save(receipt_path,receipt)
    runner=runner or job.run_once
    try:
        process=invoke(runner,[str(package/EXE),'--register-once','--dll',str(package/DLL),'--sha256',files[DLL]['sha256'],'--ledger',str(ledger)],directory,'register',timeout,root_created)
        receipt['process']=process
        receipt['stdout']=evidence_file(directory/'register-stdout.txt');receipt['stderr']=evidence_file(directory/'register-stderr.txt')
        require(valid_root(receipt['rootIdentity']) and process.get('rootIdentity')==receipt['rootIdentity'],'root receipt mismatch')
        if process.get('treeStopped') is True and ledger.is_file():receipt['ledgerSha256']=sha(read_bytes(ledger,65536))
        receipt['status']='failed-or-inconclusive'
        if completed(process,4):
            verify=invoke(runner,[str(package/EXE),'--verify'],directory,'verify',timeout)
            if completed(verify,0):
                result=gate.validate(read_bytes(directory/'register-stdout.txt').decode('utf-8-sig'),read_bytes(directory/'register-stderr.txt').decode('utf-8-sig'),4,
                                     read_bytes(directory/'verify-stdout.txt').decode('utf-8-sig'),read_bytes(directory/'verify-stderr.txt').decode('utf-8-sig'),0,files[DLL]['sha256'])
                save(directory/'activation-evidence.json',result)
                receipt['activationEvidenceConsistent']=True;receipt['status']='activation-and-cleanup-evidence-consistent'
    except (OSError,ValueError,TypeError,KeyError) as error:
        receipt['status']='failed-or-inconclusive';receipt['failureReason']=str(error)[:200]
    finally:save(receipt_path,receipt)
    return receipt

INSPECT_FIELDS={'schema','scope','status','stage','code','ledgerSha256','ownerPid','ownerCreationTime','dllSha256','bindingVerified','ownerDeadVerified','ownedScopeVerified','cleanupVerified','flags','recoveryRequired','residueShape','recoveryToolCapable'}
LEDGER_FLAGS={'preflightAbsent','comAttempted','comOwned','profileAttempted','categoryAttempted','enableAttempted','activationAttempted','cleanupVerified'}
RESIDUE_SHAPES={'absent','owned-empty-shell','not-owned'}
SNAPSHOT_FIELDS={'schema','scope','status','stage','code','ledgerSha256','dllSha256','residueShape','entries'}


def validate_inspection(data,receipt,ledger_hash):
    require(isinstance(data,dict) and set(data)==INSPECT_FIELDS,'inspection fields')
    require(data['schema']=='mycomputer-recovery-inspection-v1' and data['scope']=='readonly-recovery-ownership' and data['status']=='verified' and data['stage']=='completed' and type(data['code']) is int and data['code']==0,'inspection incomplete')
    for flag in ('bindingVerified','ownerDeadVerified','ownedScopeVerified'):require(data[flag] is True,'inspection ownership unproven')
    require(data['ledgerSha256']==ledger_hash and data['dllSha256']==receipt['dllSha256'],'inspection hash mismatch')
    root=receipt['rootIdentity']
    require(type(data['ownerPid']) is int and data['ownerPid']==root['pid'] and type(data['ownerCreationTime']) is int and data['ownerCreationTime']==int(root['creationFileTime']),'inspection original owner mismatch')
    require(type(data['cleanupVerified']) is bool and type(data['recoveryRequired']) is bool and type(data['recoveryToolCapable']) is bool,'inspection bool fields')
    require(data['residueShape'] in RESIDUE_SHAPES,'inspection residue shape')
    flags=data['flags'];require(isinstance(flags,dict) and set(flags)==LEDGER_FLAGS and all(type(value) is bool for value in flags.values()),'inspection ledger flags')
    require(data['cleanupVerified']==flags['cleanupVerified'],'inspection cleanup contradiction')
    require(not data['recoveryRequired'] or flags['comAttempted'] and flags['comOwned'] and not flags['cleanupVerified'],'inspection recovery contradiction')
    # The tool itself decides capability; the orchestrator only refuses contradictions.
    require(data['recoveryToolCapable']==(data['residueShape'] in ('absent','owned-empty-shell')),'inspection capability contradiction')
    require(not data['recoveryRequired'] or data['recoveryToolCapable'],'recovery tool cannot clear residue shape '+data['residueShape']+'; engineering review required')
    return data['recoveryRequired']


def validate_snapshot(data,inspection,ledger_hash):
    require(isinstance(data,dict) and set(data)==SNAPSHOT_FIELDS,'snapshot fields')
    require(data['schema']=='mycomputer-residue-snapshot-v1' and data['scope']=='readonly-owned-residue-snapshot' and data['status']=='captured' and data['stage']=='completed' and type(data['code']) is int and data['code']==0,'snapshot incomplete')
    require(data['ledgerSha256']==ledger_hash and data['dllSha256']==inspection['dllSha256'] and data['residueShape']==inspection['residueShape'],'snapshot binding mismatch')
    entries=data['entries'];require(isinstance(entries,list) and len(entries)<=256,'snapshot entries')
    for entry in entries:
        require(isinstance(entry,dict) and set(entry)=={'hive','view','path','subkeys','values'},'snapshot entry fields')
        require(entry['hive'] in ('HKLM','HKCU') and entry['view'] in ('32','64') and isinstance(entry['path'],str),'snapshot entry identity')
        require(isinstance(entry['subkeys'],list) and all(isinstance(name,str) for name in entry['subkeys']),'snapshot subkeys')
        for value in entry['values']:
            # Value names, types, lengths and hashes only; data itself must never appear.
            require(isinstance(value,dict) and set(value)=={'name','type','bytes','sha256'} and isinstance(value['name'],str) and type(value['type']) is int and type(value['bytes']) is int and isinstance(value['sha256'],str) and HEX.fullmatch(value['sha256']),'snapshot value record')


def registration_binding_allowed(receipt,manifest,files,anchor):
    """Same package, or a registration explicitly pinned by this package's manifest.

    A pinned record binds the original package's manifest, source, tool and DLL hashes.
    The native tool separately re-opens and hash-checks the DLL at the ledger's path."""
    current=(receipt.get('manifestSha256'),receipt.get('sourceCommit'),receipt.get('exeSha256'),receipt.get('dllSha256'))
    if current==(anchor,manifest['sourceCommit'],files[EXE]['sha256'],files[DLL]['sha256']):return 'same-package'
    rows=manifest.get('recoverableRegistrations')
    require(isinstance(rows,list) and rows,'original package binding mismatch')
    for row in rows:
        require(isinstance(row,dict) and set(row)=={'manifestSha256','sourceCommit','exeSha256','dllSha256'} and all(isinstance(row[k],str) for k in row),'recoverable registration record')
        require(HEX.fullmatch(row['manifestSha256']) and re.fullmatch(r'[0-9a-f]{40}',row['sourceCommit']) and HEX.fullmatch(row['exeSha256']) and HEX.fullmatch(row['dllSha256']),'recoverable registration identity')
        require(row['exeSha256']!=files[EXE]['sha256'],'recoverable registration must name an older tool')
        if current==(row['manifestSha256'],row['sourceCommit'],row['exeSha256'],row['dllSha256']):return 'pinned-older-package'
    raise ValueError('original package binding mismatch')


def recover(package,original_evidence,evidence,anchor,confirmation,timeout=30,runner=None):
    require(confirmation==RECOVER_CONFIRM,'separate explicit recovery confirmation required')
    require(type(timeout) is int and 1<=timeout<=120,'timeout must be 1..120')
    package,manifest,files,job,gate=package_context(package,anchor)
    original=Path(original_evidence).resolve(strict=True)
    require(original!=package and package not in original.parents,'original evidence inside package')
    receipt=read_json(original/'registration.json')
    require(receipt.get('schema')=='mycomputer-registration-run-v1' and receipt.get('mode')=='register-once','original registration receipt required')
    binding=registration_binding_allowed(receipt,manifest,files,anchor)
    process=receipt.get('process');root=receipt.get('rootIdentity')
    require(valid_root(root) and isinstance(process,dict) and process.get('rootIdentity')==root and process.get('started') is True and process.get('treeStopped') is True,'original process tree not proven stopped; manual engineering review required')
    require(read_json(original/'register-process.json')==process,'original process receipt mismatch')
    require(type(process.get('exitCode')) is int and type(process.get('timedOut')) is bool and process.get('errorCode') is None,'original process receipt incomplete')
    for field in ('stdout','stderr'):
        expected=receipt.get(field);require(isinstance(expected,dict) and expected.get('path')=='register-'+field+'.txt','original log binding')
        require(evidence_file(original/expected['path'])==expected,'original log hash mismatch')
    ledger=original/'ledger'/'registration-ledger.dpapi'
    require(receipt.get('ledgerPath')==str(ledger),'original ledger location mismatch')
    ledger_hash=sha(read_bytes(ledger,65536));require(receipt.get('ledgerSha256')==ledger_hash,'original ledger changed or checkpoint missing')
    claim=original/'recovery-claim.json'
    require(not claim.exists(),'recovery already claimed for this registration; manual engineering review required')
    directory=fresh_directory(evidence,[package,original])
    result={'schema':'mycomputer-recovery-run-v1','status':'incomplete','originalEvidence':str(original),
            'manifestSha256':anchor,'originalLedgerSha256':ledger_hash,'packageBinding':binding,'recoveryInvocations':0,
            'claimCreated':False,'residueShape':None,'cleanupEvidenceConsistent':False,'activationEvidenceConsistent':False,'sourceAuthenticityVerified':False}
    save(directory/'recovery.json',result);runner=runner or job.run_once
    try:
        # Read-only inspection runs before any claim so an incapable tool or foreign
        # residue refuses here without consuming the single recovery opportunity.
        inspection=invoke(runner,[str(package/EXE),'--inspect-recovery','--ledger',str(ledger),'--expected-ledger-sha256',ledger_hash],directory,'inspect',timeout)
        require(completed(inspection,0),'inspection process incomplete')
        require(not read_bytes(directory/'inspect-stderr.txt').strip(),'inspection stderr')
        inspected=read_json(directory/'inspect-stdout.txt')
        required=validate_inspection(inspected,receipt,ledger_hash);result['residueShape']=inspected['residueShape']
        require(sha(read_bytes(ledger,65536))==ledger_hash,'ledger changed after inspection')
        if required:
            # A persistent claim is consumed even on later failure. Never delete it or
            # silently replay a recovery after a partial mutation or uncertain outcome.
            with claim.open('x',encoding='utf-8') as stream:
                json.dump({'schema':'mycomputer-recovery-claim-v1','evidence':str(directory),'ledgerSha256':ledger_hash},stream)
                stream.flush();os.fsync(stream.fileno())
            result['claimCreated']=True;save(directory/'recovery.json',result)
            snapshot=invoke(runner,[str(package/EXE),'--snapshot-residue','--ledger',str(ledger),'--expected-ledger-sha256',ledger_hash],directory,'snapshot',timeout)
            require(completed(snapshot,0),'residue snapshot process incomplete')
            require(not read_bytes(directory/'snapshot-stderr.txt').strip(),'residue snapshot stderr')
            validate_snapshot(read_json(directory/'snapshot-stdout.txt'),inspected,ledger_hash)
            require(sha(read_bytes(ledger,65536))==ledger_hash,'ledger changed after snapshot')
            result['recoveryInvocations']=1;save(directory/'recovery.json',result)
            cleanup=invoke(runner,[str(package/EXE),'--recover','--ledger',str(ledger),'--expected-ledger-sha256',ledger_hash],directory,'recover',timeout)
            require(completed(cleanup,0),'recovery process incomplete')
            require(not read_bytes(directory/'recover-stderr.txt').strip(),'recovery stderr')
            report=gate.report(read_bytes(directory/'recover-stdout.txt').decode('utf-8-sig'))
            require(report['mode']=='recover' and report['status']=='pass' and report['cleanupVerified'] is True,'recovery not verified')
        verify=invoke(runner,[str(package/EXE),'--verify'],directory,'verify',timeout)
        require(completed(verify,0),'independent verify process incomplete')
        require(not read_bytes(directory/'verify-stderr.txt').strip(),'verify stderr')
        gate.validate_absence(read_bytes(directory/'verify-stdout.txt').decode('utf-8-sig'),read_bytes(directory/'verify-stderr.txt').decode('utf-8-sig'),0)
        result['cleanupEvidenceConsistent']=True
        result['status']='recovery-and-absence-evidence-consistent' if required else 'already-absent-evidence-consistent'
    except (OSError,ValueError,TypeError,KeyError) as error:
        result['status']='failed-or-inconclusive';result['failureReason']=str(error)[:200]
    finally:save(directory/'recovery.json',result)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    sub=parser.add_subparsers(dest='mode',required=True)
    for mode in ('register','recover'):
        command=sub.add_parser(mode)
        for name in ('package','evidence'):command.add_argument('--'+name,type=Path,required=True)
        command.add_argument('--manifest-sha256',required=True)
        command.add_argument('--confirm',required=True)
        command.add_argument('--timeout-seconds',type=int,default=30)
        if mode=='recover':command.add_argument('--original-evidence',type=Path,required=True)
    args=parser.parse_args()
    try:
        if args.mode=='register':result=register(args.package,args.evidence,args.manifest_sha256,args.confirm,args.timeout_seconds)
        else:result=recover(args.package,args.original_evidence,args.evidence,args.manifest_sha256,args.confirm,args.timeout_seconds)
    except (OSError,ValueError,TypeError,KeyError) as error:
        print(json.dumps({'status':'refused','reason':str(error),'automaticRecoveryAttempted':False}));return 1
    print(json.dumps(result))
    return 0 if result.get('activationEvidenceConsistent') or result.get('cleanupEvidenceConsistent') else 1


if __name__=='__main__':sys.exit(main())
