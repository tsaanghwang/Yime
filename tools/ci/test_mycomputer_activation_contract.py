"""Source wiring regressions only; no Windows execution or registration proof."""
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[2]
TESTS=ROOT/'YimeTextServiceExperiment/tests'

class ActivationSourceContract(unittest.TestCase):
    def test_opt_in_target_does_not_enter_existing_workflows(self):
        text=(ROOT/'YimeTextServiceExperiment/CMakeLists.txt').read_text()
        self.assertRegex(text,r'option\(YIME_MYCOMPUTER_ACTIVATION_STAGE1 "[^"]+" OFF\)')
        block=text.split('if(YIME_MYCOMPUTER_ACTIVATION_STAGE1)\n',1)[1]
        self.assertIn('NOT YIME_TOUCH_PRODUCT OR NOT CMAKE_GENERATOR_PLATFORM STREQUAL "x64"',block)
        self.assertIn('add_executable(YimeMyComputerActivationStage1 tests/RegistrationProbe.cpp)',block)
        self.assertIn('YIME_MYCOMPUTER_ACTIVATION_STAGE1=1',block)
        for path in (ROOT/'.github/workflows').glob('*'):
            if path.name == 'mycomputer-activation-package.yml':
                self.assertTrue((ROOT/'tools/ci/test_mycomputer_package_workflow.py').is_file())
                continue  # Exact compile/package-only exception; all old workflows remain forbidden.
            self.assertNotIn('YIME_MYCOMPUTER_ACTIVATION_STAGE1',path.read_text(),str(path))
            self.assertNotIn('YimeMyComputerActivationStage1',path.read_text(),str(path))

    def test_default_preflight_only_observes(self):
        text=(TESTS/'MyComputerActivationMain.h').read_text()
        self.assertIn('const auto args=yime::stage1::ParseArguments(arguments)',text)
        observation=text.split('yime::stage1::PreflightFacts inspectLocal(',1)[1].split('json localReport(',1)[0]
        for forbidden in ('ledger.create(', 'transaction.run(', 'transaction.cleanup(', 'ActivateProfile(', 'RegisterProfile('):
            self.assertNotIn(forbidden,observation)
        preflight=text.split('if(args.mode==Mode::Preflight){',1)[1].split('\n    else{',1)[0]
        for forbidden in ('ledger.create(', 'transaction.run(', 'transaction.cleanup('): self.assertNotIn(forbidden,preflight)
        registration=text.split('\n    else{',1)[1].split('}else if(args.mode==Mode::Verify)',1)[0]
        self.assertLess(registration.index('CanRegister(facts)'),registration.index('ledger.create('))
        self.assertLess(registration.index('ledger.create('),registration.index('transaction.run('))
        self.assertIn('if(args.mode==Mode::RegisterOnce && transaction.writes)',text)

    def test_ledger_protection_and_binding_are_on_actual_path(self):
        text=(TESTS/'RegistrationProbe.cpp').read_text()
        support=(TESTS/'MyComputerActivationSupport.h').read_text()
        self.assertIn('const auto text=protectLocalJournal(data.dump())',text)
        self.assertIn('data=json::parse(unprotectLocalJournal(cipher))',text)
        self.assertIn('data.at("host")==localUtf8(localHostName()) && data.at("sid")==localSid()',text)
        self.assertIn('dllLock.open(dll.wstring(),expectedSha)',text)
        self.assertIn('CryptProtectData(',support); self.assertIn('CryptUnprotectData(',support)
        self.assertNotIn('CRYPTPROTECT_LOCAL_MACHINE',support)
        self.assertIn('GetLastError()==ERROR_INVALID_PARAMETER,"original-process-state-unknown"',text)
        self.assertIn('ValidLedgerOrder(',text)

    def test_cleanup_checks_owned_shape_before_mutation(self):
        text=(TESTS/'RegistrationProbe.cpp').read_text()
        cleanup=text.split(' void cleanup() {',1)[1].split('\n};',1)[0]
        guard=cleanup.index('ledger->validateOwnedCom()')
        self.assertLess(guard,cleanup.index('DeactivateProfile('))
        self.assertLess(cleanup.index('strictLocalTipShape('),cleanup.index('UnregisterProfile('))
        validate=text.split(' void validateOwnedCom() {',1)[1].split(' void mark(',1)[0]
        self.assertIn('strictLocalComShape(',validate)
        for flag,api in [('comAttempted','RegCreateKeyExW('),('profileAttempted','RegisterProfile('),('categoryAttempted','RegisterCategory('),('enableAttempted','EnableLanguageProfile('),('activationAttempted','ActivateProfile(')]:
            run=text.split(' void run(',1)[1].split(' void cleanup()',1)[0]
            self.assertLess(run.index('ledger->mark("'+flag+'")'),run.index(api),flag)

    def test_api_activation_is_not_dll_activation_pass(self):
        text=(TESTS/'MyComputerActivationMain.h').read_text()
        self.assertIn('report["status"]="activation-unconfirmed";exit=4;',text)
        self.assertIn('{"actualDllActivationVerified",false}',text)
        self.assertIn('{"brokerEditingVerified",false}',text)

    def test_recovery_inspection_is_readonly_and_cleanup_rechecks_pinned_ledger(self):
        main=(TESTS/'MyComputerActivationMain.h').read_text()
        inspect=main.split('int inspectRecoveryOnly(',1)[1].split('json localReport(',1)[0]
        self.assertIn('ledger.expectedCipherSha256=args.ledgerSha256',inspect)
        self.assertIn('ledger.load(args.ledger)',inspect)
        self.assertIn('inspectOwnedScope(transaction,ledger)',inspect)
        for forbidden in ('transaction.cleanup(', 'ledger.mark(', 'ledger.create(', 'transaction.run('):
            self.assertNotIn(forbidden,inspect)
        recovery=main.split('}else if(args.mode==Mode::Verify)',1)[1].split('catch(const Failure& failure)',1)[0]
        self.assertLess(recovery.index('ledger.load(args.ledger)'),recovery.index('transaction.cleanup()'))
        self.assertLess(recovery.index('inspectOwnedScope(transaction,ledger)'),recovery.index('transaction.cleanup()'))
        self.assertNotIn('ledger.mark(',recovery)
        source=(TESTS/'RegistrationProbe.cpp').read_text()
        self.assertIn('cipherReadLock=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ',source)
        self.assertIn('cipherSha256==localUtf8(expectedCipherSha256)',source)

    def test_generation_marker_is_owned_before_cleanup_and_preserved_on_failure(self):
        source=(TESTS/'RegistrationProbe.cpp').read_text()
        self.assertIn('data.at("schema")=="18u-mycomputer-ledger-v3"',source)
        self.assertNotIn('data.at("schema")=="18u-mycomputer-ledger-v2"',source)
        local=source.split('const std::wstring generation=localGeneration(ledger->data);',1)[1].split('#else',1)[0]
        self.assertLess(local.index('RegSetValueExW(root.value,L"YimeMyComputerGeneration"'),local.index('ledger->mark("comOwned")'))
        self.assertLess(local.index('ledger->mark("comOwned")'),local.index('comOwned=true'))
        support=(TESTS/'MyComputerActivationSupport.h').read_text()
        self.assertIn('yime::stage1::Generation(',support)
        self.assertIn('actualGeneration==generation,"owned-generation-mismatch"',support)
        cleanup=source.split(' void cleanup() {',1)[1].split('\n};',1)[0]
        self.assertIn('if(comOwned && cleanupOK)try{ledger->validateOwnedCom();localTipAbsent(',cleanup)
        self.assertIn('if(comOwned && cleanupOK)\n#else',cleanup)

if __name__=='__main__': unittest.main()
