# DP1-S: actual off-repository evidence archive

Affected product: the independent Rime/PIME product. YimeCore, installed products, the default input method and production user data are outside this change. DP1-S takes the existing DP1-P candidate evidence, publishes an immutable content-addressed capsule outside every Git worktree and repository `.tmp`, and proves that fresh PowerShell 5.1 and PowerShell 7 processes can reopen it while the original candidate directory is unavailable.

## Narrow outcome

- Actual off-repository archive for the current process and static-evidence scope: **PASS**.
- Source-independent strict receipt and candidate-byte reopen under PS5 and PS7: **PASS**.
- Idempotent immutable verification reuse: **PASS**.
- Explorer-launched independent reopen, directory-metadata durability, hardware power-loss recovery and physical prevention of hostile same-SID replacement: **not established**.

The implementation is commit `adfa55505580f6ceb6b28f7b89d2e620dc46d335`, tree `6886a601aa11c8cffc704a08d039f0cf54068332`. The tracked [structured evidence](../testing/dual-product/2026-09-07-dp1-s-off-repository-archive.json) binds that source, the actual external capsule, both fresh-process verification records, PS5/PS7 regressions and the current-source baseline. Its SHA-256 sidecar is stored alongside it.

## Archive and reopen boundary

`publish-rime-pime-dp1s-off-repository-archive.ps1` accepts only a DP1-O candidate below this repository's `.tmp/dual-product` and always publishes below `%USERPROFILE%\Yime Rime-PIME Evidence Archives\DP1-S`. It enumerates all Git worktrees and rejects any destination within one. The external capsule is immutable and content-addressed by its manifest.

The existing candidate lacked the actual `build-manifest.json.sha256` sidecar required by the DP1-Q capsule protocol. DP1-S derives that sidecar in a temporary projection, without writing it into the candidate. It then temporarily moves the original source directory aside, reconstructs a projection at the exact recorded root solely from the external capsule, invokes the strict receipt-v2 reader and verifies the installer bytes in fresh PS5 and PS7 child processes, removes the projection and restores the original directory in `finally`.

The exact path reconstruction is required because the historical strict receipt deliberately binds absolute paths. It does not mean the original source remained available: the original directory was unavailable throughout both reopens, and the projection came only from archived immutable objects.

## Actual archive

| Item | Evidence |
| --- | --- |
| Capsule | `C:\Users\tsaan\Yime Rime-PIME Evidence Archives\DP1-S\c4a1f035ce830c24be1582dda4ce548d10846316a5f6681495ebf6ce2adddc06.capsule` |
| Archive ID | `c4a1f035ce830c24be1582dda4ce548d10846316a5f6681495ebf6ce2adddc06` |
| Manifest | 12,587 bytes; SHA-256 `cfee7781d1ccf71bc383373f15de8697964d083ec0a80c7666381da83a907185` |
| Archived objects | 43 |
| Physical archive | 88 files; 41,789,196 bytes |
| Candidate | 41,455,231 bytes; SHA-256 `ac97f65af80e9686525a3c2f289670aaa14edb60a6effc80ce7cc3580333970d` |
| PS5 verification | 994 bytes; SHA-256 `c44fa2068b6b4b92785306a380fd5634ab14e8e87a24c70622f6b8eaab68bab5` |
| PS7 verification | 982 bytes; SHA-256 `7945adf3dcbc67a528842b77de6132fe705df7e964fa443d4492dc33c1fc2e81` |

The first publication result has SHA-256 `0db119987e3fe21150d60da42f7a3a05b4636c0630b6b1f41ea77bed25ce76d7`. A second run reused both immutable verification records without overwriting them; its result SHA-256 is `a09f9efdd6721c20bc66e7fa36ed60dc3e5fa447d39eea083bbe64fff0114597`.

Both child processes reported no package identity. They were still descendants of the packaged Codex application, so the result explicitly keeps `child_processes_have_packaged_codex_ancestor=true` and `explorer_launched_independent_reopen_verified=false`. This is system-visible evidence from fresh nonpackaged child processes, not an Explorer-launched independence claim.

## Regression and baseline evidence

| Suite | Result | Sealed result SHA-256 |
| --- | --- | --- |
| Contract, Windows PowerShell 5.1 | 11/11 | `096f4668b9cb0067db1c509e58462b18860d84d01208b81ab2b53cfd87e48933` |
| Contract, PowerShell 7.6.5 | 11/11 | `392c2ea1ccd15eda196e42b35d94830185ce0de0ee29306b0e9d6aa228734b11` |
| Actual archive reopen, Windows PowerShell 5.1 | 12/12 | `0d8113b4581b4ce38c86467582b1b69d615f50639633c53f8768b9a3eb672b06` |
| Actual archive reopen, PowerShell 7.6.5 | 12/12 | `589ffaa4641d47cd7e5a78a357efe7dd4969422669b9ff56cad4a4cacf788c4f` |
| Current-source baseline | 152 sources; 66/66; 7 pending | `141e7d01d1c737cfdb3e8df34a329c060d16b0d6ed35f562df88cd39149a9a31` |

The regression fixes a DP1-Q fixture mismatch at the same time: the fixture now names the canonical receipt `installer/package-build-receipt.json`, matching the actual builder and strict reader. The full DP1-Q suite remains 24/24 under both shells after that correction. Build guards also pass under PS5 and PS7 with `-SkipPackagedRime`.

## Honest remaining boundary

DP1-S does not equate file flushes and content-addressed recovery with a real power interruption. It has no Explorer-launched independent run, no measured directory-entry persistence across hardware loss and no mechanism that physically excludes a hostile process with the same SID. Those fields remain false. The full-interval NSIS monitor from DP1-K still detects and rejects unlisted members; it does not become an access-control boundary through this archive work.

No installer or uninstaller was run. No registry, profile, product process, installed Rime/PIME runtime, default input method, production user data or YimeCore local.12 state was read or changed.

DP1-T is next: provide the dedicated actual-root adapter, bind one exact authorization to one reviewed transition and migrate the canonical installer plus receipt through the DP1-N transaction only when every required admission is supported by actual evidence. DP1-U then covers registration convergence, rollback, concurrent-safe removal and non-elevated Runtime readiness. DP1, DP2, DP3, L5 and L6 remain incomplete.
