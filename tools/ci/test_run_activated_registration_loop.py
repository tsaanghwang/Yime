"""Synthetic offline fixtures only: no real binaries, TSF, registration or registry writes."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import run_activated_registration_loop as loop


def hash_bytes(value): return hashlib.sha256(value).hexdigest()


def native_fixture():
    host = dict(stage='result', scenario='commit', actualDLLLoaded=True, activationIdentity='windows-activated-profile', registered=True, sendInput=False, outcome='applied', rejected=False, duplicateRejected=False, readbackMatches=True, readbackEmpty=False, otherContextEmpty=True, unknownAfterPendingEditCovered=False, operationPendingObserved=False, postWriteDisconnectObserved=False, replayRejected=False, hostCleanupVerified=True,
                sessionBinding={'sessionId': 'synthetic-session', 'identity': {'layoutSHA256': loop.LAYOUT_SHA, 'dictionarySHA256': loop.DICTIONARY_SHA, 'mode': 'variable', 'sessionPolicy': 'concept-keyboard-modes-v2+ellipsis-choice-v1'}, 'focus': {'context': 'synthetic-owned-context', 'epoch': 1}})
    return dict(schema='activated-loop-result-v1', status='passed', writesStarted=True, cleanupVerified=True, operationFailure=None, cleanupFailure=None, hostResult=host, hostPID=101, brokerPID=102, windowsSessionID=1, brokerCreationTime=200, ledgerOwnerPID=101, ledgerOwnerCreationTime=100, publisherTrust='not-established')


def report_fixture():
    return dict(schema='activated-loop-controller-v1', status='evidence-consistent', stage='completed', hostPID=101, brokerPID=102, hostExited=True, brokerExited=True, hostExitCode=0, brokerExitCode=0, nativeResult=native_fixture(), cleanupVerified=True, readbackVerified=True)


def verify_fixture():
    return dict(schema='mycomputer-activation-stage1-v1', scope='mycomputer-registration-activation-only', mode='verify', status='pass', stage='completed', code=0, writesStarted=False, cleanupVerified=True, preconditions=dict.fromkeys(['nativeX64', 'hostMatches', 'hkl0804', 'tsf0804', 'elevated', 'identityAbsent', 'dllVerified', 'directTestAbsent']), prerequisitesSatisfied=False, actualHostName=None, threadLanguage=None, currentLanguage=None, dllSha256=None, dllPresent=None, publisherTrust='not-established', brokerEditingVerified=False, profileActivationApiVerified=False, actualDllActivationVerified=False)


class SyntheticLoopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.bins = self.root/'bin'; self.source = self.root/'source'; self.data = self.root/'data'
        for directory in [self.bins, self.source, self.data]: directory.mkdir()
        variable = b'synthetic-variable-dictionary-not-product-data\n'
        # Explicitly substitute only this offline test's immutable data identity.
        self.pin = patch.object(loop, 'DICTIONARY_SHA', hash_bytes(variable)); self.pin.start(); self.addCleanup(self.pin.stop)
        validator = Path(loop.__file__).with_name('validate_local_activation_evidence.py').read_bytes()
        for name in loop.BINARIES:
            (self.bins/name).write_bytes(validator if name == 'validate_local_activation_evidence.py' else b'# synthetic nonexecutable fixture '+name.encode())
        product = {'schema_version': 'yimecore-18u-touch-product-v1', 'installable': False,
                   'identity': {'product_key': 'YimeCore18uTouch', 'clsid': '{6DFACE1F-562E-4773-A9D6-D5753A314711}', 'profile': '{1BD904AC-3194-4419-B70A-5574100F18B3}', 'language_id': '0804'},
                   'data': {'layout_sha256': loop.LAYOUT_SHA, 'dictionary_sha256': loop.DICTIONARY_SHA, 'standard_index_fallback': False},
                   'scope': {'architecture': 'x64', 'language': 'CN', 'mode': 'variable', 'persistent_learning': False, 'registration_validated': False, 'user_machine_execution_approved': False}}
        for name in loop.SOURCES:
            path = self.source/name; path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(json.dumps(product).encode() if name.endswith('18u-touch-product.json') else b'synthetic source fixture')
        for name in loop.DATA: (self.data/name).write_bytes(variable if name == 'yime_variable.dict.yaml' else b'synthetic other dictionary fixture')
        self.manifest = {'schema': 'activated-loop-development-manifest-v1', 'sourceCommit': 'a'*40, 'architecture': 'native-x64', 'binaryDirectory': str(self.bins), 'sourceRoot': str(self.source), 'dataDirectory': str(self.data), 'binaries': {}, 'sources': {}, 'data': {}}
        self.path = self.root/'development-inputs.json'; self.repin()
        self.calls = []; self.report = report_fixture(); self.verify = verify_fixture()
        self.timeout = False; self.tree = True; self.marker = True; self.ledger = True; self.duplicate = False; self.report_mismatch = False
    def repin(self):
        for group, directory, names in [('binaries', self.bins, loop.BINARIES), ('sources', self.source, loop.SOURCES), ('data', self.data, loop.DATA)]:
            self.manifest[group] = {name: loop.digest(directory/name) for name in names}
        self.path.write_text(json.dumps(self.manifest)); self.anchor = hash_bytes(self.path.read_bytes())
    def runner(self, command, cwd, stdout, stderr, timeout, on_root_created=None):
        self.calls.append(command)
        state = dict(started=True, treeStopped=True, timedOut=False, errorCode=None, exitCode=0, rootIdentity=dict(pid=100, creationFileTime='10'))
        if on_root_created:
            on_root_created(state['rootIdentity'])
            self.assertEqual(Path(command[0]).name, 'YimeActivatedLoopController.exe')
            self.assertEqual(command[-2:], ['--confirm', loop.CONFIRM])
            child = Path(command[command.index('--evidence-dir')+1]); child.mkdir()
            raw = json.dumps(self.report)
            if self.duplicate: raw = raw.replace('"hostPID": 101', '"hostPID": 101, "hostPID": 101', 1)
            Path(stdout).write_text(raw); Path(stderr).write_bytes(b'')
            other = copy.deepcopy(self.report)
            if self.report_mismatch: other['stage'] = 'different'
            (child/'controller-result.json').write_text(json.dumps(other))
            (child/'host-stdout.jsonl').write_text(json.dumps({'stage': 'connected', 'accepted': True})+'\n'+json.dumps(self.report['nativeResult'])+'\n')
            (child/'host-stderr.jsonl').write_text(json.dumps({'stage': 'registered-probe/actual-activate-success', 'kind': 'marker', 'code': 0}) if self.marker else '')
            (child/'broker-stderr.jsonl').write_bytes(b'')
            if self.ledger: (child/'registration-ledger.dpapi').write_bytes(b'synthetic encrypted-ledger fixture, not actual DPAPI')
            self.assertEqual(timeout, 240)
            state.update(timedOut=self.timeout, treeStopped=self.tree)
        else:
            self.assertEqual(command, [str(self.bins/'YimeMyComputerActivationStage1.exe'), '--verify'])
            Path(stdout).write_text(json.dumps(self.verify)); Path(stderr).write_bytes(b'')
        return state
    def execute(self):
        return loop.execute(self.path, self.anchor, self.root/'evidence', loop.CONFIRM, runner=self.runner)
    def test_synthetic_happy_path_is_one_loop_then_one_absence(self):
        result = self.execute(); self.assertEqual(len(self.calls), 2)
        self.assertEqual(result['status'], 'edit-and-independent-cleanup-evidence-consistent')
        self.assertFalse(result['sourceAuthenticityVerified']); self.assertFalse(result['entryScriptCoveredByManifest'])
        self.assertFalse(result['automaticRecoveryAttempted']); self.assertFalse(result['physicalAcceptance'])
    def test_timeout_or_unknown_tree_never_verifies_or_recovers(self):
        for attribute in ['timeout', 'tree']:
            with self.subTest(attribute=attribute):
                self.timeout = attribute == 'timeout'; self.tree = attribute != 'tree'
                result = loop.execute(self.path, self.anchor, self.root/attribute, loop.CONFIRM, runner=self.runner)
                self.assertFalse(result['cleanupEvidenceConsistent']); self.assertEqual(result['verificationInvocations'], 0)
        self.assertEqual(len(self.calls), 2)
    def test_failed_native_cleanup_does_not_launch_absence(self):
        self.report['nativeResult']['cleanupVerified'] = False
        result = self.execute(); self.assertEqual(len(self.calls), 1); self.assertFalse(result['editingEvidenceConsistent'])
    def test_wrong_owner_and_direct_activation_rejected(self):
        root = dict(pid=100, creationFileTime='10')
        for mutate in [lambda r: r['nativeResult'].update(ledgerOwnerPID=999), lambda r: r['nativeResult']['hostResult'].update(activationIdentity='owned-host-activation-client')]:
            candidate = report_fixture(); mutate(candidate)
            with self.assertRaises(ValueError): loop.validate_controller(candidate, self.manifest, root)
    def test_session_identity_and_focus_are_required(self):
        for mutate in [lambda b: b.update(sessionId=''), lambda b: b['identity'].update(dictionarySHA256='0'*64), lambda b: b['focus'].update(epoch=False)]:
            candidate = report_fixture(); mutate(candidate['nativeResult']['hostResult']['sessionBinding'])
            with self.assertRaises(ValueError): loop.validate_controller(candidate, self.manifest, dict(pid=100, creationFileTime='10'))
    def test_missing_or_null_nested_fields_rejected(self):
        for location in [(), ('nativeResult',), ('nativeResult', 'hostResult')]:
            original = report_fixture(); fields = original
            for part in location: fields = fields[part]
            for name in list(fields):
                candidate = copy.deepcopy(original); target = candidate
                for part in location: target = target[part]
                del target[name]
                with self.assertRaises(ValueError): loop.validate_controller(candidate, self.manifest, dict(pid=100, creationFileTime='10'))
    def test_duplicate_json_never_launches_verify(self):
        self.duplicate = True; result = self.execute()
        self.assertEqual(len(self.calls), 1); self.assertFalse(result['cleanupEvidenceConsistent'])
    def test_missing_ledger_never_launches_absence(self):
        self.ledger = False; result = self.execute()
        self.assertEqual(len(self.calls), 1); self.assertFalse(result['cleanupEvidenceConsistent'])
    def test_missing_marker_fails_even_with_success_labels(self):
        self.marker = False; result = self.execute()
        self.assertEqual(len(self.calls), 1); self.assertFalse(result['editingEvidenceConsistent'])
    def test_stdout_and_persisted_report_must_match(self):
        self.report_mismatch = True; result = self.execute()
        self.assertEqual(len(self.calls), 1); self.assertFalse(result['editingEvidenceConsistent'])
    def test_independent_absence_failure_is_not_overridden(self):
        self.verify['cleanupVerified'] = False; result = self.execute()
        self.assertEqual(len(self.calls), 2); self.assertTrue(result['editingEvidenceConsistent']); self.assertFalse(result['cleanupEvidenceConsistent'])
    def test_manifest_anchor_and_tampered_binary_stop_before_launch(self):
        with self.assertRaises(ValueError): loop.execute(self.path, '0'*64, self.root/'bad', loop.CONFIRM, runner=self.runner)
        (self.bins/'YimeBroker18u.exe').write_bytes(b'tampered')
        with self.assertRaises(ValueError): self.execute()
        self.assertEqual(self.calls, [])
    def test_invalid_product_objects_are_cleanly_rejected(self):
        target = self.source/'tools/yimecore/18u-touch-product.json'
        for item in [[], None, {'identity': []}, {'identity': {}, 'data': None}]:
            target.write_text(json.dumps(item)); self.repin()
            with self.assertRaises(ValueError): loop.inputs(self.path, self.anchor)
    def test_confirmation_required_before_any_process(self):
        with self.assertRaises(ValueError): loop.execute(self.path, self.anchor, self.root/'denied', '', runner=self.runner)
        self.assertEqual(self.calls, [])


if __name__ == '__main__': unittest.main()
