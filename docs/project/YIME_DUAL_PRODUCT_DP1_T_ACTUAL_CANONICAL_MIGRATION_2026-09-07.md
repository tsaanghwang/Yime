# DP1-T: actual canonical artifact migration

Affected product: the independent Rime/PIME product. DP1-T migrates repository canonical package artifacts only. It does not install or uninstall the product, modify registration or the default input method, start a product process, access production user data, or touch installed YimeCore local.12.

## Outcome

- Exact-checkout migration adapter and private DP1-N actual capability: **PASS**.
- Byte-identical PS5/PS7 migration plan and full 45/45 fault-matrix binding: **PASS**.
- One-time authorized actual canonical installer-plus-receipt migration: **PASS**.
- PS7 idempotent Resume after completion: **PASS**.
- Installed registration, rollback, uninstall and Runtime readiness: **not exercised; DP1-U later implemented their source admission gates, while actual acceptance remains closed**.
- Directory-metadata durability, real hardware power-loss recovery and physical prevention of hostile same-SID replacement: **false**.

The final implementation is commit `5d12adfbd3da7f4dce4c6d4d4e0c58bbb8b53b30`, tree `db3b81133406c74dbb1c5b3beaea8df19454293d`. The [structured evidence](../testing/dual-product/2026-09-07-dp1-t-actual-canonical-migration.json) binds the implementation, external authorization, actual transition and regressions.

## Adapter boundary

`invoke-rime-pime-actual-canonical-migration.ps1` accepts only the checkout containing the adapter, a content-addressed DP1-S capsule under the fixed off-repository archive root, a fresh `.tmp/dual-product/dp1-t-*` output and passing full PS5 plus PS7 DP1-N fault matrices. Apply and Resume additionally require a sidecar-sealed authorization under the fixed off-repository DP1-T authorization directory. The authorization binds the exact user instruction, repository, old and successor identities, pre-migration snapshot, archive manifest, adapter and source-set hashes.

The archived successor evidence contains absolute paths from its isolated candidate checkout. The adapter first verifies the archived objects, then deterministically replaces that exact isolated root in the build and postbuild JSON with `C:\dev\Yime`, derives new evidence and receipt digests, and binds those derived identities in the migration plan. The source archive remains unchanged. The migrated receipt then passes the existing strict reader against the actual repository's retained CAS.

The public DP1-N module still exports exactly `Publish-RimePimeInstallerReceiptTransaction` and `Resume-RimePimeInstallerReceiptTransaction`, and both public functions continue rejecting the actual checkout. DP1-T invokes a private, finally-scoped capability only after its stronger actual-root, archive, matrix and authorization checks.

## Actual transition

| Item | Evidence |
| --- | --- |
| PS5/PS7 plan SHA-256 | `c6c1f1fb778c393bf7d336890dcf2ec70e9eb8001051cfeefeb40e3ab2db7208` |
| Authorization | `dp1-t-c6c1f1fb778c393b`; SHA-256 `81a7d8ff4d30e329a2817a15ebbac10ebf3ac0a77646905052f7f5f1a444ab3a` |
| Archive candidate receipt | `185d9056e11a89c7ed5f425147e91b66a677a043e9234a1702acdda5372567fa` |
| Migrated build result | `38b073aca89ed07af95e444b87563119be7df3444e365806e262e0f5d38b099a` |
| Migrated postbuild result | `81c5dbf2daa111e229511949bae281ca2f9ebf493f73f35c213fd96b5cf5ffdf` |
| Old canonical receipt | `c18d1202ad78dcd6f8c1f74b34859a83489adb01fb156fa4e2546160aff5b0be` |
| New canonical receipt | 6,185 bytes; `f1b67aa40d0fce85244e00656f6017b4e9e8c313eed538f596da5fd9ba312719` |
| Old installer, preserved | `YIME-1.4.0-dev-setup.exe`; `32a7d66e06284d512675e40495b6e244a23630d2e368ac2cf73ce652e623efe2` |
| New installer, published | 41,455,231 bytes; `ac97f65af80e9686525a3c2f289670aaa14edb60a6effc80ce7cc3580333970d` |
| Completed intent | `completed-ee9c17d389708f19bdb5d281ceadb4c832c204808bc85ade6dfa2e4a9f16ae56.json`; SHA-256 `3d59988024708d4e7b4db19b28ab61962968fac2596abc526a0891fa545c5245` |
| Apply result | SHA-256 `f2e62791c515ed1fdf34635399f6ac4728e6af4595fa75b1295d4e05fbcf36f1` |
| PS7 Resume result | SHA-256 `70a40cbb9497687ead05e647fceb5c9be68bd82ee8177087166cb2ab85a3916e` |

The Apply result records `transaction_disposition=published`; Resume records `transaction_disposition=resumed`, zero copied leaves and the same plan and canonical digests. `pending.json` is absent after both.

Two failed attempts are retained as engineering evidence. The first was rejected before any artifact write because PS5 decoded the script's unmarked UTF-8 Chinese literal differently from the explicitly UTF-8 authorization JSON; the fix stores the expected sentence as ASCII Base64 and decodes it at runtime. The second copied already verified archive objects into the ignored CAS, then failed before intent publication because the archived strict receipt still described the isolated clone root. The deterministic evidence rebase fixes that mismatch. In both attempts the canonical receipt remained `c18d1202...b0be` and `pending.json` was absent.

## Regression evidence

| Suite | Result | SHA-256 |
| --- | --- | --- |
| DP1-T adapter, Windows PowerShell 5.1 | 14/14 | `a39207bd11917b4ee36c7d1c76db56995f3a6b02a3d88c0a02bbb56ca50ac3cd` |
| DP1-T adapter, PowerShell 7.6.5 | 14/14 | `d9fce20384063d21e8d5e4f4be94a43b57f7caa860403d3d19dba37d103e53e8` |
| DP1-N full matrix, Windows PowerShell 5.1 | 45/45 | `24e6f4125dc4ecfa33df6d90fc1aec528d7b6582c20e390a78a6ac879b0c8d2f` |
| DP1-N full matrix, PowerShell 7.6.5 | 45/45 | `ec6f473d7893600689b1abb44f5ad4c3a2eb3b956b4c9bcbabcedd072f532d12` |
| Current-source baseline | 154 sources; 67/67; 7 pending | `eedf43dd5795fa878b067c918484cfbd589f9d5d4717b1e0e1dbf045ea8c3bf9` |

Build guards pass under PS5 and PS7 with `-SkipPackagedRime`. The baseline is intentionally source-only and therefore continues to report that it did not itself consume the authorization or execute migration; its pending descriptions point to this separate actual evidence rather than claiming the migration is still undone.

## Remaining boundary

The transaction uses write-through file streams, `Flush(true)`, no-replace moves, persistent intent and roll-forward Resume. This is process-interruption evidence. It does not prove directory-entry persistence after physical power loss, and it does not physically exclude a hostile same-SID process from replacing an unleased ancestor or creating an unlisted tree member. Those fields remain false.

No installer or uninstaller was run. Registration, rollback, installed removal, Runtime readiness, registered/native hosts, signing, delivery and ARM64-native acceptance remain separate gates. DP1-U now supplies the unified source admission layer, but those actual installed gates remain false; DP1, DP2, DP3, L5 and L6 remain incomplete.
