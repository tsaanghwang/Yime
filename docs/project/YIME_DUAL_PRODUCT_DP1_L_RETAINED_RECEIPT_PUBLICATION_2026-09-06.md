# DP1-L: retained Rime/PIME receipt evidence and v2 supersession

Affected product: independent Rime/PIME. YimeCore and installed products are outside this change. This implements the canonical publication API and exercises it against synthetic repository roots; it does not migrate this checkout's actual canonical receipt or run a compiler, installer, uninstaller, signing tool, or product process.

## Storage and publication contract

`tools/dual-product/rime-pime-receipt-v2-store.ps1` is loaded by the existing receipt-v2 module. Its explicit `Publish-RimePimePackageReceiptV2Supersession` API takes an expected current receipt digest and a strictly validated v2 successor. Both receipts must describe the same canonical installer path and bytes. Replacing an installer is a separate package transaction; neither this API nor the existing v1 builder bypasses the no-downgrade guards.

Evidence is retained under `installer/receipt-evidence/sha256/<prefix>/<sha256>.blob`, outside `.tmp`. The store contains the directly bound package plan, stage manifest, include and include receipt, build result, static postbuild result, installer source, disabled installer bytes, and historical v1 receipt. Original v2 receipt bytes are also retained. Objects are hash-checked, have SHA-256 sidecars, and are never overwritten to repair corruption or automatically garbage-collected. Missing object sidecars can be recreated from fully verified object bytes before publication. Unpublished temporary files are ignored and retained after interruption.

The retained v2 representation changes only `evidence_artifacts_durable` to true. Existing path fields remain provenance, while the strict reader resolves retained evidence exclusively through its digest; it never falls back to transient files when a retained object is absent or corrupt. Legacy receipts with false keep their existing behavior. The strict reader also verifies the retained v1 predecessor. This preserves the exact original receipts without relabeling their historical retention outcome. The store retains the receipt's direct evidence set, not an entire reproducible compiler distribution or all payload files named inside a stage manifest.

Publication uses the same exclusive `.rime-pime-publication.lock` as existing package publication. It validates and retains both generations before atomically publishing `pending.json`. The intent binds the previous original receipt, its retained conversion, the retained successor, and the unchanged installer path. Recovery checks the previous conversion, both strict receipts, every retained object, and the actual disabled installer bytes. Object read leases deny write/delete through publication. The canonical JSON and then its sidecar are replaced using flushed sibling temporary files and `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)`. Completion renames the intent to a retained `completed-<intent-sha256>.json` record.

The canonical JSON/sidecar pair is not a single atomic object. Readers reject a mixed pair during interrupted publication. `Resume-RimePimePackageReceiptV2Publication` reacquires the same lock and rolls forward only recognized old/new combinations. Unknown receipt bytes, unknown sidecars, corrupt objects, and impossible ordering fail closed; pending work blocks successors. Repeated recovery is idempotent. No exception handler discards the persistent intent or relies on process-local rollback flags.

Retention here means persistent local evidence independent of transient build roots, with flushed file writes and write-through same-volume publication. It is not an independent backup, a trusted-signature claim, physical object immutability, verified hardware power-loss recovery, or proof against a hostile same-SID writer racing direct leaves, members, or ancestor directories outside the shared lock protocol. Directory metadata/power-loss acceptance remains pending. The store must be retained or backed up together with the receipt; ordinary transient-output cleanup must not remove it. All delivery, signing, final-payload, installed/live acceptance, and product-execution flags remain false.

## Explicit use

Import `tools/dual-product/rime-pime-package-receipt-v2.psm1`, then call:

```powershell
Publish-RimePimePackageReceiptV2Supersession `
    -RepoRoot $repo `
    -ReceiptPath $strictV2SuccessorPath `
    -ExpectedPreviousDigest $reviewedCurrentReceiptSha256 `
    -HistoricalV1Path $originalSealedV1Path

# After an interrupted publication; no successor or original build root needed:
Resume-RimePimePackageReceiptV2Publication -RepoRoot $repo
```

For retention-only migration, the successor may be the current canonical v2 receipt itself. Supply the exact historical v1 file when its digest is not already in the store; no search of other repositories, installed products, or historical payload execution occurs. Later retained-to-retained publications do not need the transient historical path. The old v1-to-v2 finalizer remains a distinct API and now leases the newly imported store source along with its existing execution logic.

## Verification

`test-rime-pime-receipt-v2-store.ps1` uses only fresh synthetic roots under `.tmp/dual-product`. It covers loss of original evidence paths, repeated retained supersession, eight child-process hard-exit boundaries (object temp/data, all objects, intent temp/commit, receipt, sidecar, completion), fresh-module recovery, shared-lock rejection from another process, stale CAS, v1 rejection, corruption, false retention, hardlinks, pending-transaction conflicts, and an actual sidecar sharing failure. It also checks the exact six-function public module surface; strict pending-intent JSON, types and leased identity; required sidecars for every retained raw object; and malformed canonical sidecars including double-LF and lone-CR tails. `-CheckPattern` selects a focused regression; CI runs the full suite under Windows PowerShell 5.1 and PowerShell 7. Child processes are test PowerShell instances only.

The existing strict receipt, no-downgrade and Python baseline suites remain required. The baseline distinguishes implementation wiring from actual canonical migration and does not promote DP1, DP2, DP3, L5 or L6 to complete.

The first local validation remains historical: Windows PowerShell 5.1 and PowerShell 7 each passed 16/16 store/recovery checks, 26/26 strict receipt checks and 7/7 no-downgrade checks. Python baseline tests passed 49/49; `git diff --check` passed. The [initial retained verification record](../testing/dual-product/2026-09-06-dp1-l.json) binds only that earlier implementation and result set. Two implementation/test issues found during that validation were corrected: cross-process sharing errors are checked by Windows error code instead of localized text, and PS7 JSON timestamp coercion is disabled when reading receipts for reserialization.

## Strict reader follow-up

The reader now validates JSON syntax before PS5/PS7 conversion, rejecting duplicate (including case-folded and escaped) keys, comments, trailing commas and excessive nesting. It revalidates the bound build and postbuild evidence contracts and checks stage, include, predecessor and receipt summary consistency. A resealed digest cannot hide a contradictory execution flag, product version, stage count or archive identity. Retained v1 evidence must satisfy the original predecessor contract and match the receipt's package identity.

Recovery after a committed intent now runs in an independent PowerShell process, including receipt/sidecar interruption and completion boundaries. The earlier record's module-reload recovery remains historical evidence, not retroactively independent-process recovery. Temporary object filenames use a short sibling GUID name to avoid exceeding PS5 path limits by appending it to an existing digest filename.

The [reader follow-up verification record](../testing/dual-product/2026-09-06-dp1-l-reader-followup.json) preserves the later 25/25 suite and its source hashes separately from the initial record, including failed trial outputs. It remains historical after the hardening below.

## Final recovery hardening follow-up

The final current-source runs passed 36/36 store/recovery checks, 26/26 strict receipt checks and 7/7 no-downgrade checks under both Windows PowerShell 5.1 and PowerShell 7. The registration-completeness source guard passed 36/36 under both shells, the build guards passed under both shells, and the Python baseline tests passed 51/51 with a 132-file source manifest. A failed PS7 trial concretely exposed that the former `.NET` `$` tail anchor accepted double-LF and lone-CR sidecars; the replacement uses absolute `\A...\z` anchoring. A separate PS5 trial exposed overlong negative-fixture paths before their assertions; shortened names then exercised the intended negatives in the final 36/36 run.

The [DP1-K/DP1-L hardening record](../testing/dual-product/2026-09-06-dp1-k-l-governance-hardening.json) binds the final result artifacts and current implementation sources by SHA-256 while retaining both failed trials as non-passing evidence. This work does not publish or refresh the actual canonical receipt. It remains `c18d1202ad78dcd6f8c1f74b34859a83489adb01fb156fa4e2546160aff5b0be`, with `evidence_artifacts_durable=false` and no `installer/receipt-evidence` directory. A new build-result admission schema that requires DP1-K interval evidence, followed by the separately pending installer-identity transaction, must precede any claim that a newly compiled package supersedes the canonical package. Directory metadata/hardware power-loss durability, hostile same-SID path or ancestor replacement, signing and installed acceptance remain unverified.
