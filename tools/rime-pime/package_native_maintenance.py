"""Attach a package-bound ARM64 maintenance entry and pinned portable PowerShell.

Never installs/registers a product. Formal archives require a clean exact commit;
--draft explicitly permits source work in progress and marks the archive identity.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import zipfile

from build_arm64 import pe_machine

SHELL_MEMBER = 'maintenance/powershell/pwsh.exe'
DEFAULT_PSHOME = 'C:/Program Files/WindowsApps/Microsoft.PowerShell_7.6.9.0_arm64__8wekyb3d8bbwe'


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)+'\n', encoding='utf-8')


def valid_member(name):
    if not name or '\\' in name or ':' in name or name.startswith('/') or re.search(r'[\x00-\x1f<>"|?*]',name):
        return False
    for part in name.split('/'):
        if not part or part in ('.', '..') or part.strip() != part or part.endswith('.'):
            return False
        if re.fullmatch(r'(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])', part.split('.')[0], re.IGNORECASE):
            return False
    return True


def inventory(root):
    root = Path(root).resolve()
    result = {}
    seen = set()
    for directory, directories, filenames in os.walk(root, followlinks=False):
        for name in directories+filenames:
            path = Path(directory)/name
            info = path.lstat()
            if getattr(info,'st_file_attributes',0) & getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',1024):
                raise ValueError('reparse point is not package content: '+str(path))
            if path.is_dir():
                continue
            if not stat.S_ISREG(info.st_mode):
                raise ValueError('non-regular package file: '+str(path))
            relative = path.relative_to(root).as_posix()
            if not valid_member(relative) or relative.lower() in seen:
                raise ValueError('invalid or case-colliding package member: '+relative)
            seen.add(relative.lower())
            result[relative] = {'bytes':info.st_size,'sha256':digest(path)}
    return dict(sorted(result.items()))


def copy_inventory(source, destination, records):
    for name, record in records.items():
        target = destination/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source/name, target)
        if target.stat().st_size != record['bytes'] or digest(target) != record['sha256']:
            raise ValueError('copy differs from locked source: '+name)


def checked(repo, script, parameters, work, bootstrap):
    work.mkdir(parents=True, exist_ok=True)
    params = work/(Path(script).stem+'-params.json')
    write_json(params, parameters)
    env = os.environ.copy()
    env['PATH'] = str(bootstrap)+os.pathsep+env['PATH']
    command = [sys.executable,str(repo/'tools/powershell/run_checked.py'),'--edition','ps7',
               '--script',str(script),'--params-file',str(params)]
    result = subprocess.run(command, cwd=repo, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace')
    (work/(Path(script).stem+'.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
    if result.returncode:
        raise RuntimeError('checked PowerShell failed: '+result.stdout+result.stderr)
    print(result.stdout.strip(), flush=True)


def prepare_shell(args):
    repo, cache = Path(args.repo).resolve(), Path(args.cache).resolve()
    source = Path(args.source_pshome).resolve()
    if cache == source or source in cache.parents:
        raise ValueError('shell cache must be separate from installed PSHOME')
    cache.mkdir(parents=True, exist_ok=True)
    shell = cache/'powershell'
    lock_path = cache/'shell-lock.json'
    if lock_path.exists():
        lock = json.loads(lock_path.read_text(encoding='utf-8'))
        if inventory(shell) != lock['files']:
            raise ValueError('shared shell cache differs from its lock')
        if digest(cache/'source-signatures.json') != lock['sourceSignatureReportSHA256']:
            raise ValueError('shared signature evidence differs from its lock')
        print('REUSE locked shell:',len(lock['files']),'files',flush=True)
        return
    if shell.exists():
        raise ValueError('incomplete shell cache exists; preserve it and choose a fresh cache')
    inspection = repo/'tools/rime-pime/inspect_maintenance_shell.ps1'
    checked(repo,inspection,{'ShellRoot':str(source),'ReportPath':str(cache/'source-signatures.json')},cache/'source-inspection',args.bootstrap_directory)
    records = inventory(source)
    if len(records) < 100 or any(name not in records for name in ('pwsh.exe','LICENSE.txt','ThirdPartyNotices.txt')):
        raise ValueError('incomplete official PowerShell source tree')
    shell.mkdir()
    copy_inventory(source,shell,records)
    if inventory(shell) != records or inventory(source) != records:
        raise ValueError('PowerShell source changed during copy')
    checked(repo,inspection,{'ShellRoot':str(shell),'ReportPath':str(cache/'portable-signatures.json')},cache/'portable-inspection',shell)
    portable = json.loads((cache/'portable-signatures.json').read_text(encoding='utf-8'))
    if Path(portable['processPSHOME']).resolve() != shell or portable['processArchitecture'] != 'arm64':
        raise ValueError('copied shell did not run independently as native ARM64')
    write_json(lock_path,{'schema':'yime-bundled-powershell-v1','source':str(source),
        'powerShellVersion':portable['powerShellVersion'],'files':records,
        'sourceSignatureReportSHA256':digest(cache/'source-signatures.json'),
        'portableSignatureReportSHA256':digest(cache/'portable-signatures.json')})
    print('SHELL READY',shell,len(records),'files',sum(x['bytes'] for x in records.values()),'bytes',flush=True)


def source_state(repo, commit, draft, git):
    if not re.fullmatch('[0-9a-f]{40}',commit):
        raise ValueError('source commit must be full lowercase SHA-1')
    actual = subprocess.check_output([git,'rev-parse','HEAD'],cwd=repo,text=True).strip()
    if actual != commit:
        raise ValueError('source commit must identify current HEAD')
    status = subprocess.check_output([git,'status','--porcelain','--untracked-files=normal'],cwd=repo,text=True)
    if status and not draft:
        raise ValueError('formal maintenance package requires a clean committed source tree')
    return {'commit':actual,'clean':not bool(status),'statusSHA256':hashlib.sha256(status.encode()).hexdigest()}


def zip_package(package, path):
    expected = inventory(package)
    with zipfile.ZipFile(path,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for name in expected:
            archive.write(package/name,name)
    with zipfile.ZipFile(path) as archive:
        if sorted(archive.namelist()) != sorted(expected):
            raise ValueError('ZIP member inventory differs from package')
        for name, row in expected.items():
            entry = archive.getinfo(name)
            with archive.open(entry) as stream:
                actual = hashlib.file_digest(stream,'sha256').hexdigest()
            if entry.file_size != row['bytes'] or actual != row['sha256']:
                raise ValueError('ZIP file differs from package: '+name)
    if inventory(package) != expected:
        raise ValueError('package changed while creating ZIP')
    return expected


def preserve_assembly_metadata(package, maintenance):
    preserved = []
    for name in ('package-evidence.json','signatures.json','README.md','README.txt'):
        original = package/name
        if original.is_file():
            target = maintenance/'prior-assembly'/name
            target.parent.mkdir(parents=True,exist_ok=True)
            original.rename(target)
            preserved.append(target.relative_to(package).as_posix())
    return preserved


def attach(args):
    repo, package, output, cache = (Path(x).resolve() for x in (args.repo,args.package_root,args.output_root,args.cache))
    if output == package or package in output.parents:
        raise ValueError('archive output must be outside the bound package')
    if output.exists():
        raise ValueError('choose a new archive output directory')
    state = source_state(repo,args.source_commit,args.draft,args.git)
    manifest = json.loads((package/'product-package.json').read_text(encoding='utf-8-sig'))
    if manifest.get('product') not in ('rime-pime','yimecore-18u') or manifest.get('target') != 'windows-arm64':
        raise ValueError('native maintenance supports explicit ARM64 Rime/PIME and 18u packages only')
    for name in ('maintenance','maintenance-plan.json','YimeMaintenance.exe'):
        if (package/name).exists():
            raise ValueError('package already has a maintenance attachment: '+name)
    lock = json.loads((cache/'shell-lock.json').read_text(encoding='utf-8'))
    if inventory(cache/'powershell') != lock['files']:
        raise ValueError('shared shell bytes differ from lock')
    for kind in ('source','portable'):
        if digest(cache/(kind+'-signatures.json')) != lock[kind+'SignatureReportSHA256']:
            raise ValueError('shell signature evidence differs from lock')
    if pe_machine(cache/'powershell/pwsh.exe') != 0xaa64 or pe_machine(args.go) != 0xaa64:
        raise ValueError('native ARM64 shell and Go compiler are required')
    output.mkdir(parents=True)
    maintenance = package/'maintenance'
    maintenance.mkdir()
    prior_metadata = preserve_assembly_metadata(package,maintenance)
    copy_inventory(cache/'powershell',maintenance/'powershell',lock['files'])
    shutil.copyfile(repo/'tools/powershell/preflight.ps1',maintenance/'preflight.ps1')
    shutil.copyfile(cache/'shell-lock.json',maintenance/'powershell-files.json')
    shutil.copyfile(cache/'source-signatures.json',maintenance/'powershell-source-signatures.json')
    (package/'Setup.cmd').write_bytes(b'@echo off\r\n"%~dp0YimeMaintenance.exe" %*\r\nexit /b %errorlevel%\r\n')
    (package/'README.md').write_text(
        '# Native ARM64 maintenance package\n\n'+
        ('This draft was prepared from the working tree based on commit ' if args.draft else 'This source-frozen package was prepared from commit ')+args.source_commit+'.\n\n'
        '`Setup.cmd` defaults to the non-mutating package check. Explicit maintenance commands are '
        '`Setup.cmd -action Install` and `Setup.cmd -action Uninstall`; they use the native ARM64 helper.\n\n'
        'The complete Microsoft PowerShell runtime is pinned under `maintenance/powershell`; installed Store paths are not runtime prerequisites. '
        '`maintenance-plan.json` binds every package file except itself and its compiled helper. '
        'The adjacent ZIP identity JSON records the final archive and every member, including both binding files.\n\n'
        'Any metadata under `maintenance/prior-assembly` describes the earlier payload assembly only; '
        'it is preserved as history and does not claim coverage of this final maintenance attachment. '
        'No product installation, registration or installed-input acceptance is claimed by packaging.\n',encoding='utf-8')
    files = inventory(package)
    required = ('Setup.ps1','Product.psm1','product-package.json','maintenance/preflight.ps1',SHELL_MEMBER)
    if any(name not in files for name in required) or len(files)>4096:
        raise ValueError('incomplete or oversized maintenance file inventory')
    plan = {'schema':'yime-native-maintenance-v1','product':manifest['product'],'target':'windows-arm64',
        'sourceCommit':args.source_commit,'shell':{'path':SHELL_MEMBER,'sha256':files[SHELL_MEMBER]['sha256']},'files':files}
    write_json(package/'maintenance-plan.json',plan)
    plan_hash = digest(package/'maintenance-plan.json')
    env = os.environ.copy()
    env.update(GOOS='windows',GOARCH='arm64',CGO_ENABLED='0',GOENV='off',GOTOOLCHAIN='local',GOFLAGS='',
        GOCACHE=str(output/'go-cache'),GOMODCACHE=str(output/'go-mod'),GOTMPDIR=str(output/'go-tmp'))
    (output/'go-tmp').mkdir()
    command = [str(Path(args.go).resolve()),'build','-trimpath','-buildvcs=false','-ldflags',
        '-s -w -X main.expectedPlanSHA='+plan_hash,'-o',str(package/'YimeMaintenance.exe'),'./cmd/yime-maintenance']
    result = subprocess.run(command,cwd=repo/'go-backend',env=env,capture_output=True,text=True,encoding='utf-8',errors='replace')
    (output/'maintenance-build.log').write_text(result.stdout+result.stderr,encoding='utf-8')
    if result.returncode or pe_machine(package/'YimeMaintenance.exe') != 0xaa64:
        raise RuntimeError('native maintenance compilation failed: '+result.stdout+result.stderr)
    # Check only locks/hashes/PE; no shell execution, elevation or product mutation.
    result = subprocess.run([str(package/'YimeMaintenance.exe'),'-action','Check'],cwd=package,capture_output=True,text=True,encoding='utf-8',errors='replace')
    (output/'maintenance-check.log').write_text(result.stdout+result.stderr,encoding='utf-8')
    if result.returncode:
        raise RuntimeError('native maintenance package check failed: '+result.stdout+result.stderr)
    checked(repo,repo/'tools/rime-pime/observe_package_signatures.ps1',
        {'PackageRoot':str(package),'ReportPath':str(output/'package-signatures.json')},output/'signature-inspection',cache/'powershell')
    if not args.draft:
        source_state(repo,args.source_commit,False,args.git)
    stem = 'yime-'+manifest['product']+'-windows-arm64-'+args.source_commit[:12]+('-draft' if args.draft else '')
    archive = output/(stem+'.zip')
    records = zip_package(package,archive)
    identity = {'schema':'yime-native-maintenance-archive-v1','deliveryState':'draft' if args.draft else 'source-frozen',
        'product':manifest['product'],'target':'windows-arm64','source':state,'planSHA256':plan_hash,
        'maintenanceSHA256':digest(package/'YimeMaintenance.exe'),'shellSHA256':files[SHELL_MEMBER]['sha256'],
        'zip':{'name':archive.name,'bytes':archive.stat().st_size,'sha256':digest(archive)},
        'fileCount':len(records),'files':records,'signatureObservationSHA256':digest(output/'package-signatures.json'),
        'preservedPriorAssemblyMetadata':prior_metadata,'installed':False,'published':False}
    write_json(output/(stem+'.identity.json'),identity)
    print('DRAFT' if args.draft else 'SOURCE-FROZEN',archive,'SHA256',identity['zip']['sha256'],flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',default=Path(__file__).resolve().parents[2])
    parser.add_argument('--bootstrap-directory',default=Path(os.environ.get('LOCALAPPDATA',''))/'Microsoft/WindowsApps/Microsoft.PowerShell_8wekyb3d8bbwe')
    commands = parser.add_subparsers(dest='command',required=True)
    prepare = commands.add_parser('prepare-shell')
    prepare.add_argument('--source-pshome',default=DEFAULT_PSHOME)
    prepare.add_argument('--cache',required=True)
    package = commands.add_parser('attach')
    for name in ('package-root','output-root','cache','source-commit','go'):
        package.add_argument('--'+name,required=True)
    git_default = Path(sys.executable).parents[1]/'native/git/cmd/git.exe'
    package.add_argument('--git',default=str(git_default) if git_default.is_file() else shutil.which('git'))
    package.add_argument('--draft',action='store_true')
    args = parser.parse_args()
    if args.command == 'prepare-shell':
        prepare_shell(args)
    else:
        attach(args)


if __name__ == '__main__':
    main()
