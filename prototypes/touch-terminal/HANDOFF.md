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
