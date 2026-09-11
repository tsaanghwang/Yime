# Rime/PIME candidate exit 51 on test PC

Affected product: Rime/PIME coexistence candidate. Existing YimeCore is the protected peer.

## Fixed candidate and observed failure

- Delivery commit: `c45bf9655c58551360edab0f4075c109a4d47003`; CI run 34567452496 succeeded.
- Source compile commit: `6321067de503463a71262a84239b8f5c3064f10d`.
- Delivery: `test-delivery/rime-pime-coexistence-20260911-empty`.
- Installer SHA-256: `0276245dff5aa5e6441a829152eb178471b8cba0a21314e15ba04a9e5ff83617`.
- Six-artifact integrity verification and Explorer-launched preparation succeeded. User then ran the prepared Install entry from Explorer.
- User observed `Candidate failed with exit code 51; retain all evidence and recovery tickets.` The wrapper returned 1.

## Evidence and limits

Original evidence remains outside Git under `C:\Users\Golde\Yime Rime-PIME Test Archives`, run `84ccacac-c115-4c2d-8d7a-47df8e0ea4a0`. Authorization, boundary and original recovery ticket remain unchanged.

- Three `peer-*-result.json` records in the run's approval directory report `unchanged=true`; all before/after digests equal `9fbcf26fc7b557f6393b4a8ae890048e0231a708591ad66fa044cf7e5f12b447`. Installed acceptance remains false.
- The install journal contains `prepared.bin` and `transaction.lock`, with no install commit or terminal record.
- The removal journal contains `prepared.bin`, `commit.bin` and `transaction.lock`, with no terminal record. Removal/rollback was initiated, but completion is not established.
- Product payload files and independent recovery executable remain. This is no longer a preparation-only failure and must not be described as no filesystem mutation.
- A PS5 read-only inspection using the source's `Get-CandidateRegistrationLayout` and `Get-CandidateTreeObservation -AllowDisabled` observed all 36 expected registration tree nodes absent, without read errors. Evidence: `approval-84ccacac-c115-4c2d-8d7a-47df8e0ea4a0/readonly-registration-e637cae257c543dabdf642c859017670.json`. This does not establish full rollback, Run-value absence, live-host acceptance, or a fresh default-input comparison.

## Diagnostic gap and next step

`invoke-rime-pime-candidate.ps1` maps any caught exception to 51. The elevated worker's encoded command does the same. Both emit only `Write-Error`; the NSIS `ExecWait` and hidden worker launch do not persist that exception. The reported code therefore cannot identify the original failure or the subsequent rollback failure. No installation replay or manual cleanup was performed during this investigation.

Development must retain full controller and elevated-worker exception type/message/stack and action phase in unique external diagnostic files, including the original failure and rollback failure separately. Preserve fixed package/receipt checks and same-SID native-context gates. Any new diagnostic package must provide a reviewed recovery path for this existing transaction; do not assume a newly rebuilt package can consume an old package-bound ticket. Resolve the pending transaction before a fresh installation attempt. Do not delete retained roots, edit approval/PIN files, or report coexistence acceptance as passed.
