# CN/EN134 development handoff — 2026-10-18

Branch: `codex/ascii-physical-layout-experiment`. Affected scope: isolated
keyboard lab and its offline generated projection/data. The original-layout
reconciliation is separate in PR #67.

The lab runs at <http://127.0.0.1:8766/> on this development PC. For a new
session use the generation/start commands in [README](README.md); source
checkout alone does not deliver the large experimental dictionaries.

Layout: CN/EN134 with identical 24.75 × 7.25u geometry, retained English view
preference, lowercase/uppercase EN layers, 23 disabled EN blanks, fixed colors,
node reuse, paired language/punctuation, and optional explicit literal entrances.
The branch retains its contextual-digit experiment rule, separate from the
installed products' Shift+1–9 policy. No installer or registered host was run.

Checks: 21 Python prototype tests; 40 JavaScript tests; 34 projection/tool/syllable-audit/Rime-export tests passed; one pre-existing
omission-audit test skipped because its separate unified source_lexicon.sqlite3
is unavailable (no source-boundary fallback was added);
Go keyboard-lab/codemode/systemlexicon tests (including explicit-symbol retry and pending-quote preview refresh); all 1,737 canonical semantic
syllables and 135 derived-contraction fixtures; complete 2,457,474-reading source
projection and three-mode dictionaries; full-corpus-index HTTP checks for
source-ID-derived 你/好, paging and all coding-symbol candidates. The corpus
manifest is preserved in [corpus evidence](../../docs/testing/ascii-keyboard/2026-10-18/corpus-manifest.json).

Browser automation passed: all95 ASCII,75 ID paths,23 disabled keys,node/color reuse,
200 switches without requests,CN134/EN111 coverage,simulated two-finger Shift,
ISO cancellation and format6 export. Switching handler-to-frame timing: p50
14.3 ms,p95 15.0 ms,max 16.1 ms on the recorded browser.
This is a browser proxy,not physical end-to-end input latency. Raw session
(gzip),metadata,timing samples and screenshots are preserved in
[browser evidence](../../docs/testing/ascii-keyboard/2026-10-18/browser-result.json).
Actual finger/pen coverage, comfort, and end-to-end touch latency remain to be
measured on the now-available display. Automation is not hardware acceptance.

Earlier checkpoint `56ed04b2` intentionally preserves the mismatched historical
138-key runtime and later design drafts, with its failing geometry check noted.
The current generation/tests must pass before using this 134-key handoff.

## CI isolation repair

Build runs 39089360667 and 39089358021 exposed experimental projection data in
product-default paths. The fix preserves the CN/EN134 page and moves its sole
editable layout to `encoding/manual_key_layout.json`, its generated sidecars
to `encoding/`, and generated Go metadata to `go-backend/internal/asciicodemode/`.
Product manual/projection/semantic records, locks, shared code-mode defaults and
existing regression tests are restored to mainline. No lock is repinned and no
CI job or assertion is disabled. Earlier experiment tools/checkpoints remain in
Git history; they are not current instructions for modifying product paths.

The lab copy of the code-mode algorithm is generated from the standard source;
only its layout metadata is substituted. Offline Go dictionary compilers use an
explicit `-overlay` for this one file in their own process. Product compilation,
test execution and installed services never use this overlay. Semantic encoding
still comes from the shared formal Pinyin -> four Yinyuan IDs pipeline.

A complete independent rebuild into `.generated/ascii-keyboard-134-ci-fix`
exports all 2,457,474 source readings and 131 reviewed erhua records. All three
dictionary hashes exactly match the original 134-key evidence above. The
running browser service and its existing dictionary data therefore remain valid.

Local repair validation: complete Go package suite passed; Python tests: 420 passed, 15 environment/optional skips, 11,161 subtests passed; 41 offline lexicon unittests passed; prototype now has 23 Python and 40 JavaScript tests. Product target lock and repository data boundary both pass unchanged. Real-Rime and GitHub CI results are reported separately after completion.

All production real-Rime cases passed locally (406.5 s). The first wrapper run then rejected shard coverage because the optional lab-only corpus test shared the automatic TestRealRime prefix and intentionally skipped without its external corpus flag. The optional test is now named TestASCIIConceptErhuaThreeModesAndRollback; the production shard selector and coverage verifier are unchanged.

The first repaired CI run exposed a Windows locale issue: the generated shared
Go source contains Chinese error strings, but subprocess stdin used CP1252 on
the CI worker. Its writer thread raised UnicodeEncodeError and gofmt waited for
EOF. The gofmt pipe now uses explicit UTF-8 and a 30-second timeout. A separate
child-process regression disables Python UTF-8 mode and simulates CP1252 while
generating all artifacts. No global encoding setting or test gate is changed.
