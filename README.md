# Yime for Windows

**Yime (音元拼音)** maps attested Pinyin syllables through a formal syllable encoder into Yinyuan input codes. It provides variable, full and shorthand modes derived from the same canonical records and keyboard layout.

[简体中文](README.zh-CN.md) · [Documentation](docs/README.md) · [Project status](docs/YIME_PROJECT_ASSESSMENT.md) · [Roadmap](docs/YIME_DEVELOPMENT_ROADMAP.md)

## Two independent products

| Product | Role | Runtime | Development entry |
|---|---|---|---|
| **YimeCore** | Primary development line | Independent Go core, Runtime/Broker, C++ TSF and candidate UI | [Build and experiment tools](tools/yimecore/README.md) |
| **Rime/PIME** | Independently maintained stable product | librime, Go product logic, Rust PIMELauncher, C++ PIME/TSF | [Go backend](go-backend/README.md), [Rime integration](docs/YIME_RIME_INTEGRATION.md) |

Install either product or both. Each owns its installation directory, runtime endpoints, registration identity, settings, learning and user lexicon. Neither requires the other to run or be maintained. They share canonical sources and offline tooling; each package carries its own generated assets. There is no automatic cross-product learning migration or requirement for feature parity. See the [product plan](docs/project/YIME_DUAL_PRODUCT_DEVELOPMENT_PLAN_2026-09-05.md) and [architecture](docs/YIME_ARCHITECTURE.md).

## Current status

Reviewed on September 19, 2026 against `main` at `d8776121`; the delivered package remains built from `c5216861`:

- `installer/simple/` supports installing, uninstalling and reinstalling either or both products, with explicit test-data reset.
- The September 14, 2026 source candidate completed acceptance within the reported scope on the development and test PCs. Both products worked in Codex and Notepad before and after reboot on the test PC; Word was not reported. These results belong to that historical package. See [validation](installer/simple/VALIDATION.md).
- PR #57 added package completeness checks and stopped destructive cleanup when profile removal fails. A complete dual-product package from `c5216861`, its provenance and local validation scope are recorded in [HANDOFF](installer/simple/HANDOFF.md). This delivery does not include new installed/input acceptance or request installation; the previous ZIP is not acceptance evidence for this package.
- The current general package targets x64 Windows and WOW64 applications. ARM64 remains a separate source experiment without a delivered complete installer or native-host acceptance.
- Trusted signed distribution, outstanding YimeCore performance gates and production data migration remain unfinished. See [project status](docs/YIME_PROJECT_ASSESSMENT.md) for the exact boundaries.

## Install and use

For development and controlled testing, extract a complete package and run `Install-Uninstall.cmd` from Explorer. Select the action and product. A single-product package also provides `Setup.cmd`. The target machine does not need Python, Git or the other product.

The [handoff](installer/simple/HANDOFF.md) records package URLs, sizes, SHA-256 hashes, provenance and whether any new test action is requested. A source checkout is not package delivery, and completed historical instructions do not request another installation.

Save work and close applications using the selected input method before maintenance. Retry or cancel if files remain in use; a normal reboot may be needed. User data is preserved by default; `-ResetData` clears the selected product's entire user-data directory for an authorized development/test reset. See the [installer guide](installer/simple/README.md) for logs, exit codes and details.

## Input rules

Full mode retains the four-Yinyuan syllable structure. Variable mode merges eligible adjacent equal units within the syllable stem; shorthand mode further omits eligible middle-tone stem units. Initial and zero-initial boundaries remain explicit. See the [data and encoding reference](docs/YIME_DATA_FORMAT_REFERENCE.md#首音干音与三模式派生).

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

- Bare `0`–`9` always enter composition codes, including while candidates are visible.
- Ordinal candidate selection uses `Shift+1`–`Shift+9`, displayed as `⇧1`–`⇧9`. `Shift+0` does not select a candidate.
- Menus and tools depend on the selected product. The detailed tool descriptions in the [user guide](docs/YIME_USER_INSTALL_GUIDE.md) apply to Rime/PIME; they are not a claim of complete feature parity.

## Development and validation

Use [tools/toolchain.lock.json](tools/toolchain.lock.json) and the [CI workflow](.github/workflows/ci.yaml) as the toolchain references. Builds use Windows C++ tools, CMake, Go and Python offline tools. Rime/PIME's Launcher additionally requires the full `stable-i686-pc-windows-msvc` Rust **host toolchain** and pinned Corrosion. CI uses Go 1.26.4; `go-backend/go.mod` requires at least Go 1.25.

Run repository PowerShell work through the checked entry point. Select PS7 by default and PS5 explicitly for compatibility checks; pass complex parameters in UTF-8 JSON. See the [PowerShell guide](tools/powershell/README.md).

```text
python tools/verify_toolchain_lock.py
rustup toolchain install stable-i686-pc-windows-msvc --profile minimal
python tools/powershell/run_checked.py --script Build.ps1 --edition ps7
```

The final command builds and packages **Rime/PIME**. YimeCore uses `tools/yimecore/build-local-product.ps1` to build independent current-identity payloads, followed by `installer/simple/Build-Package.ps1`. Prepare the applicable scope, speech-admission inputs and package parameters using the [YimeCore tools](tools/yimecore/README.md) and script definitions.

Choose Go, real-Rime, race, offline-tooling, native TSF and installer checks according to the affected product. The [testing guide](docs/YIME_TESTING_GUIDE.md) describes commands and actual CI coverage. Source checks, CI and installed input acceptance are separate evidence layers; documentation work does not trigger installation or default-input-method changes.

## Repository layout

| Path | Purpose |
|---|---|
| `go-backend/input_methods/yime/` | Go product packages, Rime integration, YimeCore/Broker, tools and generated data |
| `YimeTextServiceExperiment/` | YimeCore native TSF sources and tests; the directory retains its historical name |
| `PIMETextService/`, `PIMELauncher/`, `libIME2/` | Rime/PIME native host, launcher and library; libIME2 is included directly |
| `installer/simple/` | Active packaging, installation, removal and handoff |
| `syllable/`, `yime/`, `tools/lexicon/` | Python offline encoding, lexicon and review tools; not an input runtime |
| `internal_data/`, `external_data/` | Tracked canonical data, source snapshots and metadata; large inputs use a separate locked archive |
| `tools/yimecore/` | Current-identity builds, speech admission and platform experiments |
| `docs/`, `docs/testing/` | Current documentation and dated evidence |

`internal_data/manual_key_layout.json` is the only editable layout source. Do not patch generated code tables or read data from other Git worktrees. See the [repository data boundary](docs/project/YIME_REPOSITORY_DATA_BOUNDARY.md).

## Contribution and distribution

Start new work on a goal-specific `codex/*` branch from current `main`. `perf/i7-7820x-local` carries test-PC reports. The completed `codex/yimecore-replacement-experiment` phase remains in Git history. Validate new packages locally, commit and push, wait for the corresponding CI, then deliver the complete package through the handoff.

[Contributing](CONTRIBUTING.md) · [Agent constraints](AGENTS.md) · [Distribution and signing](docs/YIME_RELEASE_AND_SIGNING.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md)

The Rime/PIME product is an independently maintained downstream of [EasyIME/PIME](https://github.com/EasyIME/PIME), not an official upstream release. Relevant upstream history, copyright and licenses are retained. YimeCore runs independently. See [NOTICE.md](NOTICE.md).

PIME-derived components retain their original copyright and `LGPL-2.0-or-later` terms. Unless otherwise stated, new Yime software uses `LGPL-2.1-or-later`. Third-party engines, data, fonts and libraries retain their own licenses; see [LICENSE.txt](LICENSE.txt), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES](LICENSES).
