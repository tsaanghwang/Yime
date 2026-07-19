# Yime / PIME Help

This help menu collects the ordinary-user entry points from Yime for the PIME
Rime frontend.

## Quick Start

- Use the Yime schema from the PIME language bar settings menu.
- Choose candidates with Space, Enter, or the displayed selection keys.
- Use arrow keys, Page Up, Page Down, Home, and End to move around candidates.
- Press Esc to cancel the current composition.

## Menus

- Tool hub: opens `tool-hub.exe`, the standalone Yime tool window. It contains
  advanced user layouts, lexicon management, reverse lookup, system-lexicon audit, blocklist,
  settings, diagnostics, data directories, help, and feedback guidance.
- Language bar quick buttons:
  - **用户词库** → `lexicon-manager.exe`
  - **反查编码** → `reverse-lookup.exe`
  - **工具中心** → `tool-hub.exe`
  - **中西 / 全半 / 横竖** — fixed two-character labels; state shown by icons
- When Windows docks the language bar in the taskbar and hides those standalone
  quick buttons, open the **设置** menu from the **中** button. Its root contains
  the equivalent **用户词库**, **反查编码**, and **工具中心** commands.
- Settings: Yime variable-length, fixed-length, and shorthand schemas,
  Chinese/English mode, shape, punctuation, and data/log folders. Guarded Rime
  maintenance commands live in the `数据维护` submenu. `重新部署…`
  requires confirmation, builds with the external deployer, validates the
  current schema, and reloads only the session at a safe request boundary; it
  is not a "re-import system lexicon" button. `同步数据…` also requires
  confirmation and uses Rime's native sync action. It does not include Yime-only
  standalone state such as `yime_settings_state.json`. The shorthand
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
- Settings tool: applies schema and candidate-display settings. It can also
  create a verified portable backup under `Documents\YIME 备份` and restore the
  latest manual backup after first creating a safety snapshot.
- Advanced layout: clones the active layout, lets an advanced user swap
  Yinyuan IDs on a keyboard diagram, test all three code modes, and save named
  profiles. Applying a profile writes only to `%APPDATA%\PIME\Rime`, migrates
  layout-dependent learning databases, explicitly compiles all three Yime
  schemas, and then asks active sessions to reload safely.
- Help: view this help or the trial-feedback guidance.

## Standalone Tools Direction

Yime treats user-facing tools as standalone Win32 executables shipped next to
`server.exe`, not as PowerShell scripts inside the TSF callback path.

- Lexicon management, reverse lookup, settings, diagnostics, system lexicon
  audit, and user blocklist all run as native GUI apps. Result lists use native
  ListView tables with headers, selection state, and scrollbars.
- The tool hub (`tool-hub.exe`) renders a manifest built in Go
  (`yime_tool_catalog.go`) and launches each tool via `run_executable`.
- Settings and lexicon deployment run outside the language-bar callback and
  notify active YIME sessions after their on-disk work completes.

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
- Portable user backups: `%USERPROFILE%\Documents\YIME 备份`
- Saved personal layouts: `%APPDATA%\PIME\Rime\yime_layouts`
