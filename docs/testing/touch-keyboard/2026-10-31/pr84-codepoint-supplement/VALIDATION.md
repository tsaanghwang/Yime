# Tool validation (2026-10-31)

- Windows PowerShell 5.1 preflight and `Read-WordCodepoints.ps1 -SelfTest` passed through `tools/powershell/run_checked.py`. Synthetic inputs cover both expected strings, extra space/paragraph/ellipsis preservation, U+2026 versus U+22EF and supplementary Unicode scalar conversion.
- The Firefox expression from README was evaluated with a stub DOM: both cases, exact string, extra space, duplicated string and over-12-character suffix (8 checks) passed. This is logic verification, not Firefox execution.
- JSON template parsing and pending states checked; staged whitespace check passed.
- No live Word COM read, Firefox readback, input reproduction or host acceptance was executed in this implementation turn. COM attachment/permissions and current host identity still require the specified target-session run. All four result records remain pending.
- PR84 archived evidence is unchanged. This supplement does not install or alter any input method.
