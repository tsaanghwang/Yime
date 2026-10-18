# Workspace reconciliation — 2026-10-18

Affected product: YimeCore registration and historical delivery documentation.

The original-layout workspace was inspected before the independent 134-key
ASCII keyboard experiment resumed. Its registration implementation duplicated
the fix already committed as `2ffee432` on
`codex/yimecore-registration-fix-20260929`; that branch delivered its package in
`2dbbe5d9`. The CMake change was identical. The source comment and stronger
regression test from `2ffee432` are retained here, including explicit WOW64
view and registry-error checks. This is reconciliation of an existing fix,
not a new installed-runtime modification.

The September 27 status edits in README, README.zh-CN, the roadmap and project
assessment are historical snapshots. September 28 raw registration and input
evidence is preserved under
`docs/testing/simple-maintenance/2026-09-28/current-issues/`; its statements
about uncommitted work describe that date. The subsequent registration-fix
delivery supersedes those pending-source statements, not the original failed
installation evidence or the package-specific acceptance scope.

Workspace settings exclude temporary build directories and select PowerShell
as the integrated terminal. Browser session files and local `output/` files
remain local. The concept-layout branch keeps its own projection and data.
No installation, default input-method change, or user-data reset was performed.

Validation: fresh x64 and Win32 Release builds of the registration tool and query test passed. CTest YimeRegistrationQueryTests passed on both architectures. The test redirects only its own process to a temporary HKCU fixture. The initial sandbox run could not create that fixture; the approved per-command run passed. Historical evidence was scanned for credential patterns before staging.
