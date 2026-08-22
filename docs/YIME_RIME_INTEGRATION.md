# Yime Rime data in PIME

> Status (2026-08-22): Yime owns the production source, encoding, handoff, runtime derivation and
> packaging chain. The retired prototype is not an input or fallback. A repository-only replay uses
> the committed approved handoff; a source-evidence reconstruction additionally requires the
> content-locked external corpus described below.

This branch prepares PIME to consume Yime through the upstream Go Rime backend.

## Data flow

1. Yime's offline tools verify the 29 external source inputs against
   `tools/lexicon/data/external_inputs.lock.json`. Those large sources live outside every Git
   worktree and are addressed only through `YIME_LEXICON_EXTERNAL_ROOT`.
2. The repository-local source, syllable and encoding pipeline produces and validates the curated
   fixed-length handoff. The approved handoff, evidence and target lock are committed under
   `tools/lexicon/handoff/` and `tools/lexicon/data/`.
3. `replay-approved-handoff.ps1` reproduces the full, variable-length and shorthand dictionaries
   from that committed handoff without the prototype or external corpus.
4. Verified pinyin and display assets are committed beside the generated runtime dictionaries under
   `go-backend\input_methods\yime\data`.
5. Build/install copies the shared data into the installed runtime; Rime deployment refreshes
   `%AppData%\PIME\Rime` and its compiled cache.

## Prepare local data

For the repository-only handoff replay, use a new output directory:

```powershell
.\tools\lexicon\replay-approved-handoff.ps1 `
  -OutputDir .\.generated\approved_core_handoff_replay
```

This proves that the committed production handoff can regenerate all packaged dictionary modes.
It does not claim to reconstruct the source database from BCC, Unihan, the character catalog and
Wanxiang. That stronger release operation intentionally requires an independent, content-locked
external corpus and restore evidence; see
[Yime offline lexicon tools](../tools/lexicon/README.md) and
[repository data boundary](project/YIME_REPOSITORY_DATA_BOUNDARY.md).

When importing a newly reviewed Yime-local candidate, treat the fixed-length dictionary and its
evidence manifest as an atomic pair. Do not combine files from different builds:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy-yime-rime-data.ps1 `
  -InputPath C:\path\to\two_level_full.dict.yaml `
  -EvidenceManifest C:\path\to\dictionary.manifest.json `
  -PronunciationEntries C:\path\to\lexicon_source_bundle\entries.tsv `
  -SourceRevision <yime-source-revision>
```

To generate the three dictionaries without deploying them:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\import-yime-core-lexicon.ps1 `
  -InputPath C:\path\to\two_level_full.dict.yaml `
  -EvidenceManifest C:\path\to\dictionary.manifest.json `
  -PronunciationEntries C:\path\to\lexicon_source_bundle\entries.tsv `
  -SourceRevision <yime-source-revision>
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

Its production source chain is maintained by the offline tooling in this repository:

1. Content-locked Unihan, character-catalog, Wanxiang and BCC source data pass the source and
   pinyin compliance gates through `YIME_LEXICON_EXTERNAL_ROOT`.
2. `.generated\lexicon_source_bundle\source_lexicon.sqlite3` becomes the source-of-truth database.
3. The canonical syllable inventory drives `SyllableEncodingPipeline` / `YinjieEncoder`.
4. Yime's candidate, selection and handoff tools rebuild the reviewed production artifacts.
5. The approved Windows handoff and its evidence are locked in this repository, including the
   identity used to verify `pinyin_normalized.json`.

Authoritative documents for this flow:

- `docs/lexicon/CURRENT_ARCHITECTURE.md`
- `docs/lexicon/PINYIN_DATA_MIGRATION.md`
- `tools/lexicon/README.md`

For the Go backend, we currently vendor the exported JSON into:

- `go-backend\input_methods\yime\data\pinyin_normalized.json`

The backend then resolves standard-pinyin comments through this runtime path:

1. candidate text -> current Yime schema code from `yime_*.dict.yaml`
2. Yime code -> numeric-tone pinyin via `yime_pinyin_codes.tsv`
3. numeric-tone pinyin -> marked standard pinyin via `pinyin_normalized.json`

This means "标准拼音" display is tied to the same audited source bundle and handoff run as the
system dictionary, without importing another repository's runtime database or candidate-window
implementation into PIME.

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

Use this checklist when Yime dictionary or pinyin source data changes.

1. Verify all external inputs against `external_inputs.lock.json`, then complete the Yime-local
   source rebuild and its compliance, coverage, layout, and ranking gates.
2. Use the paired files produced in Yime's `.generated\two_level_runtime_trial`.
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
   Yime source materialization manifest, with no runtime-only syllable; declared canonical-only
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

Do not reintroduce retired or cross-repository inputs such as:

- `yime\pinyin_hanzi.db`
- `.generated\runtime_candidates_by_code_true.json`
- a prototype candidate window or SQLite runtime implementation

The Go backend vendors only the reviewed runtime exports and continues to use
Rime dictionaries plus `yime_pinyin_codes.tsv` for reverse lookup.
