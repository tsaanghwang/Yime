"""Actual stage-3 Python flow with synthetic package/process boundaries only."""
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import collect_mycomputer_preflight as collector
import run_mycomputer_registration as flow
import validate_local_activation_evidence as gate
from test_collect_mycomputer_preflight import fake_pe
from test_local_activation_evidence import fixtures


class RegistrationFlowTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.package=self.root/'package';self.package.mkdir();self.source=Path(flow.__file__).parent
        names={flow.EXE,flow.DLL,'README.zh-CN.md','collect_mycomputer_preflight.py','windows_job_once.py','run_mycomputer_registration.py','validate_local_activation_evidence.py'}
        for name in names:
            data=fake_pe(name==flow.DLL) if name in (flow.EXE,flow.DLL) else b'# fixture' if name.endswith('.md') else (self.source/name).read_bytes()
            (self.package/name).write_bytes(data)
        self.manifest=dict(schema=flow.V2,identity=collector.IDENTITY,architecture='native-x64',scope='registration-activation-only-development',targetHost='MyComputer',defaultOperation='read-only-preflight',sourceCommit='a'*40,userDesktopExecutionApproved=False,registrationExecutionApproved=False,brokerEditingVerified=False,physicalAcceptance=False)
        self.pin();location=patch.object(flow,'__file__',str(self.package/'run_mycomputer_registration.py'));location.start();self.addCleanup(location.stop)
        self.calls=[];self.root_identity={'pid':1234,'creationFileTime':'123456789'}
        self.register_state={};self.missing_marker=False;self.inspect_changes={};self.recover_state={};self.required=True

    def pin(self):
        self.manifest['files']=[dict(path=p.name,bytes=p.stat().st_size,sha256=flow.sha(p.read_bytes())) for p in self.package.iterdir() if p.name!='manifest.json']
        (self.package/'manifest.json').write_text(json.dumps(self.manifest));self.anchor=flow.sha((self.package/'manifest.json').read_bytes())
        self.dll_sha=flow.sha((self.package/flow.DLL).read_bytes())

    def runner(self,command,cwd,stdout,stderr,timeout,on_root_created=None):
        op=command[1];self.calls.append(op)
        state=dict(started=True,treeStopped=True,timedOut=False,errorCode=None,exitCode=0,rootIdentity=dict(self.root_identity))
        registration,verification=fixtures();registration['dllSha256']=self.dll_sha
        stderr.write_text('')
        if op=='--register-once':
            self.assertIsNotNone(on_root_created);on_root_created(dict(self.root_identity))
            durable=json.loads((cwd/'registration.json').read_text());self.assertEqual(durable['rootIdentity'],self.root_identity)
            ledger=Path(command[-1]);ledger.write_bytes(b'opaque DPAPI fixture')
            stdout.write_text(json.dumps(registration));stderr.write_text('' if self.missing_marker else json.dumps(gate.MARKER))
            state['exitCode']=4;state.update(self.register_state)
        elif op=='--verify':stdout.write_text(json.dumps(verification))
        elif op=='--inspect-recovery':
            ledger=Path(command[3]);self.assertEqual(command[4],'--expected-ledger-sha256')
            flags={key:True for key in flow.LEDGER_FLAGS};flags['cleanupVerified']=not self.required
            record=dict(schema='mycomputer-recovery-inspection-v1',scope='readonly-recovery-ownership',status='verified',stage='completed',code=0,
                        ledgerSha256=flow.sha(ledger.read_bytes()),ownerPid=self.root_identity['pid'],ownerCreationTime=int(self.root_identity['creationFileTime']),dllSha256=self.dll_sha,
                        bindingVerified=True,ownerDeadVerified=True,ownedScopeVerified=True,cleanupVerified=not self.required,flags=flags,recoveryRequired=self.required)
            record.update(self.inspect_changes);stdout.write_text(json.dumps(record))
        elif op=='--recover':
            verification.update(mode='recover',writesStarted=True)
            stdout.write_text(json.dumps(verification));state.update(self.recover_state)
        else:self.fail('unexpected native operation '+op)
        return state

    def register(self,**kwargs):return flow.register(self.package,self.root/'original',self.anchor,flow.REGISTER_CONFIRM,runner=self.runner,**kwargs)
    def recover(self,**kwargs):return flow.recover(self.package,self.root/'original',self.root/'recovery',self.anchor,flow.RECOVER_CONFIRM,runner=self.runner,**kwargs)

    def test_native_failure_receipt_keeps_original_and_cleanup_diagnostics(self):
        def fail_runner(command,cwd,stdout,stderr,timeout,on_root_created=None):
            state=self.runner(command,cwd,stdout,stderr,timeout,on_root_created)
            value=json.loads(stdout.read_text())
            value.update(status='failed',stage='existing-tip-identity',code=2147500037)
            value['diagnostics']=dict(schema='activation-diagnostics-v1',primaryFailure=dict(phase='registration',stage='activate',code=5),cleanupFailures=[dict(phase='cleanup',stage='existing-tip-identity',code=2147500037)],stages=[],registryMatch=None)
            stdout.write_text(json.dumps(value));state['exitCode']=1
            return state
        result=flow.register(self.package,self.root/'original',self.anchor,flow.REGISTER_CONFIRM,runner=fail_runner)
        self.assertEqual(self.calls,['--register-once'])
        self.assertEqual(result['diagnostics']['primaryFailure']['stage'],'activate')
        self.assertEqual(result['diagnostics']['cleanupFailures'][0]['stage'],'existing-tip-identity')
        self.assertEqual(result['failureReason'],'native-registration-incomplete')
        self.assertFalse(result['automaticRecoveryAttempted'])

    def test_registration_once_and_separate_verify(self):
        result=self.register()
        self.assertEqual(self.calls,['--register-once','--verify']);self.assertTrue(result['activationEvidenceConsistent'])
        self.assertFalse(result['automaticRecoveryAttempted']);self.assertFalse(result['sourceAuthenticityVerified'])
        self.assertEqual(json.loads((self.root/'original/registration.json').read_text()),result)

    def test_invalid_native_json_preserves_receipt_and_never_verifies(self):
        samples=['', '{"status":', '[]', 'null', 'true', '1', '"text"', '{"status":1,"status":2}']
        for number,raw in enumerate(samples):
            for exit_code in (1,4):
                with self.subTest(raw=raw,exit_code=exit_code):
                    evidence=self.root/f'invalid-{number}-{exit_code}'
                    def invalid_runner(command,cwd,stdout,stderr,timeout,on_root_created=None):
                        state=self.runner(command,cwd,stdout,stderr,timeout,on_root_created)
                        stdout.write_text(raw);state['exitCode']=exit_code
                        return state
                    before=len(self.calls)
                    result=flow.register(self.package,evidence,self.anchor,flow.REGISTER_CONFIRM,runner=invalid_runner)
                    self.assertEqual(self.calls[before:],['--register-once'])
                    self.assertEqual(result['status'],'failed-or-inconclusive')
                    self.assertTrue(result['failureReason'])
                    self.assertEqual(result['process']['exitCode'],exit_code)
                    self.assertFalse(result['automaticRecoveryAttempted'])
                    self.assertFalse(result['activationEvidenceConsistent'])
                    self.assertEqual(result['stdout']['sha256'],flow.sha(raw.encode()))
                    self.assertEqual(json.loads((evidence/'registration.json').read_text()),result)

    def test_timeout_with_truncated_json_keeps_process_and_ledger_evidence(self):
        self.register_state={'timedOut':True,'exitCode':124}
        def truncated_runner(command,cwd,stdout,stderr,timeout,on_root_created=None):
            state=self.runner(command,cwd,stdout,stderr,timeout,on_root_created)
            stdout.write_text('{"status":');return state
        result=flow.register(self.package,self.root/'truncated',self.anchor,flow.REGISTER_CONFIRM,runner=truncated_runner)
        self.assertEqual(self.calls,['--register-once'])
        self.assertTrue(result['process']['timedOut'])
        self.assertTrue(result['process']['treeStopped'])
        self.assertEqual(result['process']['exitCode'],124)
        self.assertIsNotNone(result['ledgerSha256'])
        self.assertTrue(result['failureReason'])
        self.assertFalse(result['automaticRecoveryAttempted'])

    def test_timeout_keeps_ledger_and_never_auto_recovers(self):
        self.register_state={'timedOut':True,'exitCode':124}
        result=self.register();self.assertEqual(self.calls,['--register-once'])
        self.assertFalse(result['activationEvidenceConsistent']);self.assertTrue((self.root/'original/ledger/registration-ledger.dpapi').exists())
        self.assertIsNotNone(result['ledgerSha256'])

    def test_missing_marker_never_success(self):
        self.missing_marker=True
        result=self.register();self.assertFalse(result['activationEvidenceConsistent'])
        self.assertNotIn('--recover',self.calls)

    def test_explicit_confirmation_and_fresh_evidence_required(self):
        with self.assertRaises(ValueError):flow.register(self.package,self.root/'original',self.anchor,'yes',runner=self.runner)
        self.assertEqual(self.calls,[])
        self.register()
        with self.assertRaises(FileExistsError):self.register()
        self.assertEqual(self.calls,['--register-once','--verify'])

    def test_v1_or_tampered_package_never_launches(self):
        self.manifest['schema']=collector.SCHEMA;self.pin()
        with self.assertRaises(ValueError):self.register()
        self.manifest['schema']=flow.V2;self.pin();(self.package/flow.DLL).write_bytes(b'tampered')
        with self.assertRaises(ValueError):self.register()
        self.assertEqual(self.calls,[])

    def test_recovery_is_separate_inspect_once_then_verify(self):
        self.register_state={'timedOut':True,'exitCode':124};before=self.register();original=(self.root/'original/registration.json').read_bytes()
        result=self.recover()
        self.assertEqual(self.calls,['--register-once','--inspect-recovery','--recover','--verify'])
        self.assertTrue(result['cleanupEvidenceConsistent']);self.assertFalse(result['activationEvidenceConsistent'])
        self.assertEqual((self.root/'original/registration.json').read_bytes(),original)
        self.assertTrue((self.root/'original/recovery-claim.json').is_file())
        with self.assertRaises(FileExistsError):flow.recover(self.package,self.root/'original',self.root/'recovery2',self.anchor,flow.RECOVER_CONFIRM,runner=self.runner)
        self.assertEqual(self.calls.count('--recover'),1)

    def test_unknown_tree_or_missing_final_receipt_blocks_before_inspection(self):
        self.register_state={'treeStopped':False,'timedOut':True,'exitCode':None};self.register()
        with self.assertRaises(ValueError):self.recover()
        self.assertEqual(self.calls,['--register-once'])

    def test_inspection_wrong_owner_stops_without_recovery(self):
        self.register_state={'timedOut':True,'exitCode':124};self.register();self.inspect_changes={'ownerPid':4321}
        result=self.recover();self.assertFalse(result['cleanupEvidenceConsistent']);self.assertNotIn('--recover',self.calls)

    def test_already_clean_requires_only_independent_verify(self):
        self.register();self.required=False;result=self.recover()
        self.assertTrue(result['cleanupEvidenceConsistent']);self.assertEqual(result['recoveryInvocations'],0)
        self.assertEqual(self.calls[-2:],['--inspect-recovery','--verify'])

    def test_timed_out_recovery_never_verifies_or_retries(self):
        self.register_state={'timedOut':True,'exitCode':124};self.register();self.recover_state={'timedOut':True,'exitCode':124}
        result=self.recover();self.assertFalse(result['cleanupEvidenceConsistent'])
        self.assertEqual(self.calls,['--register-once','--inspect-recovery','--recover'])

    def test_changed_original_log_or_ledger_refused(self):
        self.register_state={'timedOut':True,'exitCode':124};self.register()
        (self.root/'original/register-stdout.txt').write_text('modified')
        with self.assertRaises(ValueError):self.recover()
        self.assertEqual(self.calls,['--register-once'])

    def test_inspection_all_binding_failures_refused(self):
        self.register_state={'timedOut':True,'exitCode':124};receipt=self.register();self.recover()
        valid=json.loads((self.root/'recovery/inspect-stdout.txt').read_text())
        for field,bad in (('bindingVerified',False),('ownerDeadVerified',False),('ownedScopeVerified',False),
                          ('ownerCreationTime',1),('ledgerSha256','b'*64),('dllSha256','b'*64),
                          ('status','blocked'),('ownerPid',True),('flags',None)):
            changed=copy.deepcopy(valid);changed[field]=bad
            with self.subTest(field=field),self.assertRaises(ValueError):flow.validate_inspection(changed,receipt,receipt['ledgerSha256'])

    def test_changed_ledger_or_missing_completion_refused(self):
        self.register_state={'timedOut':True,'exitCode':124};self.register()
        ledger=self.root/'original/ledger/registration-ledger.dpapi';ledger.write_bytes(b'changed')
        with self.assertRaises(ValueError):self.recover()
        self.assertEqual(self.calls,['--register-once'])

    def test_no_arguments_cannot_launch_or_write(self):
        with patch.object(flow.sys,'argv',['run_mycomputer_registration.py']),patch.object(flow.argparse.ArgumentParser,'error',side_effect=ValueError('usage')):
            with self.assertRaises(ValueError):flow.main()
        self.assertEqual(self.calls,[]);self.assertFalse((self.root/'original').exists())

if __name__=='__main__':unittest.main()
