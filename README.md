# Yime for Windows

**音元拼音** — A Windows Chinese phonetic input method developed as two independent products: the [Rime](https://rime.im)/[PIME](https://github.com/EasyIME/PIME) edition and the self-contained YimeCore edition.

[中文文档](README.zh-CN.md)

Under the [2026-09-05 dual-product plan](docs/project/YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md), YimeCore is the main feature-development track and Rime/PIME remains a stable, maintained option. Either product may be installed alone, or both may coexist; each must run, upgrade, uninstall, and maintain its writable data independently, without requiring the other. The installation combinations still need their own acceptance evidence; a unified three-choice installer is not yet implemented.

Current [DP1-H evidence](docs/project/YIME_DUAL_PRODUCT_DP1_H_CANONICAL_V2_NSIS_INPUT_BOUNDARY_2026-09-06.md) binds one x86/x64 Rime/PIME disabled candidate, its exact sealed stage, generated include, build result, and static archive comparison in the canonical v2 receipt. The pinned NSIS distribution covers 303 known files in 17 directories, but a same-SID process can still create and remove an unlisted plugin between snapshots; full toolchain closure is therefore explicitly false. The candidate remains unsigned, disabled, unexecuted, non-deliverable, and dependent on non-durable evidence; supersession, durable transactions, and installed/live acceptance are still pending.

Current [DP1-I evidence](docs/project/YIME_DUAL_PRODUCT_DP1_I_FIXTURE_TRANSACTION_JOURNAL_2026-09-06.md) adds a fixture-only hash-chain journal, idempotent replay decisions, typed synthetic registry snapshots, and manifest-driven leaf-first removal. PowerShell 5.1 and 7 each pass 114/114 journal checks and 16/16 replay-model checks; the original 24-stage, 96-case fault matrix remains 9/9 on each. Only fresh repository-local `.tmp` fixtures were created and deleted. `Resume` does not run rollback or cleanup adapters, module reload is not a real process crash, and cross-process replay/locking, power-loss/directory durability, real registry recovery, and concurrent replacement safety remain unproven. Nothing is wired into the engine or installer; all install, release, DP1–DP3, L5, and L6 gates remain blocked.

Historical [DP1-J evidence](docs/project/YIME_DUAL_PRODUCT_DP1_J_ISOLATED_MEMBERSHIP_AND_SUPERSESSION_2026-09-06.md) added two fixture-only protocols: a continuous NSIS tree-membership monitor (15/15 on PowerShell 5.1 and 7) and a content-addressed generation, atomic-head, sealed-journal supersession model (16/16 on each). At that stage the monitor had not enclosed a real `makensis` process and the supersession fixture did not use the strict receipt-v2 reader.

Current [DP1-K evidence](docs/project/YIME_DUAL_PRODUCT_DP1_K_NSIS_COMPILER_INTERVAL_2026-09-06.md) copies the pinned NSIS inputs into a fresh compiler stage and encloses the synchronous real-minimal-`makensis` interval with continuous membership monitoring before candidate admission. This detects and rejects transient membership activity; it does not physically prevent a hostile same-SID writer, establish non-OS/full toolchain closure, run a full product rebuild, or bind the interval into a durable canonical receipt.

Current [DP1-L work](docs/project/YIME_DUAL_PRODUCT_DP1_L_RETAINED_RECEIPT_PUBLICATION_2026-09-06.md) wires content-addressed evidence retention and an explicit strict-reader v2-to-v2 receipt-only supersession/recovery API behind the shared publication lock. The actual canonical receipt has not been migrated. Hardware power-loss/directory durability, installer-identity replacement, real transaction adapters, and all installed/live gates remain pending.

The feature list and build, install, first-run, and debugging instructions below describe the **Rime/PIME product**, not YimeCore. For YimeCore's separate development and maintenance entry points, use [tools/yimecore](tools/yimecore/README.md); do not apply the PIME reinstall or registration commands to it.

Yime maps pinyin syllables to a structured keyboard encoding where shouyin units follow memorable patterns (zh/ch/sh → 7/8/9, j/q/x → 3/2/1, z/c/s → 6/5/4). The installed runtime provides variable-length, fixed-length, and shorthand modes, all deterministically derived from one curated core candidate set.

In fixed-length mode, each syllable consists of one *shouyin* followed by a *ganyin*. The ganyin always contains three yinyuan: *huyin*, *zhuyin*, and *moyin*. Variable-length mode preserves the real or virtual shouyin and merges adjacent identical yinyuan that compose the ganyin: ABC stays ABC, AAC becomes AC, ABB becomes AB, and AAA becomes A. Shorthand mode then omits an eligible middle-tone yinyuan from the variable-length result. See the [data format reference](docs/YIME_DATA_FORMAT_REFERENCE.md#首音干音与三模式派生) for the structural rules.

## Features (Rime/PIME)

- **Dynamic sentence composition** — a 1,166,753-entry encoded runtime dictionary includes all 46,095 encoded characters plus short components; Rime composes missing longer phrases and learns corrections
- **Evidence-locked core** — ranking uses BCC first, RIME-LMDG as fallback, and a separate structural floor
- **Single-source modes** — variable-length, fixed-length, and shorthand all run from the same curated candidate set
- **Candidate window** — 5–9 candidates per page, vertical or horizontal layout, one-click toggle
- **Reverse lookup** — display standard pinyin, Yime codes, or key sequences alongside candidates
- **User lexicon** — add custom phrases with numeric-tone pinyin; auto-converts to Yime codes
- **Portable user backup** — verified settings, lexicon, blocklist, and Rime sync snapshots with guarded restore
- **Standalone tools** — advanced layout design, settings, diagnostics, reverse lookup, lexicon management, system lexicon audit, and blocklist management as native Win32 executables
- **Language bar** — IME list name「音元」; static two-character toggle labels (中西 / 全半 / 横竖) with icon state; dispatcher for schema, layout, page size, and maintenance commands

## Repository Layout

```
go-backend/              Go backend: Yime IME logic, Rime integration, standalone tools
  input_methods/yime/    Yime-specific code and data
    yime.go              Core IME: key handling, language bar, candidate window
    librime.go           Rime DLL loader and deployment
    data/                Schemas, dictionaries, code maps, pinyin tables
    help/                User-facing help documents
PIMETextService/         TSF text service host (C++/COM)
PIMELauncher/            Process launcher and monitor (Rust)
installer/               NSIS installer assets
libIME2/                 In-tree TSF integration component
docs/                    Development documentation
```

## Branches

| Branch | Purpose |
|--------|---------|
| `main` | Stable baseline and release target |
| `yime-stable` | Maintained integration branch |
| `codex/**` | Active task branches covered by push CI |

Yime owns its encoding, lexicon, layout, and offline evaluation sources. The retired Python
prototype is a detached maintenance/cleanup workspace: Yime never reads it or any sibling Git
repository by default. See [Repository Data Boundary](docs/project/YIME_REPOSITORY_DATA_BOUNDARY.md).

The Rime/PIME runtime architecture and its qualification evidence are documented in
[Default Dynamic Lexicon Runtime](docs/DEFAULT_DYNAMIC_LEXICON_RUNTIME.md).

## Build Requirements (Rime/PIME)

- [Visual Studio 2022](https://visualstudio.microsoft.com/vs/) with C++ desktop workload
- [CMake](https://cmake.org/) 3.5+
- [Rust](https://rustup.rs/) with the `stable-i686-pc-windows-msvc` host toolchain
- [Go](https://go.dev/) 1.26.4 for reproducible/CI builds (`go.mod` keeps the 1.21 language compatibility floor)
- [Git](https://git-scm.com/)

## Build (Rime/PIME)

### Clone

```powershell
git clone git@github.com:tsaanghwang/Yime.git
cd Yime
```

`libIME2` is tracked directly in this repository so worktrees, local builds and
CI all use the same source snapshot. Its imported history base is
`tsaanghwang/libIME2@e7e11888343a4fd72b8610bc067109ed16d57def`; subsequent
component commits are kept path-pure by the libIME2 commit boundary gate so the
component can be extracted again later.

### Install the pinned Rust host toolchain

```powershell
rustup toolchain install stable-i686-pc-windows-msvc --profile minimal
```

The full i686 host toolchain is required, not only an i686 target added to an
x64 toolchain. The root CMake build pins this host toolchain so Corrosion does
not mix x64 host build scripts with i686 MSVC libraries. If `cargo` is not
found but `%USERPROFILE%\.cargo\bin\cargo.exe` exists, restore that directory
to the user `PATH` instead of changing the CMake, Corrosion, or Cargo target
configuration.

### Build the complete product

```powershell
cmd /c build.bat
```

The root `build.bat` verifies the pinned i686 host toolchain, builds Win32 and
x64 native components, builds the Go backend and tools, and runs PE architecture
guards. Do not repeat the Go build separately for a normal full build. On Windows
machines with an enabled WinINET proxy, the build wrapper may expose it to tools
that explicitly need the network, but the Win32 CMake/Rust build itself resolves
Corrosion and all locked crates from committed vendored sources. A fresh clone
therefore needs the compiler toolchains and SDKs, not GitHub or crates.io access.
The root `.cargo/config.toml` covers CMake/Corrosion invocations, while
`PIMELauncher/.cargo/config.toml` retains the required i686 target for focused
launcher builds.

`go-backend\build.bat` remains available for focused backend work. Go tool versions
come from `version.txt`, and reproducible flags keep hashes stable across unrelated commits.

## Install (Rime/PIME)

### Development reinstall

From an elevated prompt:

```powershell
.\Reinstall-PIME-Test.cmd
```

This script includes pre-flight checks, DLL-lock detection, and automatic fallback. Do not simplify it — see `AGENTS.md` for constraints.

### Distribution

Ship `installer\YIME-*-setup.exe` after verifying the NSIS package includes the Go backend. See [docs/dev-build-reinstall.html](docs/dev-build-reinstall.html).

### Manual registration

```powershell
regsvr32 "C:\Program Files (x86)\YIME\x86\PIMETextService.dll"
regsvr32 "C:\Program Files (x86)\YIME\x64\PIMETextService.dll"
```

To unregister:

```powershell
regsvr32 /u "C:\Program Files (x86)\YIME\x86\PIMETextService.dll"
regsvr32 /u "C:\Program Files (x86)\YIME\x64\PIMETextService.dll"
```

## First-Run Checklist (Rime/PIME)

- [ ] Clone the repository and confirm the toolchain is installed
- [ ] If the curated core changed, run `tools\deploy-yime-rime-data.ps1 -InputPath <two_level_full.dict.yaml> -EvidenceManifest <dictionary.manifest.json> -PronunciationEntries <entries.tsv> -SourceRevision <commit>` (see [docs/YIME_RIME_INTEGRATION.md](docs/YIME_RIME_INTEGRATION.md))
- [ ] Run `.\tools\dev-build-install-verify.ps1` for the complete build → reinstall → installed-runtime verification loop
- [ ] For a split workflow, run `cmd /c build.bat`, then `.\Reinstall-PIME-Test.cmd` from an elevated prompt, then `tools\verify-installed-runtime.ps1 -RequireRunningLauncher -RequireFreshRimeCache`
- [ ] Switch to Yime in a text application and verify: activation, candidates, settings, reverse lookup
- [ ] Run `.\tools\test-go.ps1`; use `.\tools\test-real-rime.ps1` and `.\tools\test-go-race.ps1` when the affected layer requires them

## Encoding Reference

### Shouyin → key mapping

In Yime, shouyin are divided into real and virtual classes. In phonetic terms, a real shouyin corresponds to a
traditional non-zero initial, while a virtual shouyin corresponds to a zero initial; Yime's actual encoding differs
from mainstream Pinyin input methods and is listed below. Under the Chinese-phonology convention used by this
project, zero initials are represented in *Hanyu Pinyin* by the separator `'` and by initial `y` or `w`; all three
are carried by virtual shouyin in Yime. A virtual shouyin also marks an explicit syllable boundary in continuous input.

| Shouyin | Key | Shouyin | Key |
|---------|-----|---------|-----|
| b | `b` | p | `p` |
| m | `-` | f | `[` |
| d | `]` | t | `t` |
| n | `n` | l | `\` |
| g | `g` | k | `q` |
| h | `h` | zh | `7` |
| ch | `8` | sh | `9` |
| r | `0` | z | `6` |
| c | `5` | s | `4` |
| j | `3` | q | `2` |
| x | `1` | y (virtual shouyin) | `y` |
| w (virtual shouyin) | `=` | `'` (virtual shouyin; separator) | `'` |
| ɥ (virtual shouyin before ü) | `` ` `` | ŋ (contextual shouyin of 啊) | `'` |
| ɹ (contextual shouyin of 啊; not Pinyin initial z) | `` ` `` |  |  |

### Candidate selection keys

| Key | Physical keycap | Candidate label | Selects |
|-----|-----------------|-----------------|---------|
| Space / Enter | Space / Enter | — | 1st candidate |
| Shift+1 | `!` | `⇧1` | 1st candidate |
| Shift+2…Shift+9 | `@ # $ % ^ & * (` | `⇧2`…`⇧9` | 2nd…9th candidates |

The candidate window does not use punctuation keycaps as ordinal labels because they scan poorly. Unlike mainstream Pinyin IMEs, Yime deliberately does not use bare digits for candidate selection: all ten Base-layer digits, `0`…`9`, always remain composition input even while candidates are visible. Ordinal selection uses Shift+1…Shift+9; Shift+0 does not select a candidate.

## Debugging (Rime/PIME)

Run the launcher with a console window:

```powershell
PIMELauncher.exe /console
```

Check logs at `%LOCALAPPDATA%\PIME\Logs\go_backend.log`.

## Documentation

| Document | Description |
|----------|-------------|
| [Dual-Product Development Plan](docs/project/YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md) | Independent products, optional coexistence, development priorities, and remaining acceptance gates |
| [DP1-J Isolated Membership and Supersession](docs/project/YIME_DUAL_PRODUCT_DP1_J_ISOLATED_MEMBERSHIP_AND_SUPERSESSION_2026-09-06.md) | Fixture-only continuous membership monitoring and supersession protocol evidence with explicit non-claims |
| [YimeCore Development Entry Points](tools/yimecore/README.md) | Separate YimeCore build, trial, and maintenance boundaries |
| [Project Assessment](docs/YIME_PROJECT_ASSESSMENT.md) | Consolidated review findings, completed fixes, verification evidence, and remaining risks |
| [Architecture](docs/YIME_ARCHITECTURE.md) | System architecture, key mechanisms, data files |
| [Usability Assessment](docs/YIME_USABILITY_ASSESSMENT.md) | Current usability issues and priorities |
| [Development Roadmap](docs/YIME_DEVELOPMENT_ROADMAP.md) | Phased roadmap, fix workflows, AGENTS.md constraints |
| [Rime Integration](docs/YIME_RIME_INTEGRATION.md) | Rime data flow, pinyin_normalized.json chain, maintainer checklist |
| [librime 1.17 Migration Evaluation](docs/LIBRIME_1_17_MIGRATION_EVALUATION.md) | Compatibility result, pinned runtime hashes, shared-data and upgrade gates |
| [Tooling Strategy](docs/YIME_TOOLING_STRATEGY.md) | Standalone tools vs. language-bar UI design |
| [Tool Development Guide](docs/YIME_TOOL_DEVELOPMENT_GUIDE.md) | How to add a new standalone tool |
| [Native UI Guidelines](docs/YIME_NATIVE_UI_GUIDELINES.md) | Win32 layout, dialogs, wording, focus, and UI tests |
| [Testing Guide](docs/YIME_TESTING_GUIDE.md) | CI layers, real Rime tests, and installed-runtime verification |
| [Release and Signing](docs/YIME_RELEASE_AND_SIGNING.md) | Reproducible builds, Authenticode, packaging, and rollback |
| [Data Format Reference](docs/YIME_DATA_FORMAT_REFERENCE.md) | TSV/JSON/YAML data file format specifications |
| [Single-Source Lexicon Refactor](docs/project/SINGLE_SOURCE_LEXICON_REFACTOR.md) | Why and how three maintained code tables became one fixed-length source |
| [Prototype Retirement Migration Plan](docs/project/PROTOTYPE_RETIREMENT_MIGRATION_PLAN.md) | Phased plan and inventory for moving useful offline tooling into Yime and retiring the Python prototype |
| [YimeCore Independent-Stack Experiment](docs/project/YIMECORE_REPLACEMENT_EXPERIMENT.md) | Current dual-product direction and historical gated engine, broker, and TSF evidence |
| [User Install Guide](docs/YIME_USER_INSTALL_GUIDE.md) | Installation and usage instructions for end users |
| [Troubleshooting](docs/YIME_TROUBLESHOOTING.md) | Common issues and solutions |
| [Changelog](CHANGELOG.md) | Version change history |
| [Contributing](CONTRIBUTING.md) | PR process, code style, commit format |
| [Security Policy](SECURITY.md) | Private vulnerability reporting and supported security boundaries |
| [AGENTS.md](AGENTS.md) | AI-assisted development constraints |

## Issues

Report issues in this repository. Framework-level issues that also affect upstream PIME should cross-reference [EasyIME/PIME](https://github.com/EasyIME/PIME).

## Relationship to PIME

The Rime/PIME edition of Yime for Windows is an independently maintained downstream derivative of
[EasyIME/PIME](https://github.com/EasyIME/PIME). It reuses and modifies PIME's
Windows TSF text-service host, process launcher, backend protocol, and
installation/registration infrastructure, while preserving the relevant
upstream Git history, copyright notices, and license terms. The Yime encoding
system, Rime integration, lexicons, maintenance tools, and YIME-specific
product configuration are developed and maintained by the Yime project.

Yime is not an official EasyIME/PIME release and is not affiliated with,
sponsored by, or endorsed by EasyIME/PIME or its original authors. Retained
internal PIME names are technical compatibility identifiers, not product or
publisher branding. See [NOTICE.md](NOTICE.md) for the complete statement.

## License

PIME-derived components retain their original copyright notices and
`LGPL-2.0-or-later` terms. Unless otherwise noted, Yime-specific software is
licensed under `LGPL-2.1-or-later`. Third-party engines, data, fonts, libraries,
and installer plug-ins retain their own licenses. See [LICENSE.txt](LICENSE.txt),
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and the [LICENSES](LICENSES)
directory.
