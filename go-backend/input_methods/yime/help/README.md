# Yime / PIME Help

This help menu collects the ordinary-user entry points from Yime for the PIME
Rime frontend.

## Quick Start

- Use the Yime schema from the PIME language bar settings menu.
- Choose candidates with Space, Enter, or the displayed selection keys.
- Use arrow keys, Page Up, Page Down, Home, and End to move around candidates.
- Press Esc to cancel the current composition.

## Menus

- Tool hub: opens the standalone Yime tool window. This is the preferred place
  to gather heavy UI surfaces so the TSF/PIME language bar only needs to
  dispatch lightweight commands.
- Settings: Yime variable-length, fixed-length, and shorthand schemas,
  Chinese/English mode, shape, punctuation, deploy, sync, and data folders. The
  shorthand entry is enabled when the shorthand schema is bundled with the
  installed Rime data.
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
  Because this dialog is an external window rather than the original TSF host
  context, Windows may restore another input method such as Microsoft Pinyin
  when the focus enters it. Yime does not try to forcibly seize the input
  method back inside that external window, because doing so is not aligned with
  normal Windows input-method switching and has proven likely to destabilize
  the host application, taskbar focus, or other system UI.
- Help: view this help, view trial feedback guidance, and copy a trial feedback
  template.

## Standalone Tools Direction

Yime now treats user-facing tools as standalone windows or documents whenever
that reduces pressure on the language-bar callback path.

- Lexicon management already runs as an external dialog.
- Settings-facing material, diagnostics, logs, and help should prefer the same
  pattern over adding more complex UI inside the TSF callback chain.
- The `C:\dev\Yime-variable-length` prototype is the reference proof that this
  tool-oriented workflow is practical for Yime rather than an afterthought.
- The current framework is manifest-driven: the Go backend defines the tool
  entries, and the external tool-hub window renders and dispatches them.
- The current tool hub already includes standalone settings and diagnostics
  shells, even though their detailed workflows are still intentionally light.

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
