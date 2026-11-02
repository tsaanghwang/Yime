"""Explicit, separate prepare/preflight/register operations; possession is not authorization.

Package hashes detect mismatch, not publisher trust or same-account replacement races.
Default prepare performs no process launch. Registration needs separate user approval.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys

BIN = {'YimeActivatedLoopController.exe', 'YimeActivatedLoopOnce.exe', 'YimeTextService18u.dll', 'YimeBroker18u.exe', 'YimeMyComputerActivationStage1.exe', 'windows_job_once.py', 'validate_local_activation_evidence.py'}
SOURCE = {'tools/yimecore/18u-touch-product.json', 'prototypes/touch-terminal/data/physical-layout.json', 'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json', 'internal_data/yime_syllable_decomposition.tsv'}
DATA = {'ascii_keyboard_manifest.json', 'yime_variable.dict.yaml', 'yime_full.dict.yaml', 'yime_shorthand.dict.yaml'}
ROOT = {'run_activated_registration_loop.py', 'prepare_activated_loop_package.py', 'README.zh-CN.md', 'signatures.json'}
FILES = {'bin/'+n for n in BIN} | {'source/'+n for n in SOURCE} | {'data/'+n for n in DATA} | ROOT
PE = {'bin/'+n for n in BIN if n.endswith(('.exe', '.dll'))}
HEX = re.compile('[0-9a-f]{64}\\Z')
CONFIRM = 'once-activated-18u-loop'
BASE_IMPLEMENTATION = 'e3962604d333df098f31ad689e11801c8b1622c5'


def require(value, reason):
    if not value: raise ValueError(reason)


def regular(path):
    for item in (path, *path.parents):
        info = item.lstat()
        require(not item.is_symlink() and not getattr(info, 'st_file_attributes', 0) & 0x400, 'reparse-path-rejected')
    require(path.is_file(), 'regular-file-required')


def digest(path):
    regular(path); h = hashlib.sha256(); size = 0
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''): h.update(block); size += len(block)
    return {'bytes': size, 'sha256': h.hexdigest()}


def read_json(path):
    regular(path); require(path.stat().st_size <= 1024*1024, 'json-size')
    def unique(pairs):
        out = {}
        for key, value in pairs:
            require(key not in out, 'duplicate-json-key'); out[key] = value
        return out
    return json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite-json')))


def load(path, name):
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result); return result


def pe(path, dll):
    with path.open('rb') as stream:
        dos = stream.read(64); require(len(dos) == 64 and dos[:2] == b'MZ', 'pe-dos')
        offset = struct.unpack_from('<I', dos, 60)[0]
        require(64 <= offset <= path.stat().st_size-24, 'pe-offset'); stream.seek(offset); header = stream.read(24)
        require(header[:4] == b'PE\0\0' and struct.unpack_from('<H', header, 4)[0] == 0x8664, 'pe-native-amd64')
        flags = struct.unpack_from('<H', header, 22)[0]
        require(flags & 2 and bool(flags & 0x2000) == dll, 'pe-executable-kind')


def validate(package, anchor):
    package = Path(package).absolute()
    require(isinstance(anchor, str) and HEX.fullmatch(anchor), 'independent-package-anchor-required')
    require(digest(package/'manifest.json')['sha256'] == anchor, 'package-anchor-mismatch')
    manifest = read_json(package/'manifest.json')
    require(isinstance(manifest, dict) and set(manifest) == {'schema', 'sourceCommit', 'baseImplementation', 'architecture', 'scope', 'registrationExecuted', 'userMachineExecutionApproved', 'files'}, 'package-fields')
    require(manifest['schema'] == 'activated-loop-package-v1' and manifest['architecture'] == 'native-x64' and manifest['scope'] == 'activated-instance-single-edit-development', 'package-identity')
    require(manifest['baseImplementation'] == BASE_IMPLEMENTATION and isinstance(manifest['sourceCommit'], str) and re.fullmatch('[0-9a-f]{40}', manifest['sourceCommit']), 'source-identity')
    require(manifest['registrationExecuted'] is False and manifest['userMachineExecutionApproved'] is False, 'package-no-execution-authority')
    require(isinstance(manifest['files'], dict) and set(manifest['files']) == FILES, 'fixed-payload-set')
    actual = set()
    for directory, dirs, names in os.walk(package, followlinks=False):
        for name in dirs:
            p = Path(directory)/name
            require(not p.is_symlink() and not getattr(p.lstat(), 'st_file_attributes', 0) & 0x400, 'reparse-directory')
        for name in names: actual.add((Path(directory)/name).relative_to(package).as_posix())
    require(actual == FILES | {'manifest.json'}, 'unexpected-package-file')
    for name, row in manifest['files'].items():
        require(isinstance(row, dict) and set(row) == {'bytes', 'sha256'} and type(row['bytes']) is int and isinstance(row['sha256'], str) and HEX.fullmatch(row['sha256']), 'payload-record')
        require(digest(package/name) == row, 'payload-hash-mismatch')
    for name in PE: pe(package/name, name.endswith('.dll'))
    signatures = read_json(package/'signatures.json')
    require(isinstance(signatures, dict) and set(signatures) == {'schema', 'sourceCommit', 'files'} and signatures['schema'] == 'activated-loop-signatures-v1' and signatures['sourceCommit'] == manifest['sourceCommit'], 'signature-schema')
    rows = signatures['files']; require(isinstance(rows, list) and len(rows) == 5, 'signature-file-count'); seen = set()
    for row in rows:
        require(isinstance(row, dict) and set(row) == {'path', 'sha256', 'bytes', 'status', 'signerThumbprint'}, 'signature-fields')
        name = row['path']; require(isinstance(name, str) and name in PE and name not in seen, 'signature-file'); seen.add(name)
        require(type(row['bytes']) is int and {'bytes': row['bytes'], 'sha256': row['sha256']} == manifest['files'][name], 'signature-payload-match')
        require(isinstance(row['status'], str) and row['status'] in {'Valid', 'UnknownError', 'NotSigned', 'HashMismatch', 'NotTrusted', 'NotSupportedFileFormat', 'Incompatible'}, 'signature-status')
        thumb = row['signerThumbprint']; require(thumb is None or isinstance(thumb, str) and re.fullmatch('[0-9A-Fa-f]{40}', thumb), 'signature-thumbprint')
        require(row['status'] != 'Valid' or thumb is not None, 'valid-signature-signer')
        require(row['status'] != 'NotSigned' or thumb is None, 'unsigned-signature-has-no-signer')
    development = {'schema': 'activated-loop-development-manifest-v1', 'sourceCommit': manifest['sourceCommit'], 'architecture': 'native-x64', 'binaryDirectory': str(package/'bin'), 'sourceRoot': str(package/'source'), 'dataDirectory': str(package/'data')}
    for key, prefix, names in [('binaries', 'bin', BIN), ('sources', 'source', SOURCE), ('data', 'data', DATA)]:
        development[key] = {n: manifest['files'][prefix+'/'+n] for n in names}
    return package, manifest, development


def fresh(path, package):
    path = Path(path).absolute(); resolved = path.resolve()
    require(not path.exists() and not path.is_symlink() and package.resolve() not in resolved.parents and resolved != package.resolve(), 'fresh-output-outside-package')
    # Reject junction/symlink ancestors rather than silently writing through them.
    for parent in path.parents:
        require(parent.exists() and not parent.is_symlink() and not getattr(parent.lstat(), 'st_file_attributes', 0) & 0x400, 'output-parent-required-nonreparse')
    return path


def execute(package, anchor, output, mode='prepare', prepared=None, prepared_sha=None, confirm=None, runner=None):
    require(mode in {'prepare', 'preflight', 'register'}, 'explicit-mode')
    if mode == 'register': require(confirm == CONFIRM and prepared is not None and prepared_sha is not None, 'separate-registration-confirmation-and-prepared-manifest-required')
    else: require(confirm is None and prepared is None and prepared_sha is None, 'mode-arguments-separated')
    package, manifest, development = validate(package, anchor)
    output = fresh(output, package)
    original = load(package/'run_activated_registration_loop.py', 'pinned_activated_loop')
    if mode == 'register':
        prepared = Path(prepared).absolute()
        require(isinstance(prepared_sha, str) and HEX.fullmatch(prepared_sha) and digest(prepared)['sha256'] == prepared_sha, 'prepared-manifest-anchor')
        require(read_json(prepared) == development, 'prepared-manifest-package-binding')
        return original.execute(prepared, prepared_sha, output, confirm, runner=runner)
    output.mkdir()
    target = output/'development-manifest.json'; original.save(target, development)
    development_sha = digest(target)['sha256']; original.inputs(target, development_sha)
    receipt = {'schema': 'activated-loop-package-entry-v1', 'mode': mode, 'sourceCommit': manifest['sourceCommit'], 'packageManifestSHA256': anchor, 'developmentManifestSHA256': development_sha, 'sourceAuthenticityVerified': False, 'registrationExecuted': False, 'status': 'prepared-static-only'}
    original.save(output/'entry-result.json', receipt)
    if mode == 'prepare': return receipt
    if runner is None: runner = load(package/'bin/windows_job_once.py', 'pinned_preflight_job').run_once
    stdout = output/'preflight-stdout.json'; stderr = output/'preflight-stderr.log'
    try:
        state = runner([str(package/'bin/YimeMyComputerActivationStage1.exe'), '--preflight', '--dll', str(package/'bin/YimeTextService18u.dll'), '--sha256', manifest['files']['bin/YimeTextService18u.dll']['sha256']], output, stdout, stderr, 30)
        receipt['process'] = state
        require(original.complete(state), 'preflight-process-incomplete')
        validator = load(package/'bin/validate_local_activation_evidence.py', 'pinned_preflight_validator')
        require(stdout.stat().st_size <= 65536 and stderr.stat().st_size <= 65536, 'preflight-evidence-size')
        raw_report = stdout.read_text(encoding='utf-8-sig')
        receipt['preflight'] = validator.strict_json(raw_report)
        # report() also requires completed/code 0 and rejects actual DLL activation.
        report = validator.report(raw_report)
        require(report['mode'] == 'preflight' and report['status'] == 'checked' and report['writesStarted'] is False and report['profileActivationApiVerified'] is False and not stderr.read_bytes().strip(), 'readonly-preflight-only')
        require(all(type(v) is bool for v in report['preconditions'].values()) and type(report['prerequisitesSatisfied']) is bool and report['prerequisitesSatisfied'] == all(report['preconditions'].values()), 'preflight-prerequisite-consistency')
        require(report['dllSha256'] == manifest['files']['bin/YimeTextService18u.dll']['sha256'], 'preflight-dll-binding')
        validate(package, anchor)
        receipt.update(status='preflight-observed-not-registration', preflight=report)
    except (OSError, ValueError, TypeError, KeyError): receipt['status'] = 'preflight-incomplete'
    finally:
        receipt['evidenceFiles'] = {p.name: digest(p) for p in (stdout, stderr) if p.is_file()}
        original.save(output/'entry-result.json', receipt)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['prepare', 'preflight', 'register'], default='prepare')
    parser.add_argument('--package', type=Path, required=True); parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--prepared-manifest', type=Path); parser.add_argument('--prepared-manifest-sha256'); parser.add_argument('--confirm')
    args = parser.parse_args()
    result = execute(args.package, args.manifest_sha256, args.output, args.mode, args.prepared_manifest, args.prepared_manifest_sha256, args.confirm)
    print(json.dumps(result))
    expected = {'prepare': 'prepared-static-only', 'preflight': 'preflight-observed-not-registration', 'register': 'edit-and-independent-cleanup-evidence-consistent'}
    return 0 if result['status'] == expected[args.mode] else 1


if __name__ == '__main__': sys.exit(main())
