"""Static cross-file wiring only: NOT PowerShell execution or registry validation."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
PRODUCT = (ROOT / 'installer/simple/Product.psm1').read_text(encoding='utf-8-sig')
SETUP = (ROOT / 'installer/simple/Setup.ps1').read_text(encoding='utf-8-sig')
OWNERSHIP = PRODUCT.split('function Assert-Installed18uOwnership(', 1)[1].split('function Wait-ProductFiles(', 1)[0]
FIXTURE = (ROOT / 'installer/simple/tests/Test-Installed18uOwnership.ps1').read_text()
SEQUENCE = (ROOT / 'installer/simple/tests/Test-18uUnregisterSequence.ps1').read_text()


class LifecycleSourceContracts(unittest.TestCase):
    def test_tip_phase_retains_com_and_final_absence_guard(self):
        source = (ROOT / 'YimeTextServiceExperiment/ProductRegistrationMain.h').read_text()
        remove = source.split('void productRemove(', 1)[1].split('\nint wmain(', 1)[0]
        phase = remove.index('if(tipOnly)')
        final = remove.index('const auto api=productSnapshot();')
        self.assertLess(remove.index('if(finalPersistent.anyTip)'), phase)
        self.assertIn('return;', remove[phase:final])
        self.assertIn('com_retained=true', remove[phase:final])
        self.assertLess(final, remove.index('COM-delete-last'))
        self.assertIn('FinalApiAbsent(api.categoriesKnown,api.categories,api.profilesKnown,api.profiles)', remove)
        self.assertIn('productComOwned(dll);', remove[final:])
        self.assertLess(SETUP.index("@('unregister-tip',$dll)"), SETUP.index("@('unregister',$dll)"))

    def test_old_installed_manifest_not_incoming_package(self):
        self.assertIn("Read-MaintenancePackage (Join-Path $root '.setup')", OWNERSHIP)
        self.assertIn('$manifest=$maintenance.manifest', OWNERSHIP)
        self.assertNotIn('$package.manifest', OWNERSHIP)
        self.assertIn('$marker.version -cne $manifest.version', OWNERSHIP)

    def test_fixed_identity_and_exact_inventory(self):
        self.assertIn("Assert-OwnedDirectory $root 'yimecore-18u' 'windows-amd64'", OWNERSHIP)
        self.assertIn("$maintenance.product.id -cne 'yimecore-18u'", OWNERSHIP)
        self.assertIn('$row.path -cnotin $expected', OWNERSHIP)
        self.assertIn('$seen.Count -ne $expected.Count', OWNERSHIP)
        self.assertIn('$relative -cnotin $allowed', OWNERSHIP)

    def test_hash_and_path_checks_precede_identity_assertion(self):
        self.assertIn("$path.StartsWith($root+'\\'", OWNERSHIP)
        self.assertIn('(Get-ContentHash $path) -cne $row.sha256', OWNERSHIP)
        self.assertLess(OWNERSHIP.index('(Get-ContentHash $path)'), OWNERSHIP.index('Assert-18uPackageIdentity $root'))
        self.assertIn('Assert-ProductPe $path', OWNERSHIP)

    def test_ownership_before_process_stop_or_tip_removal(self):
        check = SETUP.index('Assert-Installed18uOwnership $root')
        self.assertLess(check, SETUP.index('foreach($p in Get-Process)'))
        self.assertLess(check, SETUP.index('InstallLayoutOrTip($tip,1)'))
        self.assertIn("@('check-owned',(Join-Path $root ('x64\\'+$product.dll)))", SETUP)
        self.assertIn("@('verify-absent')", SETUP)

    def test_no_18u_startup_or_implicit_acceptance(self):
        self.assertIn("if($product.id -ne 'yimecore-18u'){Set-UserStartup ''}", SETUP)
        self.assertIn("if($product.id -ne 'yimecore-18u'){Set-UserStartup", SETUP)
        end = SETUP.index("$stage='start installed runtime'")
        self.assertIn('exit 0', SETUP[SETUP.index("Write-Output ('Installed persistent independent 18u:"):end])

    def test_full_old_upgrade_stops_before_file_copy_and_preserves_evidence(self):
        start = SETUP.index("$stage='unregister selected product'")
        removed = SETUP.index('Remove-ProductDirectory $root $product.id', start)
        copied = SETUP.index('Copy-ProductPayload $package $root', removed)
        self.assertLess(SETUP.index('Set-Registration $false', start), removed)
        self.assertLess(removed, copied)
        self.assertIn('& $Path @Arguments', SETUP)
        self.assertIn("[guid]::NewGuid().ToString('N')", SETUP)
        self.assertIn('Start-Transcript -LiteralPath $logPath -Append', SETUP)
        self.assertLess(SETUP.index("if($ResetData){throw '18u maintenance preserves user data", 0), start)
        self.assertIn('oldFiles', SEQUENCE)
        self.assertIn('userData', SEQUENCE)
        self.assertIn('evidence', SEQUENCE)
        self.assertIn("$script:fail='register'", SEQUENCE)
        self.assertNotIn('Remove-Item', SEQUENCE)

    def test_actual_ps_fixture_is_nonsystem_and_honestly_mocked(self):
        self.assertIn('Assert-Installed18uOwnership $root', FIXTURE)
        self.assertIn('function script:Assert-ProductPe', FIXTURE)
        self.assertIn('function script:Assert-18uPackageIdentity', FIXTURE)
        self.assertNotIn('function script:Read-MaintenancePackage', FIXTURE)
        for forbidden in ('Invoke-CimMethod', 'OpenBaseKey', 'Start-Process', 'InstallLayoutOrTip'):
            self.assertNotIn(forbidden, FIXTURE)
        for case in ('marker-product', 'marker-version', 'marker-target', 'path-escape', 'foreign-manifest', 'extra-file', 'wrong-hash', 'old-not-new'):
            self.assertIn(case, FIXTURE)


if __name__ == '__main__': unittest.main()
