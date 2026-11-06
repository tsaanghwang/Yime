"""Inspect downloaded CI evidence only; never execute Go or product programs."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[6]
sys.dont_write_bytecode = True
from verify_package import (MAX_SMALL, file_digest, git, inventory, json_object,
                            plain_path, require, source_bytes, source_match, zip_members)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--architecture', choices=('amd64', 'arm64'), required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--expected-sha256', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    require(re.fullmatch('[0-9a-f]{40}', args.source_commit), 'Full lowercase source SHA required')
    require(re.fullmatch('[0-9a-f]{64}', args.expected_sha256), 'Expected artifact SHA-256 required')
    args.archive, args.output = plain_path(args.archive), plain_path(args.output)
    require(args.archive.is_file() and not args.output.exists(), 'Existing archive and fresh output required')
    require(git(ROOT, 'rev-parse', args.source_commit + '^{commit}').decode().strip() == args.source_commit,
            'Source must identify an existing exact commit')
    helper_path = 'tools/yimecore/verify_18u_broker_offline.py'
    helper_binding = source_match(ROOT, args.source_commit, helper_path, (ROOT / helper_path).read_bytes())
    # This pinned helper defines validators only on import; run()/main() are
    # never called, and bytecode writes are disabled for this archive audit.
    sys.path.insert(0, str(ROOT / 'tools/yimecore'))
    import verify_18u_broker_offline as verifier
    archive_record = file_digest(args.archive)
    archive_hash = archive_record['sha256']
    if archive_hash != args.expected_sha256:
        raise ValueError('Artifact hash mismatch')
    with zipfile.ZipFile(args.archive) as archive:
        names = {'result.json', 'cmd-yimebroker-18u.jsonl', 'internal-touchbroker.jsonl'}
        members = zip_members(archive)
        if set(members) != names or any(info.file_size > MAX_SMALL for info in members.values()):
            raise ValueError('Evidence inventory mismatch')
        raw = {name:archive.read(name) for name in names}
    result = json_object(raw['result.json'])
    if (result['schema'] != '18u-broker-native-offline-v1'
            or result['scope'] != 'startup-ready-orchestration-and-in-memory-resource-session-only'
            or result['status'] != 'passed' or result['architecture'] != args.architecture
            or result['sourceCommit'] != args.source_commit or result['sourceChanges'] is not False):
        raise ValueError('Source/architecture/success identity mismatch')
    for field in ('productServiceExecuted','namedPipeOpened','installationExecuted',
                  'registrationExecuted','realHostExecuted','physicalAcceptance'):
        if result[field] is not False:
            raise ValueError('Not offline evidence: ' + field)
    if result['readyContract'] != {'transport': 'stub-no-named-pipe',
                                    'resourceIdentityBeforeReady': 'production-descriptor',
                                    'resourceBytesValidation': 'separate-first-open-tests',
                                    'actualBrokerReadyObserved': False}:
        raise ValueError('Unexpected READY contract claim')
    require(result['readyContract']['actualBrokerReadyObserved'] is False, 'Actual READY observation must be false')
    lock_path = 'prototypes/touch-terminal/desktop/resources.lock.json'
    lock_raw = source_bytes(ROOT, args.source_commit, lock_path)
    lock = json_object(lock_raw)
    require(lock.get('schemaVersion') == 1 and lock.get('scope') == 'isolated-cn134-complete-derived-runtime',
            'Fixed-source resource lock schema mismatch')
    require(inventory(result['resources']) == inventory(lock['files']), 'Reported resources differ from fixed source lock')
    # The report hashes runner checkout bytes, while git show returns blob
    # bytes. Accept only the fixed blob or its LF/CRLF checkout representations,
    # and report which representation matches instead of claiming raw equality.
    lf_lock = lock_raw.replace(b'\r\n', b'\n')
    lock_forms = {'git-blob': lock_raw, 'LF': lf_lock, 'CRLF': lf_lock.replace(b'\n', b'\r\n')}
    matching_forms = [name for name, content in lock_forms.items()
                      if hashlib.sha256(content).hexdigest() == result['resourceLockSHA256']]
    require(matching_forms, 'Reported resource lock hash does not match fixed source bytes or checkout line endings')
    verifier.validate_go_environment(result['goEnvironment'], args.architecture)
    require(result['goEnvironment'].get('GOHOSTARCH') == args.architecture, 'Native Go toolchain architecture mismatch')
    require(set(result['tests']) == set(verifier.GROUPS), 'Unexpected reported test group inventory')
    checked = {}
    for group, required in verifier.GROUPS.items():
        log = raw[group.replace('/', '-') + '.jsonl']
        if hashlib.sha256(log).hexdigest() != result['tests'][group]['logSHA256']:
            raise ValueError('Log digest mismatch')
        checked[group] = verifier.validate_events(log.decode('utf-8'), verifier.MODULE + '/' + group,
                                                  required, args.architecture,
                                                  require_native=group == 'cmd/yimebroker-18u')
        if any(result['tests'][group][key] != value for key,value in checked[group].items()):
            raise ValueError('Reported test observation mismatch')
    require(file_digest(args.archive) == archive_record, 'Evidence archive changed during verification')
    args.output.mkdir(parents=True, exist_ok=False)
    for name, content in raw.items():
        (args.output / name).write_bytes(content)
    summary = {'schema':'installed-18u-dot9-native-evidence-verification-v1',
               'status':'passed','sourceCommit':args.source_commit,'architecture':args.architecture,
               'verifiedAtUTC':datetime.now(timezone.utc).isoformat(),
               'archiveSHA256':archive_hash,'archiveBytes':archive_record['bytes'],
               'verifierScript':file_digest(Path(__file__)), 'validationHelper':helper_binding,
               'staticArchiveHelper':file_digest(Path(__file__).with_name('verify_package.py')),
               'resourceLockBinding':{'sourcePath':lock_path,
                                      'sourceGitBlob':git(ROOT, 'rev-parse', args.source_commit + ':' + lock_path).decode().strip(),
                                      'sourceBlobBytes':{'bytes':len(lock_raw),'sha256':hashlib.sha256(lock_raw).hexdigest()},
                                      'reportedCheckoutSHA256':result['resourceLockSHA256'],
                                      'matchingRepresentations':matching_forms, 'resources':lock['files']},
               'requiredTestCount':sum(len(group) for group in verifier.GROUPS.values()),
               'tests':checked,'scope':'downloaded-evidence-only-no-test-rerun',
               'testRerun':False,'productBinaryExecuted':False,'installationExecuted':False,
               'registrationExecuted':False,'installedHostAcceptance':False,'physicalAcceptance':False}
    (args.output / 'verification.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(summary))

if __name__ == '__main__':
    main()
