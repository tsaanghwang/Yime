"""Build an isolated x64 activation-development ZIP; never execute its payload."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import stat
import struct
import zipfile

PE_NAMES=('YimeTextService18u.dll','YimeMyComputerActivationStage1.exe')
SCRIPT_NAMES=('collect_mycomputer_preflight.py','windows_job_once.py')
V2_SCRIPT_NAMES=('run_mycomputer_registration.py','validate_local_activation_evidence.py')
PRODUCT_IDENTITY={'product':'YimeCore18uTouch','clsid':'6DFACE1F-562E-4773-A9D6-D5753A314711',
                  'profile':'1BD904AC-3194-4419-B70A-5574100F18B3','languageId':'0x0804'}
SIGNATURE_STATUSES={'Valid','UnknownError','NotSigned','HashMismatch','NotTrusted','NotSupportedFileFormat','Incompatible'}


def require(condition,message):
    if not condition: raise ValueError(message)


def digest(data): return hashlib.sha256(data).hexdigest()


def read_file(path,limit):
    path=Path(path)
    require(not path.is_symlink() and stat.S_ISREG(path.stat().st_mode),'regular non-symlink file required')
    with path.open('rb') as stream: data=stream.read(limit+1)
    require(0<len(data)<=limit,'input size out of bounds')
    return data


def pe_identity(data,is_dll):
    require(len(data)>=64 and data[:2]==b'MZ','invalid DOS header')
    offset=struct.unpack_from('<I',data,60)[0]
    require(offset>=64 and offset+24<=len(data) and data[offset:offset+4]==b'PE\0\0','invalid PE header')
    machine,sections,_,_,_,optional_bytes,flags=struct.unpack_from('<HHIIIHH',data,offset+4)
    require(machine==0x8664 and bool(flags&0x2000)==is_dll and bool(flags&2),'not expected AMD64 executable kind')
    require(sections>0 and optional_bytes>=112 and offset+24+optional_bytes+sections*40<=len(data),'truncated PE tables')
    require(struct.unpack_from('<H',data,offset+24)[0]==0x20b,'not PE32+')
    return {'machine':'AMD64','machineCode':'0x8664','format':'PE32+','dll':is_dll}


def unique_json(data):
    def unique(pairs):
        result={}
        for key,value in pairs:
            require(key not in result,'duplicate JSON key');result[key]=value
        return result
    return json.loads(data.decode('utf-8-sig'),object_pairs_hook=unique)


def signatures(data,payload):
    value=unique_json(data)
    require(isinstance(value,dict) and set(value)=={'schema','files'} and value['schema']=='mycomputer-authenticode-v1','signature schema')
    rows=value['files'];require(isinstance(rows,list) and len(rows)==2,'two signature records required')
    result={}
    for row in rows:
        require(isinstance(row,dict) and set(row)=={'name','sha256','status','signerCertificateThumbprint','timestampCertificateThumbprint'},'signature fields')
        name=row['name'];require(isinstance(name,str) and name in PE_NAMES and name not in result,'signature filename')
        require(row['sha256']==digest(payload[name]),'signature hash mismatch')
        require(isinstance(row['status'],str) and row['status'] in SIGNATURE_STATUSES,'signature status')
        for field in ('signerCertificateThumbprint','timestampCertificateThumbprint'):
            require(row[field] is None or isinstance(row[field],str) and re.fullmatch('[0-9A-Fa-f]{40}',row[field]),'certificate thumbprint')
        require(row['status']!='Valid' or row['signerCertificateThumbprint'] is not None,'Valid signature lacks signer')
        require(row['status']!='NotSigned' or row['signerCertificateThumbprint'] is None and row['timestampCertificateThumbprint'] is None,'NotSigned contradicts certificate')
        result[name]=row
    require(set(result)==set(PE_NAMES),'missing signature')
    return result


def recoverable_registrations(path):
    """Reviewed older registrations this package may recover. The native tool still opens
    and hash-checks the DLL at the ledger's original path; the shipped DLL is not reused."""
    if path is None:return []
    value=json.loads(read_file(path,65536).decode('utf-8'))
    require(isinstance(value,dict) and set(value)=={'schema','registrations'} and value['schema']=='mycomputer-recoverable-registrations-v1','recoverable registrations schema')
    rows=value['registrations'];require(isinstance(rows,list) and 0<len(rows)<=8,'recoverable registrations count')
    result=[];seen=set()
    for row in rows:
        require(isinstance(row,dict) and set(row)=={'manifestSha256','sourceCommit','exeSha256','dllSha256','note'},'recoverable registration fields')
        for key in ('manifestSha256','exeSha256','dllSha256'):require(isinstance(row[key],str) and re.fullmatch('[0-9a-f]{64}',row[key]),'recoverable registration hash')
        require(isinstance(row['sourceCommit'],str) and re.fullmatch('[0-9a-f]{40}',row['sourceCommit']),'recoverable registration source')
        require(isinstance(row['note'],str) and 0<len(row['note'])<=400,'recoverable registration note')
        require(row['exeSha256'] not in seen,'duplicate recoverable registration');seen.add(row['exeSha256'])
        result.append({key:row[key] for key in ('manifestSha256','sourceCommit','exeSha256','dllSha256')})
    return result


def build_package(dll,tool,source_sha,readme,collector,job_helper,signature_file,output_dir,package_version='v1',registration_runner=None,evidence_validator=None,recoverable=None):
    require(isinstance(source_sha,str) and re.fullmatch('[0-9a-f]{40}',source_sha),'exact source SHA required')
    inputs={PE_NAMES[0]:dll,PE_NAMES[1]:tool,'README.zh-CN.md':readme,SCRIPT_NAMES[0]:collector,SCRIPT_NAMES[1]:job_helper}
    require(package_version in ('v1','v2'),'explicit supported package version required')
    if package_version=='v2':
        require(registration_runner is not None and evidence_validator is not None,'v2 companion scripts required')
        inputs.update({V2_SCRIPT_NAMES[0]:registration_runner,V2_SCRIPT_NAMES[1]:evidence_validator})
    else:
        require(registration_runner is None and evidence_validator is None,'v1 cannot include registration companions')
        require(recoverable is None,'v1 cannot pin recoverable registrations')
    for name in (*PE_NAMES,*SCRIPT_NAMES,*(V2_SCRIPT_NAMES if package_version=='v2' else ())):require(Path(inputs[name]).name==name,'fixed input basename required')
    payload={name:read_file(path,128*1024*1024 if name in PE_NAMES else 1024*1024) for name,path in inputs.items()}
    architecture={name:pe_identity(payload[name],name.endswith('.dll')) for name in PE_NAMES}
    signing=signatures(read_file(signature_file,65536),payload)
    pinned=recoverable_registrations(recoverable)
    for row in pinned:require(row['exeSha256']!=digest(payload[PE_NAMES[1]]),'recoverable registration must name an older tool')
    manifest={'schema':'mycomputer-activation-development-package-'+package_version,'scope':'registration-activation-only-development',
              'sourceCommit':source_sha,'architecture':'native-x64','targetHost':'MyComputer','identity':dict(PRODUCT_IDENTITY),
              'defaultOperation':'read-only-preflight','userDesktopExecutionApproved':False,
              'registrationExecutionApproved':False,'brokerEditingVerified':False,'physicalAcceptance':False,
              'signatureEvidenceSource':'Windows Get-AuthenticodeSignature; hash-bound supplied build evidence',
              'files':[]}
    if pinned:manifest['recoverableRegistrations']=pinned
    for name,data in sorted(payload.items()):
        row={'path':name,'bytes':len(data),'sha256':digest(data)}
        if name in architecture:row.update(pe=architecture[name],authenticode=signing[name])
        manifest['files'].append(row)
    payload['manifest.json']=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    output=Path(output_dir);output.mkdir(parents=True,exist_ok=False)
    archive=output/('YimeMyComputerActivationStage1-x64.zip' if package_version=='v1' else 'YimeMyComputerActivationProtected-v2-x64.zip')
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for name,data in sorted(payload.items()):
            info=zipfile.ZipInfo(name,(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            info.external_attr=0o100644<<16;z.writestr(info,data)
    # Verify exact members and bytes, not merely the archive's successful creation.
    with zipfile.ZipFile(archive) as z:
        require(z.namelist()==sorted(payload),'unexpected ZIP member')
        for name,data in payload.items():require(z.read(name)==data,'ZIP round-trip mismatch')
    evidence={'schema':'mycomputer-package-build-evidence-v1','sourceCommit':source_sha,'zip':archive.name,
              'bytes':archive.stat().st_size,'sha256':digest(archive.read_bytes()),
              'manifestSHA256':digest(payload['manifest.json']),'payloadCount':len(payload)-1,
              'authenticode':signing,'windowsActivationExecutedByBuilder':False}
    (output/'package-evidence.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    return evidence


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for flag in ('dll','tool','readme','collector','job-helper','signatures','output-dir'):
        parser.add_argument('--'+flag,type=Path,required=True)
    parser.add_argument('--source-sha',required=True)
    parser.add_argument('--package-version',choices=('v1','v2'),default='v1')
    parser.add_argument('--registration-runner',type=Path)
    parser.add_argument('--evidence-validator',type=Path)
    parser.add_argument('--pinned-registrations',type=Path,help='reviewed JSON naming older registrations this v2 tool may recover')
    a=parser.parse_args()
    result=build_package(a.dll,a.tool,a.source_sha,a.readme,a.collector,a.job_helper,a.signatures,a.output_dir,a.package_version,a.registration_runner,a.evidence_validator,a.pinned_registrations)
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':main()
