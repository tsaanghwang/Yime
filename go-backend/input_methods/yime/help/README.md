# Yime / PIME Help

This help menu collects the ordinary-user entry points from Yime for the PIME
Rime frontend.

## Quick Start

- Use the Yime schema from the PIME language bar settings menu.
- Choose candidates with Space, Enter, or the displayed selection keys.
- Use arrow keys, Page Up, Page Down, Home, and End to move around candidates.
- Press Esc to cancel the current composition.

## Menus

- Tool hub: opens `tool-hub.exe`, the standalone Yime tool window. This is the
  preferred place to gather heavy UI surfaces so the TSF/PIME language bar only
  needs to dispatch lightweight commands.
- Language bar quick buttons:
  - **用户词库** → `lexicon-manager.exe`
  - **反查编码** → `reverse-lookup.exe`
  - **工具** → `tool-hub.exe`
  - **中西切换 / 全半切换 / 横竖切换** — fixed labels; state shown by icons
- Settings: Yime variable-length, fixed-length, and shorthand schemas,
  Chinese/English mode, shape, punctuation, `重新部署 Rime`, `同步 Rime 用户数据`,
  and data/log folders. `重新部署 Rime` is the full runtime redeploy path for the
  currently installed Rime data; it is not a "re-import system lexicon" button.
  `同步 Rime 用户数据` is Rime's native user-data sync action and does not include
  Yime-only standalone state such as `yime_settings_state.json`. The shorthand
  entry is enabled when the shorthand schema is bundled with the installed
  Rime data.
- Reverse code lookup: choose how reverse lookup codes are displayed for Hanzi.
- User lexicon: opens the independent lexicon-manager dialog for adding,
  deleting, editing, searching, importing, exporting, and applying the user
  lexicon. The window also supports weight editing, visible-list sorting, and
  an unapplied-change status so the user can tell whether the source lexicon
  has already been pushed into Rime's generated table. It also supports
  conflict-preview import, selective conflict merge, recent-operation history,
  one-step undo for the most recent source-lexicon change, and copying a
  concise operation summary for issue reports. The import preview can switch
  between conflict and new-entry views and can copy a concise import summary.
  It shows the editable source file and generated Rime lexicon paths so issue
  reports can point to the right files quickly. The
  editable source file is `%APPDATA%\PIME\Rime\yime_user_phrases.txt`, using the format
  `phrase<TAB>numeric-tone-pinyin<TAB>weight`; applying the lexicon generates
  Rime's `%APPDATA%\PIME\Rime\custom_phrase.txt` table-code file.
- Help: view this help, view trial feedback guidance, and copy a trial feedback
  template.

## Standalone Tools Direction

Yime treats user-facing tools as standalone Win32 executables shipped next to
`server.exe`, not as PowerShell scripts inside the TSF callback path.

- Lexicon management, reverse lookup, settings, diagnostics, system lexicon
  audit, and user blocklist all run as native GUI apps.
- The tool hub (`tool-hub.exe`) renders a manifest built in Go
  (`yime_tool_catalog.go`) and launches each tool via `run_executable`.
- The `C:\dev\Yime-variable-length` prototype is the reference proof that this
  tool-oriented workflow is practical for Yime rather than an afterthought.
- Repository-side debugging also has a local helper
  `go-backend\run_admin_yime_tests.cmd` for repeatable elevated test attempts.
  It is for developer troubleshooting only and is not part of the installed
  runtime surface.

## Reverse Code Lookup

The reverse code lookup menu controls what code representations should be shown
for Chinese text lookup:

- Hidden: keep only candidate/status information.
- Standard pinyin.
- Yime pinyin.
- Key sequence.

Numeric-tone pinyin is intentionally not a normal display mode. It is an input
format for adding user phrases, where typing `lv4` or `ri4 ben3` is practical
and typing tone-marked pinyin is not.

## Data Locations

- PIME user Rime data: `%APPDATA%\PIME\Rime`
- PIME shared Rime data: installed under
  `PIME\go-backend\input_methods\yime\data`
- PIME Go backend logs: `%LOCALAPPDATA%\PIME\Logs`
