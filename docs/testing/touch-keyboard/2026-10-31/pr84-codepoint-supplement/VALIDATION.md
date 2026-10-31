# Tool validation (2026-10-31)

- Windows PowerShell 5.1 preflight and `Read-WordCodepoints.ps1 -SelfTest` passed through `tools/powershell/run_checked.py`. Synthetic inputs cover both expected strings, extra space/paragraph/ellipsis preservation, U+2026 versus U+22EF and supplementary Unicode scalar conversion.
- The Firefox expression from README was evaluated with a stub DOM: both cases, exact string, extra space, duplicated string and over-12-character suffix (8 checks) passed. This is logic verification, not Firefox execution.
- JSON template parsing and pending states checked; staged whitespace check passed.
- At the initial implementation checkpoint, no live host readback had been executed and all four template records were pending. Subsequent user-assisted runs are documented separately in RESULTS.zh-CN.md: Word COM readback and Firefox screenshot diagnostic verification passed. The reusable template remains pending.
- PR84 archived evidence is unchanged. This supplement does not install or alter any input method.
