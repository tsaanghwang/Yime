"""Build isolated native ARM64 Rime/PIME payload. No product registration or installation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import time

TOOLS = {
    'server.exe': ('.', False),
    'reverse-lookup.exe': ('./cmd/reverse-lookup-tool', True),
    'tool-hub.exe': ('./cmd/tool-hub', True),
    'yime-trainer.exe': ('./cmd/yime-trainer', True),
    'input-toolbar.exe': ('./cmd/input-toolbar', True),
    'lexicon-manager.exe': ('./cmd/lexicon-manager', True),
    'system-lexicon-audit.exe': ('./cmd/system-lexicon-audit', True),
    'lexicon-promotion-scan.exe': ('./cmd/lexicon-promotion-scan', False),
    'blocklist-manager.exe': ('./cmd/blocklist-manager', True),
    'settings-tool.exe': ('./cmd/settings-tool', True),
    'diagnostics-tool.exe': ('./cmd/diagnostics-tool', True),
    'yime-layout-designer.exe': ('./cmd/yime-layout-designer', True),
}

def pe_machine(path):
    data = Path(path).read_bytes()
    if data[:2] != b'MZ' or len(data) < 64:
        raise ValueError('not PE: ' + str(path))
    offset = struct.unpack_from('<I', data, 60)[0]
    if data[offset:offset+4] != b'PE\0\0':
        raise ValueError('bad PE: ' + str(path))
    return struct.unpack_from('<H', data, offset + 4)[0]

def record(path):
    path = Path(path)
    with path.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    result = {'bytes': path.stat().st_size, 'sha256': digest}
    if path.suffix.lower() in ('.exe', '.dll'):
        result['machine'] = hex(pe_machine(path))
    return result

def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

class Build:
    def __init__(self, args):
        self.repo = Path(args.repo).resolve()
        self.root = Path(args.root).resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.logs = self.root / 'logs'
        self.logs.mkdir(exist_ok=True)
        self.env = os.environ.copy()
        for name in ('GOFLAGS', 'RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'LIB', 'LIBPATH', 'INCLUDE'):
            self.env.pop(name, None)
        self.env.update(VSLANG='1033', GOTOOLCHAIN='local', CGO_ENABLED='0', GOOS='windows', GOARCH='arm64',
                        GOCACHE=str(self.root/'go-cache'), GOTMPDIR=str(self.root/'go-tmp'),
                        GOMODCACHE=str(self.root/'go-mod'), CARGO_HOME=str(self.root/'cargo-home'),
                        RUSTUP_HOME=str(self.root/'rustup-home'), CARGO_TARGET_DIR=str(self.root/'cargo-target'))
        (self.root/'go-tmp').mkdir(exist_ok=True)
        vswhere = Path(os.environ['ProgramFiles(x86)'])/'Microsoft Visual Studio/Installer/vswhere.exe'
        self.vs = Path(subprocess.check_output([str(vswhere), '-latest', '-products', '*', '-property', 'installationPath'], text=True).strip())
        self.cmake = self.vs/'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
        if not self.cmake.is_file():
            raise ValueError('CMake missing from Visual Studio')
        self.go = Path(args.go).resolve()
        if pe_machine(self.go) != 0xaa64:
            raise ValueError('native ARM64 Go required')
        self.env['PATH'] = str(self.go.parent) + os.pathsep + str(self.cmake.parent) + os.pathsep + self.env['PATH']

    def run(self, name, command, cwd=None, env=None, timeout=1800):
        print('RUN', name, flush=True)
        start = time.time()
        attempt = 1
        stem = name
        while (self.logs/(stem+'.log')).exists():
            attempt += 1
            stem = name+'.attempt'+str(attempt)
        with (self.logs/(stem+'.log')).open('w', encoding='utf-8') as output:
            output.write(json.dumps([str(x) for x in command])+'\n'); output.flush()
            result = subprocess.run([str(x) for x in command], cwd=cwd or self.repo, env=env or self.env,
                                    stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
        write_json(self.logs/(stem+'.json'), {'command': [str(x) for x in command], 'exitCode': result.returncode,
                   'seconds': round(time.time()-start, 2), 'cwd': str(cwd or self.repo)})
        if result.returncode:
            tail = (self.logs/(stem+'.log')).read_text(encoding='utf-8', errors='replace').splitlines()[-35:]
            raise RuntimeError(name+' failed\n'+'\n'.join(tail))

    def vcenv(self, architecture='arm64'):
        script = self.vs/'VC/Auxiliary/Build/vcvarsall.bat'
        if architecture not in ('arm64', 'arm64_x86', 'arm64_x64'):
            raise ValueError('unsupported compiler host/target')
        command = 'cmd.exe /d /s /c ""'+str(script)+'" '+architecture+' >nul && set"'
        raw = subprocess.check_output(command, env=self.env, text=True, encoding='utf-8', errors='replace')
        result = self.env.copy()
        for line in raw.splitlines():
            if '=' in line:
                key, value = line.split('=', 1)
                if key:
                    # Windows environment names are case-insensitive.
                    existing = next((k for k in result if k.upper()==key.upper()), key)
                    result[existing] = value
        return result

    def native(self):
        native = self.root/'pime-arm64'
        for arch, stage, targets in (
            ('ARM64', 'ARM64', ['PIMETextService', 'PIMERegistrationStatus', 'PIMERpcResponseTests', 'PIMEAbiLoadTests']),
            ('ARM64EC', 'ARM64EC', ['PIMETextService']),
            ('Win32', '', ['PIMETextService', 'PIMERegistrationStatus', 'PIMERpcResponseTests', 'PIMEAbiLoadTests']),
            ('x64', '', ['PIMEAbiLoadTests'])):
            destination = self.root/('pime-'+arch.lower())
            command = [self.cmake, '-S', self.repo, '-B', destination, '-G', 'Visual Studio 17 2022', '-A', arch,
                       '-DPIME_BUILD_LAUNCHER=OFF', '-DCMAKE_CONFIGURATION_TYPES=Release']
            if stage:
                command.append('-DPIME_ARM64X_STAGE='+stage)
            if stage == 'ARM64EC':
                command.append('-DPIME_ARM64X_NATIVE_LINK_RSP='+str(native/'PIMETextService/arm64x/PIMETextService.rsp'))
            self.run('pime-configure-'+arch, command)
            self.run('pime-build-'+arch, [self.cmake, '--build', destination, '--config', 'Release', '--parallel', '6', '--target', *targets])
        for arch in ('arm64', 'win32'):
            self.run('pime-rpc-'+arch, [self.root/('pime-'+arch)/'PIMETextService/Release/PIMERpcResponseTests.exe'])
        for arch, dll in [('arm64','arm64ec'), ('x64','arm64ec'), ('win32','win32')]:
            self.run('pime-load-'+arch, [self.root/('pime-'+arch)/'PIMETextService/Release/PIMEAbiLoadTests.exe',
                                       self.root/('pime-'+dll)/'PIMETextService/Release/PIMETextService.dll'])

    def rime(self):
        source = self.root/'sources/librime'
        prefix = self.root/'rime-deps'
        base = [self.cmake, '-G', 'Visual Studio 17 2022', '-A', 'ARM64', '-DCMAKE_CONFIGURATION_TYPES=Release',
                '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded',
                '-DCMAKE_CXX_FLAGS=/DWIN32 /D_WINDOWS /W3 /GR /EHsc /utf-8 /MP6',
                '-DCMAKE_C_FLAGS=/DWIN32 /D_WINDOWS /W3 /utf-8 /MP6',
                '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW', '-DBUILD_SHARED_LIBS=OFF', '-DBUILD_TESTING=OFF',
                '-DCMAKE_INSTALL_PREFIX='+str(prefix)]
        configs = {
            'glog': ['-DWITH_GFLAGS=OFF'],
            'leveldb': ['-DLEVELDB_BUILD_BENCHMARKS=OFF', '-DLEVELDB_BUILD_TESTS=OFF'],
            'yaml-cpp': ['-DYAML_MSVC_SHARED_RT=OFF', '-DMSVC_SHARED_RT=OFF', '-DYAML_CPP_BUILD_CONTRIB=OFF', '-DYAML_CPP_BUILD_TESTS=OFF', '-DYAML_CPP_BUILD_TOOLS=OFF'],
            'marisa-trie': ['-DENABLE_TOOLS=OFF'],
            'opencc': ['-DBUILD_TESTING=OFF', '-DPYTHON_EXECUTABLE='+sys.executable],
        }
        for dependency, flags in configs.items():
            destination = self.root/('rime-'+dependency)
            self.run('rime-configure-'+dependency, [*base, '-S', source/'deps'/dependency, '-B', destination, *flags])
            self.run('rime-build-'+dependency, [self.cmake, '--build', destination, '--config', 'Release', '--parallel', '6', '--target', 'install'])
        destination = self.root/'rime-build'
        self.run('rime-configure', [*base, '-S', source, '-B', destination, '-DBUILD_SHARED_LIBS=ON', '-DBUILD_STATIC=ON',
            '-DBUILD_TEST=OFF', '-DBUILD_DATA=OFF', '-DBOOST_ROOT='+str(self.root/'sources/boost'),
            '-DCMAKE_PREFIX_PATH='+str(prefix), '-DCMAKE_INSTALL_PREFIX='+str(self.root/'rime-dist')])
        self.run('rime-build', [self.cmake, '--build', destination, '--config', 'Release', '--parallel', '6', '--target', 'install'])
        dll = self.root/'rime-dist/lib/rime.dll'
        if pe_machine(dll) != 0xaa64:
            raise ValueError('librime is not ARM64')

    def launcher(self):
        rustup = self.root/'cargo-home/bin/rustup.exe'
        env = self.vcenv()
        if not rustup.exists():
            self.run('rust-bootstrap', [self.root/'downloads/rustup-init-arm64.exe', '-y', '--no-modify-path', '--profile', 'minimal',
                '--default-host', 'aarch64-pc-windows-msvc', '--default-toolchain', '1.97.0-aarch64-pc-windows-msvc'], env=env)
        env['PATH'] = str(rustup.parent)+os.pathsep+env['PATH']
        command = [rustup, 'run', '1.97.0-aarch64-pc-windows-msvc', 'cargo']
        self.run('launcher-build', [*command, 'build', '--locked', '--offline', '--release', '--target', 'aarch64-pc-windows-msvc', '--bin', 'PIMELauncher'], cwd=self.repo/'PIMELauncher', env=env)
        self.run('launcher-tests', [*command, 'test', '--locked', '--offline', '--target', 'aarch64-pc-windows-msvc'], cwd=self.repo/'PIMELauncher', env=env)

    def backend(self):
        output = self.root/'go-bin'
        output.mkdir(exist_ok=True)
        version = (self.repo/'version.txt').read_text().strip()
        for filename, (package, gui) in TOOLS.items():
            flags = '-s -w -X main.version='+version+(' -H=windowsgui' if gui else '')
            self.run('go-'+filename, [self.go, 'build', '-trimpath', '-buildvcs=false', '-ldflags', flags, '-o', output/filename, package], cwd=self.repo/'go-backend')
            if pe_machine(output/filename) != 0xaa64:
                raise ValueError('Go product binary is not native ARM64')

    def payload(self):
        destination = self.root/'payload'
        if destination.exists():
            raise ValueError('payload already exists; use a new root or preserve it for review')
        destination.mkdir()
        def copy(source, relative):
            target = destination/relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        def require_machine(source, expected):
            if pe_machine(source) != expected:
                raise ValueError('unexpected PE architecture: '+str(source))
        for arch, build in [('arm64','arm64ec'), ('x86','win32')]:
            require_machine(self.root/('pime-'+build)/'PIMETextService/Release/PIMETextService.dll',0xaa64 if arch=='arm64' else 0x14c)
            copy(self.root/('pime-'+build)/'PIMETextService/Release/PIMETextService.dll', arch+'/PIMETextService.dll')
            probe = 'arm64' if arch == 'arm64' else 'win32'
            copy(self.root/('pime-'+probe)/'PIMETextService/Release/PIMERegistrationStatus.exe', arch+'/PIMERegistrationStatus.exe')
        launcher = self.root/'cargo-target/aarch64-pc-windows-msvc/release/PIMELauncher.exe'
        require_machine(launcher,0xaa64)
        copy(launcher, 'PIMELauncher.exe')
        for filename in TOOLS:
            require_machine(self.root/'go-bin'/filename,0xaa64)
            copy(self.root/'go-bin'/filename, 'go-backend/'+filename)
        method = self.repo/'go-backend/input_methods/yime'
        excluded = {'.go','.exe','.dll','.lib','.pdb','.exp','.syso'}
        for source in method.rglob('*'):
            relative = source.relative_to(method)
            if not source.is_file() or source.suffix.lower() in excluded or 'testdata' in relative.parts or 'brise' in relative.parts:
                continue
            if source.name in ('rime_runtime.lock.json', 'rime.dll.bak-32bit'):
                continue
            copy(source, 'go-backend/input_methods/yime/'+relative.as_posix())
        runtime = {}
        for filename in ('rime.dll', 'rime_deployer.exe', 'rime_dict_manager.exe'):
            matches = list((self.root/'rime-dist').rglob(filename))
            if len(matches) != 1 or pe_machine(matches[0]) != 0xaa64:
                raise ValueError('unique native runtime required: '+filename)
            copy(matches[0], 'go-backend/input_methods/yime/'+filename)
            runtime[filename] = record(matches[0])['sha256']
        source_lock = json.loads((self.repo/'tools/rime-pime/arm64-sources.lock.json').read_text())
        lock = {'schema_version': 1, 'source': 'https://github.com/rime/librime/releases/tag/1.17.0',
                'librime_version': '1.17.0', 'librime_commit': source_lock['sources']['librime']['commit'],
                'platform': 'Windows-msvc-arm64', 'plugins': {x['repository']:x['commit'] for p,x in source_lock['sources'].items() if p.startswith('librime/plugins/') and not p.endswith('/thirdparty')}, 'files':runtime}
        write_json(destination/'go-backend/input_methods/yime/rime_runtime.lock.json',lock)
        write_json(destination/'backends.json',[{'name':'go-backend','command':'go-backend\\server.exe','workingDir':'go-backend','params':''}])
        copy(self.repo/'version.txt','version.txt')
        for source in (self.repo/'licenses').rglob('*'):
            if source.is_file():
                copy(source,'licenses/'+source.relative_to(self.repo/'licenses').as_posix())
        copy(self.repo/'PIMELauncher/Cargo.lock','licenses/rust/Cargo.lock')
        for crate in (self.repo/'PIMELauncher/vendor').iterdir():
            if crate.is_dir():
                for source in crate.glob('*'):
                    if source.is_file() and source.name.lower().startswith(('license','copying','copyright','notice')):
                        copy(source,'licenses/rust/'+crate.name+'/'+source.name)
        for name, row in source_lock['sources'].items():
            for source in (self.root/'sources'/name).glob('*'):
                if source.is_file() and source.name.lower().startswith(('license','copying','copyright')):
                    copy(source,'licenses/arm64-sources/'+name+'/'+source.name)
        copy(self.root/'sources/boost/LICENSE_1_0.txt','licenses/arm64-sources/boost/LICENSE_1_0.txt')
        # Upstream embeds the complete MIT notice in lua.h rather than LICENSE.
        copy(self.root/'sources/librime/plugins/lua/thirdparty/lua5.4/lua.h','licenses/arm64-sources/lua/lua.h')
        # The Lua source license is nested below the plugin's thirdparty root.
        for source in (self.root/'sources/librime/plugins/lua/thirdparty').rglob('*'):
            if source.is_file() and source.name.lower().startswith(('license','copying','copyright')):
                copy(source,'licenses/arm64-sources/lua/'+source.relative_to(self.root/'sources/librime/plugins/lua/thirdparty').as_posix())
        copy(self.repo/'tools/rime-pime/arm64-sources.lock.json','licenses/arm64-sources.lock.json')
        manifest = {p.relative_to(destination).as_posix():record(p) for p in destination.rglob('*') if p.is_file()}
        write_json(self.root/'payload-inventory.json', manifest)
        print('PAYLOAD',destination,flush=True)

    def verify(self):
        data = self.root/'payload/go-backend/input_methods/yime/data'
        if not data.is_dir():
            raise ValueError('create the isolated payload first')
        dumpbins = sorted((self.vs/'VC/Tools/MSVC').glob('*/bin/Hostarm64/arm64/dumpbin.exe'))
        if not dumpbins:
            raise ValueError('native ARM64 dumpbin is required for ABI evidence')
        self.run('pime-arm64x-loadconfig',[dumpbins[-1],'/headers','/loadconfig',
            self.root/'payload/arm64/PIMETextService.dll'])
        for relative in ('PIMELauncher.exe','go-backend/input_methods/yime/rime.dll',
                         'go-backend/input_methods/yime/rime_deployer.exe'):
            self.run('imports-'+Path(relative).name,[dumpbins[-1],'/dependents',self.root/'payload'/relative])
        # An explicit test-only overlay changes the fixture directory, never the
        # product layout/code-mode source or the checked-in x64 runtime bundle.
        original = self.repo/'go-backend/input_methods/yime/rime_runtime_test.go'
        content = original.read_text(encoding='utf-8')
        needle = 'func rimeRuntimeTestDataDir(t *testing.T) string {\n\tt.Helper()\n'
        if content.count(needle) != 1:
            raise ValueError('review changed real-Rime fixture entry before using overlay')
        content = content.replace(needle, needle+'\tif isolated := os.Getenv("YIME_ARM64_RIME_TEST_DATA"); isolated != "" {\n\t\treturn isolated\n\t}\n')
        overlay_source = self.root/'rime_runtime_test.go'
        overlay_source.write_text(content,encoding='utf-8')
        overlay = self.root/'real-rime-overlay.json'
        write_json(overlay,{'Replace':{str(original):str(overlay_source)}})
        env = self.env.copy()
        env.update(YIME_RUN_REAL_RIME_TESTS='1',YIME_ARM64_RIME_TEST_DATA=str(data))
        isolated_temp = self.root/'test-temp'
        isolated_temp.mkdir(exist_ok=True)
        env.update(TEMP=str(isolated_temp),TMP=str(isolated_temp))
        selected = '|'.join(('TestNativeBackendKeepsRimeOwnedCandidatePaging',
            'TestRealRimeCanCommitText', 'TestRealRimeAllSchemasComposeSentence',
            'TestRealRimeNeutralToneEntryAcrossAllThreeSchemas',
            'TestRealRimePrintableLayoutKeysAreNeverPagingBindings',
            'TestRealRimeBackspaceUpdatesComposition', 'TestRealRimeEscapeClearsComposition',
            'TestRealRimePunctuationKeys', 'TestRealRimeRedeployAppliesPageSize',
            'TestRealRimeExternalBuildAppliesPageSize',
            'TestRealRimeEndSessionPersistsLearningAcrossRestart'))
        self.run('real-rime-tests',[self.go,'test','-overlay',overlay,'-count=1','-timeout=30m','-v',
            '-run','^('+selected+')$','./input_methods/yime'],cwd=self.repo/'go-backend',env=env,timeout=1860)

    def audit(self):
        payload = self.root/'payload'
        expected = json.loads((self.root/'payload-inventory.json').read_text(encoding='utf-8'))
        current = {p.relative_to(payload).as_posix():record(p) for p in payload.rglob('*') if p.is_file()}
        if current != expected:
            raise ValueError('payload changed after inventory generation')
        binaries = {path:row for path,row in current.items() if 'machine' in row}
        if len(binaries) != 20:
            raise ValueError('expected exactly 20 product EXE/DLL files')
        dumpbin = sorted((self.vs/'VC/Tools/MSVC').glob('*/bin/Hostarm64/arm64/dumpbin.exe'))[-1]
        for path,row in binaries.items():
            expected_machine = '0x14c' if path.startswith('x86/') else '0xaa64'
            if row['machine'] != expected_machine:
                raise ValueError('wrong payload architecture: '+path)
            output = subprocess.check_output([str(dumpbin),'/dependents',str(payload/path)],env=self.env,text=True,encoding='utf-8',errors='replace')
            row['imports'] = re.findall(r'^\s+([A-Za-z0-9_.-]+\.dll)\s*$',output,re.MULTILINE|re.IGNORECASE)
        loadconfig = subprocess.check_output([str(dumpbin),'/loadconfig',str(payload/'arm64/PIMETextService.dll')],env=self.env,text=True,encoding='utf-8',errors='replace')
        if not all(re.search(r'^\s+'+abi+r'\s+[0-9A-Fa-f]+',loadconfig,re.MULTILINE) for abi in ('arm64','arm64ec','x64')):
            raise ValueError('ARM64X code ranges are incomplete')
        write_json(self.root/'arm64-payload-audit.json',{'schema':1,'payload':str(payload),
            'fileCount':len(current),'totalBytes':sum(x['bytes'] for x in current.values()),
            'arm64xCodeRanges':['arm64','arm64ec','x64'],'binaries':binaries,
            'runtimeLock':'go-backend/input_methods/yime/rime_runtime.lock.json',
            'registrationPerformed':False,'installedAcceptance':False})
        print('AUDIT',len(current),'files;',len(binaries),'PE binaries; ARM64X ranges verified',flush=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default=Path(__file__).resolve().parents[2])
    parser.add_argument('--root', required=True)
    parser.add_argument('--go', required=True)
    parser.add_argument('--stage', choices=('native','rime','launcher','backend','payload','verify','audit','all'), required=True)
    args = parser.parse_args()
    build = Build(args)
    for stage in (('native','rime','launcher','backend','payload','verify','audit') if args.stage=='all' else (args.stage,)):
        getattr(build,stage)()

if __name__ == '__main__':
    main()
