import hashlib
import json
import pathlib
import subprocess
from datetime import datetime, timezone

repo = pathlib.Path(r'C:\dev\Yime')
delivery = pathlib.Path(r'C:\dev\Yime-deliveries\current-readiness-20260927-0ab86312')
package = delivery / 'rime-build' / 'rime-pime'
evidence = delivery / 'rime-evidence'
temporary = repo / '.tmp' / 'current-readiness-delivery-20260927' / 'rime'

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def git(*args):
    return subprocess.check_output(['git', *args], cwd=repo).decode('utf-8').strip()

commit = git('rev-parse', 'HEAD')
manifest_path = package / 'product-package.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
assert manifest['product'] == 'rime-pime'
actual = {f.relative_to(package / 'payload').as_posix() for f in (package / 'payload').rglob('*') if f.is_file()}
declared = {r['path'] for r in manifest['files']}
assert actual == declared
assert len(declared) == len(manifest['files'])
tracked = set(git('ls-files').splitlines())
source_map = []
fresh_binaries = []
for row in manifest['files']:
    target = package / 'payload' / row['path']
    assert target.stat().st_size == row['bytes']
    assert digest(target) == row['sha256']
    parts = pathlib.PurePosixPath(row['path']).parts
    if parts[0] in ('x86', 'x64'):
        source = temporary / ('native-' + parts[0]) / 'PIMETextService' / 'Release' / parts[1]
        kind = 'new-isolated-native-build'
    elif parts[0] == 'PIMELauncher.exe':
        source = repo / 'PIMELauncher' / 'target' / 'i686-pc-windows-msvc' / 'release' / 'PIMELauncher.exe'
        kind = 'rebuilt-pinned-i686-rust-package'
    elif parts[0] == 'go-backend' and len(parts) == 2 and parts[1].endswith('.exe'):
        source = repo / 'go-backend' / 'build' / 'go-backend' / parts[1]
        kind = 'rebuilt-go-amd64-executable'
    elif parts[0] == 'go-backend':
        source = repo.joinpath(*parts)
        kind = 'bundled-source-resource'
    elif parts[0] == 'licenses':
        source = repo.joinpath(*parts)
        kind = 'bundled-license'
    elif parts[0] == 'backends.json':
        source = delivery / 'rime-build' / 'source-payload' / 'backends.json'
        kind = 'generated-product-backend-descriptor'
    else:
        raise AssertionError(f'Unmapped file: {row["path"]}')
    assert source.is_file(), source
    assert digest(source) == row['sha256'], source
    relative = source.relative_to(repo).as_posix() if source.is_relative_to(repo) else None
    record = dict(packagePath=row['path'], sourcePath=str(source), origin=kind,
                  sourceCommit=commit, sha256=row['sha256'], bytes=row['bytes'],
                  sourceTracked=relative in tracked if relative else False,
                  sourceLastWriteUtc=datetime.fromtimestamp(source.stat().st_mtime, timezone.utc).isoformat())
    source_map.append(record)
    if kind in ('new-isolated-native-build','rebuilt-pinned-i686-rust-package','rebuilt-go-amd64-executable'):
        fresh_binaries.append(record)
assert len(fresh_binaries) == 17, len(fresh_binaries)
lock = json.loads((repo / 'go-backend' / 'input_methods' / 'yime' / 'rime_runtime.lock.json').read_text())
for name, expected in lock['files'].items():
    assert digest(package / 'payload' / 'go-backend' / 'input_methods' / 'yime' / name) == expected
assert not any('/brise/' in p or p.endswith('.go') or 'yime_core_trial' in p for p in actual)
source_data = repo / 'go-backend' / 'input_methods' / 'yime' / 'data'
packaged_data = package / 'payload' / 'go-backend' / 'input_methods' / 'yime' / 'data'
retired = {'yime_core_trial.dict.yaml', 'yime_core_trial.schema.yaml', 'yime_core_trial_manifest.json'}
source_data_files = {f.relative_to(source_data).as_posix(): f for f in source_data.rglob('*') if f.is_file() and f.name not in retired}
packaged_data_files = {f.relative_to(packaged_data).as_posix(): f for f in packaged_data.rglob('*') if f.is_file()}
assert source_data_files.keys() == packaged_data_files.keys(), (source_data_files.keys() - packaged_data_files.keys(), packaged_data_files.keys() - source_data_files.keys())
for relative, source in source_data_files.items():
    target = packaged_data_files[relative]
    assert source.stat().st_size == target.stat().st_size and digest(source) == digest(target), relative
for mode in ('variable', 'full', 'shorthand'):
    for prefix in ('yime_', 'yime_erhua_mixed_', 'yime_erhua_mixed_sentence_', 'yime_sentence_', 'yime_third_tone_stage5c_', 'yime_particle_a_stage6d_', 'yime_psc_peripheral_', 'yime_psc_peripheral_sentence_'):
        assert f'go-backend/input_methods/yime/data/{prefix}{mode}.dict.yaml' in actual
    assert f'go-backend/input_methods/yime/data/yime_{mode}.schema.yaml' in actual
for required in ('fonts/YinYuan-Regular.ttf', 'trainer/foundation.json', 'trainer/yinyuan_catalog.json', 'trainer/yinyuan_groups.json', 'opencc/t2s.json', 'opencc/s2t.json', 'opencc/TSCharacters.ocd2', 'opencc/STCharacters.ocd2', 'yime_pinyin_codes.tsv', 'yime_yinyuan_layout.json', 'yime_lexicon_manifest.json', 'yime_core_source_manifest.json', 'yime_runtime_profile.json', 'yime_system_candidate_exclusions.tsv'):
    assert 'go-backend/input_methods/yime/data/' + required in actual
for script in ('Setup.ps1', 'Setup.cmd', 'Product.psm1'):
    assert digest(package / script) == digest(repo / 'installer' / 'simple' / script)
report = dict(format='yime-rime-delivery-build-evidence-1', sourceCommit=commit,
              packageRoot=str(package), manifestSha256=digest(manifest_path), fileCount=len(actual),
              payloadBytes=sum(row['bytes'] for row in manifest['files']), rebuiltBinaryCount=len(fresh_binaries),
              payloadExactMembership=True, payloadHashesValid=True, resourceSourceBytesMatch=True,
              dataDirectoryExactSourceMembership=True, dataDirectoryFileCount=len(source_data_files),
              dataDirectorySizeAndSha256Match=True, allowedRetiredDataExclusions=sorted(retired),
              bundledThreeModeAssetsPresent=True, entryScriptsMatchCurrentSource=True,
              pinnedLibrime=lock, productExecution=False, nativeInstallationAcceptance=False,
              noGoModTidy=True, goBuildModuleMode='readonly',
              rawBuildTranscript=str(evidence / 'build-transcript.log'),
              commandEvidence=str(evidence / 'commands.json'))
(evidence / 'payload-source-map.json').write_text(json.dumps(source_map, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
(evidence / 'rebuilt-binaries.json').write_text(json.dumps(fresh_binaries, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
(evidence / 'package-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
(evidence / 'verify-rime.py').write_text(pathlib.Path(__file__).read_text(), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
