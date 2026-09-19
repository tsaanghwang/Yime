# Current readiness development validation (2026-09-19)

Status: **reboot pending**. The legacy-entry retirement gate and E3 performance
work are complete. The current x64/x86 dual-product package has passed build,
package, installation, payload, registration, and pre-reboot real-application
input checks. Reboot was deliberately not started because an unrelated
Notepad++ document was already open with unsaved user edits.

## Scope and frozen gates

- In scope, in order: retire the exact legacy YimeCore user input entry; improve
  E3 latency; build, install, and exercise the latest YimeCore plus Rime/PIME
  development package; then repeat the installed-state checks after a normal
  reboot.
- ARM64 real-machine acceptance remains frozen because no ARM64 host is
  available. Cross-built ARM64 artifacts do not change that status.
- Formal-signing and public-release gates remain frozen because no production
  signing identity is available.
- No persistent default-input setting was changed during this run.

## Legacy YimeCore entry retirement

This was a provenance-and-safe-retirement problem, not a normal functional
defect. The prior tool coupled removal of one exact obsolete per-user language
entry to proof about historical packages. That made a missing fixed historical
package list block a user-profile-only cleanup even though the operation never
needed to mutate files, machine registration, or defaults.

The retirement command now removes only the exact legacy YimeCore TIP from the
current user's language list. Historical package manifests are evidence inputs,
not a precondition for that narrow operation. The command refuses unsupported
hosts and does not remove payload files, machine registrations, current product
profiles, peer profiles, or the user's default input method.

Explorer-launched Windows PowerShell 5.1 Plan and Apply were exercised as an
ordinary user. The trusted system-language-list view reported no legacy entry,
one current YimeCore entry, one stable PIME entry, and one simple Rime entry.
Apply was therefore a successful no-op. Machine-readable evidence is in
`../legacy-entry-retirement.json`.

Relevant commits:

- `d228aaae` - `fix(maintenance): retire exact legacy user input entry safely`
- `e2569762` - `fix(maintenance): require system language-list view for retirement`

Both corresponding GitHub Actions runs completed successfully:

- <https://github.com/tsaanghwang/Yime/actions/runs/35410109813>
- <https://github.com/tsaanghwang/Yime/actions/runs/35410743586>

## E3 performance

The reproducible installed-index baseline passed full mode but failed the E3
tail-latency gate in variable-length and shorthand modes. CPU profiling traced
the repeated learned-only cost to `userCandidateModelScore` hash lookup on every
candidate replay.

The engine now keeps a bounded, generation-aware score-sequence cache. Every
replay still verifies the full candidate identity; a mismatch falls back to the
original lookup path; model-generation changes invalidate all cached sequences;
and the global cache is capped at 4096 entries.

Final 100-sample, 5000-replay result using the current code and installed
indexes (gate: p95 <= 1.10 ms, p99 <= 1.20 ms):

| Mode | p95 (ms) | p99 (ms) | Result |
| --- | ---: | ---: | --- |
| Full | 1.056 | 1.075 | Pass |
| Variable-length | 1.055 | 1.127 | Pass |
| Shorthand | 0.996 | 1.031 | Pass |

`go test ./...` passed. Commit `53b409d7` (`perf(yimecore): cache learned
score sequences`) is pushed, and GitHub Actions run
<https://github.com/tsaanghwang/Yime/actions/runs/35411599859> completed
successfully, including Go, race, native, simple-installer, all Rime shards, and
core jobs.

## Current dual-product development package

The source admission, x64/x86 YimeCore native and Go tests, deterministic
indexes, speech export, product-independence audits, Rime/PIME build, package
checks, payload-isolation checks, occupancy checks, and reinstall simulation all
passed.

Package root:

`C:\dev\Yime.worktrees\current-readiness-gates\.tmp\dual-package\r1-complete`

Admission evidence:

- Root: `C:\dev\Yime.worktrees\current-readiness-gates\.tmp\yimecore-experiment\speech-admission-20260919-090936-2aeb909bb94a41c9b1ed6f61186c0a58`
- Summary SHA-256: `a08430e0a59030cdc4b4c749dd2dc7aa7044ea393c7b6e80cab737ebda6d478d`
- Inventory SHA-256: `9dfd92d65181a940263d61fe008d8c39fe799ef5d2f4a3a769db1dbe053379e2`

The first combined installation installed Rime/PIME but YimeCore registration
returned the known transient `0x800700B7` conflict. The failure log is preserved
at `C:\Users\tsaan\Yime Setup Logs\37498156b3a9436a93470e231eaac5c.admin.log`.
A same-package YimeCore retry, without reboot, succeeded; its user/admin logs use
run id `a111aff33e8640a0b93470e231eaac5c`. The failed first attempt is not counted as
a successful install.

Installed payload verification found 65/65 expected YimeCore files and 160/160
expected Rime/PIME files, with zero mismatches. Evidence is retained at
`C:\dev\Yime.worktrees\current-readiness-gates\.tmp\installed-audit-pre-reboot.json`.
Rime/PIME x64 and x86 registration verification passed. YimeCore x86 passed the
complete registered-host contract. The x64 registered-host harness could locate
and activate the profile but Windows foreground locking prevented that harness
from becoming foreground; a real 64-bit Word check below superseded that UI-only
harness limitation.

## Real-application input before reboot

Temporary session-only TSF activation was used to select exact profiles without
changing the persistent default input method.

- Notepad++ 32-bit: current YimeCore candidate UI displayed and committed a
  candidate; Rime/PIME candidate UI displayed and committed a candidate. The
  inserted test text was undone, restoring the document to its pre-test content.
- Microsoft Word 64-bit: Rime/PIME candidate UI displayed and committed a
  candidate; current YimeCore candidate UI displayed and committed a candidate.
  Both insertions were undone, the document returned to empty, and Word was
  closed without saving.

The Notepad++ document was already unsaved before validation and remains open in
that state. Its contents were neither saved nor discarded. A normal reboot and
post-login installed-payload, registration, and real-input repeat are the only
remaining actions in this run.
