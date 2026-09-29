# Current issues: development-PC results (2026-09-28)

Host: MYCOMPUTER, Windows x64 with x86 application support.
Scope: YimeCore registration conflict, terminal execution, and September 27
original-package acceptance. ARM64 hardware, production signing, and other
previously excluded release gates remain excluded.

Status: original-package recovery and the available-host pre/post-reboot input
acceptance are complete. The initial reinstall failure remains recorded. The
registration source fix is not yet committed or delivered; the terminal sandbox
launcher still fails, with an approved per-command execution path available.

## Registration defect and source fix

The original package reproduced `0x800700B7` after both unregister operations
returned success. Rime/PIME succeeded; YimeCore stopped at `register new product`.
See [original failure](raw/218f9476a0634b6792332b2bc421a3d2.admin.log) and
[failure state and log hashes](raw/registration-failure-state.json).

Controlled YimeCore-only registration diagnostics were explicitly authorized.
The existing TSF profile enumeration is not reliable as immediate persisted
registration evidence: it can report a removed profile present and a newly
registered profile absent. Changing `EnumProfiles(0804)` to `EnumProfiles(0)`
did not resolve that behavior; the failed probe was not retained as the fix.

The source fix queries the exact machine-level CTF TIP language/profile key in
the selected architecture's registry view. Missing keys mean absent; other
registry errors propagate. It retains the COM/profile/category duplicate guard
and adds registration-step diagnostics. It does not delete arbitrary registry
keys, retry registration automatically, or relax product ownership.

The [controlled passing comparison](raw/registration-persistence-verification-01.log)
shows, immediately after unregister, the original x64 and x86 tools reporting
`profile_registered=true` while the corrected tools report false. Corrected
registration then succeeds; actual duplicate registration still fails with
`0x800700B7`. New profiles are detected before user enablement. Final cleanup
verified both views absent. The original failing installer lacks step-level
logs, so its exact branch cannot be proven retrospectively from its HRESULT
alone; the state-query defect and corrected behavior were directly reproduced.

Local validation passed:

- x64 and Win32 Release registration-tool builds.
- `YimeRegistrationQueryTests` on x64 and x86, using process-local registry
  redirection: absence, disabled-but-registered profile, other language/profile
  exclusion, null output, and immediate removal.
- The controlled installed-identity checks above, including duplicate rejection
  and preservation of the Microsoft Pinyin default input override.

Changes are uncommitted and have not passed CI or been delivered in a new
package. No corrected diagnostic executable was copied into the installed
products. Do not claim that the original package contains this source fix.

## Original package acceptance

Release: <https://github.com/tsaanghwang/Yime/releases/tag/test-current-readiness-20260927-0ab86312>

- Source baseline: `0ab8631266736775bf1386f456d4a1d53e8e2eb3`.
- ZIP: `Yime-Current-Readiness-20260927.zip`, 256650784 bytes.
- SHA-256: `45c4a0d93f8a40a4c26bebf934efb10c876f1305732c1e95a2e43547f2ddd341`.
- All 239 extracted members matched the ZIP before installation:
  [verification](raw/extracted-verification.json).

Rime/PIME installation succeeded on the first attempt. After the recorded core
failure and controlled diagnosis, the unchanged original YimeCore package was
installed successfully from verified absence; this is recovery, not a passing
first-attempt reinstall. [Core recovery log](raw/e94f42f979ae4f028047f5f4eae1889c.user.log).

[Installed audit](raw/installed-audit-pre-reboot.json) passed: 65/65 core and
160/160 Rime/PIME manifest files matched, x64/x86 registrations were present,
startup values were read through external StdRegProv, and elevated read-only
inspection confirmed actual Runtime/Broker/Launcher executable paths. Ordinary
process inspection could see the elevated core PIDs but not their executable
paths; that limitation was not treated as runtime failure. Default input
remained Microsoft Pinyin; user data was not reset.

Both original installed [registered-host tests](raw/registered-host-results.json)
passed, including candidate commits, delayed edit completion, focus cancellation,
failed-write recovery, and retained language-bar lifetime checks.

The user explicitly confirmed candidate display and Shift+1 commit for both
products in Word x64 and Notepad++ x86. [Physical-input record](raw/physical-input-pre-reboot.json)
separates those confirmations from observed modules: Word loaded both installed
x64 product DLLs; the module enumeration did not capture Notepad++ product DLLs.
These checks do not constitute a full three-mode or every-feature matrix.

## Post-reboot acceptance

The [post-reboot machine audit](raw/installed-audit-post-reboot.json) observed a
new boot at `2026-09-28T08:08:21.5000000+08:00`, replacing
`2026-09-27T06:48:42.4999320+08:00`. Both package manifest hashes remained the
same as before reboot, with all 65 core and 160 Rime/PIME payload files matching.
Both products' x64/x86 registration checks and external startup readbacks passed.

Ordinary-user process inspection now confirmed installed paths: core Runtime
PID 30288 started at 08:08:53, Broker PID 30596 at 08:08:54, and Rime/PIME
Launchers PIDs 29928/30076 at 08:08:52 (local time, UTC+08:00). No runtime was
started or installation changed by this audit. The user confirmed no manual
runtime start or reinstall after reboot, supporting automatic-start acceptance.

The user again confirmed candidate display and Shift+1 commit for both products
in Word x64 and Notepad++ x86. The [post-reboot physical-input record](raw/physical-input-post-reboot.json)
keeps user confirmation separate from module observations: Word loaded both
installed x64 product DLLs; Notepad++ product modules were not captured by this
enumeration. Microsoft Pinyin remained the persistent default input method.
The installed x64/x86 synthetic registered-host results above were obtained
before reboot, not rerun or relabeled as post-reboot results.

## Terminal execution

The earlier terminal log showed a PowerShell sandbox wrapper sent to Git Bash,
producing an ampersand syntax error. The workspace default terminal profile was
changed to PowerShell, preserving existing exclusions and user settings.

Normal sandboxed execution remains defective: subsequent probes produced a
PowerShell provider error and an ampersand parsing error. No global sandbox
disable was performed. Working execution is the explicitly approved per-command
unsandboxed route, with repository PowerShell actions passed through
`python tools/powershell/run_checked.py --edition ps5`. PS7 was unavailable.
Native builds, tests, installation, and audits succeeded through that route.
This restores a usable execution path, not a verified repair of VS Code's
sandbox launcher. The post-reboot normal-sandbox audit attempt again failed
before script execution with `DriveNotFound` for
`Microsoft.PowerShell.Core\FileSystem`. The same audit passed through the
explicitly approved unsandboxed route, without elevation. The launcher problem
remains separate from the product source fix and requires further resolution.

## Remaining work

- Deliver the registration fix separately through the normal source/CI/package
  path. Do not silently replace the accepted original-package binaries.
- Resolve the VS Code sandbox launcher independently; the approved execution
  workaround is not evidence that normal sandbox execution works.
- No further restart or reinstall is requested by this completed available-host
  acceptance record. Previously excluded release gates remain excluded.
- Preserve the first failed install and diagnostic logs. The September 19
  report's failed-log reference had a wrong suffix; the actual copied historic
  log is [37498156b3a9436a934ee3af2a1f5706.admin.log](raw/37498156b3a9436a934ee3af2a1f5706.admin.log).
