# Diagnostics

This is the placeholder diagnostics-side guide for the standalone Yime tools
direction.

Use this page as the stable landing point for future work such as:

- log collection
- runtime path checks
- deploy/reload verification steps
- focused troubleshooting flows for this input method

Current first places to inspect:

- `%LOCALAPPDATA%\PIME\Logs`
- `%APPDATA%\PIME\Rime`
- the installed `server.exe` and bundled `rime_deployer.exe`

The current diagnostics tool already checks these concrete layers:

- a findings section that turns common path/install/process combinations into
  direct troubleshooting judgments
- a structured-report copy action that formats the current diagnostics snapshot
  for sharing or filing an issue
- report presets for issue-ready sharing, local debugging, and minimal sharing,
  so the common option combinations do not need to be rebuilt by hand
- a `Custom` preset state that appears automatically after manual option
  changes, so the preset label continues to reflect the actual report shape
- saved named presets under the user data directory, so frequently used report
  shapes can survive across sessions instead of being rebuilt each time
- basic saved-preset management for overwriting the currently selected saved
  preset, renaming it, or deleting it from the user-side preset store
- preset labels that distinguish built-in choices from user-saved choices, plus
  an export action that writes the current option set to a standalone preset
  file under the user data directory
- an import action that reads those exported preset files back into the saved
  preset list, closing the loop between file sharing and in-tool reuse
- a dedicated import picker dialog for exported preset files, so importing does
  not depend on manually typing file names
- optional report layers for environment summary, mapped next actions, and a
  tail excerpt from the current primary log, so the copied report can be kept
  lightweight or turned into an issue-ready evidence bundle
- an anonymized-report mode that hides usernames, machine names, and concrete
  absolute paths before the report is copied out
- a lighter anonymization mode that hides usernames and machine names while
  keeping the surrounding path structure readable
- a keep-drive option for anonymized reports when you still want to preserve
  which volume a path came from without exposing the full location
- focused raw-log excerpt modes that can either keep the ordinary tail, reduce
  the excerpt to error-like lines, or center it around the most recent
  `onCommand` / `commandId` activity
- an error-window excerpt mode that centers the copied evidence around the most
  recent error-like line instead of the most recent command
- a command-window radius selector so the command-centered excerpt can stay
  tight for issue reports or widen out for timeline debugging
- path existence for user data, shared data, help docs, and logs
- installed runtime detection for `server.exe` and `rime_deployer.exe`
- running-process status for `PIMELauncher` and `server.exe`
- key user Rime files such as `default.custom.yaml`, `custom_phrase.txt`, and
  `yime_user_phrases.txt`
- latest log file summary, including the most recent line when available
- lightweight log interpretation for recent backend traffic, command hits,
  deploy/reload signals, and obvious error-like lines
- command-level interpretation that translates recent `commandId=` values into
  concrete language-bar actions such as deploy, reverse-lookup display, help,
  lexicon manager, and candidate-count changes
- time-related interpretation that compares the last command, the last
  deploy/reload signal, and the last error-like line
- recommended actions that turn those signals into concrete next steps such as
  retry deploy, restart PIMELauncher/server, inspect the last error line, or
  verify user-side configuration content
