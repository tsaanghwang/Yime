# Yime Tooling Strategy

This note records the current consensus for Yime's ordinary-user surfaces.

## Decision

Treat these as standalone tools instead of language-bar-hosted dialogs whenever
possible:

- lexicon management
- settings-oriented UI
- diagnostics and log viewing
- reverse code lookup
- system lexicon audit (read-only)
- user blocklist management
- product-specific help and trial guidance

The language bar should stay a lightweight dispatcher for commands that open or
focus external tools.

## Why

For PIME/TSF integration, opening rich UI directly from language-bar callbacks
has a higher risk of focus problems, modal-window issues, and host instability.
Standalone tools reduce that risk and are easier to iterate on independently.

Early prototypes used embedded PowerShell WinForms scripts. As of 2026-07-09
those surfaces have migrated to **Go-built Win32 GUI executables** shipped next
to `server.exe`, launched via `run_executable` from the tool hub or language
bar.

## Evidence

- This repository ships native tool executables from `go-backend/build.bat`.
- The `C:\dev\Yime-variable-length` prototype already proved out a tool-heavy
  workflow with dedicated scripts, settings artifacts, diagnostics, and help.
- Production incidents with hidden PowerShell child processes (encoding,
  focus, and silent exit) motivated the move to compiled tools.

## Working Rule

When we add a new ordinary-user surface:

1. Prefer a standalone window, document, or launcher entry.
2. Keep TSF/PIME menu handlers thin.
3. Route file edits, deploy/reload work, and log access through stable helper
   entry points instead of embedding more UI in the callback path.
4. Register the tool in `yime_tool_catalog.go` and build it from `go-backend/cmd/`.

## Current Framework

The current implementation uses a manifest-driven tool hub:

- Go builds a typed list of standalone tool entries (`buildToolHubManifest`).
- `tool-hub.exe` renders buttons from that manifest.
- Each entry uses either `run_executable` (native tool) or `open_path` (folders,
  help HTML).
- Language-bar buttons for lexicon, reverse lookup, and the hub itself launch
  the same executables directly.
- Settings, diagnostics, lexicon manager, reverse lookup, system lexicon audit,
  and blocklist manager are all native Win32 apps with Chinese UI.
- Lexicon-manager notices use native custom dialogs with Chinese action labels;
  operational paths no longer expose system `OK` or `Yes/No` buttons.

Shipped executables (under `go-backend/` in the install tree):

| Executable | Purpose |
|------------|---------|
| `tool-hub.exe` | Tool catalog launcher |
| `settings-tool.exe` | Schema, page size, reverse-lookup display, layout |
| `diagnostics-tool.exe` | Paths, processes, logs, issue-ready report presets |
| `lexicon-manager.exe` | User phrase source file CRUD and apply |
| `reverse-lookup.exe` | Hanzi → pinyin / Yime code lookup |
| `system-lexicon-audit.exe` | Read-only scan of bundled dictionaries |
| `blocklist-manager.exe` | User blocklist editing |

This does not mean every future feature must become a separate executable
immediately. It means the architecture assumes "tool first, language-bar second",
and new heavy UI should default to the native executable pattern rather than
PowerShell-in-callback.

## Build Identity And Signing

Tool versions come from the stable repository `version.txt`. Go builds use
`-trimpath -buildvcs=false` so unrelated commits do not create new hashes for
unchanged tools. Release builds can set `YIME_SIGN_CERT_SHA1` (and optionally
`YIME_SIGNTOOL_EXE` / `YIME_TIMESTAMP_URL`) to sign every Go executable.
VERSIONINFO is required metadata, but Smart App Control compatibility ultimately
requires an RSA code-signing certificate from a trusted provider.
