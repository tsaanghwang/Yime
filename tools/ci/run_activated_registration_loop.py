"""Developer-only bounded activated-instance loop. Not a v2 package entry point.

No invocation is authorized by merely possessing this file. The independent
manifest hash pins development inputs, not publisher authenticity. Mock runners
and reports are test evidence only, never proof of Windows/TSF execution.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys

CONFIRM = 'once-activated-18u-loop'
LAYOUT_SHA = '995f1a74f129249febbd09ca11a8266f6e0c94bac8c05c57754859fc3be3349c'
DICTIONARY_SHA = '43a74f4e47c7100f222a744f487762f1c31222c5f80b9a34fd24cbebc7e96353'
BINARIES = {'YimeActivatedLoopController.exe', 'YimeActivatedLoopOnce.exe', 'YimeTextService18u.dll', 'YimeBroker18u.exe', 'YimeMyComputerActivationStage1.exe', 'windows_job_once.py', 'validate_local_activation_evidence.py'}
SOURCES = {'tools/yimecore/18u-touch-product.json', 'prototypes/touch-terminal/data/physical-layout.json', 'prototypes/touch-terminal/encoding/yime_yinyuan_layout.json', 'internal_data/yime_syllable_decomposition.tsv'}
DATA = {'ascii_keyboard_manifest.json', 'yime_variable.dict.yaml', 'yime_full.dict.yaml', 'yime_shorthand.dict.yaml'}
HEX = re.compile(r'[0-9a-f]{64}\Z')


def require(value, reason):
    if not value: raise ValueError(reason)


def strict_json(raw):
    require(isinstance(raw, bytes) and len(raw) <= 1024 * 1024, 'bounded-json-required')
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'duplicate-json-field')
            result[key] = value
        return result
    return json.loads(raw.decode('utf-8-sig'), object_pairs_hook=unique,
                      parse_constant=lambda _: (_ for _ in ()).throw(ValueError('nonfinite-json')))


def regular(path):
    for part in [path, *path.parents]:
        info = part.lstat()
        require(not stat.S_ISLNK(info.st_mode) and not getattr(info, 'st_file_attributes', 0) & 0x400, 'reparse-input-rejected')
    require(path.is_file(), 'regular-input-required')


def digest(path):
    regular(path)
    h = hashlib.sha256(); size = 0
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            size += len(block); require(size <= 2**32, 'input-size-limit'); h.update(block)
    return {'bytes': size, 'sha256': h.hexdigest()}


def bounded(path, limit=1024 * 1024):
    regular(path)
    with path.open('rb') as stream: raw = stream.read(limit + 1)
    require(len(raw) <= limit, 'evidence-size-limit')
    return raw


def save(path, data):
    temporary = path.with_name(path.name + '.tmp')
    with temporary.open('x', encoding='utf-8') as stream:
        json.dump(data, stream, ensure_ascii=True, indent=2); stream.write('\n')
        stream.flush(); os.fsync(stream.fileno())
    os.replace(temporary, path)


def module(path, name):
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


def inputs(manifest_path, anchor):
    require(isinstance(anchor, str) and HEX.fullmatch(anchor), 'independent-manifest-hash-required')
    raw = bounded(Path(manifest_path).absolute())
    require(hashlib.sha256(raw).hexdigest() == anchor, 'development-manifest-hash-mismatch')
    data = strict_json(raw)
    require(isinstance(data, dict) and set(data) == {'schema', 'sourceCommit', 'architecture', 'binaryDirectory', 'sourceRoot', 'dataDirectory', 'binaries', 'sources', 'data'}, 'development-manifest-fields')
    require(data['schema'] == 'activated-loop-development-manifest-v1' and data['architecture'] == 'native-x64', 'development-manifest-identity')
    require(isinstance(data['sourceCommit'], str) and re.fullmatch('[0-9a-f]{40}', data['sourceCommit']), 'source-commit-required')
    roots = {}
    for field in ['binaryDirectory', 'sourceRoot', 'dataDirectory']:
        require(isinstance(data[field], str) and Path(data[field]).is_absolute(), 'absolute-development-directory-required')
        roots[field] = Path(data[field]); require(roots[field].is_dir(), 'development-directory-missing')
    for field, root, expected in [('binaries', roots['binaryDirectory'], BINARIES), ('sources', roots['sourceRoot'], SOURCES), ('data', roots['dataDirectory'], DATA)]:
        rows = data[field]; require(isinstance(rows, dict) and set(rows) == expected, 'fixed-development-file-set')
        for name, row in rows.items():
            require(isinstance(row, dict) and set(row) == {'bytes', 'sha256'} and type(row['bytes']) is int and row['bytes'] >= 0 and isinstance(row['sha256'], str) and HEX.fullmatch(row['sha256']), 'development-file-record')
            require(digest(root / name) == row, 'development-file-hash-mismatch')
    require(set(path.name for path in roots['binaryDirectory'].iterdir()) == BINARIES, 'unexpected-development-binary')
    product = strict_json(bounded(roots['sourceRoot'] / 'tools/yimecore/18u-touch-product.json'))
    require(isinstance(product, dict), 'product-descriptor-object-required')
    identity = product.get('identity', {}); projection = product.get('data', {})
    require(isinstance(identity, dict) and isinstance(projection, dict), 'product-identity-data-objects-required')
    require(product.get('schema_version') == 'yimecore-18u-touch-product-v1' and product.get('installable') is False, 'product-descriptor')
    require(identity.get('product_key') == 'YimeCore18uTouch' and identity.get('clsid') == '{6DFACE1F-562E-4773-A9D6-D5753A314711}' and identity.get('profile') == '{1BD904AC-3194-4419-B70A-5574100F18B3}' and identity.get('language_id') == '0804', 'independent-product-identity')
    require(projection.get('layout_sha256') == LAYOUT_SHA and projection.get('dictionary_sha256') == DICTIONARY_SHA and projection.get('standard_index_fallback') is False, 'fixed-product-data-identity')
    scope = product.get('scope')
    require(isinstance(scope, dict) and scope.get('architecture') == 'x64' and scope.get('language') == 'CN' and scope.get('mode') == 'variable' and scope.get('persistent_learning') is False and scope.get('registration_validated') is False and scope.get('user_machine_execution_approved') is False, 'product-unvalidated-development-scope')
    require(data['data']['yime_variable.dict.yaml']['sha256'] == DICTIONARY_SHA, 'fixed-variable-dictionary-hash')
    return data, roots


def complete(state):
    return isinstance(state, dict) and state.get('started') is True and state.get('treeStopped') is True and state.get('timedOut') is False and state.get('errorCode') is None and type(state.get('exitCode')) is int and state['exitCode'] == 0


def valid_root(value):
    return isinstance(value, dict) and set(value) == {'pid', 'creationFileTime'} and type(value['pid']) is int and 0 < value['pid'] <= 0xffffffff and isinstance(value['creationFileTime'], str) and re.fullmatch('[1-9][0-9]{0,19}', value['creationFileTime']) and int(value['creationFileTime']) < 2**64


def execute(manifest_path, anchor, evidence, confirmation, runner=None):
    require(confirmation == CONFIRM, 'explicit-development-loop-confirmation-required')
    manifest, roots = inputs(manifest_path, anchor)
    directory = Path(evidence).absolute()
    require(not directory.exists() and not directory.is_symlink(), 'fresh-evidence-directory-required')
    resolved = directory.resolve(strict=False)
    for path in roots.values():
        protected = path.resolve()
        require(resolved != protected and protected not in resolved.parents, 'evidence-outside-input-directories-required')
    directory.mkdir(parents=False, exist_ok=False)
    bins = roots['binaryDirectory']
    job = module(bins / 'windows_job_once.py', 'activated_loop_pinned_job') if runner is None else None
    runner = runner or job.run_once
    gate = module(bins / 'validate_local_activation_evidence.py', 'activated_loop_pinned_absence')
    receipt = {'schema': 'activated-loop-development-run-v1', 'status': 'failed-or-inconclusive',
               'manifestSha256': anchor, 'sourceCommit': manifest['sourceCommit'],
               'entryScriptSha256': digest(Path(__file__).absolute())['sha256'],
               'entryScriptCoveredByManifest': False, 'sourceAuthenticityVerified': False,
               'rootIdentity': None, 'process': None, 'verificationProcess': None,
               'loopInvocations': 0, 'verificationInvocations': 0,
               'automaticRecoveryAttempted': False, 'editingEvidenceConsistent': False,
               'cleanupEvidenceConsistent': False, 'physicalAcceptance': False,
               'files': {group: manifest[group] for group in ['binaries', 'sources', 'data']},
               'evidenceFiles': {}}
    receipt_path = directory / 'run.json'; save(receipt_path, receipt)
    def root_created(identity):
        require(valid_root(identity) and receipt['rootIdentity'] is None, 'invalid-or-repeated-root-identity')
        receipt['rootIdentity'] = dict(identity); save(receipt_path, receipt)
    command = [str(bins / 'YimeActivatedLoopController.exe'), '--root', str(roots['sourceRoot']),
               '--data-dir', str(roots['dataDirectory']), '--evidence-dir', str(directory / 'controller'),
               '--dll-sha256', manifest['binaries']['YimeTextService18u.dll']['sha256'],
               '--broker-sha256', manifest['binaries']['YimeBroker18u.exe']['sha256'], '--confirm', CONFIRM]
    try:
        receipt['loopInvocations'] = 1; save(receipt_path, receipt)
        state = runner(command, directory, directory / 'controller-stdout.json', directory / 'controller-stderr.log', 240, on_root_created=root_created)
        receipt['process'] = state; save(directory / 'controller-process.json', state)
        require(complete(state), 'controller-not-complete-or-tree-not-stopped')
        require(valid_root(receipt['rootIdentity']) and state.get('rootIdentity') == receipt['rootIdentity'], 'controller-root-receipt-mismatch')
        require(not bounded(directory / 'controller-stderr.log').strip(), 'unexpected-controller-stderr')
        report = strict_json(bounded(directory / 'controller-stdout.json'))
        require(report == strict_json(bounded(directory / 'controller/controller-result.json')), 'controller-report-file-mismatch')
        validate_controller(report, manifest, receipt['rootIdentity'])
        host_lines = bounded(directory / 'controller/host-stdout.jsonl').splitlines()
        require(len(host_lines) == 2, 'host-output-event-count')
        connected = strict_json(host_lines[0])
        require(isinstance(connected, dict) and set(connected) == {'stage', 'accepted'} and connected['stage'] == 'connected' and connected['accepted'] is True, 'accepted-connection-evidence-required')
        require(strict_json(host_lines[1]) == report['nativeResult'], 'host-terminal-controller-mismatch')
        marker = strict_json(bounded(directory / 'controller/host-stderr.jsonl'))
        require(marker == {'stage': 'registered-probe/actual-activate-success', 'kind': 'marker', 'code': 0} and type(marker.get('code')) is int, 'unique-actual-activation-marker-required')
        require(not bounded(directory / 'controller/broker-stderr.jsonl').strip(), 'unexpected-broker-stderr')
        ledger_path = directory / 'controller/registration-ledger.dpapi'
        receipt['ledgerEvidence'] = digest(ledger_path)
        require(receipt['ledgerEvidence']['bytes'] > 0, 'owned-ledger-evidence-required')
        # A normal cleanup report is necessary before a separate read-only check.
        # No timeout/failed-loop path invokes recovery or retries registration.
        inputs(manifest_path, anchor)
        receipt['editingEvidenceConsistent'] = True
        receipt['verificationInvocations'] = 1; save(receipt_path, receipt)
        verify = runner([str(bins / 'YimeMyComputerActivationStage1.exe'), '--verify'], directory,
                        directory / 'verify-stdout.json', directory / 'verify-stderr.log', 30)
        receipt['verificationProcess'] = verify; save(directory / 'verify-process.json', verify)
        require(complete(verify), 'independent-absence-check-not-complete')
        gate.validate_absence(bounded(directory / 'verify-stdout.json').decode('utf-8-sig'),
                              bounded(directory / 'verify-stderr.log').decode('utf-8-sig'), 0)
        inputs(manifest_path, anchor)
        require(digest(ledger_path) == receipt['ledgerEvidence'], 'owned-ledger-evidence-changed')
        receipt['cleanupEvidenceConsistent'] = True
        receipt['status'] = 'edit-and-independent-cleanup-evidence-consistent'
    except (OSError, ValueError, TypeError, KeyError, UnicodeError) as error:
        # Fixed parser reasons only; raw child logs remain local evidence files.
        text = str(error)
        receipt['failureReason'] = text if re.fullmatch('[a-z][a-z0-9-]{0,100}', text) else 'malformed-or-unavailable-loop-evidence'
    finally:
        for name in ['controller-stdout.json', 'controller-stderr.log', 'controller/controller-result.json', 'controller/host-stdout.jsonl', 'controller/host-stderr.jsonl', 'controller/broker-stderr.jsonl', 'controller/registration-ledger.dpapi', 'verify-stdout.json', 'verify-stderr.log']:
            path = directory / name
            if path.is_file():
                try: receipt['evidenceFiles'][name] = digest(path)
                except (OSError, ValueError): receipt['evidenceFiles'][name] = None
        save(receipt_path, receipt)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--confirm', required=True)
    args = parser.parse_args()
    result = execute(args.manifest, args.manifest_sha256, args.evidence, args.confirm)
    print(json.dumps(result))
    return 0 if result['status'] == 'edit-and-independent-cleanup-evidence-consistent' else 1


def validate_controller(report, manifest, root):
    fields = {'schema', 'status', 'stage', 'hostPID', 'brokerPID', 'hostExited', 'brokerExited', 'hostExitCode', 'brokerExitCode', 'nativeResult', 'cleanupVerified', 'readbackVerified'}
    require(isinstance(report, dict) and set(report) == fields, 'controller-report-fields')
    require(report['schema'] == 'activated-loop-controller-v1' and report['status'] == 'evidence-consistent' and report['stage'] == 'completed', 'controller-report-completion')
    for field in ['hostExited', 'brokerExited', 'cleanupVerified', 'readbackVerified']:
        require(report[field] is True, 'controller-completion-bools')
    for field in ['hostExitCode', 'brokerExitCode']:
        require(type(report[field]) is int and report[field] == 0, 'child-normal-exit-required')
    for field in ['hostPID', 'brokerPID']:
        require(type(report[field]) is int and 0 < report[field] <= 0xffffffff, 'child-pid-required')
    require(len({report['hostPID'], report['brokerPID'], root['pid']}) == 3, 'distinct-owned-processes-required')
    native = report['nativeResult']
    fields = {'schema', 'status', 'writesStarted', 'cleanupVerified', 'operationFailure', 'cleanupFailure', 'hostResult', 'hostPID', 'brokerPID', 'windowsSessionID', 'brokerCreationTime', 'ledgerOwnerPID', 'ledgerOwnerCreationTime', 'publisherTrust'}
    require(isinstance(native, dict) and set(native) == fields, 'native-terminal-fields')
    require(native['schema'] == 'activated-loop-result-v1' and native['status'] == 'passed' and native['publisherTrust'] == 'not-established', 'native-terminal-identity')
    require(native['writesStarted'] is True and native['cleanupVerified'] is True and native['operationFailure'] is None and native['cleanupFailure'] is None, 'native-operation-or-cleanup-failed')
    for key, expected in [('hostPID', report['hostPID']), ('brokerPID', report['brokerPID']), ('ledgerOwnerPID', report['hostPID'])]:
        require(type(native[key]) is int and native[key] == expected, 'native-owner-pid-binding')
    require(type(native['windowsSessionID']) is int and 0 <= native['windowsSessionID'] <= 0xffffffff, 'native-session-required')
    for field in ['brokerCreationTime', 'ledgerOwnerCreationTime']:
        require(type(native[field]) is int and 0 < native[field] < 2**64, 'native-creation-time-required')
    host = native['hostResult']
    true_fields = {'actualDLLLoaded', 'registered', 'readbackMatches', 'otherContextEmpty', 'hostCleanupVerified'}
    false_fields = {'sendInput', 'rejected', 'duplicateRejected', 'readbackEmpty', 'unknownAfterPendingEditCovered', 'operationPendingObserved', 'postWriteDisconnectObserved', 'replayRejected'}
    require(isinstance(host, dict) and set(host) == true_fields | false_fields | {'stage', 'scenario', 'activationIdentity', 'outcome', 'sessionBinding'}, 'formal-host-result-fields')
    require(host['stage'] == 'result' and host['scenario'] == 'commit' and host['activationIdentity'] == 'windows-activated-profile' and host['outcome'] == 'applied', 'activated-commit-only-required')
    require(all(host[field] is True for field in true_fields) and all(host[field] is False for field in false_fields), 'actual-edit-readback-or-host-cleanup-unproven')
    binding = host['sessionBinding']
    require(isinstance(binding, dict) and set(binding) == {'sessionId', 'identity', 'focus'}, 'session-binding-fields')
    require(isinstance(binding['sessionId'], str) and 0 < len(binding['sessionId']) <= 256, 'session-id-required')
    identity = binding['identity']; focus = binding['focus']
    require(isinstance(identity, dict) and set(identity) == {'layoutSHA256', 'dictionarySHA256', 'mode', 'sessionPolicy'}, 'session-identity-fields')
    require(identity == {'layoutSHA256': LAYOUT_SHA, 'dictionarySHA256': DICTIONARY_SHA, 'mode': 'variable', 'sessionPolicy': 'concept-keyboard-modes-v2+ellipsis-choice-v1'}, 'session-production-identity')
    require(isinstance(focus, dict) and set(focus) == {'context', 'epoch'} and isinstance(focus['context'], str) and 0 < len(focus['context']) <= 256 and type(focus['epoch']) is int and 0 < focus['epoch'] < 2**64, 'session-focus-binding')
    return report


if __name__ == '__main__': sys.exit(main())
