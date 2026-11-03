"""Static cross-file wiring only: NOT PowerShell execution or registry validation."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
PRODUCT = (ROOT / 'installer/simple/Product.psm1').read_text(encoding='utf-8-sig')
SETUP = (ROOT / 'installer/simple/Setup.ps1').read_text(encoding='utf-8-sig')
OWNERSHIP = PRODUCT.split('function Assert-Installed18uOwnership(', 1)[1].split('function Wait-ProductFiles(', 1)[0]
FIXTURE = (ROOT / 'installer/simple/tests/Test-Installed18uOwnership.ps1').read_text()


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
        self.assertIn("Assert-OwnedDirectory $root 'yimecore-18u' $maintenance.contract.target", OWNERSHIP)
        self.assertLess(OWNERSHIP.index("Read-MaintenancePackage (Join-Path $root '.setup')"), OWNERSHIP.index("Assert-OwnedDirectory $root 'yimecore-18u' $maintenance.contract.target"))
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
        self.assertIn("@('check-owned',(Join-Path $root ($contract.nativeDirectory+'\\'+$product.dll)))", SETUP)
        self.assertIn("@('verify-absent')", SETUP)

    def test_no_18u_startup_or_implicit_acceptance(self):
        self.assertIn("if($product.id -ne 'yimecore-18u'){Set-UserStartup ''}", SETUP)
        self.assertIn("if($product.id -ne 'yimecore-18u'){Set-UserStartup", SETUP)
        end = SETUP.index("$stage='start installed runtime'")
        self.assertIn('exit 0', SETUP[SETUP.index("Write-Output ('Installed persistent independent 18u:"):end])

    def test_native_architecture_contract_is_explicit_and_bound(self):
        contract = PRODUCT.split('function Get-PackageContract(',1)[1].split('function Get-NativeHostMachine',1)[0]
        for fragment in ("$Manifest.target -ceq 'windows-amd64'", "$Manifest.host_architecture -ceq 'amd64'", "$Manifest.tsf64_architecture -ceq 'x64'", "$Manifest.target -ceq 'windows-arm64'", "$Manifest.host_architecture -ceq 'arm64'", "$Manifest.tsf64_architecture -ceq 'arm64'"):
            self.assertIn(fragment, contract)
        self.assertEqual(contract.count('requireNativeProcess=$true'), 2)
        self.assertIn('requireNativeProcess -and $hostMachine.processMachine -ne 0', PRODUCT)
        self.assertIn('$descriptor.architecture -cne $expectedArchitecture', PRODUCT)
        self.assertIn('$sourceProduct.scope.architecture -cne $contract.nativeDirectory', PRODUCT)
        self.assertIn('Assert-ProductPe $path $arch', OWNERSHIP)
        self.assertIn("if($contract.target -ceq 'windows-arm64' -and $product.id -ceq 'yimecore')", PRODUCT)
        fixture = (ROOT / 'installer/simple/tests/18u-architecture-contract.ps1').read_text()
        for invalid in ("Contract 'windows-arm64' 'amd64' 'arm64'", "Contract 'windows-arm64' 'arm64' 'arm64x'", "Contract 'windows-arm64' 'arm64' 'x64'", "Contract 'windows-amd64' 'arm64' 'x64'", "Contract 'windows-amd64' 'amd64' 'arm64'"):
            self.assertIn('MustReject (' + invalid + ')', fixture)

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
