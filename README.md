# Yime for Windows

**音元拼音** — A Windows Chinese phonetic input method built on [PIME](https://github.com/EasyIME/PIME) and powered by the [Rime](https://rime.im) engine.

[中文文档](README.zh-CN.md)

Yime maps pinyin syllables to a structured keyboard encoding where initials follow memorable patterns (zh/ch/sh → 7/8/9, j/q/x → 3/2/1, z/c/s → 6/5/4). Three encoding modes are available: variable-length (default), fixed-length (4 keys per syllable, unambiguous), and shorthand (shortest codes).

## Features

- **Three encoding modes** — variable-length, fixed-length, and shorthand, switchable from the language bar
- **Rime-powered engine** — table translator with 468K+ entries per schema, weighted frequency sorting
- **Candidate window** — 5–9 candidates per page, vertical or horizontal layout, one-click toggle
- **Reverse lookup** — display standard pinyin, Yime codes, or key sequences alongside candidates
- **User lexicon** — add custom phrases with numeric-tone pinyin; auto-converts to Yime codes
- **Standalone tools** — settings, diagnostics, reverse-lookup, lexicon manager, system lexicon audit, and blocklist manager as native Win32 executables (not PowerShell in TSF callbacks)
- **Language bar** — IME list name「音元」; static toggle labels (中西/全半/横竖切换) with icon state; dispatcher for schema, layout, page size, and maintenance commands

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
python/                  Python-side support components
node/                    Node-side support components
installer/               NSIS installer assets
libIME2/                 Upstream IME library
libchewing/              Upstream chewing library
McBopomofoWeb/           Upstream Bopomofo components
docs/                    Development documentation
```

## Branches

| Branch | Purpose |
|--------|---------|
| `main` | Stable baseline |
| `yime-stable` | Active development (CI target) |
| `yime-on-pime` | Windows integration branch |

The encoding, lexicon, and experiment-heavy prototype work lives in the separate `Yime-prototype` repository.

## Build Requirements

- [Visual Studio 2022](https://visualstudio.microsoft.com/vs/) with C++ desktop workload
- [CMake](https://cmake.org/) 3.0+
- [Rust](https://rustup.rs/) with `i686-pc-windows-msvc` target
- [Go](https://go.dev/) 1.21+
- [Node.js](https://nodejs.org/) 18+
- [Git](https://git-scm.com/)

## Build

### Clone and initialize

```powershell
git clone git@github.com:tsaanghwang/Yime.git
cd Yime
git submodule update --init
```

Submodules such as `libIME2` and `McBopomofoWeb` point at `tsaanghwang/*` forks.
If you bump a submodule SHA in Yime, push that commit to the submodule remote
**before** pushing the main repository, or CI checkout will fail.

### Install Rust target

```powershell
rustup target add i686-pc-windows-msvc
```

### Build the host (32-bit)

```powershell
cmd /c build.bat
```

### Build the Go backend

```powershell
cd go-backend
cmd /c build.bat
```

### Build the 64-bit text service

```powershell
cmake . -Bbuild64 -G "Visual Studio 17 2022" -A x64
cmake --build build64 --config Release --target PIMETextService
```

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
- [ ] Run `cmd /c build.bat` from repository root
- [ ] Run `cmd /c build.bat` from `go-backend`
- [ ] If Rime data changed, run `tools\deploy-yime-rime-data.ps1` (see [docs/YIME_RIME_INTEGRATION.md](docs/YIME_RIME_INTEGRATION.md))
- [ ] Run `.\Reinstall-PIME-Test.cmd` from an elevated prompt
- [ ] Switch to Yime in a text application and verify: activation, candidates, settings, reverse lookup
- [ ] Run `go test ./input_methods/yime/...` from `go-backend` before shipping backend changes

## Encoding Reference

### Initial → key mapping

| Initial | Key | Initial | Key | Initial | Key |
|---------|-----|---------|-----|---------|-----|
| b | q | p | p | m | h | f | [ |
| d | w | t | . | n | y | l | b |
| g | ] | k | ' | h | n | | |
| zh | 7 | ch | 8 | sh | 9 | r | 0 |
| z | 6 | c | 5 | s | 4 | | |
| j | 3 | q | 2 | x | 1 | | |
| w | % | y | $ | | | | |

### Candidate selection keys

| Key | Selects |
|-----|---------|
| Space | 1st candidate |
| `` ` `` | 2nd candidate |
| `-` | 3rd candidate |
| `=` | 4th candidate |
| `\` | 5th candidate |

## Debugging

Run the launcher with a console window:

```powershell
PIMELauncher.exe /console
```

Check logs at `%LOCALAPPDATA%\PIME\Logs\go_backend.log`.

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/YIME_ARCHITECTURE.md) | System architecture, key mechanisms, data files |
| [Usability Assessment](docs/YIME_USABILITY_ASSESSMENT.md) | Current usability issues and priorities |
| [Development Roadmap](docs/YIME_DEVELOPMENT_ROADMAP.md) | Phased roadmap, fix workflows, AGENTS.md constraints |
| [Rime Integration](docs/YIME_RIME_INTEGRATION.md) | Rime data flow, pinyin_normalized.json chain, maintainer checklist |
| [Tooling Strategy](docs/YIME_TOOLING_STRATEGY.md) | Standalone tools vs. language-bar UI design |
| [AGENTS.md](AGENTS.md) | AI-assisted development constraints |

## Issues

Report issues in this repository. Framework-level issues that also affect upstream PIME should cross-reference [EasyIME/PIME](https://github.com/EasyIME/PIME).

## License

This repository follows the licensing inherited from the upstream project tree. See the license files in the repository root for details.
