# Yime Rime data in PIME

This branch prepares PIME to consume Yime through the upstream Go Rime backend.

## Data flow

1. Yime exports one Rime schema and dictionary from `C:\dev\Yime-variable-length`.
2. PIME keeps shared Rime data under `go-backend\input_methods\yime\data`.
3. PIME keeps user Rime data under `%AppData%\PIME\Rime`.
4. The Go Rime backend loads `go-backend\input_methods\yime\rime.dll`, initializes librime with those two directories, and uses the selected Yime schema.

## Prepare local data

From `C:\dev\Yime`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-yime-rime-data.ps1
```

The default mode is `variable`, which exports and deploys `yime_variable`.

Other modes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-yime-rime-data.ps1 -Mode full
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-yime-rime-data.ps1 -Mode shorthand
```

The script copies shared Rime data from `C:\dev\weasel\output\data` by default.
Use `-WeaselDataDir` if the shared data lives elsewhere.

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

## Generated files

Most generated Rime data should not be committed:

- `go-backend\input_methods\yime\data\`
- `%AppData%\PIME\Rime\`
- `%AppData%\PIME\Rime\build\`

Exception:

- `go-backend\input_methods\yime\data\pinyin_normalized.json`

That file is now a vendored runtime asset, not a local throwaway export.

## `pinyin_normalized.json` chain

The current Go Yime backend uses `pinyin_normalized.json` for the
"标准拼音" reverse-lookup display mode.

This file does not originate inside `C:\dev\Yime` itself. The formal source
chain lives in `C:\dev\Yime-variable-length`:

1. `internal_data\hanzi_pinyin\pinyin.txt` and
   `internal_data\phrase_pinyin\phrase_pinyin.txt`
2. `internal_data\pinyin_source_db\build_source_pinyin_db.py`
3. `internal_data\pinyin_source_db\validate_source_pinyin_db.py`
4. `internal_data\pinyin_source_db\rebuild_pinyin_assets.py`
5. `internal_data\pinyin_source_db\lexicon_exports\pinyin_normalized.json`
6. `yime\pinyin_normalized.json`

Upstream docs that describe this flow:

- `C:\dev\Yime-variable-length\docs\project\PINYIN_DATA_MIGRATION.md`
- `C:\dev\Yime-variable-length\internal_data\pinyin_source_db\README.md`
- `C:\dev\Yime-variable-length\scripts\integrate_lexicon_trial.ps1`

For the Go backend, we currently vendor the exported JSON into:

- `go-backend\input_methods\yime\data\pinyin_normalized.json`

The backend then resolves standard-pinyin comments through this runtime path:

1. candidate text -> current Yime schema code from `yime_*.dict.yaml`
2. Yime code -> numeric-tone pinyin via `yime_pinyin_codes.tsv`
3. numeric-tone pinyin -> marked standard pinyin via `pinyin_normalized.json`

This means "标准拼音" display is now tied to the same phase-1 lexicon rebuild
used by the prototype project, without importing the prototype runtime DB or
candidate-window implementation into PIME.

## Maintainer checklist

Use this checklist when upstream lexicon or pinyin data changes in
`C:\dev\Yime-variable-length` and this repo needs an updated standard-pinyin
display asset.

1. Rebuild the upstream phase-1 lexicon assets in
   `C:\dev\Yime-variable-length`.
2. Confirm the rebuilt export exists at
   `internal_data\pinyin_source_db\lexicon_exports\pinyin_normalized.json`.
3. Confirm the runtime copy exists at `yime\pinyin_normalized.json`.
4. Copy that JSON into this repo as
   `go-backend\input_methods\yime\data\pinyin_normalized.json`.
5. Keep `go-backend\input_methods\yime\data\yime_pinyin_codes.tsv` in sync
   with the schema dictionaries that the Go backend ships.
6. Rebuild the Go backend package with `cd go-backend` then `cmd /c build.bat`.
7. Verify reverse lookup in the candidate window:
   `隐藏编码`, `标准拼音`, `音元拼音`, `键位序列`.
8. Sanity-check that `标准拼音` changes comments only and does not trigger a
   schema reload or host exit during the language-bar click.

Minimum local verification:

- `go-backend\input_methods\yime\yime.go` still loads
  `pinyin_normalized.json` from `sharedDir()`
- `标准拼音` can resolve both a whole-word code path and a per-rune fallback path
- `音元拼音` still comes from the current schema dictionary, not from
  `pinyin_normalized.json`

What not to copy from the prototype repo:

- `yime\pinyin_hanzi.db`
- `.generated\runtime_candidates_by_code_true.json`
- the prototype candidate window or SQLite runtime logic

The Go backend only vendors the marked-pinyin export and continues to use
Rime dictionaries plus `yime_pinyin_codes.tsv` for reverse lookup.
