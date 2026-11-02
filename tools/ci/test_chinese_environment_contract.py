"""Portable source contracts, not Windows cmdlet/PowerShell runtime validation."""
from pathlib import Path
import re
import unittest

SOURCE = Path(__file__).with_name('prepare_chinese_environment.ps1').read_text()


class PrepareContract(unittest.TestCase):
    def test_modes_and_result(self):
        self.assertIn("[ValidateSet('Prepare','Restore','Verify')]", SOURCE)
        for status in ('prepared', 'blocked', 'cleanup-failed', 'verified', 'unchanged-no-mutation'):
            self.assertIn("status='" + status + "'", SOURCE)
        self.assertIn('componentServicingRollbackClaimed=$false', SOURCE)

    def test_only_language_setter(self):
        commands = re.findall(r'^\s*(Set-[A-Za-z]+)\s', SOURCE, re.M)
        self.assertEqual(commands, ['Set-StrictMode', 'Set-WinUserLanguageList', 'Set-WinUserLanguageList'])
        for forbidden in ('Install-Language', 'Add-WindowsCapability', 'Invoke-WebRequest',
                          'ActivateKeyboardLayout', 'LoadKeyboardLayout', 'EnableLanguageProfile',
                          'Restart-Computer', 'Import-Clixml'):
            self.assertNotIn(forbidden, SOURCE)

    def test_typed_roundtrip_and_singleton_array(self):
        self.assertIn('return ,@($languages | ForEach-Object', SOURCE)
        self.assertIn('return ,$typed', SOURCE)
        self.assertIn('typed-language-roundtrip-mismatch', SOURCE)
        self.assertIn('$entry.InputMethodTips.Clear()', SOURCE)
        for field in ('languageTag', 'inputMethodTips', 'handwriting', 'spellchecking'):
            self.assertIn(field, SOURCE)
        self.assertIn("$zh[0].InputMethodTips.Add($Tip)", SOURCE)
        self.assertIn("$baseline.languages[0].languageTag -notmatch '^en-'", SOURCE)

    def test_write_ahead_and_once_restore(self):
        for flag in ('mutationAttempted', 'restoreAttempted'):
            mark = SOURCE.index('$ledger.' + flag + ' = $true')
            save = SOURCE.index('Save-Json $ledgerPath $ledger', mark)
            setter = SOURCE.index('Set-WinUserLanguageList -LanguageList $typed -Force', mark)
            self.assertLess(mark, save)
            self.assertLess(save, setter)
        self.assertIn('-not $ledger.restoreAttempted', SOURCE)
        self.assertIn('Assert-OwnerDead', SOURCE)
        self.assertIn('catch [ArgumentException] { return }', SOURCE)
        self.assertIn("catch { throw 'owner-liveness-unknown' }", SOURCE)
        self.assertNotIn('SilentlyContinue', SOURCE)
        self.assertIn("$owner.StartTime.ToUniversalTime().ToString('o')", SOURCE)
        self.assertIn('[IO.FileShare]::None', SOURCE)
        self.assertIn('$stream.Flush($true)', SOURCE)

    def test_preflight_and_actual_not_assumed(self):
        guard = SOURCE.index('if (-not $baseline.native.verified)')
        mutate = SOURCE.index('$ledger.mutationAttempted = $true')
        self.assertLess(guard, mutate)
        self.assertIn("$signature.Status -ne 'Valid'", SOURCE)
        self.assertIn('O=Microsoft Corporation', SOURCE)
        self.assertIn('actualHklLanguageHint -ne 2052', SOURCE)
        self.assertIn('actualTsfLanguage -ne 2052', SOURCE)
        self.assertIn('$evidence.query = $q', SOURCE)
        self.assertIn('$evidence.exitCode = $LASTEXITCODE', SOURCE)

    def test_setter_warnings_stop_prepare_and_restore(self):
        self.assertEqual(SOURCE.count('-WarningVariable setterWarnings -WarningAction Continue'), 2)
        self.assertEqual(SOURCE.count("if ($result.warningCount -gt 0) { throw 'language-setter-warning-stop' }"), 2)
        self.assertIn('warningCount=0', SOURCE)

    def test_defaults_observe_only_and_restore_scope(self):
        self.assertIn('Defaults remain observe-only, including null overrides', SOURCE)
        self.assertIn("throw 'defaults-changed-restore-required'", SOURCE)
        self.assertIn('Stable-Native $current.native', SOURCE)
        self.assertIn('profileEnabled=$native.query.profileEnabled', SOURCE)
        self.assertIn('profileActive=$native.query.profileActive', SOURCE)
        self.assertIn("throw 'ledger-identity-mismatch'", SOURCE)
        self.assertIn('Workflow owns the sole finally Restore', SOURCE)


if __name__ == '__main__':
    unittest.main()
