# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Split GitHub Actions into independently rerunnable Rust, native, Go, real-Rime, race, and installer jobs; retain commit-addressed native and installer artifacts for rollback
- Add machine-readable installed-runtime hash verification, unsigned installer smoke testing, and commit-addressed build manifests
- Restore `go test -race ./...` as a required GitHub Actions gate with an explicitly provisioned MSYS2 UCRT64 GCC toolchain and a guard that rejects silent removal
- Add regression-tested UI policy for UI-less candidate ownership, bounded candidate font sizes, and monitor-work-area popup positioning
- PE machine-type verification for Win32, x64, and ARM64 native build outputs, enforced by local builds, development installs, and CI
- Repeatable `tools/test-go-race.ps1` entry point that pins CGO, MSYS2 UCRT64 GCC, PATH, and workspace-local Go caches
- Embed Windows VERSIONINFO in server.exe and native tools via go-winres so Windows can identify file version and publisher metadata
- Native Win32 tool executables: reverse-lookup.exe, tool-hub.exe, lexicon-manager.exe, system-lexicon-audit.exe, blocklist-manager.exe, settings-tool.exe, diagnostics-tool.exe
- Go reverselookup package with disk cache and search
- Runtime user blocklist candidate filtering
- Native Win32 tool-hub.exe launcher
- Reverse lookup tool with multi-pronunciation support and detail panel
- Instant search in reverse lookup with 500ms debounce
- User lexicon manager standalone dialog
- System lexicon audit tool (read-only)
- User blocklist manager
- Settings tool and diagnostics tool as standalone Win32 executables
- Candidate page size sync with Rime menu/page_size across three layers
- Candidate layout toggle (vertical/horizontal) via single language bar button
- Rime initialization retry after transient failure (replaces sync.Once with retryable mutex)
- Enter key commits raw composition when Rime rejects it (pendingRawCommit)
- Key-down/key-up pair tracking to replace duplicate-key counter
- User feedback messages for deploy/open/clipboard/setCandidatePageSize failures
- Placeholder '?' for missing characters in reverse lookup annotations
- User lexicon rebuild for all three schema modes (variable/full/shorthand)
- Marquee progress bar and per-step status messages during reverse lookup data loading
- Chinese localization for tool hub, settings, and diagnostics UIs
- `-Add` flag for lexicon-manager.exe to open add-phrase dialog on launch
- Continuous user-lexicon add flow with explicit exit, system-lexicon duplicate rejection, and adjustable weight step controls
- Go regression-test coverage in CI for native tools, user lexicon, language-bar labels, and Rime-owned candidate paging
- Maintainer guides for release signing, test layers, native Win32 UI conventions, and security reporting
- Fixed-length lexicon importer, deterministic three-mode generator, and generation manifest with source/output hashes

### Changed

- Make the repository, installer, build, and CI product path YIME-only; permanently remove the retired Python, Node, McBopomofoWeb, libchewing backends and their submodule records
- Remove the obsolete root-level Rime/Brise/OpenCC data mirror, retired AppVeyor pipeline, Python/Node hacking guide, embedded-Python license, and root libchewing test fixtures after confirming that the YIME build and installer have no dependency on them
- Reuse message windows within the same TSF owner, keep candidate/message UI anchored after composition changes, replace duplicate language-bar button registrations, cache IME configuration metadata, and localize the missing-config-tool prompt
- Reject ambiguous legacy `build/` CMake caches unless the generated solution is demonstrably Win32; package only input-method directories that contain `ime.json`
- Finalize the independent YIME product version as `1.4.0`; future development must use a new development suffix rather than reusing this release identity
- Validate the named-pipe server executable when Windows permits process inspection, while preserving the AppContainer ACL fallback; route candidate-list replacement through a TextService API instead of directly mutating its storage
- Reduce installer locale resources to YIME-only strings and make the developer installer mirror the YIME-only payload and legal-notice layout
- Treat the fixed-length dictionary as the only external system-lexicon source; variable and shorthand dictionaries are generated runtime artifacts
- Reduce `yime_pinyin_codes.tsv` to `pinyin_tone` and `full`; derive variable and shorthand codes through the shared Go `codemode` rules
- Regenerate the shorthand system dictionary, removing 178,317 historical entries that still used variable-length codes

- Replace showUserMessage PowerShell MessageBox with direct Win32 MessageBoxW syscall, eliminating PowerShell process spawn for every user notification
- Replace copyTextToClipboard PowerShell Set-Clipboard with direct Win32 clipboard API, also fixing missing HideWindow flag that caused console flash
- Replace userLexiconAddScript PowerShell dialog with lexicon-manager.exe -Add, removing 287-line embedded PowerShell script from runtime path
- Remove ActionRunPowerShell dead code from toolhub/manifest.go (all tools now use ActionRunExecutable)
- Remove remaining runtime PowerShell helpers while retaining PowerShell only for development, testing, and build automation
- Use stable two-character language-bar labels (`中西` / `全半` / `横竖`) and represent state through icons
- Align native lexicon dialogs with content-width labels, equal-width control rows, centered action buttons, and Chinese confirmation choices
- Make Go executable builds reproducible across unrelated commits and add optional trusted Authenticode signing for Smart App Control compatibility
- Arrange reverse-lookup controls in one equal-width content layout with a content-sized window
- Replace all lexicon-manager system `OK` / `Yes/No` prompts with centered Chinese action dialogs

- Replace Get-Content with [IO.File]::ReadAllLines/ReadAllText for 5-10x faster dict.yaml loading
- Simplify lexicon manager toolbar from 12 buttons to 6; move secondary actions into menus
- Remove right-side history panel from lexicon manager; expand list to full width
- Brand renamed from PIME to Yime for Windows
- Go backend renamed from pime-rime to yime
- Language bar slimmed: removed false IME-switch assumptions
- Tool hub catalog refactored to manifest-driven architecture
- Remove obsolete PowerShell standalone tool launchers in favor of native executables
- Language bar layout toggle changed from submenu to direct toggle
- commandShouldRefreshState changed from whitelist to blacklist

### Fixed

- Missing Windows FileVersion, ProductVersion, and ProductName metadata on PIMELauncher, the NSIS installer, and the generated uninstaller
- Standard installer upgrades failing after partially deleting the installation: the old pre-install path tried to remove a still-nonempty install root and treated the resulting reboot flag as fatal, while loaded TSF DLLs were deleted recursively. Upgrades are now in-place and DLLs use staged immediate-or-reboot replacement
- Standard fresh installations requiring sign-out or reboot before PIMELauncher first started; the installer now starts it immediately after registration
- Developer reinstall still asserting and copying already-retired Python and Node runtimes after their repository removal
- Go 1.26 `go vet` failures for Win32 callback addresses by copying message structures through `RtlMoveMemory` instead of retaining `uintptr` values as Go pointers
- CI required-test guard silently omitting a renamed deployment test; required test names are now enumerated and verified before execution
- Installer losing `$INSTDIR` after a developer uninstall left a stale uninstall entry, causing files to be written under the drive root
- Standard installer omitting the Yime Go backend while selecting the legacy Python Chewing backend by default
- Developer uninstall leaving stale YIME/PIME Add/Remove Programs entries
- Upgraded full/shorthand user schemas retaining obsolete `custom_phrase` references instead of their mode-specific lexicons
- Go tests reading the developer's real runtime-change marker and redeploying test backends unexpectedly
- Smart App Control blocking server.exe due to missing VERSIONINFO
- Reverse lookup window marked as "not responding" during data loading
- Result count not displayed in reverse lookup (PowerShell single-element array unwrapping)
- Detail label content silently lost when phrase contains curly braces breaking -f formatting
- dev-install.ps1 UnauthorizedAccessException on existing HKLM Run registry key
- refresh-dev-test-cmds.ps1 preserving template timestamps instead of showing fresh timestamps
- build.bat Rime data directory cleanup failure when directory is locked
- Duplicate key-down suppression swallowing legitimate rapid same-key presses
- Enter key silently swallowed when Rime rejects it during composition
- Composition state lost when changing candidate page size
- Reverse lookup data inconsistency on schema switch
- User phrases lost when switching schema modes
- Rejected user-lexicon additions closing the continuous-add workflow or overwriting the undo snapshot
- Console flashes while rebuilding through rime_deployer.exe
- Missing characters in reverse lookup annotations discarding entire annotation
- setCandidatePageSize syntax error (extra closing brace)
- Hardcoded dev path in findRimeExternalDeployer
- parseMenuPageSizeValue failing on inline comments
- candidatePageStart reset on rejected keys
- Settings tool corrupting Rime YAML on apply
- Host crash when selecting Yime with backend down
- CSS -webkit-user-select prefix missing for Safari compatibility

### Removed

- Retired Go demo input methods (`meow`, `simple_pinyin`, and `fcitx5`) and their production fallback registrations; protocol integration tests now use a test-only fixture
- Unused remapYimeCandidateSelectionKey dead code
- Legacy PIME files removed during dev reinstall

## [1.3.0-beta2] - 2021-12-14

### Added

- Ctrl+F12 hotkey to switch Traditional/Simplified Chinese for cin-based input methods
- Simplified Chinese status icons for cin-based input methods
- Delete phrase option on candidate list
- Test input popup window in config page
- sweetalert2 for user phrase UI
- Improved config page

### Fixed

- NSIS installer script including non-installer files
- User phrase checkbox bug
- Delete phrase popup message error
- Wrong URL in config
- Typos in hsu and eten 26 keyboard layout images

### Changed

- Use jQuery UI Dialog instead of sweetalert2

### Dependencies

- Update Python to 3.8.10
- Update libchewing to 452f622
- Update sweetalert2 to v11.1.8
- Update Bootstrap to 4.6
- Update jquery-loading-overlay
- Update tornado to 6.1
- Bump debug from 2.3.3 to 2.6.9

## [1.3.0-beta] - 2020-06-01

- Initial beta release based on PIME framework with Yime (音元拼音) input method
