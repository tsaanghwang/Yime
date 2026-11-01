"""Mock the process boundary of the real orchestrator; never configure Windows."""
import json
from pathlib import Path
import tempfile
import unittest

import run_language_prepare as prepare


class PreparationTests(unittest.TestCase):
    def scenario(self, changes=None, ledger=True, invalid_record=None):
        changes = changes or {}
        calls = []
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            def runner(command, cwd, stdout, stderr, timeout):
                self.assertEqual(command[-2], '--params-file')
                params = json.loads(Path(command[-1]).read_text())
                mode = params['Mode']; calls.append(mode)
                self.assertEqual(timeout, {'Prepare': 240, 'Restore': 180, 'Verify': 120}[mode])
                directory = Path(params['LedgerDirectory']); directory.mkdir(exist_ok=True)
                if ledger: (directory / 'ledger.json').write_text('{}')
                record = dict(schema='chinese-environment-result-v1', mode=mode,
                              status='prepared' if mode == 'Prepare' else 'verified',
                              observation={'native': {'verified': True, 'query': {'actualHklLanguageHint':2052, 'actualTsfLanguage':2052}}},
                              scope=prepare.SCOPE, mutationAttempted=True,
                              configurationAppended=True, componentServicingRollbackClaimed=False)
                state = dict(started=True, timedOut=False, treeStopped=True, exitCode=0, errorCode=None)
                state.update(changes.get(mode, {}).get('state', {}))
                record.update(changes.get(mode, {}).get('record', {}))
                raw = json.dumps(record)
                if invalid_record == mode: raw = raw[:-1] + ',"status":"prepared"}'
                (directory / (mode.lower() + '-result.json')).write_text(raw)
                return state
            result = prepare.run_prepare(root, root / 'evidence', root / 'query.exe', runner)
            self.assertEqual(json.loads((root/'evidence/workflow-result.json').read_text()), result)
        return result, calls

    def test_success_is_single_prepare_restore_verify(self):
        r,calls=self.scenario()
        self.assertEqual(calls, ['Prepare', 'Restore', 'Verify'])
        self.assertEqual(r['status'], 'prepared-and-restored')
        self.assertTrue(r['observedRestorationVerified'])
        self.assertFalse(r['componentServicingRollbackClaimed'])
        self.assertEqual([r[k] for k in ('preparationInvocations','restoreInvocations','verifyInvocations')], [1,1,1])

    def test_no_owner_ledger_never_restores_or_passes(self):
        r,calls=self.scenario(ledger=False)
        self.assertEqual(calls,['Prepare']); self.assertEqual(r['status'],'failed')
        self.assertFalse(r['observedRestorationVerified'])

    def test_live_preparation_never_runs_restore(self):
        r,calls=self.scenario({'Prepare': {'state': {'treeStopped':False, 'timedOut':True}}})
        self.assertEqual(calls,['Prepare']); self.assertEqual(r['status'],'failed')

    def test_timed_out_but_stopped_preparation_restores_not_passes(self):
        r,calls=self.scenario({'Prepare': {'state': {'timedOut':True, 'exitCode':124}}})
        self.assertEqual(calls,['Prepare','Restore','Verify']); self.assertEqual(r['status'],'failed')
        self.assertFalse(r['freshProcessChineseEnvironmentVerified'])
        self.assertTrue(r['observedRestorationVerified'])

    def test_live_restore_prevents_verify(self):
        r,calls=self.scenario({'Restore': {'state': {'treeStopped':False, 'timedOut':True}}})
        self.assertEqual(calls,['Prepare','Restore']); self.assertEqual(r['status'],'failed')

    def test_restore_failure_not_overridden_by_verify(self):
        r,calls=self.scenario({'Restore': {'state': {'exitCode':1}, 'record': {'status':'cleanup-failed'}}})
        self.assertEqual(calls,['Prepare','Restore','Verify']); self.assertEqual(r['status'],'failed')
        self.assertFalse(r['observedRestorationVerified'])

    def test_verify_failure_and_timeout_fail_closed(self):
        for state in ({'exitCode':1}, {'timedOut':True}, {'errorCode':5}, {'started':False}):
            with self.subTest(state=state):
                r,_=self.scenario({'Verify': {'state':state}})
                self.assertEqual(r['status'],'failed'); self.assertFalse(r['observedRestorationVerified'])

    def test_blocked_chinese_environment_never_counts_success(self):
        r,calls=self.scenario({'Prepare': {'state':{'exitCode':3}, 'record':{'status':'blocked','configurationAppended':False,'mutationAttempted':False}}})
        self.assertEqual(calls,['Prepare','Restore','Verify']); self.assertEqual(r['status'],'blocked')
        self.assertFalse(r['freshProcessChineseEnvironmentVerified'])

    def test_forged_or_duplicate_result_fails_closed(self):
        for mode in ('Prepare','Restore','Verify'):
            with self.subTest(mode=mode):
                r,_=self.scenario(invalid_record=mode)
                self.assertEqual(r['status'],'failed')
        for record in ({'scope':'full-system-rollback'}, {'componentServicingRollbackClaimed':True}, {'mutationAttempted':1}):
            with self.subTest(record=record):
                r,_=self.scenario({'Prepare':{'record':record}})
                self.assertEqual(r['status'],'failed')

    def test_prepared_requires_actual_native_chinese_evidence(self):
        for observation in (None, {}, {'native': []},
                            {'native': {'verified': False, 'query': {'actualHklLanguageHint':2052, 'actualTsfLanguage':2052}}},
                            {'native': {'verified': True, 'query': {'actualHklLanguageHint':1033, 'actualTsfLanguage':2052}}},
                            {'native': {'verified': True, 'query': {'actualHklLanguageHint':2052, 'actualTsfLanguage':1033}}},
                            {'native': {'verified': True, 'query': {'actualHklLanguageHint':'2052', 'actualTsfLanguage':2052}}}):
            with self.subTest(observation=observation):
                r,_=self.scenario({'Prepare': {'record': {'observation':observation}}})
                self.assertEqual(r['status'],'failed')
                self.assertFalse(r['freshProcessChineseEnvironmentVerified'])
                self.assertTrue(r['observedRestorationVerified'])

    def test_existing_transaction_is_not_reused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'evidence/transaction').mkdir(parents=True)
            def forbidden(*args): self.fail('existing transaction must not launch')
            with self.assertRaises(ValueError): prepare.run_prepare(root, root/'evidence', root/'query.exe', forbidden)


if __name__ == '__main__': unittest.main()
