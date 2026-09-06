# DP1-O: exact-HEAD isolated current Rime/PIME candidate

Affected product: the independent Rime/PIME product. YimeCore, the installed products, the default input method and production user data are outside this change. DP1-O rebuilt one unsigned, disabled current-source candidate in a detached exact-HEAD clone, completed static archive inspection, finalized a strict receipt-v2 and converted its evidence to the clone-local content-addressed store. It did not run an installer, uninstaller, signing tool or product process, and it did not publish any product artifact into the actual checkout.

## Source and runner identity

The implementation was developed in three commits:

| Role | Commit |
| --- | --- |
| isolated current-candidate runner and contract | `22a0f2eef98696aadc299ebb2392390cba7509ee` |
| preflight and source-identity hardening | `61a5d385f0fb7e8d23bf68cac79a3407eb4fed7e` |
| clone-local end-of-line policy | `ba0e2dc2d42fee66ac4e707800c43c2630794f7a` |

The final runner executed the tracked `tools/dual-product/run-rime-pime-isolated-candidate.ps1` from exact HEAD `ba0e2dc2d42fee66ac4e707800c43c2630794f7a`, tree `c35a67406e4d3292139dcd7d5d82a37bdb8ec0e5`. Its worktree blob and HEAD blob were both `3890f311bf34967e381989b55c91531205817e40`. The runner created a local clone with an exact, delimiter-protected Git argument vector, disabled hard links, omitted checkout during clone, pinned clone-local `core.autocrlf=false`, and only then checked out the exact commit detached. Ignored actual publication artifacts were required to be absent from the clone.

## Verification and tracked handoff

The final sealed outcome is `.tmp/dual-product/dp1-o-candidate-20260907-c/result.json`, SHA-256 `d922c851ef74895a65424248f176d76d30cdd6cccdd5cd1385f88afdb961af0a`. Its status is `pass`. The tracked [DP1-O evidence record](../testing/dual-product/2026-09-07-dp1-o-isolated-current-candidate.json), SHA-256 `4190b37dbd4c7e4deb5b99d0b4df98efd408be4bfa64d52c25eae1a613f4dce2`, binds the final outcome, exact source and supporting identities; its sidecar is stored alongside it. The runner output itself remains repository-local transient evidence under `.tmp`, not an archival location.

## Candidate and static evidence

The isolated chain built current source, sealed the package plan, built the disabled x86/x64 installer, wrote and checked the StaticOnly build manifest, performed read-only postbuild extraction, finalized receipt-v2, retained its directly bound evidence by content hash, and passed the strict reader. The resulting identities are:

| Evidence | Exact identity |
| --- | --- |
| candidate | `repo/installer/YIME-1.4.0-dev-setup.exe`; 41,431,585 bytes; SHA-256 `c55905a0c0cf518fb4eeda10f69d95c6d357b036461560a051accc67766699e2`; unsigned and disabled |
| current build result | SHA-256 `78f8bfc5c067b8502f48c4fd33977482006fb08fe3a5cd948e14aaa59f12c29c`; schema `yime-rime-pime-staged-nsis-build-result-membership-interval-v1` |
| PowerShell 7 postbuild result | SHA-256 `da64f083cdd386115ea76fb7ea23435e86dfa6aa93a098aef4aeb42fc0c6bc20` |
| independent Windows PowerShell 5.1 postbuild result | SHA-256 `4124c20af87da5c335becf63d53c3cf196254a1d8c6b44b2022b1449c994c005` |
| static archive membership | 181 outer installer entries and 11 nested uninstaller entries in both postbuild reads |
| generated uninstaller bytes | SHA-256 `584a332db6e2e057045a72768962ccace78c1f7019803189e2a64d013d7e4198` in both postbuild reads; inspected, not executed or trusted |
| retained strict receipt-v2 | SHA-256 `0575afbf3138e24861a014dcb0bafadad1800c5b506c85a4db4dc99f03107f11`; `evidence_artifacts_durable=true` only within the declared clone-local scope |

The retained receipt passed the strict reader under Windows PowerShell 5.1 and PowerShell 7. Its durability scope is exactly `isolated-clone-content-addressed-process-interruption-protocol`: the clone can resolve its directly bound retained objects after transient build roots disappear and can use the existing process-interruption recovery contract. Because the entire clone and store remain below the outer `.tmp` result root, this is not durable archival evidence outside `.tmp`.

The existing build step also produced ARM64 cross-build outputs incidentally. The admitted package plan and candidate remain x86/x64. No ARM64 installer, native execution, registered host or live-host evidence was produced.

## Actual checkout protection and migration decision

The protected actual-checkout snapshot was SHA-256 `7c3599619af5d82130f7852fc3c53b96302b2128cde86b54c69dba8c982b4ead` both before and after the run. The actual state remained:

| Actual protected item | Identity after DP1-O |
| --- | --- |
| canonical receipt | SHA-256 `c18d1202ad78dcd6f8c1f74b34859a83489adb01fb156fa4e2546160aff5b0be` |
| canonical sidecar | SHA-256 `ae28a8f7ed01aa784ff657f465616d794204ca624c680fa4c159a4fde15d5a74` |
| actual installer | `installer/YIME-1.4.0-dev-setup.exe`; 41,456,428 bytes; SHA-256 `32a7d66e06284d512675e40495b6e244a23630d2e368ac2cf73ce652e623efe2` |
| actual retained evidence root | `installer/receipt-evidence` absent |

The isolated candidate and actual canonical receipt both declare product version `1.4.0-dev` and the same installer leaf `YIME-1.4.0-dev-setup.exe`. Their bytes differ, but DP1-N deliberately requires distinct old and new versioned installer paths as well as distinct hashes. Therefore `distinct_versioned_installer_leaf_for_dp1n=false`, `actual_canonical_migration_admitted=false`, and the DP1-N identity-replacement transaction was not invoked. Renaming or overwriting the same leaf would weaken that reviewed contract and is not allowed. A later actual migration requires a separately reviewed new product version and distinct installer leaf, a fresh candidate built from that identity, and a new explicit migration decision.

## Concrete development regressions

The development trials exposed and fixed the following concrete pipeline defects:

- Sending an empty array through the PowerShell pipeline into `ConvertTo-Json` emitted no JSON value and broke protected-snapshot preflight. The runner now uses explicit `-InputObject` serialization so an empty collection remains an array.
- The first file guard treated Git for Windows' legitimate application hard-link layout as if it were a mutable payload hard link. Tool executables now have a separate reparse/ADS guard; strict hard-link rejection remains in force for source, evidence and protected product leaves.
- Windows PowerShell 5.1 could throw a provider `NullReferenceException` when `Remove-Item` cleaned the synthetic junction negative. Cleanup now verifies the exact junction leaf and deletes only that leaf through the .NET directory API.
- The initial runner used the wrong postbuild result leaf and the wrong nested-uninstaller property name. It now reads the sealed `evidence/result.json` and the producer's `uninstaller_archive` object, while preserving the public summary name `nested_uninstaller_archive_entry_count`.
- Trial `b` reached the disabled build but then reported `go-backend/go.mod` as stat-dirty because clone checkout and build observed different CRLF/LF policy. Pinning clone-local `core.autocrlf=false` before checkout removed that source-identity ambiguity rather than ignoring dirty state.
- Git clone, config and checkout calls are locked to exact reviewed argument vectors, including the `--` separator. The executed runner must be its tracked repository path and its `git hash-object --path` result must equal the exact HEAD blob, preventing an edited or different runner from reporting an exact-HEAD build.

The early `a` attempt created no sealed output and is not evidence. Trial `b` is retained as a failure at `.tmp/dual-product/dp1-o-candidate-20260907-b/result.json`, SHA-256 `f1b072659cdf270e696742e3c6feb317f3a646a0780bfb55c9acddec6f9c121f`; it must not be relabelled as passing. Only final trial `c` is the passing runner outcome above.

## Explicit non-claims and next work

DP1-O establishes one exact-source isolated candidate and static evidence chain. It does not establish complete NSIS or non-OS toolchain input closure, final payload closure, generated-uninstaller trust, signature or delivery admission. It does not guarantee retention of the outer `.tmp` directory, archive evidence outside `.tmp`, directory-metadata durability or hardware power-loss survival, and it does not physically exclude a hostile same-SID writer.

No actual installer or receipt was published. No real transaction adapter was wired. Neither installer nor uninstaller was executed; no installation, upgrade, uninstall, registry, registered-host, live-host, maintenance, default-input-method or production-user-data action occurred. ARM64 remains cross-build-only and has no native package or host acceptance here.

The next ordered work must first establish a reviewed distinct versioned installer identity and rebuild the isolated candidate. Only then can the DP1-N transaction be reconsidered for a separately authorized actual canonical migration. Outer evidence archival, full closure, directory/power-loss durability, real adapter work, signing, delivery and installed acceptance remain independent later gates.

The dual-product decision is unchanged: Rime/PIME and YimeCore may be installed separately or together, and each remains independent of the other's runtime, installation, maintenance, writable state and recovery. DP1-O creates no shared runtime or cross-product dependency and does not promote DP1, DP2, DP3, L5 or L6.
