"""Read the repository evidence contract; exercise one in-memory ownership model.

The contract inventories source/build wiring, compiled-artifact static analysis,
isolated-filesystem fixtures and pure-memory transaction fixtures. This script
does not itself execute all of those separate suites: its executable ownership
model is in memory, and it reads source files before writing one fresh receipt
under this checkout's .tmp directory. It never runs an installer or examines an
installed/live product, and uses no registry, process, user-data or network API.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import re
import stat
import sys
import unittest
import uuid
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).absolute().parents[2]
CONTRACT = Path(__file__).with_name("contract.json")
FIXTURE_SID = "S-1-5-21-100-200-300-1001"
EXPECTED_TEST_LEVEL = (
    "source-build-wiring-compiled-artifact-static-analysis-"
    "isolated-filesystem-fixtures-pure-memory-transaction-fixtures-"
    "not-installed-or-live"
)
RIME_PIME_PRODUCT_VERSION_PATTERN = re.compile(
    r"(?P<major>0|[1-9][0-9]*)\."
    r"(?P<minor>0|[1-9][0-9]*)\."
    r"(?P<patch>0|[1-9][0-9]*)"
    r"(?:-(?P<suffix>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
)


def fail(message):
    raise ValueError(message)


def parse_rime_pime_product_version(version):
    if not isinstance(version, str) or len(version) > 64:
        fail("Rime/PIME source product version is not a supported semantic Windows version")
    match = RIME_PIME_PRODUCT_VERSION_PATTERN.fullmatch(version)
    if match is None:
        fail("Rime/PIME source product version is not a supported semantic Windows version")
    parts = tuple(match.group(name) for name in ("major", "minor", "patch"))
    suffix = match.group("suffix")
    suffix_identifiers = suffix.split(".") if suffix is not None else ()
    if (any(int(part) > 65535 for part in parts) or
            any(identifier.isdigit() and len(identifier) > 1 and identifier.startswith("0")
                for identifier in suffix_identifiers)):
        fail("Rime/PIME source product version is not a supported semantic Windows version")
    return parts, ".".join(parts) + ".0"


def plain(path: Path) -> Path:
    """Reject reparse traversal without resolving or following it."""
    path = path.absolute()
    for part in reversed([path, *path.parents]):
        try:
            metadata = part.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(metadata.st_mode) or getattr(metadata, "st_file_attributes", 0) & 0x400:
            fail("indirect path is not permitted")
    return path


def child(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or any(c in relative for c in "\\:"):
        fail("non-canonical relative path")
    parts = relative.split("/")
    if any(p in ("", ".", "..") or p.endswith((".", " ")) for p in parts):
        fail("non-canonical relative path")
    return plain(root.joinpath(*parts))


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def one(pattern, text, label):
    matches = list(re.finditer(pattern, text, re.MULTILINE))
    if len(matches) != 1:
        fail("source extraction mismatch: " + label)
    return matches[0]


def powershell_function(text, name):
    # Fixed top-level function boundaries, fail closed if the expected source
    # shape changes. Dynamic actual-branch tests use the PowerShell AST instead.
    return one(r"(?ms)^function " + re.escape(name) + r"\b.*?(?=^function |\Z)", text, name).group()


def nsis_function(text, name):
    """Return one real NSIS function body, excluding similarly named comments."""
    return one(
        r"(?ms)^Function\s+" + re.escape(name) + r"\s*$.*?^FunctionEnd\s*$",
        text,
        "NSIS function " + name,
    ).group()


def nsis_active_call(text, name):
    """Recognize an active NSIS Call statement, never a commented token."""
    return re.search(r"(?m)^\s*Call\s+" + re.escape(name) + r"\s*(?:;.*)?$", text) is not None


def maintenance_source_status(sources):
    """Inspect current guards; this does not execute or approve maintenance."""
    helper = sources["tools/dual-product/rime-pime-ownership.ps1"]
    directed = sources["tools/dual-product/rime-pime-directed-stop-contract.ps1"]
    directed_test = sources["tools/dual-product/test-rime-pime-directed-stop.ps1"]
    launcher = sources["PIMELauncher/src/main.rs"]
    launcher_maintenance = sources["PIMELauncher/src/maintenance.rs"]
    backend_manager = sources["PIMELauncher/src/backend_manager.rs"]
    uninstall = sources["tools/dev-uninstall.ps1"]
    guards = (
        (powershell_function(uninstall, "Add-InstallRootCandidate"),
         ["Assert-YimePimeOwnedRoot -Root $Path -AllowAbsent", "if (-not $owned.exists) { return }", "$Candidates.Add($normalized)"]),
        (powershell_function(uninstall, "Remove-InstallTree"),
         ["Assert-YimePimeOwnedRoot -Root $Path", "Remove-Item -LiteralPath $Path"]),
        (powershell_function(uninstall, "Get-InstallRootsForMaintenance"),
         ["Add-InstallRootCandidate -Candidates $candidates -Path $SelectedRoot", "if ($candidates.Count -eq 0)"]),
        (powershell_function(helper, "Assert-YimePimeOwnedRoot"),
         ["Assert-YimePimePlainPath", "Assert-YimePimeNoReparseTree", "go-backend\\input_methods\\yime\\ime.json",
          "{3F6B5A12-8D44-4E71-9A2E-6B4F9C1D2A30}", "Unknown or incomplete root"]),
        (powershell_function(helper, "Stop-YimePimeOwnedProcesses"),
         ["Assert-YimePimeTargetSid", "$paths.Contains", "$imageNames.Contains", "GetOwnerSid",
          "$process.Handle", "$process.StartTime", "if($bound.Count -gt 0)", "$activeRoots",
          "Invoke-YimePimeDirectedStop"]),
        (directed, ["function Get-YimePimeDirectedStopBoundProcesses",
                    "function New-YimePimeDirectedStopRequest",
                    "function Assert-YimePimeDirectedStopAck",
                    "IO.Pipes.NamedPipeClientStream",
                    "Wait-Process -InputObject", "Get-YimePimeDirectedStopBoundProcesses -InstallRoot $root"]),
        (directed_test, ["synthetic_processes_only=$true", "transport_mocked=$true",
                         "real_stop_process_or_taskkill_executed=$false",
                         "dp1_full_implementation_passed=$false"]),
        (powershell_function(helper, "Invoke-YimePimeRequiredStopScript"),
         ["if(-not (Test-Path -LiteralPath $script -PathType Leaf)){throw", "$result -notin @(0,2)"]),
        (sources["tools/dev-install.ps1"], ["Assert-YimePimeOwnedRoot", "Invoke-YimePimeRequiredStopScript"]),
        (sources["tools/dev-stop-pime.ps1"], ["Stop-YimePimeOwnedProcesses", "exit 2"]),
        (sources["installer/installer.nsi"], ["!insertmacro YimePimeOwnershipGuard \"un.\"",
          "Call validateExistingPimeRoot", 'Section "Uninstall"',
          "Call un.verifyRegistrationOwnership", "Call un.stopOwnedPime"]),
    )
    for body, anchors in guards:
        if any(anchor not in body for anchor in anchors):
            fail("Rime maintenance ownership guard missing or changed")
    # Check order inside actual function bodies, not mere call-site presence.
    for name, guard, write in (("Add-InstallRootCandidate", "Assert-YimePimeOwnedRoot", "$Candidates.Add"),
                               ("Remove-InstallTree", "Assert-YimePimeOwnedRoot", "Remove-Item -LiteralPath")):
        body = powershell_function(uninstall, name)
        if body.index(guard) >= body.index(write):
            fail("Rime maintenance ownership guard is after mutation")
    uninstall_section = one(r'(?ms)^Section "Uninstall"\s+.*?^SectionEnd',
                            sources["installer/installer.nsi"], "Rime uninstall section").group()
    if uninstall_section.index("Call un.verifyRegistrationOwnership") >= uninstall_section.index("Call un.stopOwnedPime"):
        fail("Rime uninstall stops processes before registration ownership verification")
    checked = "\n".join(sources[path] for path in ("tools/dev-stop-pime.ps1", "tools/dev-install.ps1", "tools/dev-uninstall.ps1", "installer/installer.nsi"))
    if re.search(r"/IM\s+PIMELauncher|\$runningLaunchers\s*\|\s*Stop-Process|PIMELauncher\.exe[^\n]*?/quit", checked):
        fail("unsafe Rime maintenance termination reintroduced")
    if ("$legacyInstallRootFromRegistry" in uninstall or "$LegacyDefaultInstallRoot" in uninstall or
        re.search(r"(?m)^\s*(Stop-Process|Wait-Process|Start-Process)\b", helper)):
        fail("Rime explicit-root scope changed")
    if (re.search(r"(?mi)^\s*(Stop-Process|taskkill(?:\.exe)?)\b", directed) or
            "PIMELauncher2_QuitEvent" in directed or
            "maintenance::wait_for_directed_stop(&identity)" not in launcher or
            "backend_manager.shutdown_gracefully().await?" not in launcher or
            "DIRECTED_MAINTENANCE_EXIT_CODE" not in launcher or
            "watchdog restart is suppressed" not in launcher or
            "self.shutdown.send(true)" not in backend_manager or
            "BackendLoopExit::Shutdown" not in backend_manager or
            "ServerOptions" not in launcher_maintenance):
        fail("Rime directed-stop source contract missing or changed")
    return {
        "level": "source-guard-and-synthetic-directed-stop-checks-not-installed-live-or-transaction-acceptance",
        "quiescent_admission_only": False,
        "historical_findings_with_source_guard_anchors": ["DP1-PIME-STOP-01", "DP1-PIME-STOP-02", "DP1-PIME-LEGACY-03"],
        "directed_graceful_shutdown_source_anchors_present": True,
        "directed_graceful_shutdown_synthetic_contract_source_anchors_present": True,
        "automatic_force_stop_source_present": False,
        "installed_live_directed_shutdown_examined": False,
    }


def transaction_source_status(sources):
    """Classify current source wiring without executing maintenance or an installer."""
    fixture = sources["tools/dual-product/transaction-isolation.ps1"]
    fixture_test = sources["tools/dual-product/test-transaction-isolation.ps1"]
    core = sources["tools/yimecore/manage-e6c-trial-install.ps1"]
    core_acceptance = sources["tools/yimecore/invoke-local-product-native-install.ps1"]
    core_rollback = sources["tools/yimecore/invoke-local-rollback-rehearsal.ps1"]
    ci = sources[".github/workflows/ci.yaml"]
    nsis = sources["installer/installer.nsi"]
    pime_cleanup = sources["tools/pime-registry-cleanup.ps1"]
    pime_ownership = sources["tools/dual-product/rime-pime-ownership.ps1"]
    pime_maintenance_entry = sources["tools/dual-product/invoke-rime-pime-maintenance.ps1"]
    native_ime_module = sources["libIME2/src/ImeModule.cpp"]
    fault_engine = sources["tools/dual-product/rime-pime-transaction-engine.ps1"]
    fault_test = sources["tools/dual-product/test-rime-pime-transaction-faults.ps1"]
    replay_model_test = sources["tools/dual-product/test-rime-pime-transaction-replay-model.ps1"]
    fixture_journal = sources["tools/dual-product/rime-pime-fixture-transaction-journal.ps1"]
    fixture_journal_module = sources["tools/dual-product/rime-pime-fixture-transaction-journal.psm1"]
    fixture_journal_test = sources["tools/dual-product/test-rime-pime-fixture-transaction-journal.ps1"]
    staged_builder = sources["tools/build-rime-pime-installer.ps1"]
    go_payload_inventory = sources["tools/dual-product/rime-pime-go-payload-inventory.json"]
    go_payload_inventory_sidecar = sources["tools/dual-product/rime-pime-go-payload-inventory.json.sha256"]
    package_staging = sources["tools/dual-product/rime-pime-package-staging.ps1"]
    package_staging_module = sources["tools/dual-product/rime-pime-package-staging.psm1"]
    package_staging_test = sources["tools/dual-product/test-rime-pime-package-staging.ps1"]
    package_staging_runner = sources["tools/dual-product/run-rime-pime-package-staging.ps1"]
    nsis_stage = sources["tools/dual-product/rime-pime-nsis-stage.ps1"]
    nsis_stage_module = sources["tools/dual-product/rime-pime-nsis-stage.psm1"]
    nsis_stage_test = sources["tools/dual-product/test-rime-pime-nsis-stage.ps1"]
    staged_build = sources["tools/dual-product/rime-pime-staged-installer-build.ps1"]
    staged_build_module = sources["tools/dual-product/rime-pime-staged-installer-build.psm1"]
    staged_build_test = sources["tools/dual-product/test-rime-pime-staged-installer-build.ps1"]
    nsis_toolchain = sources["tools/dual-product/rime-pime-nsis-toolchain-closure.ps1"]
    nsis_toolchain_module = sources["tools/dual-product/rime-pime-nsis-toolchain-closure.psm1"]
    nsis_toolchain_test = sources["tools/dual-product/test-rime-pime-nsis-toolchain-closure.ps1"]
    nsis_compiler_interval = sources["tools/dual-product/rime-pime-nsis-compiler-interval.ps1"]
    nsis_compiler_interval_test = sources["tools/dual-product/test-rime-pime-nsis-compiler-interval.ps1"]
    nsis_membership_monitor = sources["tools/dual-product/rime-pime-nsis-membership-monitor-v1.ps1"]
    nsis_membership_monitor_module = sources["tools/dual-product/rime-pime-nsis-membership-monitor-v1.psm1"]
    nsis_membership_fixture_writer = sources["tools/dual-product/invoke-rime-pime-nsis-membership-fixture-writer-v1.ps1"]
    nsis_membership_monitor_test = sources["tools/dual-product/test-rime-pime-nsis-membership-monitor-v1.ps1"]
    postbuild_toolchain_lock = sources["tools/dual-product/rime-pime-postbuild-toolchain-lock.json"]
    postbuild_toolchain_lock_sidecar = sources["tools/dual-product/rime-pime-postbuild-toolchain-lock.json.sha256"]
    postbuild = sources["tools/dual-product/rime-pime-postbuild-extraction.ps1"]
    postbuild_module = sources["tools/dual-product/rime-pime-postbuild-extraction.psm1"]
    postbuild_test = sources["tools/dual-product/test-rime-pime-postbuild-extraction.ps1"]
    postbuild_runner = sources["tools/dual-product/run-rime-pime-postbuild-extraction.ps1"]
    receipt_v2 = sources["tools/dual-product/rime-pime-package-receipt-v2.ps1"]
    receipt_store = sources["tools/dual-product/rime-pime-receipt-v2-store.ps1"]
    receipt_store_test = sources["tools/dual-product/test-rime-pime-receipt-v2-store.ps1"]
    receipt_v2_module = sources["tools/dual-product/rime-pime-package-receipt-v2.psm1"]
    receipt_v2_finalizer = sources["tools/dual-product/finalize-rime-pime-package-receipt-v2.ps1"]
    receipt_v2_test = sources["tools/dual-product/test-rime-pime-package-receipt-v2.ps1"]
    receipt_no_downgrade_test = sources["tools/dual-product/test-rime-pime-receipt-no-downgrade.ps1"]
    installer_receipt_transaction = sources[
        "tools/dual-product/rime-pime-installer-receipt-transaction.ps1"
    ]
    installer_receipt_transaction_module = sources[
        "tools/dual-product/rime-pime-installer-receipt-transaction.psm1"
    ]
    installer_receipt_transaction_test = sources[
        "tools/dual-product/test-rime-pime-installer-receipt-transaction.ps1"
    ]
    isolated_candidate_runner = sources[
        "tools/dual-product/run-rime-pime-isolated-candidate.ps1"
    ]
    isolated_candidate_test = sources[
        "tools/dual-product/test-rime-pime-isolated-candidate.ps1"
    ]
    version_identity_admission = sources[
        "tools/dual-product/rime-pime-version-identity-admission.psm1"
    ]
    version_identity_admission_test = sources[
        "tools/dual-product/test-rime-pime-version-identity-admission.ps1"
    ]
    candidate_evidence_archive = sources[
        "tools/dual-product/rime-pime-candidate-evidence-archive.ps1"
    ]
    candidate_evidence_archive_module = sources[
        "tools/dual-product/rime-pime-candidate-evidence-archive.psm1"
    ]
    candidate_evidence_archive_test = sources[
        "tools/dual-product/test-rime-pime-candidate-evidence-archive.ps1"
    ]
    actual_migration_review = sources[
        "tools/dual-product/rime-pime-actual-migration-review.psm1"
    ]
    actual_migration_review_test = sources[
        "tools/dual-product/test-rime-pime-actual-migration-review.ps1"
    ]
    dp1r_trust_admission = sources[
        "tools/dual-product/rime-pime-dp1r-trust-admission.psm1"
    ]
    dp1r_trust_admission_test = sources[
        "tools/dual-product/test-rime-pime-dp1r-trust-admission.ps1"
    ]
    dp1r_actual_review = sources[
        "tools/dual-product/review-rime-pime-dp1r-trust.ps1"
    ]
    dp1s_archive_runner = sources[
        "tools/dual-product/publish-rime-pime-dp1s-off-repository-archive.ps1"
    ]
    dp1s_archive_test = sources[
        "tools/dual-product/test-rime-pime-dp1s-off-repository-archive.ps1"
    ]
    dp1t_actual_adapter = sources[
        "tools/dual-product/invoke-rime-pime-actual-canonical-migration.ps1"
    ]
    dp1t_actual_adapter_test = sources[
        "tools/dual-product/test-rime-pime-actual-canonical-migration.ps1"
    ]
    dp1u_gate = sources[
        "tools/dual-product/rime-pime-dp1u-maintenance-runtime-gate.psm1"
    ]
    dp1u_gate_test = sources[
        "tools/dual-product/test-rime-pime-dp1u-maintenance-runtime-gate.ps1"
    ]
    dp1u_current_review = sources[
        "tools/dual-product/review-rime-pime-dp1u-current-readiness.ps1"
    ]
    dp1u_preflight = sources[
        "tools/dual-product/rime-pime-dp1u-isolated-preflight.psm1"
    ]
    dp1u_preflight_schema = sources[
        "tools/dual-product/rime-pime-dp1u-isolated-preflight.schema.json"
    ]
    dp1u_preflight_fixture = sources[
        "tools/dual-product/fixtures/dp1u-isolated-preflight.synthetic.json"
    ]
    dp1u_preflight_test = sources[
        "tools/dual-product/test-rime-pime-dp1u-isolated-preflight.ps1"
    ]
    receipt_v2_supersession = sources["tools/dual-product/rime-pime-receipt-v2-supersession.ps1"]
    receipt_v2_supersession_module = sources["tools/dual-product/rime-pime-receipt-v2-supersession.psm1"]
    receipt_v2_supersession_test = sources["tools/dual-product/test-rime-pime-receipt-v2-supersession.ps1"]
    target_user = sources["tools/dual-product/rime-pime-target-user.ps1"]
    target_entry = sources["tools/dual-product/invoke-rime-pime-target-user.ps1"]
    target_test = sources["tools/dual-product/test-rime-pime-target-user.ps1"]
    try:
        inventory = json.loads(go_payload_inventory)
    except (TypeError, ValueError):
        fail("Rime/PIME Go payload inventory is not valid JSON")
    inventory_files = inventory.get("files")
    if (inventory.get("schema_version") != "yime-rime-pime-go-payload-inventory-v1" or
            inventory.get("source_root") != "go-backend/build/go-backend" or
            inventory.get("destination_root") != "go-backend" or
            inventory.get("selection_policy") != "exact-versioned-path-list-v1" or
            not isinstance(inventory_files, list) or len(inventory_files) != 148 or
            any(not isinstance(path, str) or not path or "\\" in path for path in inventory_files) or
            inventory_files != sorted(inventory_files) or
            len({path.casefold() for path in inventory_files}) != len(inventory_files)):
        fail("Rime/PIME Go payload inventory identity or exact set changed")
    inventory_digest = hashlib.sha256(go_payload_inventory.encode("utf-8")).hexdigest()
    if go_payload_inventory_sidecar != inventory_digest + "  rime-pime-go-payload-inventory.json\n":
        fail("Rime/PIME Go payload inventory sidecar is stale or malformed")
    try:
        postbuild_toolchain = json.loads(postbuild_toolchain_lock)
    except (TypeError, ValueError):
        fail("Rime/PIME post-build toolchain lock is not valid JSON")
    postbuild_nsis = postbuild_toolchain.get("nsis", {})
    postbuild_support = postbuild_nsis.get("support", [])
    compiler_input_closure = postbuild_nsis.get("compiler_input_closure", {})
    closure_roots = compiler_input_closure.get("roots", [])
    required_inputs = compiler_input_closure.get("required_inputs", [])
    expected_closure_roots = [
        {"path": "Bin", "directory_count": 1, "file_count": 6},
        {"path": "Contrib", "directory_count": 12, "file_count": 237},
        {"path": "Include", "directory_count": 2, "file_count": 31},
        {"path": "Plugins/x86-unicode", "directory_count": 1, "file_count": 16},
        {"path": "Stubs", "directory_count": 1, "file_count": 13},
    ]
    postbuild_lock_digest = hashlib.sha256(postbuild_toolchain_lock.encode("utf-8")).hexdigest()
    if (postbuild_toolchain.get("schema_version") != "yime-rime-pime-postbuild-toolchain-lock-v2" or
            postbuild_toolchain.get("toolchain_id") != "mycomputer-rime-pime-nsis-static-x86-x64-v2" or
            postbuild_toolchain.get("package_profile") != "x86-x64-v1" or
            postbuild_toolchain.get("seven_zip", {}).get("path") != "C:/Program Files/7-Zip/7z.exe" or
            postbuild_toolchain.get("seven_zip", {}).get("library", {}).get("path") !=
            "C:/Program Files/7-Zip/7z.dll" or
            postbuild_nsis.get("root") != "C:/Program Files (x86)/NSIS" or
            compiler_input_closure.get("scope") != "repository-pinned-nsis-distribution-non-os-v1" or
            compiler_input_closure.get("canonical_tree_algorithm") !=
            "sha256-directory-then-file-tab-records-utf8-lf-v1" or
            closure_roots != expected_closure_roots or
            compiler_input_closure.get("directory_count") != 17 or
            compiler_input_closure.get("file_count") != 303 or
            len(required_inputs) != 51 or
            compiler_input_closure.get("tree_sha256") !=
            "a908c3b306098217a87a62f0eb4a18c3b2bb5391efde93420bbec1f38ec8d352" or
            len(postbuild_support) != 5 or
            postbuild_lock_digest != "01e913d82b277ac9219148e9fb26df7851475ce0b70ff5d7b58df51179603c45" or
            postbuild_toolchain_lock != json.dumps(postbuild_toolchain, ensure_ascii=False,
                                                   separators=(",", ":")) + "\n" or
            postbuild_toolchain_lock_sidecar != postbuild_lock_digest +
            "  rime-pime-postbuild-toolchain-lock.json\n" or
            ("$script:RimePimePostbuildToolchainLockSha256 = '" + postbuild_lock_digest + "'")
            not in postbuild):
        fail("Rime/PIME post-build toolchain lock identity or sidecar changed")
    for body, anchors in (
        (fixture, ["function Assert-DualProductSameSidChain", "function Assert-DualProductTransactionFixture",
                   "actual_registry_or_install_mutation_executed = $false", "dp1_full_implementation_passed = $false"]),
        (fixture_test, ["rime_pime_initiating_sid_chain_wired", "remaining_real_gates",
                        "actual_restore_or_process_stop_executed=$false"]),
        (core, ["'-TargetUserSid', (Quote-Argument $TargetUserSid)",
                "'-StateRoot', (Quote-Argument $stateRootPath)",
                "must be elevated with the same Windows account that started the operation",
                "New-Item -ItemType Directory -Path $stagingRoot",
                "$preinstall = Invoke-UninstallCore",
                "Restore-PreviousInstallation $previousRoot $previousConfigText",
                "Restore-RegistryValueSnapshot $runKey $productKeyName $runSnapshot",
                "Restore-RegistryKeySnapshot $uninstallKey $uninstallSnapshot",
                "Restore-RegistryKeySnapshot $userTipKey $userTipSnapshot"]),
        (core_acceptance, ["$production='{35F67E9D-A54D-4177-9697-8B0AB71A9E04}'",
                           "$Before.protected|ConvertTo-Json", "$After.protected|ConvertTo-Json"]),
        (core_rollback, ["system_visible_registry_restored", "user_registration_and_value_kinds_restored"]),
        (target_user, ["function Assert-YimePimeElevationEnvelope",
                       "function Get-YimePimeTargetUserRegistryPath",
                       "InitiatingTokenElevated", "WorkerTokenElevated"]),
        (target_entry, ["CaptureInitiator", "CreateEnvelope", "ValidateWorker",
                        "Confirm-YimePimeElevationEnvelopeFile", "-Consume"]),
        (target_test, ["actual_elevation_executed=$false",
                       "actual_registry_or_profile_mutation_executed=$false",
                       "native_uac_and_registered_profile_acceptance_passed=$false"]),
        (pime_ownership, ["function Get-YimePimeRegistrationSnapshot",
                          "function Assert-YimePimeRegistrationSnapshot",
                          "function Remove-YimePimeTargetUserProfileValues"]),
        (pime_maintenance_entry, ["'ValidateRegistration'", "'CleanupTargetUserProfile'",
                                  "-TargetUserSid $TargetUserSid"]),
        (fault_engine, ["function Get-YimePimeUpgradeStageCatalog",
                        "function Invoke-YimePimeSyntheticUpgradeTransaction",
                        "function Get-YimePimeTransactionStageCatalog",
                        "function Get-YimePimeReplayDisposition",
                        "function Resolve-YimePimeIdempotentTransition",
                        "function Get-YimePimeManifestRemovalPlan",
                        "yime-pime-replay-disposition-v1",
                        "yime-pime-idempotent-transition-v1",
                        "yime-pime-manifest-removal-plan-v1",
                        "recursive=$false",
                        "physical_deletion_executed=$false",
                        "actual_filesystem_registry_process_or_elevation_executed=$false"]),
        (fault_test, ["every-stage-supports-before-and-after-faults-with-the-commit-boundary-preserved",
                      "postcommit-before-after-cleanup-state-is-not-misreported-as-rollback",
                      "dp1_full_implementation_passed=$false"]),
        (replay_model_test, ["generic-upgrade-catalog-preserves-the-existing-24-stage-contract",
                             "uninstall-catalog-has-journal-mutation-commit-and-cleanup-boundaries",
                             "replay-prepared-requires-rollback",
                             "replay-committed-requires-cleanup",
                             "replay-terminal-states-are-idempotent-noops",
                             "idempotent-transition-refuses-unrecognized-current-identity",
                             "manifest-removal-plan-is-leaf-first-and-reserves-two-final-files",
                             "yime-pime-transaction-replay-model-test-v1",
                             "actual_filesystem_registry_process_native_installer_or_product_operation_executed=$false"]),
        (fixture_journal, ["Fixture-only durable transaction-journal helpers for DP1-I",
                           "function Assert-RimePimeFixtureRoot",
                           "function Assert-RimePimeFixtureTransactionContext",
                           "function Write-RimePimeFixtureSealedJson",
                           "[IO.FileMode]::CreateNew",
                           "[IO.FileOptions]::WriteThrough",
                           "$stream.Flush($true)",
                           "function Open-RimePimeFixtureJournalLock",
                           "[IO.FileShare]::None",
                           "function Assert-RimePimeFixturePreparedArtifactBindings",
                           "Fixture operation ID is not bound to its transaction and stage",
                           "Fixture journal hash chain is invalid",
                           "source='synthetic-json-only'",
                           "contains_user_text=$false",
                           "function Invoke-RimePimeFixtureExactRemoval",
                           "[IO.Directory]::Delete($path,$false)",
                           "changed_or_foreign_preserved",
                           "concurrent_replacement_excluded=$false",
                           "function Resume-RimePimeFixtureTransaction",
                           "installer_or_uninstaller_executed=$false",
                           "registry_provider_used=$false",
                           "product_process_accessed=$false"]),
        (fixture_journal_module, ["defines helpers only and performs no filesystem, registry, process, installer",
                                  ". (Join-Path $PSScriptRoot 'rime-pime-fixture-transaction-journal.ps1')",
                                  "Export-ModuleMember -Function @(",
                                  "'Resume-RimePimeFixtureTransaction'",
                                  "'Invoke-RimePimeFixtureExactRemoval'"]),
        (fixture_journal_test, ["Use a fresh immediate .tmp/dual-product/dp1-i-journal-* output root",
                                "Prepared admission is bound to sealed artifacts in the same fixture case",
                                "unbound-operation",
                                "Persistent FileShare.None lock excludes a concurrent fixture writer",
                                "Sidecar-last fault points",
                                "Integrity, closed-schema, chain-binding",
                                "Static negative surface",
                                "yime-rime-pime-fixture-journal-test-result-v1",
                                "fixture_only=$true",
                                "installer_or_uninstaller_executed=$false",
                                "registry_provider_used=$false",
                                "product_process_accessed=$false",
                                "production_user_data_accessed=$false",
                                "recursive_delete_used=$false",
                                "concurrent_replacement_excluded=$false",
                                "real_crash_or_power_loss_claimed=$false",
                                "cross_process_restart_executed=$false",
                                "rollback_or_cleanup_adapter_executed=$false",
                                "directory_metadata_durability_proven=$false"]),
        (staged_builder, ["Import-Module -Name $nsisToolchainModule -Force",
                          "Import-Module -Name $stagingModule -Force",
                          "Import-Module -Name $nsisStageModule -Force",
                          "Import-Module -Name $stagedBuildModule -Force",
                          "$nsisToolchainModule=Join-Path $root 'tools\\dual-product\\rime-pime-nsis-toolchain-closure.psm1'",
                          "$buildLogicPaths=@(",
                          "function Assert-RimePimeBootstrapPlainPath",
                          "$buildLogicLeases=[Collections.Generic.List[object]]::new()",
                          "Build-logic path differs from its pre-import read lease",
                          "Test-RimePimeBuildInputLeases @($buildLogicLeases)",
                          "Write-RimePimeNsisStageInclude -StageRoot $stageResult.StageRoot",
                          "Push-Location $nsisIncludeRoot",
                          "'/NOCD','/NOCONFIG'",
                          "/DPACKAGE_STAGE_ROOT=$($stageResult.StageRoot)",
                          "/DPACKAGE_LOCALE_ROOT=$localeRoot",
                          "/DPACKAGE_UNSIGNED_DISABLED_BUILD=1",
                          "Test-RimePimeNsisStageInclude -StageRoot $stageResult.StageRoot",
                          "executed_build_logic_source_count=[int]$buildLogicDigests.Count",
                          "build_logic_read_lease_count=[int]$buildLogicLeases.Count",
                          "publication_cross_process_lock=$true",
                          "Invoke-RimePimePublicationCommit -Package $package",
                          "unsigned_disabled_build=$true",
                          "signing_hook_processes_executed=$false",
                          "signing_host_and_release_signing_pending=$true",
                          "path_searched_signing_host_not_executed=$true",
                          "nsis_distribution_tree_exact_at_open_and_test=$true",
                          "nsis_known_input_file_replacement_closure=$true",
                          "nsis_compiler_input_pre_snapshot_exact=$true",
                          "nsis_compiler_input_post_snapshot_exact=$true",
                          "nsis_compiler_input_leases_held_during_makensis=$true",
                          "active_same_sid_transient_tree_membership_interference_excluded=$false",
                          "nsis_non_os_compiler_input_closure=$false",
                          "full_nsis_toolchain_input_closure=$false",
                          "postbuild_extraction_compared_to_stage=$false",
                          "canonical_receipt_binds_stage_evidence=$false",
                          "generated_uninstaller_verified=$false",
                          "final_payload_closure=$false"]),
        (nsis, ['!include "${NSISDIR}\\Include\\MUI2.nsh"',
                '!include "${NSISDIR}\\Include\\x64.nsh"',
                '!include "${NSISDIR}\\Include\\Winver.nsh"',
                '!include "${NSISDIR}\\Include\\LogicLib.nsh"',
                '!include "${NSISDIR}\\Include\\FileFunc.nsh"',
                "!ifndef PACKAGE_LOCALE_ROOT",
                "!ifndef PACKAGE_UNSIGNED_DISABLED_BUILD",
                "!ifndef PACKAGE_SIGN_FILE_PATH",
                "!ifndef PACKAGE_POWERSHELL_PATH",
                '!include "${PACKAGE_LOCALE_ROOT}\\${LANGLOAD}.nsh"',
                '"${PACKAGE_POWERSHELL_PATH}" -NoProfile -ExecutionPolicy Bypass -File "${PACKAGE_SIGN_FILE_PATH}" -Path "%1"']),
        (package_staging, ["yime-rime-pime-payload-spec-v1",
                           "function Write-RimePimePackageStageSpec",
                           "function New-RimePimePackageCopyStage",
                           "function Test-RimePimePackageCopyStage",
                           "rime-pime-go-payload-inventory.json",
                           "exact-versioned-path-list-v1",
                           "derived-nonempty-only-v1",
                           "final_payload_closure=$false"]),
        (package_staging_module, ["module defines helpers only",
                                  ". (Join-Path $PSScriptRoot 'rime-pime-package-staging.ps1')",
                                  "Export-ModuleMember -Function '*-RimePime*','*-YimePime*'"]),
        (package_staging_test, ["portable-content-digest-does-not-contain-local-file-identity",
                                "new-file-in-closed-source-tree-is-rejected-after-spec-seal",
                                "alternate-data-stream-on-source-is-rejected-before-spec-seal",
                                "generated_uninstaller_verified=$false",
                                "nsis_consumes_stage=$false"]),
        (package_staging_runner, ["installed_namespace_file_count",
                                  "bootstrap_namespace_file_count",
                                  "source_tree_wildcard_used_for_copy=$false",
                                  "generated_uninstaller_verified=$false",
                                  "hard_blocks_remain=$true"]),
        (nsis_stage, ["yime-rime-pime-nsis-stage-include-v1",
                      "YimePimeStageTargetUserHelpers",
                      "YimePimeStageTextServiceX64",
                      "function Get-RimePimeNsisStageIncludeDocument",
                      "function Write-RimePimeNsisStageInclude",
                      "function Test-RimePimeNsisStageInclude",
                      "NSIS macro partition does not exactly cover the staged file set",
                      "final_payload_closure=$false"]),
        (nsis_stage_module, ["Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1')",
                             ". (Join-Path $PSScriptRoot 'rime-pime-nsis-stage.ps1')",
                             "Export-ModuleMember -Function '*-RimePimeNsis*'"]),
        (nsis_stage_test, ["definitions-only-module-generates-six-stage-only-macros",
                           "include-bytes-are-stable-across-distinct-stage-roots",
                           "Generated include escaped the stage-only explicit-File contract",
                           "generated_macro_count=6",
                           "actual_makensis_executed=$false",
                           "final_payload_closure=$false"]),
        (staged_build, ["function Open-RimePimeBuildInputLeases",
                        "function Test-RimePimeBuildInputLeases",
                        "function Open-RimePimePublicationLock",
                        "function New-RimePimePreparedPublication",
                        "function Invoke-RimePimePublicationCommit",
                        "$publicationLock=Open-RimePimePublicationLock -InstallerPath $InstallerPath -ReceiptPath $ReceiptPath",
                        "$publicationLock.Stream.Dispose()",
                        "Prepared publication input changed while leasing",
                        "Publication failed and rollback was incomplete"]),
        (staged_build_module, ["Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1')",
                               ". (Join-Path $PSScriptRoot 'rime-pime-staged-installer-build.ps1')",
                               "Export-ModuleMember -Function '*-RimePime*'"]),
        (staged_build_test, ["candidate-read-lease-blocks-writers-and-retains-the-same-bytes",
                             "canonical-publication-lock-excludes-a-second-publisher-and-is-reusable",
                             "YIME-1.4.0+build.7-setup.exe",
                             "prepared-publication-and-sidecar-last-commit-preserve-candidate-identity",
                             "third-item-failure-rolls-back-the-original-three-file-bundle",
                             "actual_makensis_executed=$false",
                             "final_payload_closure=$false"]),
        (nsis_toolchain, ["$script:RimePimeNsisClosureLockSha256='01e913d82b277ac9219148e9fb26df7851475ce0b70ff5d7b58df51179603c45'",
                          "$script:RimePimeNsisClosureLockSchema='yime-rime-pime-postbuild-toolchain-lock-v2'",
                          "function Open-RimePimeNsisCompilerInputClosure",
                          "function Test-RimePimeNsisCompilerInputClosure",
                          "function Close-RimePimeNsisCompilerInputClosure",
                          "nsis_distribution_tree_exact_at_open_and_test=$true",
                          "nsis_known_input_file_replacement_closure=$true",
                          "active_same_sid_transient_tree_membership_interference_excluded=$false",
                          "nsis_non_os_compiler_input_closure=$false;full_nsis_toolchain_input_closure=$false"]),
        (nsis_toolchain_module, ["Definitions-only entry point for the repository-pinned NSIS distribution",
                                 "Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1') -Force",
                                 "Export-ModuleMember -Function Open-RimePimeNsisCompilerInputClosure"]),
        (nsis_toolchain_test, ["same-sid-transient-unlisted-child-is-not-excluded-by-directory-leases",
                               "nsis_known_input_lease_contract_available_to_builder=$true",
                               "active_same_sid_transient_tree_membership_interference_excluded=$false",
                               "nsis_non_os_compiler_input_closure=$false",
                               "full_nsis_toolchain_input_closure=$false"]),
        (nsis_compiler_interval, ["DP1-NSIS-MEMBERSHIP-05",
                                  "function Open-RimePimeMonitoredNsisStage",
                                  "[YimePime.NsisMembership.MonitorHostV1]::new",
                                  "$closure=Open-RimePimeNsisCompilerInputClosureCore",
                                  "function Complete-RimePimeMonitoredNsisStage",
                                  "$result=$Stage.Monitor.Seal(10000)",
                                  "$null=Test-RimePimeNsisCompilerInputClosure $Stage.Closure",
                                  "physical_membership_prevention_claimed=$false",
                                  "active_same_sid_transient_tree_membership_interference_excluded=$false",
                                  "nsis_non_os_compiler_input_closure=$false;full_nsis_toolchain_input_closure=$false"]),
        (nsis_compiler_interval_test, ["foreach($mode in @('clean','file','directory','rename','root-file','compiler-error'))",
                                       "!system ",
                                       "same-SID child",
                                       "builder-rejects-before-publication",
                                       "actual_makensis_executed=$true",
                                       "installer_executed=$false",
                                       "full_nsis_toolchain_input_closure=$false"]),
        (postbuild_toolchain_lock, ["yime-rime-pime-postbuild-toolchain-lock-v2",
                                    "mycomputer-rime-pime-nsis-static-x86-x64-v2",
                                    '"directory_count":17',
                                    '"file_count":303',
                                    '"tree_sha256":"a908c3b306098217a87a62f0eb4a18c3b2bb5391efde93420bbec1f38ec8d352"',
                                    '"path":"C:/Program Files/7-Zip/7z.exe"',
                                    '"path":"C:/Program Files/7-Zip/7z.dll"',
                                    '"root":"C:/Program Files (x86)/NSIS"']),
        (postbuild, ["yime-rime-pime-postbuild-extraction-v1",
                     "function Test-RimePimePostbuildToolchainLockDocument",
                     "function Read-RimePimePostbuildToolchainLockDocument",
                     "function Read-RimePimePostbuildToolchainLock",
                     "function Open-RimePimePostbuildReadLease",
                     "function Assert-RimePimePostbuildReadLease",
                     "function Read-RimePimePostbuildLeaseBytes",
                     "function Open-RimePimePostbuildDirectoryLease",
                     "function Assert-RimePimePostbuildDirectoryLease",
                     "function Open-RimePimePostbuildExtractedFileLeases",
                     "function Test-RimePimePostbuildExtractedFileLeases",
                     "function Test-RimePimePostbuildExecutionLogicLeases",
                     "function Test-RimePimePostbuildRawByteBindings",
                     "[Parameter(Mandatory)][string]$PayloadNshDigest",
                     "function Test-RimePimePostbuildArchiveListing",
                     "function Test-RimePimePostbuildSevenZipLibraryBinding",
                     "function Invoke-RimePimePostbuildSevenZipRawEntry",
                     "function Invoke-RimePimePostbuildExtraction",
                     "[Parameter(Mandatory)]$Package",
                     "Assert-RimePimePackagePlanStageBindings -Package $Package -ContentManifest $manifest.Manifest",
                     "Test-RimePimeNsisStageInclude -StageRoot $stage",
                     "Read-RimePimePostbuildToolchainLock",
                     "payload_nsh_raw_byte_binding=$true",
                     "payload_nsh_raw_byte_binding_verified=$true",
                     "execution_logic_read_leases_held_through_seal=$true",
                     "installer_read_lease_held_for_all_reads=$true",
                     "uninstaller_read_lease_held_for_all_reads=$true",
                     "parent_created_per_entry_raw_stdout_snapshot=$true",
                     "installer_archive_per_entry_raw_stdout_verified=$true",
                     "nested_uninstaller_archive_per_entry_raw_stdout_verified=$true",
                     "extracted_file_read_leases_held_through_seal=$true",
                     "seven_zip_read_lease_held_for_all_calls=$true",
                     "seven_zip_parser_library_read_lease_held_for_all_calls=$true",
                     "seven_zip_call_count=197",
                     "generated_uninstaller_verified=$false",
                     "generated_uninstaller_trusted=$false",
                     "final_payload_closure=$false;delivery_admitted=$false"]),
        (postbuild_module, ["Definitions-only entry point for static post-build NSIS archive verification",
                            "Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1') -Force",
                            ". (Join-Path $PSScriptRoot 'rime-pime-postbuild-extraction.ps1')",
                            "Export-ModuleMember -Function '*-RimePimePostbuild*'"]),
        (postbuild_test, ["repository-toolchain-lock-is-code-pinned-and-current",
                          "postbuild-api-does-not-accept-tool-path-and-self-approved-digest",
                          "toolchain-lock-fake-seven-zip-library-hash-is-rejected",
                          "seven-zip-info-binds-one-pinned-parser-library",
                          "runner-explicitly-binds-real-package-to-stage-before-extraction",
                          "all-four-raw-byte-bindings-are-required",
                          "evidence-claims-per-entry-origin-but-keeps-final-delivery-false",
                          "sealed-result-create-new-memory-digest-and-leases-are-stable",
                          "precreated-hardlink-result-is-rejected-with-sentinel-unchanged",
                          "precreated-hardlink-capture-is-rejected-with-sentinel-unchanged",
                          "precreated-junction-extraction-directory-is-rejected-with-sentinel-unchanged",
                          "stable-file-read-lease-is-accepted",
                          "leased-file-write-is-blocked",
                          "leased-file-swap-is-blocked",
                          "leased-seven-zip-parser-library-replacement-is-blocked",
                          "leased-extracted-child-write-is-blocked",
                          "leased-extracted-child-delete-is-blocked",
                          "leased-extracted-child-replacement-is-blocked",
                          "incomplete-extracted-file-lease-set-is-rejected",
                          "incomplete-execution-logic-lease-set-is-rejected",
                          "stable-extraction-directory-lease-is-accepted",
                          "leased-expected-child-directory-swap-is-blocked",
                          "installer-listing-exact-multiset-is-accepted",
                          "nested-uninstaller-listing-exact-multiset-is-accepted",
                          "seven_zip_or_makensis_executed=$false",
                          "generated_uninstaller_trusted=$false",
                          "final_payload_closure=$false"]),
        (postbuild_runner, ["Assert-RimePimePackagePlanStageBindings -Package $package -ContentManifest $content.Manifest",
                            "$logicPaths=@(",
                            "Open every definitions/control file before importing any module",
                            "Test-RimePimePostbuildExecutionLogicLeases @($logicLeases)",
                            "Invoke-RimePimePostbuildExtraction",
                            "-Package $package -PayloadNshReceiptPath $PayloadNshReceiptPath",
                            "-ExpectedPayloadNshReceiptDigest $ExpectedPayloadNshReceiptDigest",
                            "-ExecutionLogicLeases @($logicLeases)",
                            "locked NSIS archives passed exact listing, per-entry raw-stdout hashing, and stable leased snapshot comparison",
                            "installer and uninstaller were not executed",
                            "final closure remains false"]),
        (receipt_v2, ["$script:RimePimePackageReceiptV2Schema='yime-rime-pime-package-build-receipt-v2'",
                      "function New-RimePimePackageReceiptV2Preparation",
                      "function Publish-RimePimePackageReceiptV2",
                      "function Read-RimePimePackageBuildReceiptV2",
                      "receipt_state='canonical-static-closure-disabled'",
                      "evidence_artifacts_embedded=$false;evidence_artifacts_durable=$false",
                      "active_same_sid_transient_tree_membership_interference_excluded=$false",
                      "non_os_compiler_input_closure=$false;full_toolchain_input_closure=$false",
                      "Receipt-v2 publication requires the current canonical v1 receipt as its predecessor"]),
        (receipt_v2_module, ["Definitions-only entry point",
                             ". (Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.ps1')",
                             ". (Join-Path $PSScriptRoot 'rime-pime-receipt-v2-store.ps1')",
                             "Export-ModuleMember -Function @(",
                             "'New-RimePimePackageReceiptV2Preparation'",
                             "'Close-RimePimePackageReceiptV2Preparation'",
                             "'Publish-RimePimePackageReceiptV2'",
                             "'Read-RimePimePackageBuildReceiptV2'",
                             "'Publish-RimePimePackageReceiptV2Supersession'",
                             "'Resume-RimePimePackageReceiptV2Publication'"]),
        (receipt_store, ["function Open-RimePimeReceiptPublicationIntentLease",
                         "Assert-RimePimeReceiptJsonSyntax $text",
                         "function Publish-RimePimePackageReceiptV2Supersession",
                         "function Resume-RimePimePackageReceiptV2Publication",
                         "Open-RimePimePublicationLock", "pending.json"]),
        (receipt_store_test, ["module-exports-only-six-explicit-receipt-apis",
                              "strict-intent-json-rejects-",
                              "missing-retained-object-sidecar-fails-closed",
                              "hard-exit-", "fresh-process-recovery",
                              "installer_or_uninstaller_executed=$false",
                              "product_processes_executed=$false",
                              "power_loss_verified=$false"]),
        (receipt_v2_finalizer, ["if(-not $PublishCanonical){throw",
                                "Duplicate receipt-v2 execution logic",
                                "Import-Module -Name $module -Force",
                                "Publish-RimePimePackageReceiptV2 -Prepared $prepared",
                                "No installer, uninstaller or signing process ran"]),
        (receipt_v2_test, ["dishonest-transient-membership-exclusion-claim-is-rejected",
                           "runner-requires-explicit-canonical-publication",
                           "staged-builder-refuses-canonical-v2-downgrade",
                           "receipt-v2-implementation-has-no-process-launch-surface"]),
        (receipt_no_downgrade_test, ["yime-rime-pime-receipt-no-downgrade-test-v1",
                                     "Refusing to overwrite canonical package build receipt schema",
                                     "v1/v2 no-downgrade checks passed without signing or product execution"]),
        (installer_receipt_transaction, [
            "Definitions-only, fixture-gated installer/receipt identity replacement",
            "function Assert-RimePimeInstallerReceiptTransactionFixtureRoot",
            "dp1-package-receipt-v2-test-dp1n-",
            "function Move-RimePimeInstallerReceiptNoReplace",
            "[YimeReceiptStorage.Native]::MoveFileEx($Source,$Destination,8)",
            "Deliberately omit REPLACE_EXISTING.",
            "function Write-RimePimeInstallerReceiptIntentNoReplace",
            "('.rime-pime-intent-'+[guid]::NewGuid().ToString('N')+'.tmp')",
            "Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'intent-copy'",
            "function Stage-RimePimeInstallerReceiptPhysicalLeaf",
            "New physical installer must remain absent while its durable stage is prepared.",
            "('.rime-pime-copy-'+[guid]::NewGuid().ToString('N')+'.tmp')",
            "Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'installer-copy'",
            "function Assert-RimePimeInstallerReceiptCompletionTargetAbsent",
            "function Complete-RimePimeInstallerReceiptTransaction",
            "function Publish-RimePimeInstallerReceiptTransaction",
            "function Resume-RimePimeInstallerReceiptTransaction",
            "Canonical receipt pair is outside the allowed old/new transaction states.",
        ]),
        (installer_receipt_transaction_module, [
            "Definitions-only isolated DP1-N entry point.",
            "rime-pime-nsis-toolchain-closure.psm1",
            "rime-pime-package-staging.psm1",
            "rime-pime-nsis-stage.psm1",
            "rime-pime-staged-installer-build.psm1",
            ". (Join-Path $PSScriptRoot 'rime-pime-package-receipt-v2.ps1')",
            ". (Join-Path $PSScriptRoot 'rime-pime-receipt-v2-store.ps1')",
            ". (Join-Path $PSScriptRoot 'rime-pime-installer-receipt-transaction.ps1')",
            "Export-ModuleMember -Function @(",
            "'Publish-RimePimeInstallerReceiptTransaction'",
            "'Resume-RimePimeInstallerReceiptTransaction'",
        ]),
        (installer_receipt_transaction_test, [
            "Transaction worker is fixture-only.",
            "module-exports-only-two-isolated-transaction-apis",
            "foreign-completion-leaf-is-rejected-before-any-transaction-write",
            "installer-no-replace-preserves-foreign-before-move-race",
            "completion-no-replace-rename-preserves-pending-file-id",
            "'objects','installer-copy','installer-temp','intent-copy','intent-temp'",
            "full_suite_executed=[bool]$fullSuiteExecuted",
            "all_executed_checks_passed=[bool]$allChecksPassed",
            "full_transaction_matrix=[bool]$fullMatrixVerified",
            "fixture_only=$true",
            "invoked_process_class='PowerShell test workers only'",
            "installed_product_actions_out_of_scope=$true",
            "hardware_power_loss_verified=$false",
            "directory_metadata_durability_verified=$false",
            "active_same_sid_physical_replacement_prevention_verified=$false",
        ]),
        (isolated_candidate_runner, [
            "'clone', '--local', '--no-hardlinks', '--no-checkout', '--no-tags'",
            "$gitCommand = @(Get-Command -Name $GitPath -CommandType Application -ErrorAction Stop)[0]",
            "$GitPath = Assert-ToolApplicationFile $gitCommand.Source 'Git client'",
            "'pin-clone-autocrlf-off'",
            "'-C', $clone, 'config', '--local', 'core.autocrlf', 'false'",
            "Isolated clone did not pin core.autocrlf=false before checkout.",
            "'checkout', '--detach', $head",
            "$runnerRelativePath = 'tools/dual-product/run-rime-pime-isolated-candidate.ps1'",
            "'hash-object', ('--path=' + $runnerRelativePath), '--', $runnerPath",
            "Runner file differs from exact source HEAD.",
            "runner_matches_exact_head = $true",
            "'build-current-source'",
            "'static-installer-manifest-check'",
            "'-StaticOnly'",
            "'static-postbuild-extraction'",
            "'finalize-canonical-receipt-v2'",
            "$retainedV2 = Publish-RimePimePackageReceiptV2Supersession",
            "$strictV2 = Read-RimePimePackageBuildReceiptV2",
            "Protected actual repository state changed during isolated candidate work.",
            "rime_pime_source_product_version -cne $headVersion",
            "Exact source HEAD version.txt differs from the reviewed dual-product source product identity.",
            "distinct_versioned_installer_leaf_for_dp1n = [bool]$distinctVersionedInstallerLeaf",
            "$cloneInstallerLeaf -ine $actualCanonicalInstallerLeaf",
            "Read-RimePimePackageBuildReceiptV2 -RepoRoot $root -ReceiptPath $actualCanonicalPath",
            "Get-RimePimeVersionIdentityAdmission -OldIdentity $oldIdentity",
            "dp1n_version_identity_admission = $identityAdmission",
            "actual_canonical_migration_admitted = $false",
            "directory_metadata_durability_verified = $false",
            "outer_tmp_retention_guaranteed = $false",
            "evidence_archived_outside_tmp = $false",
            "durability_scope = 'isolated-clone-content-addressed-process-interruption-protocol'",
            "full_nsis_toolchain_input_closure = $false",
        ]),
        (isolated_candidate_test, [
            "yime-rime-pime-isolated-candidate-contract-test-v1",
            "existing-output-is-rejected-before-clone",
            "reparse-repository-root-is-rejected",
            "full-static-chain-order-is-fixed",
            "product-install-sign-and-dp1n-entrypoints-are-absent",
            "full_candidate_build_executed = $false",
            "actual_canonical_touched = $false",
        ]),
        (version_identity_admission, [
            "Pure-data DP1-P admission contract",
            "function Get-RimePimeVersionIdentityAdmission",
            "old-and-successor-installer-path-not-distinct-on-windows",
            "$oldPath -ieq $newPath",
            "successor-durable-evidence-not-proven",
            "successor-current-build-evidence-not-proven",
            "successor-product-version-is-not-strictly-greater-by-semver",
            "function Compare-RimePimeProductVersionPrecedence",
            "actual_canonical_migration_admitted = $false",
            "installer_or_uninstaller_executed = $false",
            "registry_or_product_process_touched = $false",
            "Export-ModuleMember -Function 'Get-RimePimeVersionIdentityAdmission'",
        ]),
        (version_identity_admission_test, [
            "yime-rime-pime-version-identity-admission-test-v1",
            "distinct-canonical-successor-is-admitted-only-at-identity-layer",
            "module-exports-only-pure-admission-function",
            "same-leaf-different-hash-is-rejected",
            "core-version-downgrade-is-rejected",
            "semver-prerelease-precedence-is-enforced",
            "case-only-version-and-leaf-change-is-rejected-on-windows",
            "distinct-leaf-same-hash-is-rejected",
            "actual_canonical_read_or_written = $false",
            "actual_canonical_migration_admitted = $false",
        ]),
        (candidate_evidence_archive, [
            "Definitions-only DP1-Q protocol",
            ".tmp/dual-product/dp1-candidate-evidence-archive-test-*/cases/*",
            "'tools/dual-product/run-rime-pime-isolated-candidate.ps1'",
            "yime-rime-pime-candidate-evidence-archive-root-v1",
            "yime-rime-pime-candidate-evidence-archive-manifest-v1",
            "yime-rime-pime-candidate-evidence-archive-head-v1",
            "yime-rime-pime-candidate-evidence-archive-intent-v1",
            "yime-rime-pime-candidate-evidence-archive-completion-v1",
            "owner_scope='fixture-candidate-evidence-only'",
            "[IO.FileMode]::CreateNew",
            "$stream.Flush($true)",
            "MoveFileEx($nativeSource,$nativeDestination,8)",
            "function Assert-RimePimeCandidateArchiveRelativePathText",
            "$object.Data.Sha256 -cne [string]$row.sha256",
            "Candidate archive manifest must uniquely bind its $kind path, digest, and byte count.",
            "function Move-RimePimeCandidateArchiveWritingOrphans",
            "Candidate archive root physical member set is not exact.",
            "function Publish-RimePimeCandidateEvidenceArchive",
            "function Resume-RimePimeCandidateEvidenceArchive",
            "function Read-RimePimeCandidateEvidenceArchive",
            "fixture_sibling_archive_protocol_passed=$true",
            "actual_archive_root_published=$false;actual_evidence_archived_outside_repository_tmp=$false",
            "actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false",
            "hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false",
            "active_hostile_same_sid_physical_replacement_prevented=$false",
        ]),
        (candidate_evidence_archive_module, [
            "Import-Module -Name (Join-Path $PSScriptRoot 'rime-pime-package-staging.psm1')",
            ". (Join-Path $PSScriptRoot 'rime-pime-candidate-evidence-archive.ps1')",
            "'Publish-RimePimeCandidateEvidenceArchive'",
            "'Resume-RimePimeCandidateEvidenceArchive'",
            "'Read-RimePimeCandidateEvidenceArchive'",
        ]),
        (candidate_evidence_archive_test, [
            "yime-rime-pime-candidate-evidence-archive-test-v1",
            "dp1-candidate-evidence-archive-test-",
            "module-exports-exact-public-api",
            "clean-publish-read-and-source-independent-idempotency",
            "wrong-expected-runner-is-rejected-before-an-archive",
            "foreign-final-root-wins-before-commit-race-without-replacement",
            "hardlinked-source-is-rejected",
            "alternate-data-stream-source-is-rejected",
            "reparse-source-ancestor-is-rejected",
            "hard-exit-'+$phaseCopy+'-resumes-in-a-fresh-process",
            "'lock-created','object-copy','object-data'",
            "Committed archive retained an interrupted writing orphan.",
            "Interrupted object-copy orphan was not isolated outside the archive capsule.",
            "actual-checkout-root-is-rejected",
            "semantically-resealed-and-scalar-shape-tampering-is-rejected",
            "actual_archive_root_published=$false;actual_evidence_archived_outside_repository_tmp=$false",
            "actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false",
            "hardware_power_loss_verified=$false;directory_metadata_durability_verified=$false",
            "active_hostile_same_sid_physical_replacement_prevented=$false",
        ]),
        (actual_migration_review, [
            "Pure-data DP1-Q review gate",
            "function Get-RimePimeActualMigrationReview",
            "function Test-RimePimeMigrationReviewCanonicalWindowsPath",
            "$segment -match '[\\x00-\\x1f<>:\"|?*]'",
            "'tools/dual-product/invoke-rime-pime-actual-canonical-migration.ps1'",
            "non-note-property-",
            "'schema_version','product','repo_root','product_version'",
            "'schema_version','adapter_kind','actual_repo_root','adapter_path'",
            "yime-rime-pime-off-repository-archive-evidence-v1",
            "yime-rime-pime-actual-canonical-adapter-evidence-v1",
            "yime-rime-pime-actual-canonical-authorization-v1",
            "review_scope = 'actual-canonical-artifacts-only'",
            "review_ready = $reasons.Count -eq 0",
            "separate_execution_gate_required = $true",
            "archive-root-is-inside-actual-repository",
            "adapter-actual-repo-root-binding-mismatch",
            "authorization-repo-root-binding-mismatch",
            "$archiveReady = [bool]($sourceReady -and $reasons.Count -eq $archiveStart)",
            "$adapterReady = [bool]($sourceReady -and $archiveReady -and $reasons.Count -eq $adapterStart)",
            "actual_canonical_migration_admitted = $false",
            "actual_canonical_migrated = $false",
            "installer_or_uninstaller_execution_admitted = $false",
            "installed_yimecore_action_admitted = $false",
            "dp1_or_release_completion_admitted = $false",
            "Export-ModuleMember -Function 'Get-RimePimeActualMigrationReview'",
        ]),
        (actual_migration_review_test, [
            "yime-rime-pime-actual-migration-review-test-v1",
            "module-exports-only-one-pure-review-function",
            "complete-synthetic-evidence-is-review-ready-but-never-admitted",
            "every-required-field-has-a-stable-missing-reason",
            "script-property-getters-are-rejected-without-execution",
            "identity-binding-fields-must-be-nonempty-strings",
            "archive-and-repository-paths-must-be-canonical-and-cross-bound",
            "canonical-windows-paths-and-adapter-path-fail-closed",
            "archive-must-survive-source-unavailability-in-fresh-ps5-and-ps7-processes",
            "downstream-readiness-depends-on-valid-upstream-bindings",
            "actual-adapter-must-preserve-dp1n-fixture-gate-and-exact-write-set",
            "actual-adapter-preserves-physical-durability-and-hostile-same-sid-nonclaims",
            "explicit-one-time-user-authorization-is-required",
            "install-sign-delivery-host-and-arm64-remain-independent-negative-boundaries",
            "actual_canonical_read_or_written = $false",
            "[IO.FileMode]::CreateNew",
            "$stream.Flush($true)",
        ]),
        (dp1r_trust_admission, [
            "function Get-RimePimeDp1RTrustAdmission",
            "full_payload_static_closure = [bool]$ready",
            "nsis_non_os_compiler_input_closure = [bool]$ready",
            "generated_uninstaller_trusted_for_unsigned_disabled_static_scope = [bool]$ready",
            "historical_build_and_postbuild_non_claims_preserved = $true",
            "active_same_sid_physical_replacement_prevented = $false",
            "full_nsis_toolchain_input_closure = $false",
            "generated_uninstaller_signature_trusted = $false",
            "delivery_admitted = $false",
            "dp1_complete = $false",
            "Export-ModuleMember -Function 'Get-RimePimeDp1RTrustAdmission'",
        ]),
        (dp1r_trust_admission_test, [
            "yime-rime-pime-dp1r-trust-admission-test-v1",
            "complete-converged-evidence-is-admitted-in-static-scope",
            "membership-event-is-rejected",
            "ps7-uninstaller-mismatch-is-rejected",
            "script-property-is-not-executed",
            "actual_installer_or_uninstaller_executed=$false",
            "installed_yimecore_local12_touched=$false",
            "full_nsis_toolchain_input_closure=$false",
            "delivery_admitted=$false;dp1_complete=$false",
        ]),
        (dp1r_actual_review, [
            "yime-rime-pime-dp1r-actual-trust-review-v1",
            "actual DP1-R static trust review completed without executing installer or uninstaller",
            "dynamic_compiler_directives_absent=$true",
            "environment_macro_reads_absent=$true",
            "wildcard_payload_reads_absent=$true",
            "historical_build_and_postbuild_non_claims_preserved=$true",
            "active_same_sid_physical_replacement_prevented=$false",
            "full_nsis_toolchain_input_closure=$false",
            "generated_uninstaller_signature_trusted=$false",
            "installed_or_registered_host_verified=$false;dp1_complete=$false",
        ]),
        (dp1s_archive_runner, [
            "yime-rime-pime-dp1s-off-repository-archive-result-v1",
            "Yime Rime-PIME Evidence Archives\\DP1-S",
            "Assert-OutsideWorktrees $archiveBase $worktrees",
            "New-ArchiveSourceProjection",
            "Read-RimePimePackageBuildReceiptV2",
            "source_temporarily_unavailable_during_reverification=$true",
            "strict_receipt_read_ps5_without_source=$true",
            "strict_receipt_read_ps7_without_source=$true",
            "child_processes_have_packaged_codex_ancestor=$true",
            "explorer_launched_independent_reopen_verified=$false",
            "directory_metadata_durability_verified=$false;hardware_power_loss_verified=$false",
            "active_hostile_same_sid_physical_replacement_prevented=$false",
            "actual_canonical_migration_admitted=$false;actual_canonical_migrated=$false",
            "installed_yimecore_local12_touched=$false;production_user_data_read_or_written=$false",
        ]),
        (dp1s_archive_test, [
            "yime-rime-pime-dp1s-off-repository-archive-test-v1",
            "actual-off-repository-archive-and-verifications-reopen",
            "candidate-archive-canonical-receipt-path-matches-real-build",
            "verification-files-are-create-new-and-never-overwritten",
            "directory_metadata_durability_verified=$false;hardware_power_loss_verified=$false",
            "actual_canonical_migration_admitted=$false",
        ]),
        (dp1t_actual_adapter, [
            "yime-rime-pime-actual-canonical-adapter-result-v1",
            "one-time-actual-canonical-artifact-migration",
            "actual-canonical-artifacts-only",
            "Publish-RimePimeInstallerReceiptTransactionActual",
            "Resume-RimePimeInstallerReceiptTransactionActual",
            "MoveFileEx($temp,$Destination,8)",
            "if($Mode -ne 'Plan')",
            "actual_canonical_migration_admitted=[bool]($Mode -ne 'Plan')",
            "installer_or_uninstaller_executed=$false",
            "installed_yimecore_local12_touched=$false",
            "hardware_power_loss_recovery_verified=$false",
            "directory_metadata_durability_verified=$false",
            "hostile_same_sid_replacement_prevented=$false",
        ]),
        (dp1t_actual_adapter_test, [
            "yime-rime-pime-actual-canonical-adapter-test-v1",
            "dp1n-public-api-remains-exact-and-fixture-only",
            "authorization-binds-exact-user-scope-and-all-identities",
            "archive-objects-are-hash-checked-and-copied-no-replace",
            "plan-mode-is-read-only-for-canonical-artifacts",
            "hardware_power_loss_recovery_verified=$false",
        ]),
        (dp1u_gate, [
            "yime-rime-pime-dp1u-maintenance-runtime-evidence-v1",
            "Test-RimePimeDp1UMaintenanceRuntimeGate",
            "actual_registration_converged_x86",
            "actual_rollback_persistent_journal_replayed",
            "actual_removal_concurrent_replacement_excluded",
            "actual_runtime_non_elevated",
            "installed_yimecore_local12_touched",
            "hardware_power_loss_verified",
            "directory_metadata_durability_verified",
            "Export-ModuleMember -Function Test-RimePimeDp1UMaintenanceRuntimeGate",
        ]),
        (dp1u_gate_test, [
            "yime-rime-pime-dp1u-maintenance-runtime-gate-test-v1",
            "complete-actual-evidence-admits-all-four-gates",
            "current-no-execution-evidence-keeps-four-acceptance-gates-closed",
            "every-registration-observation-is-required",
            "every-rollback-observation-is-required",
            "every-removal-observation-is-required",
            "every-runtime-observation-is-required",
            "physical-nonclaims-must-remain-false",
            "missing-fields-return-rejection-instead-of-throwing",
            "null-scalars-arrays-and-dictionaries-return-rejection",
            "all-boolean-fields-reject-nonboolean-values",
        ]),
        (dp1u_current_review, [
            "yime-rime-pime-dp1u-current-readiness-result-v1",
            "DP1-U current readiness must pass source contracts and keep unexecuted acceptance closed.",
            "actual_registration_probe_executed=$false",
            "actual_rollback_executed=$false",
            "actual_uninstaller_executed=$false",
            "actual_runtime_executed=$false",
            "installed_yimecore_local12_touched=$false",
        ]),
        (dp1u_preflight, [
            "yime-rime-pime-dp1u-isolated-preflight-result-v1",
            "Test-RimePimeDp1UIsolatedPreflight",
            "Independent approval digest missing or mismatched",
            "MYCOMPUTER daily-use local.12 target prohibited",
            "execution_authorized=$false",
            "Export-ModuleMember -Function Test-RimePimeDp1UIsolatedPreflight",
        ]),
        (dp1u_preflight_schema, [
            "DP1-U supplied isolated authorization and preflight contract (no execution capability)",
            "yime-rime-pime-dp1u-isolated-preflight-evidence-v1",
            "unpackaged-explorer-powershell",
            "out-of-process-StdRegProv",
            "isolated-mainstream-windows-x64",
        ]),
        (dp1u_preflight_fixture, [
            "fixture-only:NOT-A-REAL-APPROVAL",
            "DP1-FIXTURE-PC",
            "production_rime_pime_allowed\": false",
            "yimecore_local12_allowed\": false",
        ]),
        (dp1u_preflight_test, [
            "yime-rime-pime-dp1u-isolated-preflight-test-v1",
            "synthetic-positive-never-authorizes-execution-or-installed-gates",
            "mycomputer-rejected-even-with-resealed-approval",
            "same-sid-chain-and-explicit-hku-required",
            "source-has-no-process-registry-or-maintenance-execution-commands",
            "actual_installer_or_uninstaller_executed=$false",
        ]),
    ):
        missing = [anchor for anchor in anchors if anchor not in body]
        if missing:
            fail("dual-product transaction source anchor changed: " + missing[0])
    builder_import_order = tuple(staged_builder.index(anchor) for anchor in (
        "Import-Module -Name $nsisToolchainModule -Force",
        "Import-Module -Name $stagingModule -Force",
        "Import-Module -Name $nsisStageModule -Force",
        "Import-Module -Name $stagedBuildModule -Force",
    ))
    if builder_import_order != tuple(sorted(builder_import_order)):
        fail("Rime/PIME builder module import safety order changed")
    isolated_candidate_order = tuple(isolated_candidate_runner.index(anchor) for anchor in (
        "'build-current-source'",
        "'seal-package-plan'",
        "'build-disabled-installer'",
        "'write-build-manifest'",
        "'static-installer-manifest-check'",
        "'static-postbuild-extraction'",
        "'finalize-canonical-receipt-v2'",
        "$retainedV2 = Publish-RimePimePackageReceiptV2Supersession",
        "$strictV2 = Read-RimePimePackageBuildReceiptV2",
    ))
    if isolated_candidate_order != tuple(sorted(isolated_candidate_order)):
        fail("Rime/PIME isolated current-source candidate sequence changed")
    for label, pattern in (
        ("clone", r"(?m)^[ \t]*'clone', '--local', '--no-hardlinks', '--no-checkout', '--no-tags', '--', \$root, \$clone[ \t]*$"),
        ("autocrlf", r"(?m)^[ \t]*'-C', \$clone, 'config', '--local', 'core\.autocrlf', 'false'[ \t]*$"),
        ("checkout", r"(?m)^[ \t]*'-C', \$clone, 'checkout', '--detach', \$head[ \t]*$"),
    ):
        if len(re.findall(pattern, isolated_candidate_runner)) != 1:
            fail(f"Rime/PIME isolated current-source candidate {label} argument vector changed")
    if any(name in isolated_candidate_runner for name in (
            "-AllowLocalMachine", "sign-release.ps1", "verify-release-signatures.ps1",
            "Install-PIME-Test.cmd", "Uninstall-PIME-Test.cmd",
            "rime-pime-installer-receipt-transaction.ps1")):
        fail("Rime/PIME isolated current-source candidate runner gained a prohibited product entrypoint")
    isolated_candidate_runner_source_contract_wired = True
    if (candidate_evidence_archive_module.count("Export-ModuleMember") != 1 or
            any(candidate_evidence_archive_module.count("'" + name + "'") != 1 for name in (
                "Publish-RimePimeCandidateEvidenceArchive",
                "Resume-RimePimeCandidateEvidenceArchive",
                "Read-RimePimeCandidateEvidenceArchive")) or
            "*-RimePime" in candidate_evidence_archive_module):
        fail("Rime/PIME candidate evidence archive export surface changed")
    for prohibited in (
            "Install-PIME-Test.cmd", "Uninstall-PIME-Test.cmd", "Reinstall-PIME-Test.cmd",
            "build-rime-pime-installer.ps1",
            "Publish-RimePimeInstallerReceiptTransaction", "Registry::", "Start-Process"):
        if prohibited in candidate_evidence_archive + candidate_evidence_archive_module:
            fail("Rime/PIME candidate evidence archive gained a prohibited product action")
    if candidate_evidence_archive.count(
            "'tools/dual-product/run-rime-pime-isolated-candidate.ps1'") != 1:
        fail("Rime/PIME candidate evidence archive runner identity binding changed")
    if candidate_evidence_archive.count(
            "$object.Data.Sha256 -cne [string]$row.sha256") != 2:
        fail("Rime/PIME candidate evidence archive object path-to-bytes binding changed")
    for promoted in (
            "actual_archive_root_published", "actual_evidence_archived_outside_repository_tmp",
            "actual_canonical_migration_admitted", "actual_canonical_migrated",
            "hardware_power_loss_verified", "directory_metadata_durability_verified",
            "active_hostile_same_sid_physical_replacement_prevented"):
        if re.search(r"\b" + re.escape(promoted) + r"\s*=\s*\$true\b", candidate_evidence_archive):
            fail("Rime/PIME candidate evidence archive promoted an unverified boundary")
    candidate_evidence_archive_source_contract_wired = True
    if actual_migration_review.count("Export-ModuleMember") != 1:
        fail("Rime/PIME actual migration review export surface changed")
    for forbidden in (
            "Get-Content", "Set-Content", "Test-Path", "New-Item", "Remove-Item",
            "Copy-Item", "Move-Item", "Start-Process", "Stop-Process", "Invoke-Expression",
            "Import-Module", "Read-RimePimePackageBuildReceiptV2", "[IO.File",
            "[Microsoft.Win32.Registry", "[Diagnostics.Process", "Registry::",
            "Publish-RimePimeInstallerReceiptTransaction",
            "Resume-RimePimeInstallerReceiptTransaction"):
        if forbidden in actual_migration_review:
            fail("Rime/PIME actual migration review gained an action surface")
    for promoted in (
            "actual_canonical_migration_admitted", "actual_canonical_migrated",
            "installer_or_uninstaller_execution_admitted", "signing_admitted",
            "delivery_admitted", "installed_or_registered_host_action_admitted",
            "arm64_native_claim_admitted", "installed_yimecore_action_admitted",
            "dp1_or_release_completion_admitted"):
        if re.search(r"\b" + re.escape(promoted) + r"\s*=\s*\$true\b", actual_migration_review):
            fail("Rime/PIME actual migration review promoted an execution boundary")
    actual_migration_review_source_contract_wired = True
    if dp1r_trust_admission.count("Export-ModuleMember") != 1:
        fail("Rime/PIME DP1-R trust admission export surface changed")
    for forbidden in (
            "Start-Process", "Invoke-Expression", "Invoke-Command", "Remove-Item", "Move-Item",
            "Copy-Item", "Set-Content", "Add-Content", "Registry::", "HKLM", "HKCU",
            "Get-Process", "Stop-Process", "makensis.exe", "7z.exe"):
        if forbidden in dp1r_trust_admission:
            fail("Rime/PIME DP1-R pure trust admission gained an action surface")
    for forbidden in ("Install-PIME-Test.cmd", "Uninstall-PIME-Test.cmd", "Reinstall-PIME-Test.cmd",
                      "Start-Process", "Stop-Process", "Registry::"):
        if forbidden in dp1r_actual_review:
            fail("Rime/PIME DP1-R actual review gained a prohibited product action")
    dp1r_trust_admission_source_contract_wired = True
    if "[IO.File]::Delete($ResultPath)" in dp1s_archive_runner:
        fail("Rime/PIME DP1-S archived verification gained an overwrite path")
    if "YIME-package-build-receipt-v2.json" in candidate_evidence_archive:
        fail("Rime/PIME candidate archive reverted to its fixture-only receipt path")
    dp1s_off_repository_archive_source_contract_wired = True
    if "Start-Process" in dp1t_actual_adapter or "Registry::" in dp1t_actual_adapter:
        fail("Rime/PIME DP1-T actual adapter gained a prohibited product action")
    dp1t_actual_adapter_source_contract_wired = True
    for forbidden in ("Start-Process", "Stop-Process", "Remove-Item", "Registry::", "HKLM", "HKCU", "msiexec"):
        if forbidden in dp1u_gate:
            fail("Rime/PIME DP1-U pure gate gained a prohibited action surface")
    dp1u_maintenance_runtime_gate_source_contract_wired = True
    for forbidden in ("Start-Process", "Stop-Process", "Remove-Item", "Registry::", "HKLM", "HKCU", "msiexec", "Invoke-Expression"):
        if forbidden in dp1u_preflight:
            fail("Rime/PIME DP1-U supplied-evidence preflight gained an execution surface")
    dp1u_isolated_preflight_source_contract_wired = True
    if core.index("New-Item -ItemType Directory -Path $stagingRoot") >= core.index("$preinstall = Invoke-UninstallCore"):
        fail("YimeCore active mutation moved before complete package staging")
    ci_postbuild_step = one(
        r"(?ms)^      - name: Test post-build archive extraction contract\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI synthetic post-build extraction step",
    ).group()
    synthetic_postbuild_ci_is_host_tool_independent = (
        ci_postbuild_step.count("test-rime-pime-postbuild-extraction.ps1") == 2 and
        "PowerShell 5.1 postbuild-extraction test failed with exit code $LASTEXITCODE" in ci_postbuild_step and
        all(name not in ci_postbuild_step for name in (
            "SevenZipPath", "ExpectedSevenZipDigest", "NsisRoot", "ExpectedMakensisDigest",
            "run-rime-pime-postbuild-extraction.ps1",
        ))
    )
    ci_toolchain_step = one(
        r"(?ms)^      - name: Test NSIS compiler input closure contract\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI synthetic NSIS compiler input closure step",
    ).group()
    ci_membership_monitor_step = one(
        r"(?ms)^      - name: Test DP1-J isolated NSIS membership monitor\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-J isolated membership-monitor step",
    ).group()
    ci_compiler_interval_step = one(
        r"(?ms)^      - name: Test DP1-K NSIS compiler membership interval\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-K NSIS compiler-interval step",
    ).group()
    ci_receipt_v2_step = one(
        r"(?ms)^      - name: Test canonical package receipt v2 contract\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI synthetic canonical receipt v2 step",
    ).group()
    ci_no_downgrade_step = one(
        r"(?ms)^      - name: Test canonical receipt no-downgrade contract\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI synthetic receipt no-downgrade step",
    ).group()
    ci_receipt_store_step = one(
        r"(?ms)^      - name: Test retained receipt publication and crash recovery\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI retained receipt publication step",
    ).group()
    ci_installer_receipt_transaction_step = one(
        r"(?ms)^      - name: Test DP1-N isolated installer and receipt transaction\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-N isolated installer/receipt transaction step",
    ).group()
    ci_isolated_candidate_step = one(
        r"(?ms)^      - name: Test DP1-O isolated current-source candidate runner contract\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-O isolated current-source candidate runner contract step",
    ).group()
    ci_version_identity_step = one(
        r"(?ms)^      - name: Test DP1-P version identity admission contract\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-P version identity admission step",
    ).group()
    ci_candidate_evidence_archive_step = one(
        r"(?ms)^      - name: Test DP1-Q candidate evidence archive contract\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-Q candidate evidence archive step",
    ).group()
    ci_actual_migration_review_step = one(
        r"(?ms)^      - name: Test DP1-Q actual migration review contract\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-Q actual migration review step",
    ).group()
    ci_dp1r_trust_admission_step = one(
        r"(?ms)^      - name: Test DP1-R static trust admission contract\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-R static trust admission step",
    ).group()
    ci_dp1s_archive_step = one(
        r"(?ms)^      - name: Test DP1-S off-repository archive boundary\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-S off-repository archive step",
    ).group()
    ci_dp1t_actual_adapter_step = one(
        r"(?ms)^      - name: Test DP1-T actual canonical migration adapter contract\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-T actual canonical migration adapter step",
    ).group()
    ci_dp1u_gate_step = one(
        r"(?ms)^      - name: Test DP1-U maintenance and Runtime admission gate\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-U maintenance and Runtime gate step",
    ).group()
    ci_dp1u_preflight_step = one(
        r"(?ms)^      - name: Test DP1-U isolated target preflight contract\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-U isolated target preflight step",
    ).group()
    ci_supersession_step = one(
        r"(?ms)^      - name: Test DP1-J isolated receipt-v2 supersession protocol\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-J isolated receipt-v2 supersession step",
    ).group()
    ci_replay_model_step = one(
        r"(?ms)^      - name: Test DP1-I pure transaction replay model\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-I pure transaction replay-model step",
    ).group()
    ci_fixture_journal_step = one(
        r"(?ms)^      - name: Test DP1-I isolated fixture transaction journal\s*$.*?(?=^      - name: |\Z)",
        ci,
        "CI DP1-I isolated fixture-journal step",
    ).group()
    prohibited_dp1h_ci_commands = (
        "finalize-rime-pime-package-receipt-v2.ps1",
        "build-rime-pime-installer.ps1",
        "run-rime-pime-postbuild-extraction.ps1",
        "sign-release.ps1",
        "Install-PIME-Test.cmd",
        "Uninstall-PIME-Test.cmd",
    )
    synthetic_dp1h_ci_contracts_present = (
        ci_toolchain_step.count("test-rime-pime-nsis-toolchain-closure.ps1") == 2 and
        ci_toolchain_step.count("-SyntheticOnly") == 2 and
        "PowerShell 5.1 NSIS toolchain-closure test failed with exit code $LASTEXITCODE" in ci_toolchain_step and
        ci_receipt_v2_step.count("test-rime-pime-package-receipt-v2.ps1") == 2 and
        "PowerShell 5.1 package-receipt-v2 test failed with exit code $LASTEXITCODE" in ci_receipt_v2_step and
        ci_no_downgrade_step.count("test-rime-pime-receipt-no-downgrade.ps1") == 2 and
        "PowerShell 5.1 receipt no-downgrade test failed with exit code $LASTEXITCODE" in ci_no_downgrade_step and
        all(name not in (ci_toolchain_step + ci_receipt_v2_step + ci_no_downgrade_step)
            for name in prohibited_dp1h_ci_commands)
    )
    prohibited_dp1i_ci_patterns = (
        r"(?i)installer\.nsi",
        r"(?i)build-rime-pime-installer\.ps1",
        r"(?i)finalize-rime-pime-package-receipt-v2\.ps1",
        r"(?i)sign-release\.ps1",
        r"(?i)run-rime-pime-postbuild-extraction\.ps1",
        r"(?i)\b(?:Install|Uninstall|Reinstall|Maintain)-[^\\\s]+\.cmd\b",
        r"(?i)\b(?:Start|Get|Stop)-Process\b",
        r"(?i)\bInvoke-(?:Command|Expression)\b",
        r"(?i)\bGet-CimInstance\b|\bStdRegProv\b|\breg\.exe\b",
        r"(?i)Registry::|\bHKLM:|\bHKCU:|\bHKU:|\bHKEY_USERS\b",
        r"(?i)\bProgram Files\b|\bAPPDATA\b|\bLOCALAPPDATA\b",
        r"(?i)\bRemove-Item\b[^\r\n]*\b-Recurse\b|\bRMDir\b[^\r\n]*/[rs]",
        r"(?i)\b(?:makensis|msiexec|cmd)\.exe\b",
        r"(?i)\\(?:PIMELauncher|server|PIMETextService)\.exe\b",
    )
    dp1i_ci_steps = ci_replay_model_step + ci_fixture_journal_step
    synthetic_dp1i_ci_contracts_present = (
        ci_replay_model_step.count("test-rime-pime-transaction-replay-model.ps1") == 2 and
        "-OutputRoot" not in ci_replay_model_step and
        "PowerShell 5.1 DP1-I replay-model test failed with exit code $LASTEXITCODE" in
        ci_replay_model_step and
        ci_fixture_journal_step.count("test-rime-pime-fixture-transaction-journal.ps1") == 2 and
        ci_fixture_journal_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-i-journal-ci-ps5-$runId" in ci_fixture_journal_step and
        ".tmp\\dual-product\\dp1-i-journal-ci-ps7-$runId" in ci_fixture_journal_step and
        "PowerShell 5.1 DP1-I fixture-journal test failed with exit code $LASTEXITCODE" in
        ci_fixture_journal_step and
        all(re.search(pattern, dp1i_ci_steps) is None for pattern in prohibited_dp1i_ci_patterns)
    )
    dp1j_ci_steps = ci_membership_monitor_step + ci_supersession_step
    synthetic_dp1j_ci_contracts_present = (
        ci_membership_monitor_step.count("test-rime-pime-nsis-membership-monitor-v1.ps1") == 2 and
        ci_membership_monitor_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-j-membership-test-ci-ps5-$runId" in ci_membership_monitor_step and
        ".tmp\\dual-product\\dp1-j-membership-test-ci-ps7-$runId" in ci_membership_monitor_step and
        "PowerShell 5.1 DP1-J membership-monitor test failed with exit code $LASTEXITCODE" in
        ci_membership_monitor_step and
        ci_supersession_step.count("test-rime-pime-receipt-v2-supersession.ps1") == 2 and
        ci_supersession_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-j-receipt-v2-supersession-ci-ps5-$runId" in ci_supersession_step and
        ".tmp\\dual-product\\dp1-j-receipt-v2-supersession-ci-ps7-$runId" in ci_supersession_step and
        "PowerShell 5.1 DP1-J receipt-v2 supersession test failed with exit code $LASTEXITCODE" in
        ci_supersession_step and
        all(re.search(pattern, dp1j_ci_steps) is None for pattern in prohibited_dp1i_ci_patterns)
    )
    compiler_interval_ci_ps5_ps7_present = (
        ci_compiler_interval_step.count("test-rime-pime-nsis-compiler-interval.ps1") == 2 and
        ci_compiler_interval_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-nsis-interval-test-ci-ps5-$runId" in ci_compiler_interval_step and
        ".tmp\\dual-product\\dp1-nsis-interval-test-ci-ps7-$runId" in ci_compiler_interval_step and
        "PowerShell 5.1 DP1-K compiler-interval test failed with exit code $LASTEXITCODE" in
        ci_compiler_interval_step and
        ci.index("      - name: Install NSIS in non-secret packaging job") <
        ci.index("      - name: Test DP1-K NSIS compiler membership interval") <
        ci.index("      - name: Build the installer") and
        all(name not in ci_compiler_interval_step for name in (
            "build-rime-pime-installer.ps1", "Install-PIME-Test.cmd", "Uninstall-PIME-Test.cmd",
        ))
    )
    retained_receipt_ci_ps5_ps7_present = (
        ci_receipt_store_step.count("test-rime-pime-receipt-v2-store.ps1") == 2 and
        ci_receipt_store_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-package-receipt-v2-test-store-ps5-$runId" in ci_receipt_store_step and
        ".tmp\\dual-product\\dp1-package-receipt-v2-test-store-ps7-$runId" in ci_receipt_store_step and
        "PS5 retained receipt publication test failed: $LASTEXITCODE" in ci_receipt_store_step
    )
    installer_receipt_ps5_ci_invocation = (
        "          & $ps5 -NoProfile -ExecutionPolicy Bypass -File "
        ".\\tools\\dual-product\\test-rime-pime-installer-receipt-transaction.ps1 `\n"
        "            -OutputRoot (Join-Path $pwd \".tmp\\dual-product\\"
        "dp1-package-receipt-v2-test-dp1n-ci-ps5-$runId\")\n"
    )
    installer_receipt_ps7_ci_invocation = (
        "          .\\tools\\dual-product\\test-rime-pime-installer-receipt-transaction.ps1 `\n"
        "            -OutputRoot (Join-Path $pwd \".tmp\\dual-product\\"
        "dp1-package-receipt-v2-test-dp1n-ci-ps7-$runId\")\n"
    )
    installer_receipt_transaction_ci_ps5_ps7_present = (
        ci_installer_receipt_transaction_step.count(
            "test-rime-pime-installer-receipt-transaction.ps1"
        ) == 2 and
        ci_installer_receipt_transaction_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-package-receipt-v2-test-dp1n-ci-ps5-$runId" in
        ci_installer_receipt_transaction_step and
        ".tmp\\dual-product\\dp1-package-receipt-v2-test-dp1n-ci-ps7-$runId" in
        ci_installer_receipt_transaction_step and
        "$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'" in
        ci_installer_receipt_transaction_step and
        "& $ps5 -NoProfile -ExecutionPolicy Bypass -File" in
        ci_installer_receipt_transaction_step and
        ci_installer_receipt_transaction_step.count(installer_receipt_ps5_ci_invocation) == 1 and
        ci_installer_receipt_transaction_step.count(installer_receipt_ps7_ci_invocation) == 1 and
        all(parameter.casefold() not in ci_installer_receipt_transaction_step.casefold()
            for parameter in ("-CheckPattern", "-WorkerCasePath", "-Phase")) and
        "PowerShell 5.1 DP1-N installer/receipt transaction test failed with exit code $LASTEXITCODE" in
        ci_installer_receipt_transaction_step and
        all(re.search(pattern, ci_installer_receipt_transaction_step) is None
            for pattern in prohibited_dp1i_ci_patterns)
    )
    isolated_candidate_runner_contract_ci_ps5_ps7_present = (
        ci_isolated_candidate_step.count("test-rime-pime-isolated-candidate.ps1") == 2 and
        ci_isolated_candidate_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-o-runner-contract-ci-ps5-$runId" in ci_isolated_candidate_step and
        ".tmp\\dual-product\\dp1-o-runner-contract-ci-ps7-$runId" in ci_isolated_candidate_step and
        "$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'" in
        ci_isolated_candidate_step and
        "PowerShell 5.1 DP1-O isolated-candidate runner contract failed with exit code $LASTEXITCODE" in
        ci_isolated_candidate_step and
        "run-rime-pime-isolated-candidate.ps1" not in ci_isolated_candidate_step and
        all(name not in ci_isolated_candidate_step for name in (
            "build-rime-pime-installer.ps1", "finalize-rime-pime-package-receipt-v2.ps1",
            "sign-release.ps1", "Install-PIME-Test.cmd", "Uninstall-PIME-Test.cmd",
        ))
    )
    version_identity_admission_ci_ps5_ps7_present = (
        ci_version_identity_step.count("test-rime-pime-version-identity-admission.ps1") == 2 and
        ci_version_identity_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-version-identity-test-ci-ps5-$runId" in ci_version_identity_step and
        ".tmp\\dual-product\\dp1-version-identity-test-ci-ps7-$runId" in ci_version_identity_step and
        "$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'" in
        ci_version_identity_step and
        "PowerShell 5.1 DP1-P version-identity admission test failed with exit code $LASTEXITCODE" in
        ci_version_identity_step and
        all(re.search(pattern, ci_version_identity_step) is None
            for pattern in prohibited_dp1i_ci_patterns)
    )
    candidate_evidence_archive_ci_ps5_ps7_present = (
        ci_candidate_evidence_archive_step.count(
            "test-rime-pime-candidate-evidence-archive.ps1"
        ) == 2 and
        ci_candidate_evidence_archive_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-candidate-evidence-archive-test-ci-ps5-$runId" in
        ci_candidate_evidence_archive_step and
        ".tmp\\dual-product\\dp1-candidate-evidence-archive-test-ci-ps7-$runId" in
        ci_candidate_evidence_archive_step and
        "$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'" in
        ci_candidate_evidence_archive_step and
        "PowerShell 5.1 DP1-Q candidate-evidence archive test failed with exit code $LASTEXITCODE" in
        ci_candidate_evidence_archive_step and
        all(parameter.casefold() not in ci_candidate_evidence_archive_step.casefold()
            for parameter in ("-CheckPattern", "-WorkerCasePath", "-Phase")) and
        all(re.search(pattern, ci_candidate_evidence_archive_step) is None
            for pattern in prohibited_dp1i_ci_patterns)
    )
    actual_migration_review_ci_ps5_ps7_present = (
        ci_actual_migration_review_step.count(
            "test-rime-pime-actual-migration-review.ps1"
        ) == 2 and
        ci_actual_migration_review_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-actual-migration-review-test-ci-ps5-$runId" in
        ci_actual_migration_review_step and
        ".tmp\\dual-product\\dp1-actual-migration-review-test-ci-ps7-$runId" in
        ci_actual_migration_review_step and
        "$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'" in
        ci_actual_migration_review_step and
        "PowerShell 5.1 DP1-Q actual-migration review test failed with exit code $LASTEXITCODE" in
        ci_actual_migration_review_step and
        all(re.search(pattern, ci_actual_migration_review_step) is None
            for pattern in prohibited_dp1i_ci_patterns)
    )
    dp1r_trust_admission_ci_ps5_ps7_present = (
        ci_dp1r_trust_admission_step.count(
            "test-rime-pime-dp1r-trust-admission.ps1"
        ) == 2 and
        ci_dp1r_trust_admission_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-r-trust-admission-test-ci-ps5-$runId" in
        ci_dp1r_trust_admission_step and
        ".tmp\\dual-product\\dp1-r-trust-admission-test-ci-ps7-$runId" in
        ci_dp1r_trust_admission_step and
        "$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'" in
        ci_dp1r_trust_admission_step and
        "PowerShell 5.1 DP1-R trust-admission test failed with exit code $LASTEXITCODE" in
        ci_dp1r_trust_admission_step and
        all(re.search(pattern, ci_dp1r_trust_admission_step) is None
            for pattern in prohibited_dp1i_ci_patterns)
    )
    dp1s_off_repository_archive_ci_ps5_ps7_present = (
        ci_dp1s_archive_step.count(
            "test-rime-pime-dp1s-off-repository-archive.ps1"
        ) == 2 and
        ci_dp1s_archive_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-s-archive-test-ci-ps5-$runId" in
        ci_dp1s_archive_step and
        ".tmp\\dual-product\\dp1-s-archive-test-ci-ps7-$runId" in
        ci_dp1s_archive_step and
        "$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'" in
        ci_dp1s_archive_step and
        "PowerShell 5.1 DP1-S archive-boundary test failed with exit code $LASTEXITCODE" in
        ci_dp1s_archive_step and
        all(re.search(pattern, ci_dp1s_archive_step) is None
            for pattern in prohibited_dp1i_ci_patterns)
    )
    dp1t_actual_adapter_ci_ps5_ps7_present = (
        ci_dp1t_actual_adapter_step.count(
            "test-rime-pime-actual-canonical-migration.ps1"
        ) == 2 and
        ci_dp1t_actual_adapter_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-t-actual-adapter-test-ci-ps5-$runId" in
        ci_dp1t_actual_adapter_step and
        ".tmp\\dual-product\\dp1-t-actual-adapter-test-ci-ps7-$runId" in
        ci_dp1t_actual_adapter_step and
        "$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'" in
        ci_dp1t_actual_adapter_step and
        "PowerShell 5.1 DP1-T actual-adapter test failed with exit code $LASTEXITCODE" in
        ci_dp1t_actual_adapter_step and
        all(re.search(pattern, ci_dp1t_actual_adapter_step) is None
            for pattern in prohibited_dp1i_ci_patterns)
    )
    dp1u_maintenance_runtime_gate_ci_ps5_ps7_present = (
        ci_dp1u_gate_step.count("test-rime-pime-dp1u-maintenance-runtime-gate.ps1") == 2 and
        ci_dp1u_gate_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-u-gate-test-ci-ps5-$runId" in ci_dp1u_gate_step and
        ".tmp\\dual-product\\dp1-u-gate-test-ci-ps7-$runId" in ci_dp1u_gate_step and
        "$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'" in ci_dp1u_gate_step and
        "PowerShell 5.1 DP1-U admission-gate test failed with exit code $LASTEXITCODE" in ci_dp1u_gate_step and
        all(re.search(pattern, ci_dp1u_gate_step) is None for pattern in prohibited_dp1i_ci_patterns)
    )
    dp1u_isolated_preflight_ci_ps5_ps7_present = (
        ci_dp1u_preflight_step.count("test-rime-pime-dp1u-isolated-preflight.ps1") == 2 and
        ci_dp1u_preflight_step.count("-OutputRoot") == 2 and
        ".tmp\\dual-product\\dp1-u-preflight-test-ci-ps5-$runId" in ci_dp1u_preflight_step and
        ".tmp\\dual-product\\dp1-u-preflight-test-ci-ps7-$runId" in ci_dp1u_preflight_step and
        "$env:SystemRoot 'System32\\WindowsPowerShell\\v1.0\\powershell.exe'" in ci_dp1u_preflight_step and
        "PowerShell 5.1 DP1-U isolated-preflight test failed with exit code $LASTEXITCODE" in ci_dp1u_preflight_step and
        all(re.search(pattern, ci_dp1u_preflight_step) is None for pattern in prohibited_dp1i_ci_patterns)
    )
    rime_sid_chain_anchors = ("RequestExecutionLevel user" in nsis and
                              "Function bootstrapTargetUser" in nsis and
                              "Function un.bootstrapTargetUser" in nsis and
                              "CaptureInitiator" in nsis and "ValidateWorker" in nsis and
                              "/InitiatingSid=" in nsis and "/TargetUserSid=" in nsis and
                              "/EnvelopePath=" in nsis and "/CorrelationId=" in nsis and
                              nsis_active_call(nsis, "acceptTargetUserWorker") and
                              nsis_active_call(nsis, "un.acceptTargetUserWorker") and
                              "InstallLayoutOrTipForUser" in nsis and
                              '-TargetUserSid "$TargetUserSid"' in nsis)
    rime_target_user_cleanup_anchors = (
        "Assert-PIMERegistryTargetUserSid" in pime_cleanup and
        "Get-YimePimeTargetUserRegistryPath -TargetUserSid $TargetUserSid" in pime_cleanup and
        "Remove-PIMEUserLanguageProfileValues -TargetUserSid $TargetUserSid" in pime_cleanup and
        'Get-ChildItem -LiteralPath "Registry::HKEY_USERS"' not in pime_cleanup and
        "HKCU:" not in pime_cleanup and
        "function Remove-YimePimeTargetUserProfileValues" in pime_ownership and
        "Get-YimePimeTargetUserRegistryPath -TargetUserSid $sid" in pime_ownership and
        "HKEY_USERS" not in one(
            r"(?ms)^HRESULT\s+ImeModule::unregisterServer\([^)]*\)\s*\{.*?(?=^[A-Za-z_][^\r\n]*\s+ImeModule::|\Z)",
            native_ime_module,
            "native unregister body",
        ).group()
    )
    full_transaction_engine_wired_into_installer = (
        "rime-pime-transaction-engine.ps1" in nsis or
        "Invoke-YimePimeSyntheticUpgradeTransaction" in nsis
    )
    registration_readback_anchors = (
        nsis_active_call(nsis, "verifyRegistrationOwnership") and
        "registrationExitCode" in nsis and
        "function Get-YimePimeExpectedRegistrationRecords" in pime_ownership and
        "function Get-YimePimeRegistrationSnapshot" in pime_ownership and
        "function Assert-YimePimeRegistrationSnapshot" in pime_ownership and
        "'ValidateRegistration'" in pime_maintenance_entry
    )
    legacy_function = nsis_function(nsis, "uninstallOldVersion")
    legacy_refusal_anchors = all(anchor in legacy_function for anchor in (
        'ReadRegStr $R2 HKLM "${LEGACY_PRODUCT_UNINST_KEY}" "UninstallString"',
        'ReadRegStr $R3 HKLM "${LEGACY_PRODUCT_INSTALL_KEY}" ""',
        "A historical PIME installation needs an explicit migration workflow. It was not changed.",
        "A partial historical PIME registration was found. It was not changed.",
    ))
    legacy_mutation = re.search(
        r"(?mi)^\s*(?:DeleteReg(?:Key|Value)|WriteReg\w+|RMDir|Delete)\b[^\r\n]*"
        r"(?:\$\{LEGACY_PRODUCT_|Software\\PIME|Uninstall\\PIME)",
        nsis,
    )
    legacy_execution = re.search(
        r"(?mi)^\s*(?:Exec|ExecWait|nsExec::Exec\w*)\b[^\r\n]*\$R[23]\b",
        legacy_function,
    )
    unowned_legacy_deletion_absent = legacy_mutation is None and legacy_execution is None
    legacy_migration_wired = not legacy_refusal_anchors or not unowned_legacy_deletion_absent
    install_init = nsis_function(nsis, ".onInit")
    main_section = one(
        r'(?ms)^Section \$\(SECTION_MAIN\) SecMain\s*$.*?^SectionEnd\s*$',
        nsis,
        "Rime/PIME main install section",
    ).group()
    upgrade_mutation = re.search(
        r"(?mi)^\s*(?:Call\s+stopRunningBackend|WriteReg\w+|DeleteReg(?:Key|Value)|"
        r"RMDir|Delete|Rename|File|Exec|ExecWait|nsExec::Exec\w*)\b|/u\s+/s",
        legacy_function,
    )
    current_upgrade_fail_closed = (
        "In-place upgrade is not enabled" in legacy_function and
        "existing installation was not stopped, unregistered, overwritten or deleted" in legacy_function and
        upgrade_mutation is None
    )
    fresh_install_final_vacancy = (
        not nsis_active_call(install_init, "uninstallOldVersion") and
        not nsis_active_call(install_init, "stopRunningBackend") and
        nsis_active_call(main_section, "uninstallOldVersion") and
        "Call verifyStagedRegistrationAbsent" in legacy_function and
        main_section.count("Call verifyStagedRegistrationAbsent") >= 1 and
        main_section.rindex("Call verifyStagedRegistrationAbsent") <
        main_section.index("SetOverwrite on")
    )
    synthetic_fault_matrix_anchors = ("write-prepared-journal" in fault_engine and
                                      "write-activation-commit" in fault_engine and
                                      "purge-quarantine" in fault_engine and
                                      "recovery-required" in fault_engine)
    transaction_replay_model_source_anchors_present = all(anchor in fault_engine for anchor in (
        "function Get-YimePimeTransactionStageCatalog",
        "function Get-YimePimeReplayDisposition",
        "function Resolve-YimePimeIdempotentTransition",
        "function Get-YimePimeManifestRemovalPlan",
        "yime-pime-replay-disposition-v1",
        "yime-pime-idempotent-transition-v1",
        "yime-pime-manifest-removal-plan-v1",
    )) and all(anchor in replay_model_test for anchor in (
        "generic-upgrade-catalog-preserves-the-existing-24-stage-contract",
        "replay-prepared-requires-rollback",
        "replay-committed-requires-cleanup",
        "replay-terminal-states-are-idempotent-noops",
        "actual_filesystem_registry_process_native_installer_or_product_operation_executed=$false",
    ))
    uninstall_stage_catalog_source_anchors_present = (
        "function Get-YimePimeTransactionStageCatalog" in fault_engine and
        "uninstall-catalog-has-journal-mutation-commit-and-cleanup-boundaries" in replay_model_test
    )
    logical_leaf_first_nonrecursive_removal_plan_present = (
        "function Get-YimePimeManifestRemovalPlan" in fault_engine and
        "recursive=$false" in fault_engine and
        "physical_deletion_executed=$false" in fault_engine and
        "manifest-removal-plan-is-leaf-first-and-reserves-two-final-files" in replay_model_test
    )
    fixture_transaction_journal_source_anchors_present = all(anchor in fixture_journal for anchor in (
        "Fixture-only durable transaction-journal helpers for DP1-I",
        "function Open-RimePimeFixtureJournalLock",
        "function Read-RimePimeFixtureJournal",
        "function Resume-RimePimeFixtureTransaction",
    )) and all(anchor in fixture_journal_module for anchor in (
        "defines helpers only",
        "Export-ModuleMember -Function @(",
        "'Resume-RimePimeFixtureTransaction'",
    ))
    fixture_transaction_journal_test_source_anchors_present = all(
        anchor in fixture_journal_test for anchor in (
            "yime-rime-pime-fixture-journal-test-result-v1",
            "fixture_only=$true",
            "installer_or_uninstaller_executed=$false",
            "registry_provider_used=$false",
            "product_process_accessed=$false",
            "production_user_data_accessed=$false",
            "recursive_delete_used=$false",
            "concurrent_replacement_excluded=$false",
            "real_crash_or_power_loss_claimed=$false",
            "cross_process_restart_executed=$false",
            "rollback_or_cleanup_adapter_executed=$false",
            "directory_metadata_durability_proven=$false",
        )
    )
    fixture_journal_hash_chain_source_anchors_present = all(anchor in fixture_journal for anchor in (
        "[IO.FileMode]::CreateNew",
        "Fixture journal hash chain is invalid",
        "previous_record_sha256",
    )) and "Integrity, closed-schema, chain-binding" in fixture_journal_test
    fixture_journal_sidecar_last_flush_protocol_present = all(anchor in fixture_journal for anchor in (
        "[IO.FileOptions]::WriteThrough",
    )) and fixture_journal.count("$stream.Flush($true)") >= 2 and \
        "Sidecar-last fault points" in fixture_journal_test
    fixture_journal_case_local_recovery_artifacts_bound = all(anchor in fixture_journal for anchor in (
        "function Assert-RimePimeFixturePreparedArtifactBindings",
        "Fixture operation ID is not bound to its transaction and stage",
    )) and "Prepared admission is bound to sealed artifacts in the same fixture case" in fixture_journal_test
    fixture_registry_snapshot_closed_typed_privacy_safe = all(anchor in fixture_journal for anchor in (
        "yime-rime-pime-fixture-registry-state-v1",
        "source='synthetic-json-only'",
        "contains_user_text=$false",
    )) and "Closed, typed, privacy-safe registry fixture state" in fixture_journal_test
    fixture_exact_removal_source_anchors_present = all(anchor in fixture_journal for anchor in (
        "function Invoke-RimePimeFixtureExactRemoval",
        "[IO.Directory]::Delete($path,$false)",
        "recursive_delete_used=$false",
    ))
    fixture_changed_or_foreign_content_preserved = (
        "changed_or_foreign_preserved" in fixture_journal and
        "preserved.changed_or_foreign_preserved -eq $true" in fixture_journal_test and
        "unexpected_filenames_disclosed=$false" in fixture_journal_test
    )
    nsis_membership_monitor_fixture_source_anchors_present = all(
        anchor in nsis_membership_monitor for anchor in (
            "fixture-only continuous directory-membership monitor",
            "ReadDirectoryChangesW",
            "FILE_FLAG_OVERLAPPED",
            "SettlePendingCancellation",
            "unique_completion_barrier_observed",
            "physical_membership_prevention_claimed = $false",
            "active_same_sid_transient_tree_membership_interference_excluded = $false",
            "nsis_non_os_compiler_input_closure = $false",
            "full_nsis_toolchain_input_closure = $false",
        )
    ) and all(anchor in nsis_membership_monitor_module for anchor in (
        "Importing it only defines functions",
        "'Open-RimePimeNsisMembershipMonitorV1'",
        "'Complete-RimePimeNsisMembershipMonitorV1'",
        "'Close-RimePimeNsisMembershipMonitorV1'",
    )) and all(anchor in nsis_membership_fixture_writer for anchor in (
        "ExpectedSidSha256",
        "Fixture writer did not inherit the expected SID",
    )) and all(promoted not in (nsis_membership_monitor + nsis_membership_monitor_test)
               for promoted in (
                   "physical_membership_prevention_claimed = $true",
                   "makensis_interval_covered = $true",
                   "active_same_sid_transient_tree_membership_interference_excluded = $true",
                   "nsis_non_os_compiler_input_closure = $true",
                   "full_nsis_toolchain_input_closure = $true",
               ))
    nsis_membership_monitor_fixture_test_source_anchors_present = all(
        anchor in nsis_membership_monitor_test for anchor in (
            "yime-rime-pime-nsis-membership-monitor-test-result-v1",
            "same-process-transient-file-invalidates-interval",
            "independent-same-sid-process-transient-file-invalidates-interval",
            "nested-subtree-transient-file-invalidates-interval",
            "root-rename-and-replacement-prerequisite-are-blocked-while-armed",
            "overlapping-notification-record-is-rejected-by-parser",
            "notification-overflow-or-zero-byte-completion-fails-closed",
            "actual_makensis_executed = $false",
            "physical_membership_prevention_claimed = $false",
            "makensis_interval_covered = $false",
            "active_same_sid_transient_tree_membership_interference_excluded = $false",
        )
    )
    interval_helper_order = tuple(nsis_compiler_interval.index(anchor) for anchor in (
        "[YimePime.NsisMembership.MonitorHostV1]::new",
        "$closure=Open-RimePimeNsisCompilerInputClosureCore",
        "$result=$Stage.Monitor.Seal(10000)",
        "$null=Test-RimePimeNsisCompilerInputClosure $Stage.Closure",
    ))
    interval_builder_order = tuple(staged_builder.index(anchor) for anchor in (
        "$compilerStage=Open-RimePimeMonitoredNsisStage",
        "$MakensisPath=Join-Path $compilerStage.Root 'Bin\\makensis.exe'",
        "$env:NSISDIR=$compilerStage.Root",
        "Push-Location $nsisIncludeRoot",
        "& $MakensisPath @arguments",
        'if ($LASTEXITCODE -ne 0)',
        "$membershipInterval=Complete-RimePimeMonitoredNsisStage",
        "$candidateLeases=Open-RimePimeBuildInputLeases $candidateExpected",
        "$prepared=New-RimePimePreparedPublication",
        "$receipt=Invoke-RimePimePublicationCommit",
    ))
    nsis_compiler_stage_membership_detection_rejection_wired = (
        interval_helper_order == tuple(sorted(interval_helper_order)) and
        interval_builder_order == tuple(sorted(interval_builder_order)) and
        len(set(interval_builder_order)) == len(interval_builder_order) and
        staged_builder.count("& $MakensisPath @arguments") == 1 and
        staged_builder.count("$membershipInterval=Complete-RimePimeMonitoredNsisStage") == 1 and
        staged_builder.count("nsis_compiler_membership_interval=$membershipInterval") == 1 and
        staged_builder.count(
            "schema_version='yime-rime-pime-staged-nsis-build-result-membership-interval-v1'"
        ) == 1 and
        "schema_version='yime-rime-pime-staged-nsis-build-result-v3'" not in staged_builder and
        staged_builder.count("Close-RimePimeMonitoredNsisStage $compilerStage") == 1 and
        "(Join-Path $root 'tools\\dual-product\\rime-pime-nsis-membership-monitor-v1.ps1')" in staged_builder and
        "(Join-Path $root 'tools\\dual-product\\rime-pime-nsis-compiler-interval.ps1')" in staged_builder and
        "if($null -ne $compilerStage){Close-RimePimeMonitoredNsisStage $compilerStage}" in staged_builder and
        all(promoted not in (nsis_compiler_interval + nsis_compiler_interval_test) for promoted in (
            "physical_membership_prevention_claimed=$true",
            "active_same_sid_transient_tree_membership_interference_excluded=$true",
            "nsis_non_os_compiler_input_closure=$true",
            "full_nsis_toolchain_input_closure=$true",
        ))
    )
    receipt_v2_supersession_fixture_source_anchors_present = all(
        anchor in receipt_v2_supersession for anchor in (
            "fixture-only receipt-v2 publication supersession protocol",
            "yime-rime-pime-publication-generation-v1",
            "yime-rime-pime-publication-head-v1",
            "yime-rime-pime-publication-journal-record-v1",
            "function Ensure-RimePimeSupersessionObject",
            "function Resume-RimePimeReceiptV2Supersession",
            "[IO.File]::Replace",
            "retention_durability_claimed=$false",
            "directory_metadata_durability_verified=$false",
            "power_loss_verified=$false",
            "canonical_receipt_mutated=$false",
        )
    ) and all(anchor in receipt_v2_supersession_module for anchor in (
        "Definitions-only entry point",
        "'Invoke-RimePimeReceiptV2Supersession'",
        "'Resume-RimePimeReceiptV2Supersession'",
    )) and all(promoted not in (receipt_v2_supersession + receipt_v2_supersession_test)
               for promoted in (
                   "retention_durability_claimed=$true",
                   "directory_metadata_durability_verified=$true",
                   "power_loss_verified=$true",
                   "canonical_receipt_mutated=$true",
                   "actual_strict_receipt_v2_schema_verified=$true",
                   "cross_process_crash_or_replay_verified=$true",
                   "physical_object_immutability_enforced=$true",
                   "concurrent_content_replacement_excluded=$true",
               ))
    receipt_v2_supersession_fixture_test_source_anchors_present = all(
        anchor in receipt_v2_supersession_test for anchor in (
            "yime-rime-pime-receipt-v2-supersession-test-v1",
            "atomic-v2-to-v2-switch-replays-after-switch-before-journal",
            "stale-cas-is-rejected-before-transaction-write",
            "unique-json-only-journal-tail-is-discarded-and-rewritten",
            "same_process_module_reimport_replay_verified=($failed.Count -eq 0)",
            "actual_strict_receipt_v2_schema_verified=$false",
            "cross_process_crash_or_replay_verified=$false",
            "retention_durability_claimed=$false",
            "canonical_receipt_mutated=$false",
        )
    )
    stage_macro_names = (
        "YimePimeStageTargetUserHelpers",
        "YimePimeStageOwnershipHelpers",
        "YimePimeStageRegistrationTools",
        "YimePimeStageMainPayload",
        "YimePimeStageTextServiceX86",
        "YimePimeStageTextServiceX64",
    )
    nsis_stage_only_wired = (
        '!include "${PACKAGE_PAYLOAD_NSH_PATH}"' in nsis and
        all(re.search(r"(?m)^\s*!insertmacro\s+" + re.escape(name) + r"\s*$", nsis)
            for name in stage_macro_names) and
        re.search(r"(?mi)^\s*File(?:\s|$)", nsis) is None and
        all(define in staged_builder for define in (
            "/DPACKAGE_STAGE_ROOT=", "/DPACKAGE_STAGE_MANIFEST_SHA256=",
            "/DPACKAGE_STAGE_CONTENT_SHA256=", "/DPACKAGE_PAYLOAD_NSH_PATH=",
            "/DPACKAGE_PAYLOAD_NSH_SHA256=", "/DPACKAGE_OUTPUT_PATH=",
            "/DPACKAGE_LOCALE_ROOT=", "/DPACKAGE_UNSIGNED_DISABLED_BUILD=",
        )) and
        "'/NOCD','/NOCONFIG'" in staged_builder and
        "/DPACKAGE_SIGN_FILE_PATH=" not in staged_builder and
        "/DPACKAGE_POWERSHELL_PATH=" not in staged_builder and
        "Write-RimePimeNsisStageInclude" in staged_builder and
        staged_builder.count("Test-RimePimeNsisStageInclude") >= 2
    )
    static_archive_exact_gate_present = (
        "function Invoke-RimePimePostbuildExtraction" in postbuild and
        "Assert-RimePimePackagePlanStageBindings -Package $Package" in postbuild and
        "Test-RimePimeNsisStageInclude -StageRoot $stage" in postbuild and
        "function Test-RimePimePostbuildRawByteBindings" in postbuild and
        "payload_nsh_raw_byte_binding_verified=$true" in postbuild and
        "function Read-RimePimePostbuildToolchainLock" in postbuild and
        "function Open-RimePimePostbuildReadLease" in postbuild and
        "function Open-RimePimePostbuildDirectoryLease" in postbuild and
        "function Open-RimePimePostbuildExtractedFileLeases" in postbuild and
        "function Test-RimePimePostbuildExtractedFileLeases" in postbuild and
        "function Test-RimePimePostbuildExecutionLogicLeases" in postbuild and
        "function Test-RimePimePostbuildSevenZipLibraryBinding" in postbuild and
        "function Invoke-RimePimePostbuildSevenZipRawEntry" in postbuild and
        "execution_logic_read_leases_held_through_seal=$true" in postbuild and
        "installer_read_lease_held_for_all_reads=$true" in postbuild and
        "parent_created_per_entry_raw_stdout_snapshot=$true" in postbuild and
        "installer_archive_per_entry_raw_stdout_verified=$true" in postbuild and
        "nested_uninstaller_archive_per_entry_raw_stdout_verified=$true" in postbuild and
        "extracted_file_read_leases_held_through_seal=$true" in postbuild and
        "seven_zip_read_lease_held_for_all_calls=$true" in postbuild and
        "seven_zip_parser_library_read_lease_held_for_all_calls=$true" in postbuild and
        "Test-RimePimePostbuildArchiveListing" in postbuild and
        "Get-RimePimePostbuildExtractedSnapshot" in postbuild and
        "archive_content_origin_proven=$true" in postbuild and
        "generated_uninstaller_verified=$false" in postbuild and
        "generated_uninstaller_trusted=$false" in postbuild and
        "final_payload_closure=$false;delivery_admitted=$false" in postbuild and
        "Invoke-RimePimePostbuildExtraction" in postbuild_runner and
        "-Package $package -PayloadNshReceiptPath $PayloadNshReceiptPath" in postbuild_runner and
        "-ExecutionLogicLeases @($logicLeases)" in postbuild_runner
    )
    postbuild_exact_gate_wired_into_builder = (
        "rime-pime-postbuild-extraction" in staged_builder or
        "Invoke-RimePimePostbuildExtraction" in staged_builder
    )
    canonical_receipt_v2_source_contract_present = (
        "yime-rime-pime-package-build-receipt-v2" in receipt_v2 and
        "function New-RimePimePackageReceiptV2Preparation" in receipt_v2 and
        "function Publish-RimePimePackageReceiptV2" in receipt_v2 and
        "function Read-RimePimePackageBuildReceiptV2" in receipt_v2 and
        "Publish-RimePimePackageReceiptV2 -Prepared $prepared" in receipt_v2_finalizer and
        "staged-builder-refuses-canonical-v2-downgrade" in receipt_v2_test and
        "yime-rime-pime-receipt-no-downgrade-test-v1" in receipt_no_downgrade_test
    )
    legacy_build_v2_read_compatibility_wired = all(anchor in receipt_v2 for anchor in (
        "$script:RimePimeLegacyBuildEvidenceSchema='yime-rime-pime-staged-nsis-build-result-v2'",
        "Legacy build evidence cannot carry membership-interval fields under the old schema.",
        "function Test-RimePimeReceiptV2BuildEvidenceSchema",
    )) and all(anchor in receipt_v2_test for anchor in (
        "function Convert-ReceiptFileToHistoricalV2",
        "function Convert-CaseBuildToHistoricalV2",
    ))
    current_membership_interval_build_admission_wired = (
        "$script:RimePimeCurrentBuildEvidenceSchema='yime-rime-pime-staged-nsis-build-result-membership-interval-v1'" in receipt_v2 and
        "$script:RimePimeCompilerMembershipIntervalSchema='yime-rime-pime-nsis-compiler-membership-interval-v1'" in receipt_v2 and
        "function Assert-RimePimeReceiptV2CompilerMembershipInterval" in receipt_v2 and
        "function Assert-RimePimeReceiptV2CurrentBuildLogicSources" in receipt_v2 and
        "function Assert-RimePimeReceiptV2CurrentBuildEvidence" in receipt_v2 and
        "$allowedStageParent=[IO.Path]::GetFullPath((Join-Path $repo '.tmp\\dual-product')).TrimEnd([char]92)" in receipt_v2 and
        "(Split-Path -Parent $buildStage) -ine $allowedStageParent" in receipt_v2 and
        "[int]$Build.package_plan_artifact_count -ne [int]$Build.staged_pe_unique_artifact_count" in receipt_v2 and
        "[int]$Build.package_plan_matching_stage_binding_count -ne [int]$Build.staged_pe_path_binding_count" in receipt_v2 and
        "Current membership-interval build evidence contradicts its sealed manifest or payload include counts." in receipt_v2 and
        "Current membership-interval build evidence has an invalid prebuild leased-input count." in receipt_v2 and
        "Current membership-interval build evidence has inconsistent candidate or publication paths." in receipt_v2 and
        "Current build evidence must be the sealed build-result.json from its declared build root." in receipt_v2 and
        "Assert-RimePimePackagePlanStageBindings" in receipt_v2 and
        "Current build publication paths contradict the actual predecessor identity." in receipt_v2 and
        "Test-RimePimeReceiptV2Boolean $manifest.Value.final_payload_closure $false" in receipt_v2 and
        "Open-RimePimeReceiptV2FileLease $logicPath ([string]$row.sha256)" in receipt_v2 and
        "Current build evidence contradicts the leased repository NSIS toolchain lock." in receipt_v2 and
        "New receipt preparation requires current membership-interval build evidence; legacy evidence is read-only." in receipt_v2 and
        "^yime-rime-pime-staged-nsis-build-result-v[1-9][0-9]*$" not in receipt_v2 and
        "Changed receipt publication requires current membership-interval build evidence." in receipt_store and
        "Changed receipt recovery requires current membership-interval build evidence." in receipt_store and
        "notification_batch_count=1" in receipt_v2_test and
        "nsis_compiler_stage_file_lease_count=303" in receipt_v2_test and
        "nsis_compiler_stage_directory_lease_count=19" in receipt_v2_test
    )
    canonical_v2_binds_postbuild_source_anchors_present = (
        "static_postbuild" in receipt_v2 and
        "Postbuild result does not close the same disabled candidate" in receipt_v2 and
        "archive_content_origin_proven=$true" in receipt_v2
    )
    # Publication is a separate, explicit PowerShell action. This baseline only
    # reads source and does not inspect or publish the canonical receipt.
    canonical_receipt_v2_published_by_baseline = False
    receipt_export_block = one(
        r"(?ms)^Export-ModuleMember -Function @\(\s*.*?^\)",
        receipt_v2_module,
        "receipt-v2 explicit module export",
    ).group()
    explicit_receipt_module_surface = (
        receipt_v2_module.count("Export-ModuleMember") == 1 and
        re.findall(r"'([^']+)'", receipt_export_block) == [
            "New-RimePimePackageReceiptV2Preparation",
            "Close-RimePimePackageReceiptV2Preparation",
            "Publish-RimePimePackageReceiptV2",
            "Read-RimePimePackageBuildReceiptV2",
            "Publish-RimePimePackageReceiptV2Supersession",
            "Resume-RimePimePackageReceiptV2Publication",
        ]
    )
    v2_to_v2_supersession_wired = all(anchor in receipt_store for anchor in (
        "function Publish-RimePimePackageReceiptV2Supersession",
        "function Resume-RimePimePackageReceiptV2Publication",
        "Open-RimePimePublicationLock", "ExpectedPreviousDigest",
        "Read-RimePimePackageBuildReceiptV2", "pending.json",
        "function Open-RimePimeReceiptPublicationIntentLease",
        "Assert-RimePimeReceiptJsonSyntax $text",
        "Open-RimePimeReceiptV2RawSidecarLease $full $Digest",
    )) and all(anchor in receipt_store_test for anchor in (
        "module-exports-only-six-explicit-receipt-apis",
        "strict-intent-json-rejects-",
        "missing-retained-object-sidecar-fails-closed",
        "hard-exit-", "fresh-process-recovery",
    )) and "Resolve-RimePimeReceiptEvidence" in receipt_v2 and \
        ". (Join-Path $PSScriptRoot 'rime-pime-receipt-v2-store.ps1')" in receipt_v2_module and \
        explicit_receipt_module_surface and retained_receipt_ci_ps5_ps7_present
    installer_receipt_move = powershell_function(
        installer_receipt_transaction, "Move-RimePimeInstallerReceiptNoReplace"
    )
    installer_receipt_intent = powershell_function(
        installer_receipt_transaction, "Write-RimePimeInstallerReceiptIntentNoReplace"
    )
    installer_receipt_stage = powershell_function(
        installer_receipt_transaction, "Stage-RimePimeInstallerReceiptPhysicalLeaf"
    )
    installer_receipt_complete = powershell_function(
        installer_receipt_transaction, "Complete-RimePimeInstallerReceiptTransaction"
    )
    installer_receipt_publish = powershell_function(
        installer_receipt_transaction, "Publish-RimePimeInstallerReceiptTransaction"
    )
    installer_receipt_worker = one(
        r"(?ms)^if\(\$WorkerCasePath\)\{.*?^}\s*$",
        installer_receipt_transaction_test,
        "installer/receipt transaction fixture worker",
    ).group()
    installer_receipt_worker_schema_fields = re.findall(
        r"'([^']+)'",
        one(
            r"(?ms)Assert-RimePimeExactProperties \$Value @\((.*?)\)\s*"
            r"'transaction worker input'",
            installer_receipt_worker,
            "installer/receipt transaction worker exact schema",
        ).group(1),
    )
    installer_receipt_worker_required_fields = re.findall(
        r"'([^']+)'",
        one(
            r"(?ms)foreach\(\$name in @\((.*?)\)\)\{",
            installer_receipt_worker,
            "installer/receipt transaction worker required fields",
        ).group(1),
    )
    installer_receipt_write_worker = powershell_function(
        installer_receipt_transaction_test, "Write-WorkerCase"
    )
    installer_receipt_result = one(
        r"(?ms)^\$result=\[ordered\]@\{.*?^}\s*$",
        installer_receipt_transaction_test,
        "installer/receipt transaction dynamic result",
    ).group()
    installer_receipt_export_block = one(
        r"(?ms)^Export-ModuleMember -Function @\(\s*.*?^\)",
        installer_receipt_transaction_module,
        "installer/receipt transaction explicit module export",
    ).group()
    installer_receipt_module_import_order = tuple(
        installer_receipt_transaction_module.index(anchor) for anchor in (
            "rime-pime-nsis-toolchain-closure.psm1",
            "rime-pime-package-staging.psm1",
            "rime-pime-nsis-stage.psm1",
            "rime-pime-staged-installer-build.psm1",
            "rime-pime-package-receipt-v2.ps1",
            "rime-pime-receipt-v2-store.ps1",
            "rime-pime-installer-receipt-transaction.ps1",
        )
    )
    installer_receipt_fixture_source_anchors_present = all(
        anchor in installer_receipt_transaction for anchor in (
            "Definitions-only, fixture-gated installer/receipt identity replacement",
            "Assert-RimePimeInstallerReceiptTransactionFixtureRoot $RepoRoot",
            "Assert-RimePimeNoReparsePath $path",
            "dp1-package-receipt-v2-test-dp1n-",
        )
    ) and all(anchor in installer_receipt_transaction_test for anchor in (
        "Transaction worker is fixture-only.",
        "actual-checkout-root-is-rejected-before-any-transaction-access",
        "fixture_only=$true",
        "installed_product_actions_out_of_scope=$true",
        "registry_and_default_input_method_actions_out_of_scope=$true",
        "production_user_data_actions_out_of_scope=$true",
    ))
    installer_receipt_preintent_durable_stage_present = (
        installer_receipt_stage.index("$destination.Flush($true)") <
        installer_receipt_stage.index("Move-RimePimeInstallerReceiptNoReplace $copy $stage") <
        installer_receipt_stage.rindex(
            "Open-RimePimeInstallerReceiptPhysicalLeaf $stage $Sha256 $Bytes 'staged new installer'"
        ) and
        installer_receipt_publish.index(
            "$null=Stage-RimePimeInstallerReceiptPhysicalLeaf $newObject.Lease.Stream"
        ) < installer_receipt_publish.index(
            "Write-RimePimeInstallerReceiptIntentNoReplace $pending $intent"
        )
    )
    installer_receipt_unique_copy_checkpoints_present = (
        installer_receipt_intent.index("('.rime-pime-intent-'+[guid]::NewGuid().ToString('N')+'.tmp')") <
        installer_receipt_intent.index(
            "Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'intent-copy'"
        ) < installer_receipt_intent.index(
            "Move-RimePimeInstallerReceiptNoReplace $temp $Pending"
        ) and
        installer_receipt_stage.index("('.rime-pime-copy-'+[guid]::NewGuid().ToString('N')+'.tmp')") <
        installer_receipt_stage.index(
            "Invoke-RimePimeInstallerReceiptTransactionCheckpoint 'installer-copy'"
        ) < installer_receipt_stage.index(
            "Move-RimePimeInstallerReceiptNoReplace $copy $stage"
        ) and
        all(anchor in installer_receipt_transaction_test for anchor in (
            "Mid-copy hard exit did not retain exactly one unique attempt leaf.",
            "Mid-copy hard exit did not retain exactly one unique intent leaf.",
            "'objects','installer-copy','installer-temp','intent-copy','intent-temp'",
        ))
    )
    installer_receipt_no_replace_present = (
        installer_receipt_transaction.count("[YimeReceiptStorage.Native]::MoveFileEx(") == 1 and
        "[YimeReceiptStorage.Native]::MoveFileEx($Source,$Destination,8)" in installer_receipt_move and
        "Deliberately omit REPLACE_EXISTING." in installer_receipt_move and
        len(re.findall(
            r"(?m)^\s+Move-RimePimeInstallerReceiptNoReplace\s+",
            installer_receipt_transaction,
        )) == 4 and
        "Move-RimePimeReceiptDurableFile" not in installer_receipt_transaction and
        "Move-Item" not in installer_receipt_transaction and
        all(anchor in installer_receipt_transaction_test for anchor in (
            "installer-no-replace-preserves-foreign-before-move-race",
            "installer-no-replace-preserves-exact-before-move-race",
            "completion-no-replace-rename-preserves-pending-file-id",
        ))
    )
    installer_receipt_completed_preflight_present = (
        installer_receipt_complete.index(
            "$completed=Assert-RimePimeInstallerReceiptCompletionTargetAbsent $Pending $intent.operation_id"
        ) < installer_receipt_complete.index(
            "$bindings=Read-RimePimeInstallerReceiptTransactionBindings $root $intent"
        ) < installer_receipt_complete.index(
            "Write-RimePimeReceiptAtomicBytes $Canonical $bindings.NewReceiptBytes"
        ) and
        installer_receipt_publish.index(
            "$null=Assert-RimePimeInstallerReceiptCompletionTargetAbsent $pending $intent.operation_id"
        ) < installer_receipt_publish.index(
            "$null=Stage-RimePimeInstallerReceiptPhysicalLeaf $newObject.Lease.Stream"
        ) < installer_receipt_publish.index(
            "Write-RimePimeInstallerReceiptIntentNoReplace $pending $intent"
        ) and
        "foreign-completion-leaf-is-rejected-before-any-transaction-write" in
        installer_receipt_transaction_test
    )
    installer_receipt_physical_leases_present = (
        installer_receipt_complete.index(
            "$oldPhysical=Open-RimePimeInstallerReceiptPhysicalLeaf $bindings.OldInstaller.Path"
        ) < installer_receipt_complete.index(
            "$newPhysical=Open-RimePimeInstallerReceiptPhysicalLeaf $bindings.NewInstaller.Path"
        ) < installer_receipt_complete.index(
            "Write-RimePimeReceiptAtomicBytes $Canonical $bindings.NewReceiptBytes"
        ) < installer_receipt_complete.index(
            "Move-RimePimeInstallerReceiptNoReplace $Pending $completed"
        ) < installer_receipt_complete.index(
            "if($null -ne $newPhysical){$newPhysical.Lease.Stream.Dispose()}"
        ) and
        installer_receipt_complete.index(
            "Move-RimePimeInstallerReceiptNoReplace $Pending $completed"
        ) < installer_receipt_complete.index(
            "if($null -ne $oldPhysical){$oldPhysical.Lease.Stream.Dispose()}"
        )
    )
    installer_receipt_exact_two_api_surface = (
        installer_receipt_transaction_module.count("Export-ModuleMember") == 1 and
        re.findall(r"'([^']+)'", installer_receipt_export_block) == [
            "Publish-RimePimeInstallerReceiptTransaction",
            "Resume-RimePimeInstallerReceiptTransaction",
        ] and
        installer_receipt_module_import_order == tuple(sorted(installer_receipt_module_import_order)) and
        "module-exports-only-two-isolated-transaction-apis" in installer_receipt_transaction_test
    )
    installer_receipt_nondurable_historical_v1_coverage_present = (
        installer_receipt_transaction_test.count(
            "Check 'non-durable-old-clean-publish-binds-distinct-retention-and-history' {"
        ) == 1 and
        installer_receipt_transaction_test.count(
            "Check 'non-durable-old-intent-hard-exit-resumes-in-fresh-process' {"
        ) == 1 and
        installer_receipt_worker_schema_fields == [
            "schema_version", "Root", "NextDigest", "Before", "HistoricalV1Path",
        ] and
        installer_receipt_worker_required_fields == [
            "Root", "NextDigest", "Before", "HistoricalV1Path",
        ] and
        installer_receipt_worker.count("-HistoricalV1Path $case.HistoricalV1Path") == 2 and
        "HistoricalV1Path=[string]$Case.HistoricalV1Path" in installer_receipt_write_worker and
        "non_durable_old_retention_conversion_and_recovery=(Test-NamedChecksPassed @(" in
        installer_receipt_result and
        "'non-durable-old-clean-publish-binds-distinct-retention-and-history'" in
        installer_receipt_result and
        "'non-durable-old-intent-hard-exit-resumes-in-fresh-process'" in
        installer_receipt_result
    )
    installer_receipt_dynamic_result_and_limitations_present = (
        all(anchor in installer_receipt_transaction_test for anchor in (
            "$fullSuiteExecuted=(($selectedNames -join \"`n\") -ceq ($expectedNames -join \"`n\"))",
            "$allChecksPassed=($failed.Count -eq 0)",
            "$fullMatrixVerified=($fullSuiteExecuted -and $allChecksPassed)",
            "full_suite_executed=[bool]$fullSuiteExecuted",
            "all_executed_checks_passed=[bool]$allChecksPassed",
            "full_transaction_matrix=[bool]$fullMatrixVerified",
            "hardware_power_loss_verified=$false",
            "directory_metadata_durability_verified=$false",
            "active_same_sid_physical_replacement_prevention_verified=$false",
        )) and all(promoted not in installer_receipt_transaction_test for promoted in (
            "full_suite_executed=$true",
            "all_executed_checks_passed=$true",
            "full_transaction_matrix=$true",
            "hardware_power_loss_verified=$true",
            "directory_metadata_durability_verified=$true",
            "active_same_sid_physical_replacement_prevention_verified=$true",
        ))
    )
    installer_receipt_transaction_isolated_contract_wired = all((
        installer_receipt_fixture_source_anchors_present,
        installer_receipt_preintent_durable_stage_present,
        installer_receipt_unique_copy_checkpoints_present,
        installer_receipt_no_replace_present,
        installer_receipt_completed_preflight_present,
        installer_receipt_physical_leases_present,
        installer_receipt_exact_two_api_surface,
        installer_receipt_nondurable_historical_v1_coverage_present,
        installer_receipt_dynamic_result_and_limitations_present,
        installer_receipt_transaction_ci_ps5_ps7_present,
    ))
    # These booleans classify source anchors only. This function never executes
    # the PowerShell contracts, an installer, a native probe, or installed code.
    if (not rime_sid_chain_anchors or not rime_target_user_cleanup_anchors or
            full_transaction_engine_wired_into_installer or
            not registration_readback_anchors or not legacy_refusal_anchors or
            not unowned_legacy_deletion_absent or legacy_migration_wired or
            not current_upgrade_fail_closed or not fresh_install_final_vacancy or
            not synthetic_fault_matrix_anchors or
            not transaction_replay_model_source_anchors_present or
            not uninstall_stage_catalog_source_anchors_present or
            not logical_leaf_first_nonrecursive_removal_plan_present or
            not fixture_transaction_journal_source_anchors_present or
            not fixture_transaction_journal_test_source_anchors_present or
            not fixture_journal_hash_chain_source_anchors_present or
            not fixture_journal_sidecar_last_flush_protocol_present or
            not fixture_journal_case_local_recovery_artifacts_bound or
            not fixture_registry_snapshot_closed_typed_privacy_safe or
            not fixture_exact_removal_source_anchors_present or
            not fixture_changed_or_foreign_content_preserved or
            not synthetic_dp1i_ci_contracts_present or
            not nsis_membership_monitor_fixture_source_anchors_present or
            not nsis_membership_monitor_fixture_test_source_anchors_present or
            not receipt_v2_supersession_fixture_source_anchors_present or
            not receipt_v2_supersession_fixture_test_source_anchors_present or
            not synthetic_dp1j_ci_contracts_present or
            not nsis_compiler_stage_membership_detection_rejection_wired or
            not compiler_interval_ci_ps5_ps7_present or
            not nsis_stage_only_wired or
            not static_archive_exact_gate_present or postbuild_exact_gate_wired_into_builder or
            not canonical_receipt_v2_source_contract_present or
            not legacy_build_v2_read_compatibility_wired or
            not current_membership_interval_build_admission_wired or
            not v2_to_v2_supersession_wired or
            not canonical_v2_binds_postbuild_source_anchors_present or
            not synthetic_postbuild_ci_is_host_tool_independent or
            not synthetic_dp1h_ci_contracts_present or
            not installer_receipt_transaction_isolated_contract_wired or
            not isolated_candidate_runner_source_contract_wired or
            not isolated_candidate_runner_contract_ci_ps5_ps7_present or
            not version_identity_admission_ci_ps5_ps7_present or
            not candidate_evidence_archive_source_contract_wired or
            not candidate_evidence_archive_ci_ps5_ps7_present or
            not actual_migration_review_source_contract_wired or
            not actual_migration_review_ci_ps5_ps7_present or
            not dp1r_trust_admission_source_contract_wired or
            not dp1r_trust_admission_ci_ps5_ps7_present or
            not dp1s_off_repository_archive_source_contract_wired or
            not dp1s_off_repository_archive_ci_ps5_ps7_present or
            not dp1t_actual_adapter_source_contract_wired or
            not dp1t_actual_adapter_ci_ps5_ps7_present or
            not dp1u_maintenance_runtime_gate_source_contract_wired or
            not dp1u_maintenance_runtime_gate_ci_ps5_ps7_present or
            not dp1u_isolated_preflight_source_contract_wired or
            not dp1u_isolated_preflight_ci_ps5_ps7_present or
            'InstallLayoutOrTip(w "${YIME_TIP}"' not in nsis or
            'Get-ChildItem -LiteralPath "Registry::HKEY_USERS"' in pime_cleanup):
        fail("Rime/PIME registration/SID/transaction status changed; dedicated review required")
    return {
        "level": "read-only-source-anchors-including-pure-model-and-isolated-journal-fixture-not-live-transaction-evidence",
        "synthetic_contract_source_anchors_present": True,
        "yimecore_same_sid_source_anchors_present": True,
        "yimecore_stage_before_active_mutation_source_anchor_present": True,
        "yimecore_rollback_restore_source_anchors_present": True,
        "yimecore_peer_product_snapshot_source_anchors_present": True,
        "rime_pime_initiating_sid_chain_source_anchors_present": rime_sid_chain_anchors,
        "rime_pime_target_user_cleanup_source_anchors_present": rime_target_user_cleanup_anchors,
        "rime_pime_target_user_synthetic_contract_source_anchors_present": True,
        "rime_pime_native_uac_and_registered_profile_acceptance_passed": False,
        "rime_pime_full_transaction_engine_wired_into_installer": full_transaction_engine_wired_into_installer,
        "rime_pime_registration_exit_and_state_source_anchors_present": registration_readback_anchors,
        "rime_pime_legacy_registration_selected_root_only": False,
        "rime_pime_unowned_legacy_deletion_absent": unowned_legacy_deletion_absent,
        "rime_pime_legacy_migration_wired": legacy_migration_wired,
        "rime_pime_current_upgrade_fail_closed": current_upgrade_fail_closed,
        "rime_pime_fresh_install_final_vacancy_source_anchor_present": fresh_install_final_vacancy,
        "rime_pime_synthetic_fault_matrix_source_anchors_present": synthetic_fault_matrix_anchors,
        "rime_pime_transaction_replay_model_source_anchors_present": transaction_replay_model_source_anchors_present,
        "rime_pime_uninstall_stage_catalog_source_anchors_present": uninstall_stage_catalog_source_anchors_present,
        "rime_pime_logical_leaf_first_nonrecursive_removal_plan_present": logical_leaf_first_nonrecursive_removal_plan_present,
        "rime_pime_fixture_transaction_journal_source_anchors_present": fixture_transaction_journal_source_anchors_present,
        "rime_pime_fixture_transaction_journal_test_source_anchors_present": fixture_transaction_journal_test_source_anchors_present,
        "rime_pime_fixture_journal_hash_chain_source_anchors_present": fixture_journal_hash_chain_source_anchors_present,
        "rime_pime_fixture_journal_sidecar_last_flush_protocol_present": fixture_journal_sidecar_last_flush_protocol_present,
        "rime_pime_fixture_journal_case_local_recovery_artifacts_bound": fixture_journal_case_local_recovery_artifacts_bound,
        "rime_pime_fixture_registry_snapshot_closed_typed_privacy_safe": fixture_registry_snapshot_closed_typed_privacy_safe,
        "rime_pime_fixture_exact_removal_source_anchors_present": fixture_exact_removal_source_anchors_present,
        "rime_pime_fixture_changed_or_foreign_content_preserved": fixture_changed_or_foreign_content_preserved,
        "rime_pime_fixture_journal_ci_ps5_ps7_present": synthetic_dp1i_ci_contracts_present,
        "rime_pime_fixture_journal_test_executed_by_baseline": False,
        "rime_pime_fixture_filesystem_io_executed_by_baseline": False,
        "rime_pime_product_filesystem_mutation_executed_by_baseline": False,
        "rime_pime_real_durable_install_transaction_journal": False,
        "rime_pime_real_power_loss_recovery_passed": False,
        "rime_pime_cross_process_replay_passed": False,
        "rime_pime_concurrent_replacement_excluded": False,
        "rime_pime_real_registry_replay_passed": False,
        "rime_pime_installed_exact_removal_passed": False,
        "rime_pime_real_installer_transaction_passed": False,
        "rime_pime_nsis_membership_monitor_fixture_source_anchors_present": nsis_membership_monitor_fixture_source_anchors_present,
        "rime_pime_nsis_membership_monitor_fixture_test_source_anchors_present": nsis_membership_monitor_fixture_test_source_anchors_present,
        "rime_pime_receipt_v2_supersession_fixture_source_anchors_present": receipt_v2_supersession_fixture_source_anchors_present,
        "rime_pime_receipt_v2_supersession_fixture_test_source_anchors_present": receipt_v2_supersession_fixture_test_source_anchors_present,
        "rime_pime_dp1j_fixture_ci_ps5_ps7_present": synthetic_dp1j_ci_contracts_present,
        "rime_pime_dp1j_fixture_tests_executed_by_baseline": False,
        "rime_pime_nsis_compiler_stage_membership_detection_rejection_wired": nsis_compiler_stage_membership_detection_rejection_wired,
        "rime_pime_nsis_compiler_interval_ci_ps5_ps7_present": compiler_interval_ci_ps5_ps7_present,
        "rime_pime_nsis_compiler_interval_test_executed_by_baseline": False,
        "rime_pime_receipt_v2_supersession_fixture_protocol_only": True,
        "rime_pime_receipt_v2_supersession_canonical_receipt_mutated": False,
        "rime_pime_prepackage_copy_stage_source_anchors_present": True,
        "rime_pime_prepackage_copy_stage_final_payload_closure": False,
        "rime_pime_prepackage_copy_stage_natively_wired": nsis_stage_only_wired,
        "rime_pime_nsis_stage_only_wired": nsis_stage_only_wired,
        "rime_pime_nsis_stage_generated_macro_count": len(stage_macro_names),
        "rime_pime_static_archive_exact_gate_source_anchors_present": static_archive_exact_gate_present,
        "rime_pime_static_archive_exact_gate_wired_into_builder": postbuild_exact_gate_wired_into_builder,
        "rime_pime_static_archive_exact_gate_executed_by_baseline": False,
        "rime_pime_synthetic_postbuild_ci_host_tool_independent": synthetic_postbuild_ci_is_host_tool_independent,
        "rime_pime_synthetic_dp1h_ci_contracts_present": synthetic_dp1h_ci_contracts_present,
        "rime_pime_final_payload_closure": False,
        "rime_pime_delivery_admitted": False,
        "rime_pime_generated_uninstaller_verified": False,
        "rime_pime_generated_uninstaller_trusted": False,
        "rime_pime_builder_safe_module_import_order": True,
        "rime_pime_nsis_toolchain_lock_schema": postbuild_toolchain["schema_version"],
        "rime_pime_nsis_toolchain_id": postbuild_toolchain["toolchain_id"],
        "rime_pime_nsis_toolchain_lock_sha256": postbuild_lock_digest,
        "rime_pime_nsis_compiler_input_root_count": len(closure_roots),
        "rime_pime_nsis_compiler_input_directory_count": compiler_input_closure["directory_count"],
        "rime_pime_nsis_compiler_input_file_count": compiler_input_closure["file_count"],
        "rime_pime_nsis_compiler_required_input_count": len(required_inputs),
        "rime_pime_nsis_compiler_input_tree_sha256": compiler_input_closure["tree_sha256"],
        "rime_pime_nsis_known_input_file_replacement_closure": True,
        "rime_pime_nsis_distribution_tree_exact_at_open_and_test": True,
        "rime_pime_active_same_sid_transient_tree_membership_interference_excluded": False,
        "rime_pime_nsis_non_os_compiler_input_closure": False,
        "rime_pime_full_nsis_toolchain_input_closure": False,
        "rime_pime_canonical_receipt_v2_source_contract_present": canonical_receipt_v2_source_contract_present,
        "rime_pime_legacy_build_v2_read_compatibility_wired": legacy_build_v2_read_compatibility_wired,
        "rime_pime_current_membership_interval_build_admission_wired": current_membership_interval_build_admission_wired,
        "rime_pime_current_build_evidence_schema": "yime-rime-pime-staged-nsis-build-result-membership-interval-v1",
        "rime_pime_canonical_v2_binds_postbuild_source_anchors_present": canonical_v2_binds_postbuild_source_anchors_present,
        "rime_pime_canonical_receipt_v2_published_by_baseline": canonical_receipt_v2_published_by_baseline,
        "rime_pime_canonical_receipt_v2_evidence_durable": False,
        "rime_pime_actual_canonical_migrated_to_current_build_evidence": False,
        "rime_pime_installer_receipt_transaction_fixture_source_anchors_present": installer_receipt_fixture_source_anchors_present,
        "rime_pime_installer_receipt_transaction_preintent_durable_stage_present": installer_receipt_preintent_durable_stage_present,
        "rime_pime_installer_receipt_transaction_unique_copy_checkpoints_present": installer_receipt_unique_copy_checkpoints_present,
        "rime_pime_installer_receipt_transaction_no_replace_present": installer_receipt_no_replace_present,
        "rime_pime_installer_receipt_transaction_completed_preflight_present": installer_receipt_completed_preflight_present,
        "rime_pime_installer_receipt_transaction_physical_leases_present": installer_receipt_physical_leases_present,
        "rime_pime_installer_receipt_transaction_exact_two_api_surface": installer_receipt_exact_two_api_surface,
        "rime_pime_installer_receipt_transaction_nondurable_historical_v1_coverage_present": installer_receipt_nondurable_historical_v1_coverage_present,
        "rime_pime_installer_receipt_transaction_dynamic_result_and_limitations_present": installer_receipt_dynamic_result_and_limitations_present,
        "rime_pime_installer_receipt_transaction_ci_ps5_ps7_present": installer_receipt_transaction_ci_ps5_ps7_present,
        "rime_pime_installer_receipt_transaction_isolated_contract_wired": installer_receipt_transaction_isolated_contract_wired,
        "rime_pime_installer_receipt_transaction_test_executed_by_baseline": False,
        "rime_pime_installer_receipt_transaction_actual_canonical_migration_executed": False,
        "rime_pime_installer_receipt_transaction_full_real_transaction_passed": False,
        "rime_pime_installer_identity_replacement_transaction_wired": False,
        "rime_pime_isolated_current_candidate_runner_source_contract_wired": isolated_candidate_runner_source_contract_wired,
        "rime_pime_isolated_current_candidate_runner_contract_ci_ps5_ps7_present": isolated_candidate_runner_contract_ci_ps5_ps7_present,
        "rime_pime_isolated_current_candidate_full_build_executed_by_baseline": False,
        "rime_pime_isolated_current_candidate_actual_canonical_migrated": False,
        "rime_pime_version_identity_admission_source_contract_wired": True,
        "rime_pime_version_identity_admission_ci_ps5_ps7_present": version_identity_admission_ci_ps5_ps7_present,
        "rime_pime_version_identity_admission_test_executed_by_baseline": False,
        "rime_pime_version_identity_actual_canonical_migration_admitted": False,
        "rime_pime_candidate_evidence_archive_source_contract_wired": candidate_evidence_archive_source_contract_wired,
        "rime_pime_candidate_evidence_archive_ci_ps5_ps7_present": candidate_evidence_archive_ci_ps5_ps7_present,
        "rime_pime_candidate_evidence_archive_test_executed_by_baseline": False,
        "rime_pime_candidate_evidence_archive_fixture_protocol_only": True,
        "rime_pime_candidate_evidence_archive_actual_root_published": False,
        "rime_pime_candidate_evidence_archive_actual_evidence_archived": False,
        "rime_pime_actual_migration_review_source_contract_wired": actual_migration_review_source_contract_wired,
        "rime_pime_actual_migration_review_ci_ps5_ps7_present": actual_migration_review_ci_ps5_ps7_present,
        "rime_pime_actual_migration_review_test_executed_by_baseline": False,
        "rime_pime_actual_migration_review_ready_from_actual_evidence": False,
        "rime_pime_actual_migration_review_separate_execution_gate_required": True,
        "rime_pime_dp1r_trust_admission_source_contract_wired": dp1r_trust_admission_source_contract_wired,
        "rime_pime_dp1r_trust_admission_ci_ps5_ps7_present": dp1r_trust_admission_ci_ps5_ps7_present,
        "rime_pime_dp1r_trust_admission_test_executed_by_baseline": False,
        "rime_pime_dp1r_actual_candidate_review_executed_by_baseline": False,
        "rime_pime_dp1r_full_payload_static_closure_from_actual_evidence": False,
        "rime_pime_dp1r_nsis_non_os_compiler_input_closure_from_actual_evidence": False,
        "rime_pime_dp1r_generated_uninstaller_trusted_static_scope_from_actual_evidence": False,
        "rime_pime_dp1s_off_repository_archive_source_contract_wired": dp1s_off_repository_archive_source_contract_wired,
        "rime_pime_dp1s_off_repository_archive_ci_ps5_ps7_present": dp1s_off_repository_archive_ci_ps5_ps7_present,
        "rime_pime_dp1s_actual_archive_executed_by_baseline": False,
        "rime_pime_dp1s_actual_archive_completed_from_tracked_source": False,
        "rime_pime_dp1s_directory_metadata_durability_verified": False,
        "rime_pime_dp1s_hardware_power_loss_verified": False,
        "rime_pime_dp1s_hostile_same_sid_physical_replacement_prevented": False,
        "rime_pime_dp1t_actual_adapter_source_contract_wired": dp1t_actual_adapter_source_contract_wired,
        "rime_pime_dp1t_actual_adapter_ci_ps5_ps7_present": dp1t_actual_adapter_ci_ps5_ps7_present,
        "rime_pime_dp1t_actual_adapter_test_executed_by_baseline": False,
        "rime_pime_dp1t_actual_adapter_dry_run_executed_by_baseline": False,
        "rime_pime_dp1t_exact_authorization_consumed_by_baseline": False,
        "rime_pime_dp1u_maintenance_runtime_gate_source_contract_wired": dp1u_maintenance_runtime_gate_source_contract_wired,
        "rime_pime_dp1u_maintenance_runtime_gate_ci_ps5_ps7_present": dp1u_maintenance_runtime_gate_ci_ps5_ps7_present,
        "rime_pime_dp1u_isolated_preflight_source_contract_wired": dp1u_isolated_preflight_source_contract_wired,
        "rime_pime_dp1u_isolated_preflight_ci_ps5_ps7_present": dp1u_isolated_preflight_ci_ps5_ps7_present,
        "rime_pime_dp1u_isolated_preflight_test_executed_by_baseline": False,
        "rime_pime_dp1u_real_target_approved": False,
        "rime_pime_dp1u_execution_authorized": False,
        "rime_pime_dp1u_gate_test_executed_by_baseline": False,
        "rime_pime_dp1u_current_readiness_executed_by_baseline": False,
        "rime_pime_dp1u_acceptance_passed": False,
        "rime_pime_actual_evidence_archived_outside_repository_tmp": False,
        "rime_pime_actual_canonical_migration_admitted": False,
        "rime_pime_actual_canonical_migration_executed": False,
        "rime_pime_v2_to_v2_supersession_wired": v2_to_v2_supersession_wired,
        "rime_pime_retained_receipt_ci_ps5_ps7_present": retained_receipt_ci_ps5_ps7_present,
        "rime_pime_installed_live_acceptance_passed": False,
        "actual_installer_executed": False,
        "actual_uninstaller_executed": False,
        "actual_elevation_executed": False,
        "actual_registry_mutation_executed": False,
        "actual_profile_mutation_executed": False,
        "actual_process_stop_executed": False,
        "actual_process_start_executed": False,
        "actual_filesystem_mutation_executed": False,
        "actual_installed_runtime_examined": False,
        "actual_native_probe_executed": False,
    }


def source_baseline(root: Path = ROOT):
    root = plain(root)
    contract_path = child(root, "tools/dual-product/contract.json")
    contract = json.loads(contract_path.read_text(encoding="utf-8-sig"))
    if contract["schema_version"] != "yime-dual-product-source-contract-v1":
        fail("unknown contract")
    if contract.get("test_level") != EXPECTED_TEST_LEVEL:
        fail("evidence test level changed")
    if (contract["products"] != ["rime-pime", "yimecore"] or
        contract["installation_choices"] != [["rime-pime"], ["yimecore"], ["rime-pime", "yimecore"]] or
        contract["runtime_dependencies_between_products"] != [] or
        contract["writable_state_shared_between_products"] is not False or
        contract["default_input_method_mutation_authorized"] is not False):
        fail("independent-product policy changed")
    paths = contract["source_paths"]
    if len(set(paths)) != len(paths):
        fail("duplicate source path")
    sources, hashes = {}, {}
    for relative in paths:
        path = child(root, relative)
        if path.stat().st_size > 2 * 1024 * 1024:
            fail("source file exceeds bound")
        payload = path.read_bytes()
        sources[relative] = payload.decode("utf-8-sig").replace("\r\n", "\n")
        hashes[relative] = hashlib.sha256(payload).hexdigest()
    hashes["tools/dual-product/contract.json"] = digest(contract_path)
    hashes["tools/dual-product/baseline.py"] = digest(child(root, "tools/dual-product/baseline.py"))
    hashes["tools/dual-product/test_baseline.py"] = digest(child(root, "tools/dual-product/test_baseline.py"))
    nsis = sources["installer/installer.nsi"]
    version = sources["version.txt"].strip()
    if version != contract.get("rime_pime_source_product_version"):
        fail("Rime/PIME version.txt differs from the reviewed source product identity")
    version_parts, numeric_version = parse_rime_pime_product_version(version)
    if f'VIProductVersion "{numeric_version}"' not in nsis:
        fail("Rime/PIME NSIS numeric VERSIONINFO differs from version.txt")
    launcher_version = sources["PIMELauncher/build.rs"]
    if ('.join("..").join("version.txt")' not in launcher_version or
            'version.split_once(\'-\')' not in launcher_version or
            '.set("FileVersion", version)' not in launcher_version or
            '.set("ProductVersion", version)' not in launcher_version or
            '.set_version_info(winresource::VersionInfo::FILEVERSION, numeric_version)' not in launcher_version or
            '.set_version_info(winresource::VersionInfo::PRODUCTVERSION, numeric_version)' not in launcher_version):
        fail("Rime/PIME launcher version identity is no longer derived from version.txt")
    text_service_version = sources["PIMETextService/PIMETextService.rc.in"]
    for anchor in (
            "FILEVERSION @PIME_VERSION_MAJOR@,@PIME_VERSION_MINOR@,@PIME_VERSION_PATCH@",
            "PRODUCTVERSION @PIME_VERSION_MAJOR@,@PIME_VERSION_MINOR@,@PIME_VERSION_PATCH@",
            'VALUE "FileVersion", "@PIME_VERSION_MAJOR@.@PIME_VERSION_MINOR@.@PIME_VERSION_PATCH@"',
            'VALUE "ProductVersion", "@PIME_VERSION_MAJOR@.@PIME_VERSION_MINOR@.@PIME_VERSION_PATCH@"'):
        if anchor not in text_service_version:
            fail("Rime/PIME text-service numeric version derivation changed")
    ime = json.loads(sources["go-backend/input_methods/yime/ime.json"])
    desc = json.loads(sources["tools/yimecore/local-product.json"])
    identity = desc["identity"]
    tip = one(r'^!define YIME_TIP "0x([0-9A-Fa-f]+):(\{[^}]+\})(\{[^}]+\})"$', nsis, "Rime TIP")
    cpp_guid = one(r'const GUID g_textServiceClsid\s*=\s*(\{.*?\};)',
                   sources["PIMETextService/PIMEImeModule.cpp"], "C++ CLSID").group(1)
    numbers = [int(value, 16) for value in re.findall(r"0x([0-9a-fA-F]+)", cpp_guid)]
    if len(numbers) != 11:
        fail("unexpected native GUID structure")
    native_guid = "{%08X-%04X-%04X-%02X%02X-%s}" % (*numbers[:5], "".join("%02X" % n for n in numbers[5:]))
    if native_guid != tip.group(2).upper() or ime["guid"].upper() != tip.group(3).upper():
        fail("Rime profile/CLSID sources disagree")
    install_dir = one(r'^InstallDir "\$PROGRAMFILES32\\([^"\\]+)"', nsis, "Rime root").group(1)
    uninstall = one(r'^!define PRODUCT_UNINST_KEY "([^"]+)"', nsis, "Rime uninstall").group(1)
    run = one(r'^\s*WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Run" "([^"]+)" .*?\$INSTDIR\\([A-Za-z0-9_.-]+)', nsis, "Rime autostart")
    server = one(r'^set "SERVER_EXE=%PACKAGE_DIR%\\([^"\\]+)"', sources["go-backend/build.bat"], "Rime server").group(1)
    app = one(r'^\s*APP\s*=\s*"([^"]+)"', sources["go-backend/input_methods/yime/yime.go"], "Rime state").group(1)
    log = one(r'ime\.openPath\(filepath.Join\(os.Getenv\("LOCALAPPDATA"\), "([^"]+)", "([^"]+)"\)\)',
              sources["go-backend/input_methods/yime/yime.go"], "Rime log root")
    if 'return filepath.Join(appData, APP, "Rime")' not in sources["go-backend/input_methods/yime/yime.go"]:
        fail("Rime user directory construction changed")
    client = sources["PIMETextService/PIMEClient.cpp"]
    if 'getPipeName(L"Launcher")' not in client or 'pipeName += L"\\\\PIME\\\\";' not in client or 'pipeName += username.get();' not in client:
        fail("Rime endpoint construction changed")
    manager = sources["tools/yimecore/manage-e6c-trial-install.ps1"]
    product_key = one(r"^\$productKeyName = '([^']+)'", manager, "Core product key").group(1)
    state_dir = one(r"\[string\]\$StateRoot = \(Join-Path \$env:LOCALAPPDATA '([^']+)'\)", manager, "Core state").group(1)
    core_root = one(r"^\$productRoot = \[IO.Path\]::GetFullPath\(\(Join-Path \$env:ProgramFiles '([^']+)'\)\)", manager, "Core root").group(1)
    runtime = sources["go-backend/cmd/yimecore-trial-runtime/main.go"]
    pipe = one(r'^\s*defaultPipeName = `([^`]+)`', runtime, "Core pipe").group(1)
    if 'filepath.Join(config.stateRoot, "logs", "runtime.log")' not in runtime or 'filepath.Join(value.installRoot, "bin", "YimeBroker.exe")' not in runtime:
        fail("Core runtime path construction changed")
    if (product_key, state_dir, core_root, pipe) != (identity["product_key"], identity["state_directory"], identity["install_directory"], identity["pipe"]):
        fail("Core descriptor/runtime/maintenance identity mismatch")
    for required in (
        '$runKey = "Registry::HKEY_USERS\\$TargetUserSid\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"',
        '$uninstallKey = "Registry::HKEY_USERS\\$TargetUserSid\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\$productKeyName"',
        '$descriptor.identity.clsid -cne $clsid', '$descriptor.identity.profile -cne $profile',
        '$allowedExecutables.Contains([IO.Path]::GetFullPath($_.ExecutablePath))',
    ):
        if required not in manager:
            fail("Core ownership source anchor changed")
    binaries = [item["path"] for item in desc["go_binaries"]]
    for executable in ("bin/YimeBroker.exe", "bin/YimeCoreTrialRuntime.exe"):
        if executable not in binaries:
            fail("Core runtime missing from package descriptor")
    # Only fixed generated build inputs are hashed; dictionary contents never enter receipts.
    lock = json.loads(sources["tools/lexicon/data/yime_core_target.lock.json"])
    artifacts = []
    for role in contract["locked_artifact_roles"]:
        selected = [item for item in lock["artifacts"] if item["role"] == role]
        if len(selected) != 1:
            fail("locked build input role mismatch: " + role)
        item = selected[0]
        actual = digest(child(root, item["path"]))
        if actual != item["sha256"]:
            fail("locked build input hash mismatch: " + role)
        hashes[item["path"]] = actual
        artifacts.append({"role": role, "path": item["path"], "sha256": actual})
    products = {
        "rime-pime": {
            "product_version": version,
            "installer_leaf": "YIME-" + version + "-setup.exe",
            "numeric_file_version": numeric_version,
            "clsid": native_guid, "profile": ime["guid"].upper(),
            "language_id": tip.group(1), "install_directory": install_dir,
            "install_parent": "ProgramFiles32", "state_relative": app + "\\Rime",
            "state_parent": "APPDATA", "log_relative": log.group(1) + "\\" + log.group(2), "log_parent": "LOCALAPPDATA",
            "run_hive": "HKLM", "run_name": run.group(1), "uninstall_hive": "HKLM",
            "uninstall_key": uninstall,
            "endpoint": r"\\.\pipe\<username>\PIME\Launcher",
            "process_paths": [run.group(2), "go-backend\\" + server],
            "build_entry": "build.bat", "maintenance_entry": "tools/dev-install.ps1",
        },
        "yimecore": {
            "clsid": identity["clsid"], "profile": identity["profile"],
            "language_id": identity["language_id"], "install_directory": core_root,
            "install_parent": "ProgramFiles", "state_relative": state_dir,
            "state_parent": "LOCALAPPDATA", "log_relative": state_dir + "\\logs", "log_parent": "LOCALAPPDATA",
            "run_hive": "HKU/<initiating-SID>", "run_name": product_key,
            "uninstall_hive": "HKU/<initiating-SID>",
            "uninstall_key": "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" + product_key,
            "endpoint": pipe, "process_paths": ["bin\\YimeCoreTrialRuntime.exe", "bin\\YimeBroker.exe"],
            "build_entry": "tools/yimecore/build-local-product.ps1",
            "maintenance_entry": "tools/yimecore/manage-e6c-trial-install.ps1",
            "descriptor_version": desc["version"], "declared_go_payload_count": len(binaries),
        },
    }
    for field in ("clsid", "profile", "endpoint", "install_directory", "state_relative", "run_name", "uninstall_key"):
        if products["rime-pime"][field].lower() == products["yimecore"][field].lower():
            fail("cross-product identity collision: " + field)
    maintenance = maintenance_source_status(sources)
    transaction = transaction_source_status(sources)
    directed_anchor = one(r'^pub async fn wait_for_directed_stop\b',
                          sources["PIMELauncher/src/maintenance.rs"], "directed maintenance server")
    pending = [
        {"id": "DP1-PIME-DIRECTED-EXIT-04", "path": "PIMELauncher/src/maintenance.rs",
         "line": sources["PIMELauncher/src/maintenance.rs"].count("\n", 0, directed_anchor.start()) + 1,
         "status": "source_anchors_present_installed_acceptance_pending",
         "reason": "Root/SID/PID/start-bound shutdown, backend EOF and watchdog suppression anchors are present. This Python baseline does not execute their PowerShell/Rust tests. An installed live process-tree run remains pending."},
        {"id": "DP1-PIME-REGISTRY-05", "path": "tools/dual-product/rime-pime-ownership.ps1",
         "status": "source_anchors_present_native_acceptance_pending",
         "reason": "Initiating-SID, exact HKU cleanup and current-family registration readback anchors are present. This Python baseline does not execute the PowerShell contracts, native probes or registered profile. Legacy-only migration remains unwired and real UAC/profile acceptance remains pending."},
        {"id": "DP1-PIME-TRANSACTION-06", "path": "installer/installer.nsi",
          "status": "fixture_journal_and_replay_source_anchors_present_real_transaction_pending",
          "reason": "Pure replay/removal models and an isolated filesystem fixture-journal source contract now cover sealed records, hash-chain validation, typed privacy-safe snapshots, replay disposition and foreign-content preservation. This Python baseline only reads their source anchors and does not execute either PowerShell test. A real durable install journal, power-loss and cross-process replay, real registry recovery, installed exact removal, installer wiring, loaded-TSF upgrade handling and native installed/live acceptance remain pending."},
        {"id": "DP1-PIME-COMPILER-INPUT-07", "path": "tools/dual-product/rime-pime-nsis-toolchain-closure.ps1",
          "status": "fresh_compiler_stage_and_strict_interval_build_admission_wired_actual_migration_external_physical_limits_pending",
          "reason": "The pinned 303-file NSIS distribution is copied from held leases into a fresh compiler stage and the continuous membership monitor encloses the synchronous makensis interval before candidate admission. A tagged build-evidence schema fails closed in old validators and current receipt preparation requires its exact interval, stage-lease and build-logic-source shape. The tracked baseline executes neither lane nor the external DP1-T migration; the separate DP1-T record binds the completed actual canonical migration. Physical same-SID prevention and full toolchain closure remain false."},
        {"id": "DP1-PIME-RECEIPT-08", "path": "tools/dual-product/rime-pime-package-receipt-v2.ps1",
          "status": "retained_v2_supersession_and_current_interval_admission_wired_actual_migration_external_physical_limits_pending",
          "reason": "The strict receipt-v2 reader retains historical build-result-v2 read compatibility while new preparation and changed receipt supersession require the tagged membership-interval build evidence. Publish and recovery guard that boundary. The tracked baseline does not execute the external DP1-T migration; its separate evidence records a successful actual canonical migration and PS7 idempotent Resume. Hardware power-loss and directory-metadata durability remain unproved."},
        {"id": "DP1-PIME-INSTALLER-RECEIPT-09", "path": "tools/dual-product/rime-pime-installer-receipt-transaction.ps1",
          "status": "installer_receipt_transaction_contract_and_private_actual_adapter_wired_actual_migration_external_installed_transaction_pending",
          "reason": "The public API remains fixture-only while DP1-T grants its dedicated actual adapter a private, finally-scoped capability after exact archive, plan, fault-matrix and one-time authorization checks. The external DP1-T record proves actual artifact migration and recovery re-entry without running an installer. This Python baseline does not execute those steps or prove installed registration, rollback, removal, Runtime readiness, hardware-power-loss directory durability or active same-SID physical prevention."},
        {"id": "DP1-PIME-CANDIDATE-EVIDENCE-10", "path": "tools/dual-product/invoke-rime-pime-actual-canonical-migration.ps1",
          "status": "actual_archive_adapter_and_canonical_migration_complete_external_to_source_baseline",
          "reason": "DP1-S publishes a content-addressed archive outside Git worktrees. DP1-T deterministically rebases path-bound build evidence, binds an identical PS5/PS7 plan plus both full fault matrices to one exact authorization, and completes the actual canonical artifact migration through the private DP1-N capability while the public API still rejects the checkout. The tracked baseline verifies source and CI anchors only; the separate DP1-T evidence proves execution. Hardware-power-loss, directory-metadata and hostile same-SID physical prevention remain false."},
        {"id": "DP1-PIME-MAINTENANCE-RUNTIME-11", "path": "tools/dual-product/rime-pime-dp1u-maintenance-runtime-gate.psm1",
          "status": "isolated_preflight_and_source_gate_wired_ps5_ps7_execution_adapter_and_installed_acceptance_pending",
          "reason": "DP1-U now has a source-closed, PS5/PS7 CI-enforced supplied-evidence preflight before its fail-closed registration, rollback, exact-removal and Runtime gate. The preflight validates an exact external approval digest and target/product boundaries but never authorizes execution. A native execution adapter, a separately approved isolated target and all installed evidence remain pending; no installer or uninstaller was run. Hardware-power-loss and directory-metadata durability remain false."},
    ]
    unchanged = all(digest(child(root, path)) == expected for path, expected in hashes.items())
    if not unchanged:
        fail("source changed during baseline")
    return {"schema_version": "yime-dual-product-source-baseline-v1", "source_baseline_passed": True,
            "test_level": contract["test_level"],
            "source_manifest": hashes, "products": products, "locked_shared_build_inputs": artifacts,
            "known_pending": pending, "maintenance_source": maintenance,
            "transaction_source": transaction, "source_unchanged": unchanged,
            "dp1_full_implementation_passed": False, "dp2_physical_acceptance_passed": False,
            "installed_runtime_examined": False, "rime_executed": False, "system_state_mutated": False,
            "user_text_or_learning_read": False}


def canonical_windows_path(value):
    """Strict lexical fixture path; no filesystem traversal or device aliases."""
    if not isinstance(value, str) or not re.match(r"^[A-Za-z]:\\", value) or "/" in value or value.startswith("\\"):
        fail("absolute fixture path required")
    if any(p in ("", ".", "..") or p.endswith((".", " ")) or ":" in p for p in value[3:].split("\\")):
        fail("ambiguous fixture path")
    reserved = {"CON", "PRN", "AUX", "NUL", *("COM" + str(n) for n in range(1, 10)), *("LPT" + str(n) for n in range(1, 10))}
    if any(p.split(".")[0].upper() in reserved or any(ord(c) < 32 or c in '*?<>|"' for c in p) for p in value[3:].split("\\")):
        fail("device or wildcard fixture path")
    return value.lower()


class FixtureOwnership:
    """Executable future contract, deliberately not wired into existing installers."""

    def __init__(self, products, installed=()):
        self.products = copy.deepcopy(products)
        self.installed = set(installed)
        if not self.installed <= set(products):
            fail("unknown installed fixture")
        self.resources = {}

    def roots(self, product):
        value = self.products[product]
        base = r"C:\DP1-Fixture"
        install = base + "\\" + value["install_parent"] + "\\" + value["install_directory"]
        state = base + "\\" + value["state_parent"] + "\\" + value["state_relative"]
        logs = base + "\\" + value["log_parent"] + "\\" + value["log_relative"]
        return install, state, logs

    def can_start(self, product):
        if product not in self.products:
            fail("unknown product")
        return product in self.installed  # No lookup or requirement for the other product.

    def authorize(self, product, kind, target, *, sid=FIXTURE_SID, view="64", value_name=None, indirect=False):
        if product not in self.products or sid != FIXTURE_SID or indirect or view not in ("32", "64"):
            fail("ownership boundary rejected")
        item = self.products[product]
        install, state, logs = self.roots(product)
        if kind == "file":
            path = canonical_windows_path(target)
            if not any(path.startswith(canonical_windows_path(root) + "\\") for root in (install, state, logs)):
                fail("file outside selected product")
        elif kind == "stop_process":
            path = canonical_windows_path(target)
            if path not in [canonical_windows_path(install + "\\" + exe) for exe in item["process_paths"]]:
                fail("process does not belong to selected product")
        elif kind == "endpoint":
            if target != item["endpoint"]:
                fail("cross-product endpoint")
        elif kind == "registry":
            if not isinstance(target, str) or any(part in ("", ".", "..") or part.endswith((".", " ")) for part in target.split("\\")):
                fail("ambiguous registry path")
            normalized = target.lower()
            hive = "HKLM" if item["run_hive"] == "HKLM" else "HKU\\" + FIXTURE_SID
            run = (hive + r"\Software\Microsoft\Windows\CurrentVersion\Run").lower()
            if normalized == run:
                if value_name != item["run_name"]:
                    fail("Run parent or foreign value")
            else:
                roots = ["HKLM\\Software\\Classes\\CLSID\\" + item["clsid"],
                         "HKLM\\Software\\Microsoft\\CTF\\TIP\\" + item["clsid"],
                         "HKU\\" + FIXTURE_SID + "\\Software\\Microsoft\\CTF\\TIP\\" + item["clsid"],
                         hive + "\\" + item["uninstall_key"]]
                if not any(normalized == root.lower() or normalized.startswith(root.lower() + "\\") for root in roots):
                    fail("registry outside selected product")
        else:
            fail("unknown operation or unapproved purge")
        return True

    def apply(self, product, operations):
        """All-or-nothing simulated writes; dictionaries only, no OS actions."""
        for operation in operations:
            self.authorize(product, **operation)
        for operation in operations:
            key = json.dumps(operation, sort_keys=True)
            self.resources[key] = product


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, help="fresh .tmp/dual-product/dp1-*/baseline.json")
    args = parser.parse_args()
    output = Path(args.output).absolute()
    relative = output.relative_to(ROOT).as_posix()
    if not re.fullmatch(r"\.tmp/dual-product/dp1-[A-Za-z0-9-]+/baseline\.json", relative):
        fail("output is not a fresh DP1 receipt path")
    child(ROOT, relative)
    if output.parent.exists():
        fail("DP1 output directory must be new")
    receipt = source_baseline()
    # Only this baseline's pure-memory ownership sub-suite is loaded here. The
    # receipt's broader test_level inventories separately executed evidence
    # suites; it does not claim that this process ran those suites.
    import test_baseline
    suite = unittest.defaultTestLoader.loadTestsFromModule(test_baseline)
    result = unittest.TextTestRunner(stream=io.StringIO(), verbosity=0).run(suite)
    if (not result.wasSuccessful() or result.skipped or result.testsRun == 0 or
        test_baseline.OwnershipTests.receipt["source_manifest"] != receipt["source_manifest"]):
        fail("pure ownership fixture suite failed or source snapshot changed")
    receipt["fixture_contract"] = {
        "passed": True, "tests_run": result.testsRun, "failures": len(result.failures),
        "errors": len(result.errors), "skipped": len(result.skipped),
        "level": "pure-memory-model-not-installer-integration", "os_symlink_created": False,
    }
    if not all(digest(child(ROOT, path)) == expected for path, expected in receipt["source_manifest"].items()):
        fail("source changed before receipt")
    receipt["run_id"] = str(uuid.uuid4())
    output.parent.mkdir(parents=True, exist_ok=False)
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(receipt, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps({"source_baseline_passed": receipt["source_baseline_passed"],
                      "test_level": receipt["test_level"],
                      "source_count": len(receipt["source_manifest"]),
                      "fixture_tests_passed": result.testsRun,
                      "pending_count": len(receipt["known_pending"]), "output": relative,
                      "dp2_physical_acceptance_passed": False}, ensure_ascii=False))


if __name__ == "__main__":
    main()
