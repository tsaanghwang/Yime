# Existing experiment checkpoint — 2026-10-18

This commit preserves the previously uncommitted 138-key experiment together
with subsequent 132/134-key design drafts, before implementing the selected
CN/EN 134-key pair. It is a work-in-progress checkpoint, not a passing 134-key
runtime or a production layout update.

The current `design/keyboard-layout.json` draft has 134 keys and its left Num
Lock starts at x=2, while the generated `data/physical-layout.json`, generator,
tests and runtime documentation still describe the earlier 138-key model.
Consequently `validate.py` currently fails the independent numeric-zone
contract. The selected `yime-cn-134k-24u-keyboard-layout.json` and matching EN
file have the agreed geometry and are the inputs for the next implementation.
Their runtime data must be generated and verified before the page is used.

Checks at this checkpoint: `tools/generate_ascii_layout.py --check` passed;
Go tests for `cmd/yime-keyboard-lab`, `codemode` and `systemlexicon` passed.
The failed physical-generation check above remains explicit. Historical
138-key full-corpus/browser results retain their original scope and date.

The independent original-layout workspace is reconciled on
`codex/workspace-reconciliation-20261018`, separately from this experiment.
The touch display is now available; current 134-key physical acceptance has
not yet been performed. No installed input method was changed.
