# DP1-N: isolated Rime/PIME installer-plus-receipt identity transaction

Affected product: the independent Rime/PIME product. YimeCore, both installed products, the default input method and production user data are outside this change. DP1-N defines and exercises an installer-plus-receipt identity replacement contract only in fresh repository-local `.tmp` fixtures. It does not migrate this checkout's actual canonical receipt or installer, build a complete product package, run an installer or product process, or connect the contract to a real installation transaction adapter.

## Contract boundary

`tools/dual-product/rime-pime-installer-receipt-transaction.psm1` exposes only `Publish-RimePimeInstallerReceiptTransaction` and `Resume-RimePimeInstallerReceiptTransaction`. Both entry points accept an exact fixture repository shaped as `.tmp/dual-product/dp1-package-receipt-v2-test-dp1n-*/cases/*/repo`. The real checkout root, paths outside the fixture case, reparse traversal and non-canonical transaction paths fail closed.

One sealed intent binds the original old receipt, its retention-only conversion, the new receipt, and both versioned installer identities by path, SHA-256 and byte count. Its operation ID is derived from that complete ordered identity. The old and new installer paths must be distinct direct leaves of the form `installer/YIME-<product_version>-setup.exe`, and their SHA-256 identities must differ. The successor must pass the strict receipt-v2 reader, use durable content-addressed evidence, and carry the current tagged membership-interval build-evidence schema introduced by DP1-M. A changed legacy successor cannot enter this transaction through either publication or recovery.

The transaction shares the existing canonical publication lock. All receipt and evidence objects needed by both generations are retained and leased before canonical publication. The old physical installer is opened and held under its exact identity; DP1-N never moves, deletes, overwrites or recreates it. The new retained installer object and, after publication, the new physical installer are likewise held and rechecked through completion.

## Durable ordering and recovery

The new installer is staged before the durable intent is published. A fresh attempt copies it from the retained object into a unique `CreateNew` sibling, uses write-through I/O and `Flush(true)`, verifies the completed copy, and then renames it to the deterministic operation stage with `MoveFileExW(MOVEFILE_WRITE_THROUGH)` and no replace flag. An interruption during the unique copy leaves an inert orphan; a later fresh `Publish` does not adopt or modify that orphan. A fully verified deterministic stage may be reused by the same fresh operation.

The intent uses the same pattern: it is first written and flushed to a unique sibling, then moved without replacement to `pending.json`. An interruption before that move remains a pre-intent state and is retried through a fresh `Publish`; it is not treated as committed recovery work. Once `pending.json` exists, the policy changes permanently to roll-forward. A new `Publish` refuses the pending transaction, while `Resume` leases and validates the exact intent and converges only through recognized states. There is no post-intent rollback or cleanup path.

After durable intent, exactly four public state families are accepted:

1. The canonical receipt and sidecar are both old, the exact deterministic installer stage exists, and the new versioned installer leaf is absent.
2. The canonical pair is still old, the deterministic stage has been atomically moved away, and the exact new physical installer exists.
3. The canonical receipt is new while its sidecar still names the old digest, and the exact new physical installer exists.
4. The canonical receipt and sidecar are both new, and the exact new physical installer exists; completion then atomically renames the leased pending intent to its deterministic completed record.

The first family is the durable-intent form of the separately permitted pre-intent stage. Receipt advancement without the exact new installer, old-receipt/new-sidecar ordering, foreign canonical bytes, a missing or foreign stage, and simultaneous exact target plus deterministic stage are not repaired heuristically; they fail closed. Repeating `Resume` after completion validates the current strict receipt and its physical installer and performs no new mutation.

## No-replace and identity rules

The ownership-changing moves use `MoveFileExW` with flags exactly `8` (`MOVEFILE_WRITE_THROUGH`) and deliberately omit `REPLACE_EXISTING`:

- unique installer copy to deterministic stage;
- deterministic stage to the new versioned installer leaf;
- unique intent copy to `pending.json`;
- `pending.json` to the deterministic completed record.

The canonical receipt JSON and sidecar are the deliberate exception: they are the existing controlled canonical pair and are advanced in order with the retained-store atomic replacement helper. A mixed new-receipt/old-sidecar pair is therefore an explicit recoverable transient, not an assertion that two files changed atomically.

A fresh transaction refuses any pre-existing new installer leaf, even when its bytes happen to match. After intent, an exact new installer with no remaining stage is accepted only as the recognized result of an interrupted no-replace move. If an exact or foreign target appears at the move boundary, the no-replace move does not overwrite it and the operation remains pending and fail-closed. A pre-existing or racing completed record is also preserved and rejected; it is checked before pre-intent stage/intent publication and again before final completion.

Normal leaves are checked for reparse points, hard links, alternate data streams, SHA-256, byte count and file identity. Read leases deny mutation or deletion of the old and new physical installers across canonical publication, and the pending-intent lease is held across its final rename. These controls close accidental and cooperating-writer races covered by the shared lock; they do not establish a hostile same-SID security boundary.

## Verification handoff

The isolated test entry point covers the strict two-generation reader relationship, clean replacement, independent-process hard exits around unique copy, deterministic stage, intent, installer publication, canonical receipt, sidecar and completion, shared-lock exclusion, exact and foreign no-replace races, completed-target collision, illegal-state rejection, old-installer preservation and actual-checkout protection. It also starts from a genuinely non-durable old canonical receipt, proves that the original and retention-only digests are distinct, retains the supplied historical v1 receipt, and resumes that durable intent in a fresh process. Test workers are PowerShell processes operating only inside their own fresh fixture cases.

The final current-source runs passed 45/45 checks in both Windows PowerShell 5.1 and PowerShell 7. Their result records are `.tmp/dual-product/dp1-package-receipt-v2-test-dp1n-final-ps5-c/transaction-result.json` (SHA-256 `24e6f4125dc4ecfa33df6d90fc1aec528d7b6582c20e390a78a6ac879b0c8d2f`) and `.tmp/dual-product/dp1-package-receipt-v2-test-dp1n-final-ps7-c/transaction-result.json` (SHA-256 `ec6f473d7893600689b1abb44f5ad4c3a2eb3b956b4c9bcbabcedd072f532d12`). Both report the exact full suite, every reviewed verification field true, and the three explicit limitations false. The durable project record is `docs/testing/dual-product/2026-09-07-dp1-n-installer-receipt-transaction.json`; its sidecar binds the final record bytes.

One validation-only compatibility defect was found and corrected before those final runs: .NET Framework's `File.WriteAllText` rejected an alternate-data-stream suffix in Windows PowerShell 5.1, so the negative fixture now creates that stream through the FileSystem provider's `-Stream` parameter. The failed 44/45 attempt remains at `.tmp/dual-product/dp1-package-receipt-v2-test-dp1n-final-ps5-b/transaction-result.json`; it did not enter the transaction under test and is not counted as a product regression or passing evidence.

## Non-claims and next work

DP1-N does not change the actual `installer/package-build-receipt.json`, the actual versioned installer, any installed Rime/PIME or YimeCore files, registry state, processes, settings, learning data or the user's default input method. It neither refreshes a complete candidate nor proves its archive, generated uninstaller, signature, delivery readiness, registration, live-host behavior or recovery on an installed machine. Historical or frozen targets remain unexecuted.

Write-through file operations and process-interruption recovery are not evidence of hardware power-loss survival or directory-metadata durability. DP1-N also does not claim physical prevention of a hostile same-SID process replacing a leaf or ancestor outside the shared protocol. Those limits, a separately reviewed complete candidate build and static verification, actual canonical migration, and a real installer/maintenance transaction adapter remain later gates.

The dual-product decision is unchanged: Rime/PIME and YimeCore are two complete input methods that may be installed together or separately, and each remains independent of the other's runtime, installation, maintenance, writable state and recovery. This Rime/PIME fixture contract neither introduces a shared runtime nor authorizes one product to modify or depend on the other. DP1, DP2, DP3, L5 and L6 are not promoted by DP1-N alone.
