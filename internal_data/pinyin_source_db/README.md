This folder contains the source-of-truth SQLite workspace for pinyin imports.

## Why it lives here

- `internal_data/hanzi_pinyin/pinyin.txt` and `internal_data/phrase_pinyin/phrase_pinyin.txt` are the curated exports after Unihan / phrase-pinyin-data pipelines.
- `source_pinyin.db` consolidates those TSV files into one SQLite database for prototype import, syllable export, and debugging.
- Keeping schema, builder, and exports together avoids scattering mutable artifacts.

## Default generated location

- `c:/dev/Yime/.generated/source_pinyin.db` (preferred)
- synced copy: `internal_data/pinyin_source_db/source_pinyin.db`

Override: set `YIME_SOURCE_PINYIN_DB`.

## Upstream inputs (v2)

| Kind | Default path |
|------|----------------|
| 单字 | `internal_data/hanzi_pinyin/pinyin.txt` |
| 词语 | `internal_data/phrase_pinyin/phrase_pinyin.txt` |

Run `internal_data/hanzi_pinyin/build_valid_pinyin.py` and `internal_data/phrase_pinyin/build_valid_pinyin.py` first if these files are missing.

## One-click rebuild (phase 1 — lexicon + syllable table, no codebook)

Default rebuild **does not** touch `syllable/codec/yinjie_code.json`. Marked forms that the source DB cannot supply are filled from `pinyin_normalized_patch.json`.

```bash
python internal_data/pinyin_source_db/rebuild_pinyin_assets.py
```

Steps: `build_source_pinyin_db.py` → `validate_source_pinyin_db.py` → `refresh_materialized_syllable_inventory.py` → `export_pinyin_normalized.py` → copy to `yime/pinyin_normalized.json` → yinyuan consistency check.

Gate before runtime or codebook replacement:

```bash
scripts/run_tests.cmd
```

### Supplemental patch (`pinyin_normalized_patch.json`)

Use this JSON when:

- the lexicon has a numeric syllable (`guai2`) but the auto `numeric_to_marked_syllable()` form is wrong; or
- a syllable must appear in `pinyin_normalized.json` before the codebook is updated.

Format: `"numeric_key": "marked_form"` (keys must stay numeric; do **not** add marked-form aliases to `yinjie_code.json`).

Standalone 儿化韵单写 `r` is normalized to numeric `er5` at import (`marked_syllable_to_numeric`); upstream marked spelling may stay `r`.

Export domain = distinct numeric syllables from `m_distinct_syllable_inventory` ∪ patch keys (inventory-first; only lexicon-attested syllables, including neutral tone). Use `--export-domain codebook` for the legacy codebook-only domain. Non-numeric codebook keys are ignored with a warning when loading the codebook reference.

`rebuild_pinyin_assets.py` refreshes the syllable inventory automatically. To rebuild it alone:

```bash
python tools/refresh_materialized_syllable_inventory.py
```

This materializes `m_distinct_syllable_inventory` directly from `char_readings` and `phrase_readings` (no intermediate view), then rebuilds analysis views. Inspect `v_numeric_syllable_marked_conflicts` for numeric→marked conflicts before patching.

## Phase 2 — replace codebook (explicit, after tests pass)

When export + unittest are green and you intend to refresh encoding artifacts:

```bash
python internal_data/pinyin_source_db/rebuild_pinyin_assets.py --apply-codebook
```

or:

```bash
scripts/apply_syllable_codebook.cmd
```

This runs `tools/rebuild_encoding_assets.py` (首音 → 干音 → `yinjie_code.json` → `code_pinyin.json`), not the lexicon-local encoder shortcut.

## Schema (v2)

| Table | Purpose |
|-------|---------|
| `source_files` | one row per kind (`char` / `phrase`) with import path |
| `char_readings` | expanded single-syllable readings per codepoint |
| `phrase_readings` | phrase-level readings (`reading_rank` for `\|` variants) |
| `metadata` | schema version, row counts |

Removed from v1: per-row `source_name`, `raw_line`, `comment` (structured TSV replaces raw-line audit; comment was only used for legacy `#` notes in colon-format phrase files).

## Downstream

- `yime/utils/prototype_single_char_import.py` / `prototype_phrase_import.py` clone into `pinyin_hanzi.db`
- `lexicon_exports/pinyin_normalized.json` — syllable codebook export (canonical rebuild output)
- `yime/pinyin_normalized.json` — runtime copy synced by `rebuild_pinyin_assets.py` for IME/static decoder

See also `docs/project/PINYIN_DATA_MIGRATION.md`.

## Trial lexicon integration (safe path)

To integrate a new `source_pinyin.db` **without touching the encoding layer** (`yinjie_code.json`), use:

```powershell
.\scripts\integrate_lexicon_trial.ps1              # build/validate/export only
.\scripts\integrate_lexicon_trial.ps1 -ApplyRuntime  # also refresh pinyin_hanzi.db (with backup)
```

The script writes `.generated/integrate_lexicon_trial_report.json` (row counts + SHA256) for baseline comparison. If `refresh_runtime_yime_codes.py` reports missing mappings, follow `PATCH_POLICY.md`.

Related orchestrators:

- `tools/update_phrase_lexicon_from_large_pinyin.py` — external char/phrase text sources
- `scripts/restore_full_pipeline.ps1 -Mode forward` — shorter forward without backup/report
