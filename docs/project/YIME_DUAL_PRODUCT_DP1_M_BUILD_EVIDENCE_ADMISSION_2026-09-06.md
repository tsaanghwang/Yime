# DP1-M: Rime/PIME build-evidence membership-interval admission

Affected product: the independent Rime/PIME product. YimeCore, both installed products, the default input method and production user data are outside this change. This work changes source contracts and fresh isolated fixtures only. It does not build or publish a complete product candidate, migrate the checkout's actual canonical receipt, install or uninstall either product, or run a product process.

## Outcome

DP1-K already placed a continuous membership monitor around the synchronous `makensis` interval in a fresh compiler stage. DP1-M now makes that result mandatory for every newly prepared Rime/PIME package receipt and every changed receipt-v2 successor. The current builder emits the deliberately tagged schema `yime-rime-pime-staged-nsis-build-result-membership-interval-v1`. Its 91 properties, the nested nine-property interval object and their cross-bindings are exact. An old validator cannot mistake the tagged name for a generic numeric `result-vN` successor.

The interval admits `notification_batch_count` from 1 through `Int32.MaxValue`; it is not fixed to one. The clean fixture observed one batch. The fixed compiler input inventory remains 303 files and 17 directories, held through 303 file leases, 19 directory leases and two anchor-directory leases. The interval must be armed before `makensis`, disarmed after the compiler returns, complete without overflow or callback errors, observe zero membership events, and bind the exact fresh compiler-stage path, 303 file leases and 19 directory leases. These controls detect and reject tested transient file, directory, rename and root-file membership changes. They do not physically prevent a hostile same-SID writer.

New receipt preparation rejects legacy build-result-v2, unknown schemas, bare numeric future versions, incomplete or extra current properties, scalar/array type substitutions, inconsistent counts and paths, and a current build result outside its declared fresh `.tmp/dual-product` build root. Historical build-result-v2 remains readable only under its exact legacy schema and cannot carry any of the four current interval fields. A same-digest historical receipt may be converted to retained storage without changing its build claim; a changed successor must carry current tagged evidence in both `Publish-RimePimePackageReceiptV2Supersession` and `Resume-RimePimePackageReceiptV2Publication`.

## Bound evidence

Preparation and the strict reader now validate the evidence values already held by their sealed JSON leases instead of reopening those paths for semantic validation. The current admission requires:

- the exact seven-property package plan with ordered `x86`, `x64`, the fixed 20 PE source rows, lowercase SHA-256 values, and architecture-aware PE minimum sizes;
- the complete copied-content manifest, deterministic content-tree digest, exact package-plan bindings and fixed 22 staged PE destinations;
- the payload spec's exact current source-to-destination declaration, including a single fixed Go source tree bound to the sealed versioned Go inventory;
- the deterministic six-macro ASCII NSIS include and its exact 21-property receipt, with leased include bytes equal to the document derived from the sealed manifest;
- all 16 ordered build-logic source paths and hashes, re-read under leases during preparation;
- the repository-fixed NSIS toolchain lock, checked against the code-pinned canonical document and cross-bound to postbuild 7-Zip, parser-library and `makensis` identities;
- the canonical `installer/installer.nsi` source path, the current predecessor and publication paths, and direct UTF-16 search for all four sealed digests in the leased disabled installer bytes;
- strict JSON scalar types for predecessor, outer receipt, current build and required postbuild producer fields. Array-wrapped strings and numeric strings cannot satisfy string, hash, byte or count fields.

Retained current receipts additionally retain the payload spec, Go inventory and toolchain lock by digest. The retained reader verifies those stored objects. It does not rehash a later checkout's build-logic source files; their preparation-time leased hashes are retained as historical evidence.

The current builder also leases 15 prebuild controls and enforces the total leased-input formula. Their identities are not all materialized as individual receipt rows: in particular, the three NSIS locale files are currently covered by the lease total rather than per-file hashes. DP1-M therefore does not claim complete prebuild-input content identity or reproducible build closure. That finer-grained identity is required before any later complete compiler-input or delivery-closure claim.

## Concrete regressions closed

The isolated negative cases demonstrated and closed these evidence-acceptance regressions:

- generic future-schema matching could not distinguish new interval semantics from an unreviewed numeric version;
- a changed receipt successor could retain or mask legacy bound build evidence;
- receipt summaries could be resealed with incomplete plan, manifest, spec, inventory, include, toolchain or installer-source relationships;
- PowerShell scalar coercion could let one-element JSON arrays or numeric strings imitate producer-defined strings, hashes, byte lengths or counts;
- the receipt could name a repository-local `.nsi` other than the builder's fixed `installer/installer.nsi`;
- a self-reported successful raw-binding flag could stand in for checking the leased installer bytes;
- older isolated plan-binding fixtures no longer represented the fixed 20-artifact current plan and were updated to exercise the strict current contract.

No installed-input regression, host crash, user-text loss or daily-use behavior regression was observed or tested in DP1-M; none is inferred from these source and fixture checks.

## Verification

The final current-source runs passed under both Windows PowerShell 5.1 and PowerShell 7:

| Contract | Result per shell |
| --- | ---: |
| strict receipt-v2 preparation and reader | 95/95 |
| retained receipt publication and recovery | 41/41 |
| real minimal `makensis` compiler interval | 7/7 |
| package staging | 31/31 |
| deterministic NSIS stage include | 20/20 |
| staged-build lease/publication | 12/12 |
| NSIS toolchain closure | 14/14 |
| membership monitor | 15/15 |
| postbuild extraction | 50/50 |
| installer static analysis | 42/42 |
| payload closure | 29/29 |
| receipt no-downgrade | 7/7 |
| registration-completeness source guard | 36/36 |

Build guards passed under both shells with `-SkipPackagedRime`. The Python source/ownership suite passed 52/52. The fresh baseline contains 125 contract source paths and 132 hashed source inputs; it does not claim that the Python process ran the PowerShell suites.

The structured record is [2026-09-06-dp1-m-build-evidence-admission.json](../testing/dual-product/2026-09-06-dp1-m-build-evidence-admission.json). It binds the final result artifacts and implementation sources by SHA-256. All generated evidence remains under fresh `.tmp/dual-product` roots.

## Preserved boundaries and next work

The actual canonical receipt remains byte-for-byte unchanged at SHA-256 `c18d1202ad78dcd6f8c1f74b34859a83489adb01fb156fa4e2546160aff5b0be`; it still binds historical `yime-rime-pime-staged-nsis-build-result-v2`, reports `evidence_artifacts_durable=false`, and has no `installer/receipt-evidence` store. No candidate or canonical outcome was relabelled.

`active_same_sid_transient_tree_membership_interference_excluded`, non-OS compiler-input closure, full NSIS toolchain closure, final payload closure and delivery admission remain false. Windows directory leases and monitoring do not prove hostile same-SID physical prevention, continuous object identity, directory metadata durability or hardware power-loss recovery.

The next ordered development item is an isolated installer-plus-receipt identity replacement transaction, followed by a separately reviewed full candidate build, static verification and actual canonical migration. Complete per-file identity for all 15 prebuild controls must be added before claiming reproducible compiler-input closure. Real transaction adapters, signing, installation, registered/live-host acceptance, daily-use confirmation and any production-state change remain separately gated. DP1, DP2, DP3, L5 and L6 are not promoted by this work.
