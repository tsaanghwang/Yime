# Yime Rime data in PIME

> Status (2026-07-28): production imports one curated, evidence-locked fixed-length core and
> deterministically derives the full, variable-length, and shorthand runtime dictionaries. All
> three modes are packaged and share the same user-learning, custom-phrase, and blocklist layers.
> See [Core Candidate Three-Mode Runtime](DEFAULT_DYNAMIC_LEXICON_RUNTIME.md).

This branch prepares PIME to consume Yime through the upstream Go Rime backend.

## Data flow

1. The prototype builds `.generated\two_level_runtime_trial\two_level_full.dict.yaml` and its
   `dictionary.manifest.json`. The manifest includes source, selection, ranking-policy, and output
   hashes.
2. The Yime importer rejects a dictionary whose SHA-256 or ranking evidence does not match that
   manifest.
3. The Go derivation accepts this curated fixed-length core as the only runtime candidate source
   and writes the full, variable, and shorthand dictionaries plus `yime_lexicon_manifest.json`.
4. Verified pinyin and display assets are vendored beside those generated dictionaries under
   `go-backend\input_methods\yime\data`.
5. Build/install copies the shared data into the installed runtime; Rime deployment then refreshes
   `%AppData%\PIME\Rime` and its compiled cache.

## Prepare local data

Generate the curated core in `C:\dev\Yime-python-prototype`:

```powershell
.\venv312\Scripts\python.exe tools\build_two_level_runtime_trial.py
```

Treat `two_level_full.dict.yaml` and `dictionary.manifest.json` as an atomic pair. Do not combine
files from different builds.

From `C:\dev\Yime`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-yime-rime-data.ps1 `
  -InputPath C:\path\to\two_level_full.dict.yaml `
  -EvidenceManifest C:\path\to\dictionary.manifest.json `
  -PronunciationEntries C:\path\to\lexicon_source_bundle\entries.tsv `
  -SourceRevision <prototype-commit>
```

To generate the three dictionaries without deploying them:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\import-yime-core-lexicon.ps1 `
  -InputPath C:\path\to\two_level_full.dict.yaml `
  -EvidenceManifest C:\path\to\dictionary.manifest.json `
  -PronunciationEntries C:\path\to\lexicon_source_bundle\entries.tsv `
  -SourceRevision <prototype-commit>
```

There is no variable-mode or shorthand-mode import switch. Those files are
reproducible runtime products and carry the source SHA-256 in
`yime_lexicon_manifest.json`.

The same import also derives `yime_pinyin_reverse_source.tsv`. This partial
sidecar preserves canonical Pinyin only where different Pinyin readings share
the same Yime code; see
[同编码不同拼音反向映射](project/REVERSE_PINYIN_SOURCE_MAPPING.md).

## Build notes

The current upstream PIME build needs Rust for `PIMELauncher`.
On this machine, Win32 builds require:

```powershell
$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
$env:RUSTUP_TOOLCHAIN = "stable-i686-pc-windows-msvc"
cmd /c build.bat
```

The Go backend additionally requires Go on `PATH`:

```powershell
cd go-backend
cmd /c build.bat
```

## Generated and packaged files

The three `yime_*.dict.yaml` files and `yime_lexicon_manifest.json` under
`go-backend\input_methods\yime\data\` are committed package inputs, but they
are generated artifacts: regenerate them from one fixed-length dictionary and
never edit the variable or shorthand dictionaries independently.

### Continuous final-syllable completion

Yime schemas use `script_translator`, not the generic main
`table_translator`. Generated dictionary codes therefore contain spaces at
syllable boundaries, for example `过程` is stored as `guew 8we;`. These spaces
belong to Rime dictionary syntax; users still type the uninterrupted sequence
`guew8we;`.

This distinction is required for continuous input. A table translation can
complete a prefix only when the whole current input is a dictionary prefix;
its sentence builder otherwise joins complete codes and drops candidates while
the final syllable is unfinished. The script translator builds a syllable graph
and keeps the already valid sentence path connected to completion of the final
syllable. Do not remove the generated spaces or change the main translator back
to `table_translator`.

The stable `table_translator@custom_phrase` remains separate for explicitly
maintained custom phrases. The main script user dictionaries carry a
`_script_v1` suffix so learning records from the former table representation
are migrated by text into the new code representation rather than opened under
an incompatible namespace.

Rime deployment caches remain local and must not be committed:

- `%AppData%\PIME\Rime\`
- `%AppData%\PIME\Rime\build\`

`pinyin_normalized.json`, `yime_pua_pinyin.json`, and the two-column
`yime_pinyin_codes.tsv` are vendored runtime assets.

## `pinyin_normalized.json` chain

The current Go Yime backend uses `pinyin_normalized.json` for the
"标准拼音" reverse-lookup display mode.

This file does not originate inside `C:\dev\Yime` itself. Its production source chain is
kept in `C:\dev\Yime-python-prototype`:

1. Unihan, pypinyin, 万象 and BCC source data pass the first pinyin compliance gate.
2. `.generated\lexicon_source_bundle\source_lexicon.sqlite3` becomes the source-of-truth database.
3. The canonical syllable inventory drives `SyllableEncodingPipeline` / `YinjieEncoder`.
4. Prototype tables and `runtime_candidates_materialized` are rebuilt.
5. `tools\prepare_windows_yime_lexicon.ps1` exports the complete Windows handoff, including
   `pinyin_normalized.json`.

Upstream docs that describe this flow:

- `C:\dev\Yime-python-prototype\docs\project\PINYIN_DATA_MIGRATION.md`
- `C:\dev\Yime-python-prototype\internal_data\pinyin_source_db\README.md`
- `C:\dev\Yime-python-prototype\scripts\integrate_lexicon_trial.ps1`

For the Go backend, we currently vendor the exported JSON into:

- `go-backend\input_methods\yime\data\pinyin_normalized.json`

The backend then resolves standard-pinyin comments through this runtime path:

1. candidate text -> current Yime schema code from `yime_*.dict.yaml`
2. Yime code -> numeric-tone pinyin via `yime_pinyin_codes.tsv`
3. numeric-tone pinyin -> marked standard pinyin via `pinyin_normalized.json`

This means "标准拼音" display is tied to the same audited source bundle and handoff run as the
system dictionary, without importing the prototype runtime DB or candidate-window implementation
into PIME.

The `音元拼音` candidate annotation uses a separate display-only path:

1. Prefer the actual ASCII code returned in the Rime candidate comment.
2. Decode that code to numeric-tone pinyin through `yime_pinyin_codes.tsv`.
3. Map each syllable to its canonical four-position BMP PUA sequence through
   `yime_pua_pinyin.json`.
4. Apply the same position mask used by the active input schema: adjacent
   yinyuan merging for variable mode and middle-tone omission for shorthand
   mode. Fixed-length mode retains all four positions.
5. Render the copied candidate comment with the bundled `YinYuan` font.

This conversion never changes Rime composition, key input, schema dictionaries,
or user-lexicon codes. `键位序列` continues to expose Rime's original ASCII
comment unchanged.

## Maintainer checklist

Use this checklist when prototype dictionary or pinyin data changes.

1. Complete the prototype core rebuild and its compliance, coverage, layout, and ranking gates.
2. Use the paired files in `.generated\two_level_runtime_trial`.
3. Verify `dictionary.manifest.json`: selection and policy hashes, source-separated ranking counts,
   zero missing selected texts, and output SHA-256.
4. Import `two_level_full.dict.yaml` only through
   `tools\import-yime-core-lexicon.ps1`, together with its `dictionary.manifest.json`;
   never import variable or shorthand dictionaries independently.
5. Copy the five verified auxiliary assets together:
   `yime_pinyin_codes.tsv`, `yime_syllable_decomposition.tsv`,
   `pinyin_normalized.json`, `yime_pua_pinyin.json`, and
   `yime_syllable_inventory_manifest.json`.
6. Confirm `yime_lexicon_manifest.json` and the three generated dictionary hashes, then run the
   stable Go verification suite. The runtime syllable-set count and SHA-256 must equal the
   prototype materialization manifest, with no runtime-only syllable; declared canonical-only
   audit records are allowed.
7. Run root `Build.cmd` to produce the package. Build does not install it.
8. Install/reinstall, restart `PIMELauncher` and `server.exe`, redeploy Rime, and compare source,
   installed, and `%AppData%\PIME\Rime` hashes. Checking the source tree alone is not sufficient.
9. Verify reverse lookup in the candidate window:
   `隐藏编码`, `标准拼音`, `音元拼音`, `键位序列`.
10. Sanity-check that both pinyin modes change comments only and do not trigger a
    schema reload or host exit during the language-bar click; reproduce the dictionary defect that
    motivated the rebuild once against the installed runtime.

Minimum local verification:

- `go-backend\input_methods\yime\yime.go` still loads
  `pinyin_normalized.json` from `sharedDir()`
- `标准拼音` can resolve both a whole-word code path and a per-rune fallback path
- `音元拼音` prefers the actual candidate code, produces PUA characters, and
  leaves the source ASCII comment unchanged

What not to copy from the prototype repo:

- `yime\pinyin_hanzi.db`
- `.generated\runtime_candidates_by_code_true.json`
- the prototype candidate window or SQLite runtime logic

The Go backend only vendors the marked-pinyin export and continues to use
Rime dictionaries plus `yime_pinyin_codes.tsv` for reverse lookup.
