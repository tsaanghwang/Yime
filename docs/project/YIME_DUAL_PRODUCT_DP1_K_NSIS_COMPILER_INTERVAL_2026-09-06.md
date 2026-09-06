# DP1-K: NSIS compiler interval membership boundary

Date: 2026-09-06. Affected product: independent Rime/PIME DP1 package lane.

DP1-NSIS-MEMBERSHIP-05 is closed as a detection-and-rejection boundary, not physical membership prevention or full toolchain closure. Historical DP1-H evidence and its canonical receipt remain unchanged. DP1 overall, durable evidence, canonical v2 supersession, maintenance transactions, installation/uninstallation and tagged release remain pending or blocked.

## Implementation

`tools/dual-product/rime-pime-nsis-compiler-interval.ps1` copies the 303 code-pinned NSIS inputs from held read/no-delete leases into a fresh `.tmp/dual-product/dp1-package-build-stage-*/NSIS` directory. Unlisted source members are not copied. The installed NSIS compiler is read only; no installed product or historical product payload is executed. Existing stage paths and reparse paths are rejected.

After copying, the helper arms recursive `ReadDirectoryChangesW` on the entire compiler stage BEFORE acquiring its known-file/directory leases and checking its baseline. A full enumeration also rejects members outside the five scoped roots. Persistent pre-arm additions fail the baseline; subsequent create/delete/rename events invalidate completion even when the endpoint tree matches.

The builder directs the executable, NSISDIR and Include working directory to this stage, retaining `/NOCD /NOCONFIG`. Both new executed sources are included in pre-import build-logic leases. Only after synchronous makensis returns success does it create and observe the unique completion barrier. Unexpected events, overflow, unexpected cancellation, root identity mismatch, timeout and cleanup failures reject the candidate before publication preparation. Leases remain held through outer cleanup. NSISDIR is restored in finally. This is not a polling/snapshot approximation of the compilation interval.

Successful build evidence adds `nsis_compiler_membership_interval` and stage path/lease counts. These historical fields remain false:

- `active_same_sid_transient_tree_membership_interference_excluded`
- `nsis_non_os_compiler_input_closure`
- `full_nsis_toolchain_input_closure`

Interference remains physically possible; the boundary rejects observed interference and indeterminate notification outcomes. OS loader DLLs, other environment inputs, scheduling and arbitrary same-SID process-memory tampering are outside this filesystem contract. Directory notifications are not a complete Windows sandbox.

## Validation

`test-rime-pime-nsis-compiler-interval.ps1` runs real staged makensis against minimal fixtures. During compilation, `!system` synchronously launches an independent same-SID PowerShell child which creates and removes an unlisted file, directory, rename target or root-level file outside scoped roots. Endpoint exact-tree verification succeeds, but interval sealing must reject the candidate. The clean case checks staged NSISDIR and Include resolution; compiler-error rejects success; a builder guard verifies open/call/completion/publication ordering.

Final interval regressions passed 7/7 on PS5 and PS7. Existing monitor tests passed 15/15 on each shell, including overflow, unexpected cancellation, root identity prerequisites and same-SID transient members. `tools/test-build-guards.ps1 -SkipPackagedRime` passed on both shells.

| Shell | Interval result (repository-relative) | SHA-256 |
| --- | --- | --- |
| PS5 | `.tmp/dual-product/dp1-nsis-interval-test-ps5-verified/result.json` | `4eb742f1dbd3c5f7de5cbb5141680a3a0ca39585f541c198d7ba2570ab4c8cb7` |
| PS7 | `.tmp/dual-product/dp1-nsis-interval-test-ps7-verified/result.json` | `19d542c5d63b90b07d64303a486f644e1ab3d226b9a7d96ae6d9fab05456b33a` |

Each interval result has a SHA-256 sidecar. Primitive results are under `.tmp/dual-product/dp1-j-membership-test-interval-ps5/result.json` and `dp1-j-membership-test-interval-ps7/result.json`, both SHA-256 `4b6da068ea02aeb7cc920c17f6174596e2fb03da73ec3eaeac366074df65463f`. Earlier PS5 runs recorded an intentional compiler-error stderr as a harness failure; the final harness preserves native exit-code inspection across PS5/PS7. Those earlier records remain unaltered.

Evidence remains in fresh `.tmp` directories, not durable or bound into a new canonical receipt. No full product package build was run: the canonical v2 anti-downgrade preflight remains intact. Evidence covers the shared production stage helper around real minimal makensis compilations plus builder wiring, not a new canonical product publication.

Candidates were generated but never executed. No installers/uninstallers, product registry, default input method, user data or YimeCore local.12 were touched.

## Governance hardening follow-up

The compiler-interval helper and its real-minimal-makensis regression are now explicit members of `tools/dual-product/contract.json`. CI runs the regression under Windows PowerShell 5.1 and PowerShell 7 after installing the pinned NSIS 3.12 toolchain and before the product builder. The source baseline fails closed if the helper, either CI invocation, false nonclaim, or builder interval ordering disappears.

The former text-position guard was replaced with PowerShell AST checks in the interval test, registration-completeness test and repository build guards. They require exactly one monitored-stage open/completion/close lifecycle; one real staged makensis invocation; a structured nonzero exit gate; completion before the first candidate probe, record and lease; publication only after that admission; a null-guarded close in the owning `finally`; and one exact `nsis_compiler_membership_interval=$membershipInterval` binding in the successful build result.

Fresh current-source validation passed the interval suite 7/7 under both shells, registration completeness 36/36 under both shells, repository build guards under both shells, and Python baseline tests 51/51 over a 132-file source manifest. The [DP1-K/DP1-L hardening record](../testing/dual-product/2026-09-06-dp1-k-l-governance-hardening.json) binds these result artifacts and current sources by SHA-256. The current staged build result is still schema v2 and strict receipt admission does not yet require the interval object; therefore this closes governance of the existing interval implementation, not the next canonical product generation.
