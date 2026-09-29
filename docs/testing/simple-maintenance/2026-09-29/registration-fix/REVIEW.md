# YimeCore registration fix: original evidence review (2026-09-29)

Affected product: YimeCore. This review supports the independent source change on
`codex/yimecore-registration-fix-20260929`; it does not report a new installation
or fixed-package acceptance.

## Evidence origin and preservation

The [September 28 current-issues report](../../2026-09-28/current-issues/RESULT.md)
and its raw files came from the existing, uncommitted report tree in `C:\dev\Yime`.
At review, that workspace's HEAD was
`448245fffa4ffc256da9d359fcab324205b8c498`; all report files were untracked.
That HEAD identifies the source workspace context, not a commit containing the
report or proving which source produced each historical binary.

The original tree contains **30 files: RESULT.md and 29 raw files**. The complete
tree was copied into this branch without rewriting the report, normalizing line
endings, or changing the raw evidence. The source and destination file lists and
all file bytes match. [original-evidence-index.json](original-evidence-index.json)
records byte counts and SHA-256 for both copies, with file paths relative to the
original report root. All six log hashes already recorded in
[registration-failure-state.json](../../2026-09-28/current-issues/raw/registration-failure-state.json)
match the copied log bytes. The two new review/index files are separate from the
30-file historical tree.

The original report's statements that the fix was uncommitted and undelivered
describe September 28. They remain intact as historical evidence; current source,
CI and package status belong in the new delivery records.

## What the original evidence establishes

| Evidence | Supported observation and limit |
| --- | --- |
| [Original failing admin log](../../2026-09-28/current-issues/raw/218f9476a0634b6792332b2bc421a3d2.admin.log), lines 21–32 | Both unregister operations returned `0x0`; the following registration returned `0x800700B7` and setup stopped at `register new product`. It has no step-level diagnostics, so the exact original failure branch cannot be established retrospectively from that HRESULT alone. |
| [Persisted-state comparison](../../2026-09-28/current-issues/raw/registration-persistence-verification-01.log), lines 132–203 | Immediately after successful unregister, the original x64 and x86 tools reported `profile_registered=true`, while the corrected tools reported false. This directly reproduces the state-query defect. |
| Same comparison, lines 204–218 and 125–131 | Corrected x64 registration succeeds from absent state; an actual existing registration is still rejected with `0x800700B7`. |
| Same comparison, lines 95–124 and 223–252 | Both architecture queries see a newly persisted profile before any user-enable step. The cycle performs full registration through x64 and `register-com` through x86; it is not separate full `RegisterProfile` acceptance on both architectures. |
| Same comparison, lines 254–326 | Final checks observe absent state in both architecture queries. The Microsoft Pinyin default input override is unchanged. The log explicitly says the bounded diagnostic cycle is not package acceptance. |
| [Enumeration alternative](../../2026-09-28/current-issues/raw/registration-enumeration-verification-01.log), lines 80–108 | The attempted `EnumProfiles(0)` approach reported the newly registered x64 profile absent and stopped. It is a failed diagnostic alternative, not the retained fix. |
| [Original report](../../2026-09-28/current-issues/RESULT.md), lines 54–107 | Later recovery, registered-host tests and physical input confirmations concern the unchanged September 27 package. They do not establish acceptance of the registration fix. |

The retained implementation reads the exact machine-level CTF TIP
CLSID/language/profile key using the calling architecture's registry-view flag.
Only missing-key errors mean absence; other registry failures propagate. The
COM/profile/category duplicate guard remains in force, with added diagnostics.
The change does not justify arbitrary registry deletion or automatic retry.

## Regression scope and delivery boundary

The inherited process-local registry test covers absent state, a disabled but
persisted exact profile, exclusion of another language or profile, a null output
pointer, and immediate removal. Review identified additional useful coverage for
registry-error propagation, another CLSID, a user-only residual profile, explicit
architecture-view selection, and rejection of genuine duplicate state. x64 and
x86 runs must be recorded separately and included in CI; adding a CMake test
alone does not demonstrate that CI builds or executes that project.

The physical registration diagnostics above were performed in the historical
September 28 run. This source-change round is limited to source/build checks and
isolated regressions; those results must be recorded in the new validation
records. This review itself only reads files and verifies their bytes. It does
not rerun historical registration, modify or reinstall either installed product,
or claim new native installation/input acceptance.

At this review's creation, the new source commit, passing CI and complete fixed
package are not yet established. No new test-PC installation or input-test
arrangement is issued here. Subsequent delivery evidence must bind the actual
source commit and successful CI run to a distinct complete package, its manifest
and SHA-256 before HANDOFF states follow-up testing arrangements. The original
September 27 release remains the original, unfixed package; neither its bytes
nor its accepted results may be relabeled as containing this fix.
