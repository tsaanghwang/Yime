# Yime / PIME Help

This help menu collects the ordinary-user entry points from Yime for the PIME
Rime frontend.

## Quick Start

- Use the Yime schema from the PIME language bar settings menu.
- Choose candidates with Space, Enter, or the displayed selection keys.
- Use arrow keys, Page Up, Page Down, Home, and End to move around candidates.
- Press Esc to cancel the current composition.

## Menus

- Settings: Yime variable-length, fixed-length, and shorthand schemas,
  Chinese/English mode, shape, punctuation, deploy, sync, and data folders. The
  shorthand entry is enabled when the shorthand schema is bundled with the
  installed Rime data.
- Reverse code lookup: choose how reverse lookup codes are displayed for Hanzi.
- User lexicon: add, edit, apply, and open the user lexicon folder. The
  add-phrase flow opens a small dialog, reads the clipboard as the default
  phrase, and asks for numeric-tone pinyin, for example `zhong1 guo2`, because
  it is much easier to type than pinyin with tone marks. Editable entries are
  written to `%APPDATA%\PIME\Rime\yime_user_phrases.txt` as
  `phrase<TAB>numeric-tone-pinyin<TAB>weight`; applying the lexicon generates
  Rime's `%APPDATA%\PIME\Rime\custom_phrase.txt` table-code file.
- Help: view this help, view trial feedback guidance, and copy a trial feedback
  template.

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
