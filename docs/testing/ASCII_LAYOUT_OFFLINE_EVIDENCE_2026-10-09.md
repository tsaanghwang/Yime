# ASCII keyboard experiment: offline projection evidence

Status: **base-keyboard experiment only; not a promoted production handoff**.
The user selected completing the base experiment, designing fused-erhua
carriers separately, and not replacing the installed input method this round.
No existing source approval, target lock, native installation or user data was
replaced. Large generated outputs remain local under `.generated/ascii-keyboard/`.

## Canonical projection

- Sole editable projection: `internal_data/manual_key_layout.json`.
- All 60 semantic IDs remain; 57 active IDs use 52 case-sensitive ASCII letters
  plus `'`, `[`, `]`, `\`, `/`.
- Shared declarations: M28/M25 on `[`, M29/M26 on `N`, M30/M27 on `]`.
  M25, M26, M27 are disabled **before** any code shortening/projection.
- N12 remains `'`; N26 and N27 are independent on `Q` and `R`.
- Layout SHA-256:
  `f35fd71838991b49fed13e5f6673b098d230d5f248a00c376c9989e8f7fe2c0b`.
- The canonical 1,737-syllable inventory remains unchanged. Four readings
  (`hm5`, `m1`, `m2`, `m4`) contain disabled IDs; 1,733 remain active.
- Go code-mode metadata is generated using the existing canonical semantic
  metadata API. Every active syllable is checked against the Python semantic
  transformation before layout projection, in full/variable/shorthand modes.

## Verified independent source

`YIME_LEXICON_EXTERNAL_ROOT=C:\YimeData\lexicon-inputs-v1`; all 29 locked input
files passed `tools/lexicon/verify_external_inputs.py`. No sibling repository
or generated Rime dictionary was used to infer upstream semantics.

Read-only immutable runtime source:
`C:\YimeData\runtime-input-v1\pinyin_hanzi.db`, 5,491,941,376 bytes,
SHA-256 `694a5c984c3784dd2a07f49db454e69d01e08b24ce7de14b45ac10b70e315379`.
Identity matches the existing source evidence. Projection reconstructs complete
semantic tuples from canonical pinyin, not from old keyboard codes.

## Completed base experiment

Command:

```text
python -B -X utf8 tools/build_ascii_keyboard_experiment.py --source-database C:\YimeData\runtime-input-v1\pinyin_hanzi.db
```

The full immutable source scan covered 2,457,474 readings; 2,457,467 remained
after excluding seven disabled readings. This broad source experiment is
**not** the curated production selection. Manifest:
`.generated/ascii-keyboard/data/ascii_keyboard_manifest.json`.

| Mode | Dictionary SHA-256 |
| --- | --- |
| Full | `e51867d8cd7059914fd5239d5d6ee79d96c8e7a249ed96add343562a1d72b8dd` |
| Variable | `46b00041b6f24ca4bca5bf9ce9b3dbd67075d59ccc78e414faab40e3bfb8dbc6` |
| Shorthand | `67b6947a55c118c791fa18344c73acc1dd629a8faf59c91baf2f122070992ea4` |

The exact excluded readings were 呒/m2, 呣/m2, 呣/m4, 唔/m2, 嘸/m1,
嘸/m2, 噷/hm5. Other active readings of these characters remain eligible.

## Completed first curated candidate rebuild

Existing source admission, capacity, ranking, and two-level-selection policies
were replayed, without altering policy counts or inferring new pronunciations:

```text
python -B -X utf8 tools/build_lexicon_source_bundle.py --output-dir .generated/ascii-keyboard/source
python -B -X utf8 tools/plan_static_lexicon_capacity.py --source-database .generated/ascii-keyboard/source/source_lexicon.sqlite3 --output-dir .generated/ascii-keyboard/capacity
python -B -X utf8 tools/build_input_candidate_model.py --source-database .generated/ascii-keyboard/source/source_lexicon.sqlite3 --output-database .generated/ascii-keyboard/input-model/input_model.sqlite3
python -B -X utf8 tools/build_two_level_runtime_trial.py --source-database .generated/ascii-keyboard/source/source_lexicon.sqlite3 --capacity-database .generated/ascii-keyboard/capacity/static_capacity.sqlite3 --input-model-database .generated/ascii-keyboard/input-model/input_model.sqlite3 --source-runtime-database C:\YimeData\runtime-input-v1\pinyin_hanzi.db --output-dir .generated/ascii-keyboard/curated --skip-runtime-database
```

- Source bundle: 2,442,053 accepted texts, 2,468,774 canonical text/readings.
- Capacity model: 49,232 mandatory texts; recommended capacity 108,332.
  The existing selection policy still uses its approved capacity base 202,290.
- Input model: 4,109,102 candidates; no decision overlays.
- Curated result: **1,166,746 mappings, 1,151,404 distinct texts**.
- All four gates passed: source-separated ranking evidence, long-form core
  migration, dynamic candidate coverage, single-character coverage.
- Original canonical character inventory remains 46,095 characters/61,011
  readings. The disabled-tuple-derived effective boundary is still 46,095
  characters, 61,004 source readings, 61,003 distinct `(text, full code)` pairs.
  The original source counts are verified before deriving that active boundary.
- Full dictionary SHA-256:
  `edd8191adf44e9303d897bf3a5911257a7b932796d3c9b1f9d546a494aa63bba`.
- Selection TSV SHA-256:
  `8a684e6eddded9352f0ed97d8a8e6f5df2d8dbd8b269850ac8ae021b67976e76`.

Outputs: `.generated/ascii-keyboard/curated/manifest.json`,
`active_character_boundary.json`, `selection.tsv`, `two_level_full.dict.yaml`.
These are **candidate-generation results**, not a changed approved target.
Although the mapping count is exactly seven lower than the historical target,
this does not prove byte-identical recovery of the historical selection.
Five accepted-source artifacts match historical evidence; the rejected-reading
artifact differs (current source locations are recorded in its diagnostics).

## Reproducibility boundary and deferred work

A genuinely separate source rebuild completed under
`.generated/ascii-keyboard/repro-b/source`. All six source artifacts matched
the first rebuild byte-for-byte. Its input model also completed. Its capacity
process was stopped after the user narrowed the scope, and its partial output
was preserved. No second trial ran; **two complete clean rebuilds were not
established**, and no reproducible-handoff evidence was issued.

`prepare_reproducible_handoff.py --candidate-only` is available for a future
two-build verification; the flag does not bypass identity or coverage gates.
Do not treat candidate preparation as approval or target promotion.

Production integration additionally requires separately designed fused-erhua
carriers: the historical 15 dedicated uppercase carriers now collide with base
ASCII assignments. The existing collision guard remains fail-closed. They were
not silently remapped or disabled. Old packaged dictionaries must not be used
with the new generated code-mode metadata; the production target lock remains
unpromoted and rejects the new layout identity.

## Source validation

- Targeted Python projection/export/boundary/lock/evidence tests: **40 passed**.
- Go `codemode` and `systemlexicon` tests: passed, including all 1,733 active
  canonical syllables in three modes.
- `tools/generate_ascii_layout.py --check`: passed.
- `tools/check_layout_change_lock.py --preflight`: passed; full production gate
  intentionally rejects the unpromoted layout identity.
- This report does not claim installed TSF/PIME, physical touch-panel, ARM64,
  fused-erhua, or production-package acceptance.
