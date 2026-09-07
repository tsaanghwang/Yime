# DP1-Q: candidate-evidence archive fixture and actual-migration review contract

Affected product: the independent Rime/PIME product. YimeCore, installed products, the default input method and production user data are outside this change. DP1-Q adds a fixture-gated evidence-archive implementation and a pure-data review of prerequisites for a later actual canonical installer-plus-receipt migration. It does not archive the DP1-P candidate outside this repository and does not admit or execute the migration.

## Narrow outcome

- Fixture candidate-evidence archive protocol: **PASS**, PS5 and PS7 each 24/24.
- Pure actual-migration review contract: **PASS**, PS5 and PS7 each 23/23.
- Actual off-repository archive, actual-evidence review and canonical migration: **not performed and not admitted**.

The implementation is commit `4c524cb5c629146e2e3c5963e47f76e506436b62`, tree `39a5582ba65d63cd90e4054f31f808a8a3f07f5d`. The tracked [structured evidence](../testing/dual-product/2026-09-07-dp1-q-candidate-evidence-archive-and-actual-migration-review.json) binds that source, the passing suites, the unchanged canonical file identities, the corrected development-gate defects and every non-claim. Its SHA-256 sidecar is stored alongside it.

## What the fixture archive proves

The public API consists of `Publish-RimePimeCandidateEvidenceArchive`, `Resume-RimePimeCandidateEvidenceArchive` and `Read-RimePimeCandidateEvidenceArchive`. It can mutate only a fresh case below `.tmp/dual-product/dp1-candidate-evidence-archive-test-*/cases/*`; the case-sibling `archive` directory models moving beyond a source `outer-tmp` directory but remains inside this repository's transient `.tmp` tree.

Within that boundary, the contract fixes SHA-256-addressed objects and sealed root, manifest, head, intent and completion records. Writes use `CreateNew`, write-through flushing and same-volume `MoveFileEx` without replacement. Recovery revalidates source evidence before a complete intent pair and rolls forward without source after it. Interrupted `.writing-*` leaves are quarantined outside the capsule before final exact-member validation. The reader binds each object filename to its actual digest and binds unique runner-result, retained-receipt and installer rows back to source HEAD/tree, version, path, hash and bytes.

The negative matrix covers ten independent-process hard exits, shared lock contention, foreign final-root races, source sidecar corruption, missing retained objects, same-length object replacement with a rewritten sidecar, semantic resealing, scalar-array coercion, zero lengths, non-canonical paths, and hardlink, ADS and reparse inputs. The committed capsule can be reopened after the fixture source is moved away.

This is not a real evidence archive. It does not establish outer `.tmp` retention, directory-metadata or hardware-power-loss durability, or physical exclusion of an actively hostile same-SID process.

## What the pure review proves

`Get-RimePimeActualMigrationReview` is the module's only export. It accepts pure data for seven groups: identity admission, old canonical state, successor state, off-repository archive evidence, a dedicated actual-checkout adapter, one-time authorization and downstream boundaries. It validates exact fields, scalar types, canonical and cross-bound paths, digests, versions and the ordered write-set contract without exposing filesystem, registry, process, build, installation, signing or product actions.

A complete synthetic object can produce `review_ready=true`; this tests the review truth table only. It is neither actual evidence nor user authorization. Actual evidence was not supplied to this function, so `actual_evidence_review_executed=false` and `actual_evidence_review_ready=false`. Every result always keeps actual migration admission and execution false and requires a separate execution gate.

## Final verification

| Suite | Result | Sealed result SHA-256 |
| --- | --- | --- |
| Candidate archive, Windows PowerShell 5.1.26100.9168 | 24/24 | `eed8ccdc2548346c308bacac76600edebf620b4521285a8d40872a512f841190` |
| Candidate archive, PowerShell 7.6.5 | 24/24 | `e925963311a11ead921d9dc89dab3c0ef9c19faf72da3857ca406ed8e948657b` |
| Pure migration review, PS5-selected run | 23/23 | `a19f41cb240b09513d77347ca80518e0dc83dc780ec288272a8036e74c7d9f8b` |
| Pure migration review, PS7-selected run | 23/23 | `a19f41cb240b09513d77347ca80518e0dc83dc780ec288272a8036e74c7d9f8b` |
| Current-source baseline after implementation commit | 147 sources; 64/64; 7 pending | `11bebe01b0b37fc5ab1ab40e0b90cb7368887f65c1536dcf07380bbf91a6e463` |

Build guards passed under both shells with `-SkipPackagedRime`. The migration-review JSON deliberately does not self-report its shell; the selecting commands and isolated output paths distinguish the two runs. Both result files are byte-identical.

Read-only comparison after the implementation commit found the actual canonical receipt, sidecar and `YIME-1.4.0-dev-setup.exe` at the same byte identities recorded by DP1-P. The actual `YIME-1.4.0-dev.1-setup.exe` leaf and `installer/receipt-evidence` directory remain absent. No aggregate protection snapshot was recomputed, so the record says exactly that the individual identities match, not that a new DP1-P-style snapshot was produced.

## Concrete development-gate regressions corrected

No installed-product regression was observed because no installed product was run. The final suites include regressions for defects found during implementation:

- data-only `intent.json` was initially treated as durable post-intent state; recovery now requires the intent sidecar too;
- an interrupted `.writing-*` object could remain in the staged capsule; it is now quarantined before exact-set validation;
- object byte counts were checked without explicitly matching actual digest to content-addressed path and manifest row; same-length replacement is now rejected;
- a self-consistent reseal could remove the semantic runner/receipt/installer mapping; those rows and their underlying objects are now uniquely rebound and reread;
- scalar arrays, zero build-manifest length, a non-false clone `core.autocrlf` value and non-canonical member paths were insufficiently constrained;
- the first pure review could execute a `ScriptProperty` getter, accept malformed identity fields, accept path/repository binding gaps, or leave downstream readiness true after an upstream failure;
- the first PS5 ADS negative fixture used an unsupported .NET ADS path spelling and failed before the intended check; the shared FileSystem `-Stream` form now exercises both shells.

These are source/test-gate corrections. They did not touch installed Rime/PIME, YimeCore local.12, product processes, registry/profile state, the default input method, user data, user text or historical payloads.

## Remaining ordered gates

DP1-Q does not call DP1-N, publish the successor installer, wire an actual-checkout adapter, consume one-time authorization, trust the generated uninstaller, establish final payload or full NSIS input closure, sign or deliver a binary, or prove installed/registered/live-host or ARM64-native behavior. DP1, DP2, DP3, L5 and L6 remain incomplete.

The next gate is DP1-R: full payload, non-OS/NSIS input closure and generated-uninstaller trust. DP1-S then covers a real off-repository archive plus directory-metadata, power-loss and hostile same-SID durability. DP1-T may add a dedicated actual adapter and exact one-time authorization before any canonical migration; DP1-U then covers registration convergence, dimensional rollback, concurrent-safe removal and non-elevated Runtime readiness. Installation and tagged-release hard blocks remain in place throughout.

The dual-product decision is unchanged: Rime/PIME and YimeCore may be installed alone or together, and each remains independent of the other's runtime, installation, maintenance, writable state and recovery.
