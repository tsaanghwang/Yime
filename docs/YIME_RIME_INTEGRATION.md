# Yime Rime data in PIME

This branch prepares PIME to consume Yime through the upstream Go Rime backend.

## Data flow

1. The importer accepts one fixed-length `yime_full.dict.yaml` as the only external lexicon source.
2. Go derives the full, variable, and shorthand Rime dictionaries plus a generation manifest.
3. PIME keeps those runtime artifacts under `go-backend\input_methods\yime\data` and copies them to `%AppData%\PIME\Rime` when deployed.
4. The Go Rime backend loads `go-backend\input_methods\yime\rime.dll`, initializes librime with those directories, and uses the selected Yime schema.

## Prepare local data

From `C:\dev\Yime`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-yime-rime-data.ps1 -Input C:\path\to\yime_full.dict.yaml
```

To generate the three dictionaries without deploying them:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\import-yime-full-lexicon.ps1 -Input C:\path\to\yime_full.dict.yaml
```

There is no variable-mode or shorthand-mode import switch. Those files are
reproducible runtime products and carry the source SHA-256 in
`yime_lexicon_manifest.json`.

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

This file does not originate inside `C:\dev\Yime` itself. Its source chain is
kept in `C:\dev\Yime-python-prototype`:

1. `internal_data\hanzi_pinyin\pinyin.txt` and
   `internal_data\phrase_pinyin\phrase_pinyin.txt`
2. `internal_data\pinyin_source_db\build_source_pinyin_db.py`
3. `internal_data\pinyin_source_db\validate_source_pinyin_db.py`
4. `internal_data\pinyin_source_db\rebuild_pinyin_assets.py`
5. `internal_data\pinyin_source_db\lexicon_exports\pinyin_normalized.json`
6. `yime\pinyin_normalized.json`

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

This means "标准拼音" display is now tied to the same phase-1 lexicon rebuild
used by the prototype project, without importing the prototype runtime DB or
candidate-window implementation into PIME.

The `音元拼音` candidate annotation uses a separate display-only path:

1. Prefer the actual ASCII code returned in the Rime candidate comment.
2. Decode that code to numeric-tone pinyin through `yime_pinyin_codes.tsv`.
3. Map each syllable to its BMP PUA sequence through `yime_pua_pinyin.json`.
4. Render the copied candidate comment with the bundled `YinYuan` font.

This conversion never changes Rime composition, key input, schema dictionaries,
or user-lexicon codes. `键位序列` continues to expose Rime's original ASCII
comment unchanged.

## Maintainer checklist

Use this checklist when pinyin display data changes in
`C:\dev\Yime-python-prototype` and this repo needs an updated runtime asset.

1. Rebuild the upstream phase-1 pinyin assets in
   `C:\dev\Yime-python-prototype`.
2. Confirm the rebuilt export exists at
   `internal_data\pinyin_source_db\lexicon_exports\pinyin_normalized.json`.
3. Confirm the runtime copy exists at `yime\pinyin_normalized.json`.
4. Copy that JSON into this repo as
   `go-backend\input_methods\yime\data\pinyin_normalized.json`.
5. Copy `yime\code_pinyin.json` into this repo as
   `go-backend\input_methods\yime\data\yime_pua_pinyin.json` when the PUA
   phonological mapping changes.
6. Keep only `pinyin_tone` and canonical `full` in
   `go-backend\input_methods\yime\data\yime_pinyin_codes.tsv`; derived columns
   must not be restored.
7. Import system lexicon changes only through
   `tools\import-yime-full-lexicon.ps1 -Input <full.dict.yaml>` and confirm the
   generated manifest and three output hashes.
8. Rebuild the Go backend package with `cd go-backend` then `cmd /c build.bat`.
9. Verify reverse lookup in the candidate window:
   `隐藏编码`, `标准拼音`, `音元拼音`, `键位序列`.
10. Sanity-check that both pinyin modes change comments only and do not trigger a
   schema reload or host exit during the language-bar click.

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
