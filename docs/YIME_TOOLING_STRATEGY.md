# Yime Tooling Strategy

This note records the current consensus for Yime's ordinary-user surfaces.

## Decision

Treat these as standalone tools instead of language-bar-hosted dialogs whenever
possible:

- lexicon management
- settings-oriented UI
- diagnostics and log viewing
- product-specific help and trial guidance

The language bar should stay a lightweight dispatcher for commands that open or
focus external tools.

## Why

For PIME/TSF integration, opening rich UI directly from language-bar callbacks
has a higher risk of focus problems, modal-window issues, and host instability.
Standalone tools reduce that risk and are easier to iterate on independently.

## Evidence

- This repository already ships an external user-lexicon manager for Yime.
- The `C:\dev\Yime-variable-length` prototype already proved out a tool-heavy
  workflow with dedicated scripts, settings artifacts, diagnostics, and help.

## Working Rule

When we add a new ordinary-user surface:

1. Prefer a standalone window, document, or launcher entry.
2. Keep TSF/PIME menu handlers thin.
3. Route file edits, deploy/reload work, and log access through stable helper
   entry points instead of embedding more UI in the callback path.

## Current Framework

The current skeleton uses a manifest-driven tool hub:

- Go builds a typed list of standalone tool entries.
- The external tool-hub window renders buttons from that manifest.
- Standalone settings and diagnostics shells already exist as thin first
  implementations on top of that manifest.
- Future dedicated apps can replace placeholder document or folder entries
  without changing the language-bar architecture.

This does not mean every feature must become a separate executable immediately.
It means the architecture should assume "tool first, language-bar second".
