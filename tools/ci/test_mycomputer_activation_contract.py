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

if __name__=='__main__': unittest.main()
