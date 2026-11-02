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
        self.snapshot_changes={};self.snapshot_state={}

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
                        bindingVerified=True,ownerDeadVerified=True,ownedScopeVerified=True,cleanupVerified=not self.required,flags=flags,recoveryRequired=self.required,
                        residueShape='owned-empty-shell' if self.required else 'absent',recoveryToolCapable=True)
            record.update(self.inspect_changes);stdout.write_text(json.dumps(record))
        elif op=='--snapshot-residue':
            ledger=Path(command[3]);self.assertEqual(command[4],'--expected-ledger-sha256')
            self.assertTrue((self.root/'original/recovery-claim.json').is_file(),'snapshot must follow the claim')
            entry=dict(hive='HKLM',view='64',path='SOFTWARE\\Microsoft\\CTF\\TIP\\{6DFACE1F-562E-4773-A9D6-D5753A314711}',subkeys=['Category','LanguageProfile'],values=[dict(name='Enable',type=4,bytes=4,sha256='c'*64)])
            record=dict(schema='mycomputer-residue-snapshot-v1',scope='readonly-owned-residue-snapshot',status='captured',stage='completed',code=0,
                        ledgerSha256=flow.sha(ledger.read_bytes()),dllSha256=self.dll_sha,residueShape='owned-empty-shell',entries=[entry])
            record.update(self.snapshot_changes);stdout.write_text(json.dumps(record));state.update(self.snapshot_state)
        elif op=='--recover':
            verification.update(mode='recover',writesStarted=True)
            stdout.write_text(json.dumps(verification));state.update(self.recover_state)
        else:self.fail('unexpected native operation '+op)
        return state

    def register(self,**kwargs):return flow.register(self.package,self.root/'original',self.anchor,flow.REGISTER_CONFIRM,runner=self.runner,**kwargs)
    def recover(self,**kwargs):return flow.recover(self.package,self.root/'original',self.root/'recovery',self.anchor,flow.RECOVER_CONFIRM,runner=self.runner,**kwargs)

    def test_registration_once_and_separate_verify(self):
        result=self.register()
        self.assertEqual(self.calls,['--register-once','--verify']);self.assertTrue(result['activationEvidenceConsistent'])
        self.assertFalse(result['automaticRecoveryAttempted']);self.assertFalse(result['sourceAuthenticityVerified'])
        self.assertEqual(json.loads((self.root/'original/registration.json').read_text()),result)

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
        self.assertEqual(self.calls,['--register-once','--inspect-recovery','--snapshot-residue','--recover','--verify'])
        self.assertTrue(result['cleanupEvidenceConsistent']);self.assertFalse(result['activationEvidenceConsistent'])
        self.assertEqual(result['packageBinding'],'same-package');self.assertEqual(result['residueShape'],'owned-empty-shell');self.assertTrue(result['claimCreated'])
        self.assertEqual((self.root/'original/registration.json').read_bytes(),original)
        self.assertTrue((self.root/'original/recovery-claim.json').is_file())
        self.assertTrue((self.root/'recovery/snapshot-stdout.txt').is_file())
        with self.assertRaises(ValueError):flow.recover(self.package,self.root/'original',self.root/'recovery2',self.anchor,flow.RECOVER_CONFIRM,runner=self.runner)
        self.assertFalse((self.root/'recovery2').exists());self.assertEqual(self.calls.count('--recover'),1)

    def test_incapable_residue_shape_refuses_before_claim(self):
        self.register_state={'timedOut':True,'exitCode':124};self.register()
        self.inspect_changes={'residueShape':'not-owned','recoveryToolCapable':False}
        result=self.recover()
        self.assertEqual(self.calls,['--register-once','--inspect-recovery'])
        self.assertEqual(result['status'],'failed-or-inconclusive');self.assertIn('not-owned',result['failureReason'])
        self.assertFalse(result['claimCreated']);self.assertFalse((self.root/'original/recovery-claim.json').exists())
        self.assertEqual(result['recoveryInvocations'],0)
        # The claim was never consumed, so a later reviewed attempt remains possible.
        self.inspect_changes={};result=flow.recover(self.package,self.root/'original',self.root/'recovery2',self.anchor,flow.RECOVER_CONFIRM,runner=self.runner)
        self.assertTrue(result['cleanupEvidenceConsistent'])

    def test_inspection_capability_contradictions_refused(self):
        self.register_state={'timedOut':True,'exitCode':124};receipt=self.register();self.recover()
        valid=json.loads((self.root/'recovery/inspect-stdout.txt').read_text())
        for changes in ({'recoveryToolCapable':False},{'residueShape':'not-owned'},{'residueShape':'unknown','recoveryToolCapable':False},{'recoveryToolCapable':'true'}):
            changed=copy.deepcopy(valid);changed.update(changes)
            with self.subTest(changes=changes),self.assertRaises(ValueError):flow.validate_inspection(changed,receipt,receipt['ledgerSha256'])
        # Only the COM generation root may remain: recovery is required although no TIP residue exists.
        changed=copy.deepcopy(valid);changed['residueShape']='absent';self.assertTrue(flow.validate_inspection(changed,receipt,receipt['ledgerSha256']))
        changed=copy.deepcopy(valid);changed.update(recoveryRequired=False,cleanupVerified=True,residueShape='absent');changed['flags']=dict(valid['flags'],cleanupVerified=True)
        self.assertFalse(flow.validate_inspection(changed,receipt,receipt['ledgerSha256']))

    def test_snapshot_failure_after_claim_stops_before_recover(self):
        self.register_state={'timedOut':True,'exitCode':124};self.register()
        leaked=dict(hive='HKLM',view='64',path='x',subkeys=[],values=[dict(name='Enable',type=4,bytes=4,sha256='c'*64,data='AQAAAA==')])
        for index,(changes,state) in enumerate((({'entries':[leaked]},{}),({'residueShape':'absent'},{}),({},{'timedOut':True,'exitCode':124}))):
            self.calls.clear();self.snapshot_changes=changes;self.snapshot_state=state
            with self.subTest(changes=changes,state=state):
                result=flow.recover(self.package,self.root/'original',self.root/('recovery-'+str(index)),self.anchor,flow.RECOVER_CONFIRM,runner=self.runner)
                self.assertEqual(result['status'],'failed-or-inconclusive');self.assertEqual(result['recoveryInvocations'],0);self.assertTrue(result['claimCreated'])
                self.assertEqual(self.calls,['--inspect-recovery','--snapshot-residue'])
            (self.root/'original/recovery-claim.json').unlink() # Test-only reset; the product never deletes a claim.

    def newer_package(self,pin):
        """Rebuild the package with different tool and DLL binaries; pin names the original registration."""
        receipt=json.loads((self.root/'original/registration.json').read_text())
        for name in (flow.EXE,flow.DLL):(self.package/name).write_bytes((self.package/name).read_bytes()+b'\0')
        self.manifest['sourceCommit']='b'*40
        if pin is None:self.manifest.pop('recoverableRegistrations',None)
        else:self.manifest['recoverableRegistrations']=pin(receipt)
        self.pin();self.dll_sha=receipt['dllSha256'] # The native tool binds the ledger's original DLL, not the shipped one.

    @staticmethod
    def exact_pin(r,**changes):
        row=dict(manifestSha256=r['manifestSha256'],sourceCommit=r['sourceCommit'],exeSha256=r['exeSha256'],dllSha256=r['dllSha256']);row.update(changes)
        return [{k:v for k,v in row.items() if v is not None}]

    def test_pinned_older_registration_recoverable_by_newer_package(self):
        self.register_state={'timedOut':True,'exitCode':124};self.register()
        self.newer_package(lambda r:self.exact_pin(r))
        result=self.recover()
        self.assertTrue(result['cleanupEvidenceConsistent']);self.assertEqual(result['packageBinding'],'pinned-older-package')
        self.assertEqual(self.calls,['--register-once','--inspect-recovery','--snapshot-residue','--recover','--verify'])

    def test_unpinned_or_mismatched_newer_package_refused_before_launch(self):
        pins=(None,lambda r:[],lambda r:self.exact_pin(r,sourceCommit='c'*40),lambda r:self.exact_pin(r,manifestSha256='d'*64),
              lambda r:self.exact_pin(r,dllSha256='e'*64),lambda r:self.exact_pin(r,dllSha256=None),
              lambda r:self.exact_pin(r,exeSha256=flow.sha((self.package/flow.EXE).read_bytes()+b'\0')))
        for index,pin in enumerate(pins):
            with self.subTest(index=index):
                if index:self.setUp()
                self.register_state={'timedOut':True,'exitCode':124};self.register();self.newer_package(pin)
                with self.assertRaises(ValueError):self.recover()
                self.assertEqual(self.calls,['--register-once']);self.assertFalse((self.root/'original/recovery-claim.json').exists())
        self.setUp();self.register_state={'timedOut':True,'exitCode':124};self.register()
        receipt_path=self.root/'original/registration.json';receipt=json.loads(receipt_path.read_text());receipt['dllSha256']='e'*64;receipt_path.write_text(json.dumps(receipt))
        with self.assertRaises(ValueError):self.recover() # A different DLL is never the same registration, even within one package.
        self.assertEqual(self.calls,['--register-once'])

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
        self.assertEqual(self.calls,['--register-once','--inspect-recovery','--snapshot-residue','--recover'])

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
