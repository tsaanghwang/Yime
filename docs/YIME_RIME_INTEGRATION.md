# Yime Rime data in PIME

This branch prepares PIME to consume Yime through the upstream Go Rime backend.

## Data flow

1. The prototype produces one versioned Windows handoff directory. It contains the fixed-length
   `yime_full.dict.yaml`, four synchronized pinyin assets, and
   `yime_handoff_manifest.json` with counts and SHA-256 values.
2. The maintainer verifies the handoff manifest before accepting any file. The prototype command
   also runs the Windows dictionary derivation into a staging subdirectory by default.
3. The Go importer accepts the fixed-length dictionary as the only external lexicon source and
   derives the full, variable, and shorthand Rime dictionaries plus
   `yime_lexicon_manifest.json`.
4. The verified auxiliary assets are vendored beside those generated dictionaries under
   `go-backend\input_methods\yime\data`.
5. Build/install copies the shared data into the installed runtime; Rime deployment then refreshes
   `%AppData%\PIME\Rime` and its compiled cache.

## Prepare local data

Generate the complete handoff in `C:\dev\Yime-python-prototype`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tools\prepare_windows_yime_lexicon.ps1
```

The default output is `.generated\windows_yime_import`. Treat that directory as one atomic
handoff: verify every asset recorded by `yime_handoff_manifest.json` before copying or importing
anything. Do not combine files from different handoff runs. The handoff producer prepares and
checks staged output; it does not deploy to PIME/Rime, and this repository does not yet provide a
single command that consumes all five handoff assets.

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
3. Map each syllable to its BMP PUA sequence through `yime_pua_pinyin.json`.
4. Render the copied candidate comment with the bundled `YinYuan` font.

This conversion never changes Rime composition, key input, schema dictionaries,
or user-lexicon codes. `键位序列` continues to expose Rime's original ASCII
comment unchanged.

## Maintainer checklist

Use this checklist when prototype dictionary or pinyin data changes.

1. Complete the prototype rebuild and its compliance/layout gates.
2. Run `tools\prepare_windows_yime_lexicon.ps1` and use only its resulting
   `.generated\windows_yime_import` directory.
3. Verify `yime_handoff_manifest.json`: schema version, audited/runtime inventory counts, declared
   source-only syllables, byte sizes, and every asset SHA-256.
4. Import `yime_full.dict.yaml` only through
   `tools\import-yime-full-lexicon.ps1`; never import variable or shorthand dictionaries.
5. Copy the four verified auxiliary assets together:
   `yime_pinyin_codes.tsv`, `yime_syllable_decomposition.tsv`,
   `pinyin_normalized.json`, and `yime_pua_pinyin.json`.
6. Confirm `yime_lexicon_manifest.json` and the three generated dictionary hashes, then run the
   stable Go verification suite. The syllable inventory test must report no runtime-only syllable;
   declared source-only syllables are allowed.
7. Run root `Build.cmd` to produce the package. Build does not install it.
8. Install/reinstall, restart `PIMELauncher` and `server.exe`, redeploy Rime, and compare source,
   installed, and `%AppData%\PIME\Rime` hashes. A source-only check is not sufficient.
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
