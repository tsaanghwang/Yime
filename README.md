# Yime for Windows

**音元拼音** — A Windows Chinese phonetic input method built on [PIME](https://github.com/EasyIME/PIME) and powered by the [Rime](https://rime.im) engine.

[中文文档](README.zh-CN.md)

Yime maps pinyin syllables to a structured keyboard encoding where shouyin units follow memorable patterns (zh/ch/sh → 7/8/9, j/q/x → 3/2/1, z/c/s → 6/5/4). Three encoding modes are available: variable-length (default), fixed-length (4 keys per syllable, unambiguous), and shorthand (shortest codes).

In fixed-length mode, each syllable consists of one *shouyin* followed by a *ganyin*. The ganyin always contains three yinyuan: *huyin*, *zhuyin*, and *moyin*. Variable-length mode preserves the real or virtual shouyin and merges adjacent identical yinyuan that compose the ganyin: ABC stays ABC, AAC becomes AC, ABB becomes AB, and AAA becomes A. Shorthand mode then omits an eligible middle-tone yinyuan from the variable-length result. See the [data format reference](docs/YIME_DATA_FORMAT_REFERENCE.md#首音干音与三模式派生) for the structural rules.

## Features

- **Three encoding modes** — variable-length, fixed-length, and shorthand, switchable from the language bar
- **Rime-powered engine** — script translator with 2.45M+ entries per schema, weighted frequency sorting and continuous sentence composition
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
libIME2/                 Upstream IME library
docs/                    Development documentation
```

## Branches

| Branch | Purpose |
|--------|---------|
| `main` | Stable baseline and release target |
| `yime-stable` | Maintained integration branch |
| `codex/**` | Active task branches covered by push CI |

The encoding, lexicon, and experiment-heavy prototype work lives in the separate `Yime-prototype` repository.

## Build Requirements

- [Visual Studio 2022](https://visualstudio.microsoft.com/vs/) with C++ desktop workload
- [CMake](https://cmake.org/) 3.0+
- [Rust](https://rustup.rs/) with the `stable-i686-pc-windows-msvc` host toolchain
- [Go](https://go.dev/) 1.26.4 for reproducible/CI builds (`go.mod` keeps the 1.21 language compatibility floor)
- [Git](https://git-scm.com/)

## Build

### Clone and initialize

```powershell
git clone git@github.com:tsaanghwang/Yime.git
cd Yime
git submodule update --init libIME2
```

The active `libIME2` submodule points at the maintained `tsaanghwang/libIME2` fork.
If you bump a submodule SHA in Yime, push that commit to the submodule remote
**before** pushing the main repository, or CI checkout will fail.

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
machines with an enabled WinINET proxy, the build wrapper copies that proxy into
`HTTP_PROXY`/`HTTPS_PROXY` for git and CMake FetchContent without changing the
global git configuration.

`go-backend\build.bat` remains available for focused backend work. Go tool versions
come from `version.txt`, and reproducible flags keep hashes stable across unrelated commits.

## Install

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

## First-Run Checklist

- [ ] Clone, initialize submodules, confirm toolchain installed
- [ ] If the fixed-length Rime lexicon changed, run `tools\deploy-yime-rime-data.ps1 -Input <full.dict.yaml>` (see [docs/YIME_RIME_INTEGRATION.md](docs/YIME_RIME_INTEGRATION.md))
- [ ] Run `.\tools\dev-build-install-verify.ps1` for the complete build → reinstall → installed-runtime verification loop
- [ ] For a split workflow, run `cmd /c build.bat`, then `.\Reinstall-PIME-Test.cmd` from an elevated prompt, then `tools\verify-installed-runtime.ps1 -RequireRunningLauncher`
- [ ] Switch to Yime in a text application and verify: activation, candidates, settings, reverse lookup
- [ ] Run `.\tools\test-go.ps1`; use `.\tools\test-real-rime.ps1` and `.\tools\test-go-race.ps1` when the affected layer requires them

## Encoding Reference

### Shouyin → key mapping

In Yime, a *shouyin* corresponds in sound value to a traditional initial, but its encoding differs from
mainstream Pinyin input methods; the actual codes are listed below. The table also includes the special
shouyin used for spellings beginning with `y` and `w`, plus the virtual shouyin used when a syllable has no real
shouyin. In continuous input, the virtual shouyin marks an explicit syllable boundary.

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
| x | `1` | y (special shouyin) | `y` |
| w (special shouyin) | `=` | zero shouyin (virtual) | `'` |

### Candidate selection keys

| Key | Physical keycap | Candidate label | Selects |
|-----|-----------------|-----------------|---------|
| Space / Enter | Space / Enter | — | 1st candidate |
| Shift+1 | `!` | `⇧1` | 1st candidate |
| Shift+2…Shift+9 | `@ # $ % ^ & * (` | `⇧2`…`⇧9` | 2nd…9th candidates |

The candidate window does not use punctuation keycaps as ordinal labels because they scan poorly. Unlike mainstream Pinyin IMEs, Yime deliberately does not use bare digits for candidate selection: all ten Base-layer digits, `0`…`9`, always remain composition input even while candidates are visible. Ordinal selection uses Shift+1…Shift+9; Shift+0 does not select a candidate.

## Debugging

Run the launcher with a console window:

```powershell
PIMELauncher.exe /console
```

Check logs at `%LOCALAPPDATA%\PIME\Logs\go_backend.log`.

## Documentation

| Document | Description |
|----------|-------------|
| [Project Assessment](docs/YIME_PROJECT_ASSESSMENT.md) | Consolidated review findings, completed fixes, verification evidence, and remaining risks |
| [Architecture](docs/YIME_ARCHITECTURE.md) | System architecture, key mechanisms, data files |
| [Usability Assessment](docs/YIME_USABILITY_ASSESSMENT.md) | Current usability issues and priorities |
| [Development Roadmap](docs/YIME_DEVELOPMENT_ROADMAP.md) | Phased roadmap, fix workflows, AGENTS.md constraints |
| [Rime Integration](docs/YIME_RIME_INTEGRATION.md) | Rime data flow, pinyin_normalized.json chain, maintainer checklist |
| [Tooling Strategy](docs/YIME_TOOLING_STRATEGY.md) | Standalone tools vs. language-bar UI design |
| [Tool Development Guide](docs/YIME_TOOL_DEVELOPMENT_GUIDE.md) | How to add a new standalone tool |
| [Native UI Guidelines](docs/YIME_NATIVE_UI_GUIDELINES.md) | Win32 layout, dialogs, wording, focus, and UI tests |
| [Testing Guide](docs/YIME_TESTING_GUIDE.md) | CI layers, real Rime tests, and installed-runtime verification |
| [Release and Signing](docs/YIME_RELEASE_AND_SIGNING.md) | Reproducible builds, Authenticode, packaging, and rollback |
| [Data Format Reference](docs/YIME_DATA_FORMAT_REFERENCE.md) | TSV/JSON/YAML data file format specifications |
| [Single-Source Lexicon Refactor](docs/project/SINGLE_SOURCE_LEXICON_REFACTOR.md) | Why and how three maintained code tables became one fixed-length source |
| [User Install Guide](docs/YIME_USER_INSTALL_GUIDE.md) | Installation and usage instructions for end users |
| [Troubleshooting](docs/YIME_TROUBLESHOOTING.md) | Common issues and solutions |
| [Changelog](CHANGELOG.md) | Version change history |
| [Contributing](CONTRIBUTING.md) | PR process, code style, commit format |
| [Security Policy](SECURITY.md) | Private vulnerability reporting and supported security boundaries |
| [AGENTS.md](AGENTS.md) | AI-assisted development constraints |

## Issues

Report issues in this repository. Framework-level issues that also affect upstream PIME should cross-reference [EasyIME/PIME](https://github.com/EasyIME/PIME).

## Relationship to PIME

Yime for Windows is an independently maintained downstream derivative of
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
