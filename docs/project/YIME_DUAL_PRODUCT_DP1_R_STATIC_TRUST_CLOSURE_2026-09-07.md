# DP1-R: static payload and generated-uninstaller trust closure

Affected product: the independent Rime/PIME product. YimeCore, installed products, the default input method and production user data are outside this change. DP1-R reviews the existing DP1-P isolated successor and derives a new, bounded trust decision without rewriting any historical build, postbuild, receipt or candidate evidence.

## Narrow outcome

- Full payload static closure: **PASS**.
- NSIS non-OS compiler-input closure: **PASS**.
- Generated uninstaller verification and trust for the unsigned, disabled, static-review scope: **PASS**.
- Independent PS5/PS7 postbuild convergence: **PASS**.
- Physical prevention of same-SID replacement, full NSIS toolchain closure including the operating system, signature trust, signing, delivery and installer execution: **not established**.

The admission implementation is commit `9a94c63941c9f8e938f766421138a933829b8819`, tree `84c9347f70ea8555aa52c0af9d38d007eee9f417`. The tracked [structured evidence](../testing/dual-product/2026-09-07-dp1-r-static-trust-closure.json) binds that source, both 15/15 regression runs, the current-source baseline, both independent actual-candidate reviews and all non-claims. Its SHA-256 sidecar is stored alongside it.

## What is admitted

`Get-RimePimeDp1RTrustAdmission` is the module's only export. It accepts pure data for the historical compiler result, independent PS5 and PS7 postbuild results, and an audit of the actual NSIS sources. It requires the full compiler interval to be armed before launch and completed only after the synchronous `makensis` process exits, with zero membership events, uninterrupted exact-file leases, exact staged and raw archive bindings, 181 outer entries, 11 generated-uninstaller entries and PS5/PS7 agreement on the installer, generated uninstaller, build result and product identity.

The source audit reads the candidate's `installer.nsi`, generated payload include and locale includes. It rejects dynamic compiler directives, environment macro reads, wildcard payload reads or an open include-root set. It also requires the source hashes used by the actual build-result evidence. These checks make the candidate payload and non-OS inputs statically closed for this exact unsigned, disabled artifact.

The generated uninstaller is trusted only as bytes extracted from that exact installer and matched independently under PS5 and PS7. This is enough for later controlled static migration work. It does not turn an unsigned executable into a signed release artifact and does not authorize running it.

## Honest historical boundary

DP1-R does not edit the DP1-P build result or either postbuild result. Their historical `final_payload_closure`, `nsis_non_os_compiler_input_closure`, `full_nsis_toolchain_input_closure`, `generated_uninstaller_trusted`, signing and delivery fields remain false. The new truth is a separate derived admission record that requires those historical non-claims to remain false, preventing later evidence from being backdated into an earlier stage.

The full NSIS toolchain field stays false because this review closes the copied NSIS distribution, build scripts, staged payload and other non-OS inputs, but does not claim the Windows kernel, filesystem implementation, loader, trust infrastructure or every ambient OS dependency. The physical same-SID field also stays false: DP1-K/MEMBERSHIP-05 detects and rejects transient unlisted tree members across the entire compiler interval, but it does not make same-SID interference physically impossible.

## Actual candidate review

The existing DP1-P successor `YIME-1.4.0-dev.1-setup.exe` was reviewed in place without executing it:

| Item | Evidence |
| --- | --- |
| Installer | 41,455,231 bytes; SHA-256 `ac97f65af80e9686525a3c2f289670aaa14edb60a6effc80ce7cc3580333970d` |
| Generated uninstaller | 585,292 bytes; SHA-256 `ffd37a56d45b8c108c0c8e1c5780cfdcc41babcb435012aac7c88a6a6416fb26` |
| Membership-interval build result | SHA-256 `65ab931e7238e59855d1ccf27abc7aa371406073a9d27220132608d899bd7195` |
| Independent PS5 postbuild result | SHA-256 `548333f4dd096061eabfffd2283a64e903c5ceaff26a9ff82623fe9ecb817b10` |
| Independent PS7 postbuild result | SHA-256 `7dd531596cc4fe943596c4782e54670330b63055e9e0b7177f1ffa419b202c49` |
| Actual installer source | SHA-256 `06de32b208d74949c63b2c1b9be84f66675113570e367fe76a07a4167e70a35d` |
| Generated payload include | SHA-256 `5087ce979db68b9e0ffa8d6ee6532708bf9c5d5be25818a1e7cbb5c03b11e730` |

The read-only review passed once under each selected shell. The result SHA-256 values are `4167cca64ce9c03796f749a521f239c7ec21713cf731db51af25f82788c7b821` and `6d2fe295b926c620e3f8813db8c8bee026e4ae832ef3b76593e12f1d7cd52524`. The review result does not self-report its shell, so the selecting commands and isolated result paths are the shell evidence. Both converge on every admission fact above.

## Regression and baseline evidence

| Suite | Result | Sealed result SHA-256 |
| --- | --- | --- |
| Trust admission, Windows PowerShell 5.1 | 15/15 | `a7a1c7ea058378e0fd1c032d946184356dce5199c6127f560db92be3aa9f6813` |
| Trust admission, PowerShell 7.6.5 | 15/15 | `e6f14bb829cee798f55bb55d4456479a3aa4a3407a5a7b4892413bc448dc9c3f` |
| Current-source baseline | 150 sources; 65/65; 7 pending | `2e1edf61eb33a97b5fc11fb134b5170e06e0f3b35068ef7c8a06f9b946c94062` |

The negative matrix rejects an observed membership event, a missing post-exit completion barrier, a compiler-input lease gap, PS5/PS7 installer or uninstaller disagreement, extra outer or nested archive members, a missing raw uninstaller binding, an open source-input audit, payload-source mismatch, historical field promotion and `ScriptProperty` input. Build guards also passed under PS5 and PS7 with `-SkipPackagedRime`.

No installer or uninstaller was run. No registry, profile, product process, installed Rime/PIME runtime, default input method, production user data or YimeCore local.12 state was read or changed by the actual review.

## Remaining ordered gates

DP1-R does not archive the transient candidate evidence outside the repository and does not authorize or execute canonical migration. DP1-S must publish and reopen an actual off-repository evidence capsule and keep directory-metadata, power-loss and hostile same-SID conclusions at their observed levels. DP1-T then supplies the dedicated actual adapter and one-time migration authorization; DP1-U covers registration convergence, rollback, concurrent-safe removal and non-elevated Runtime readiness. DP1, DP2, DP3, L5 and L6 remain incomplete.

The dual-product decision is unchanged: Rime/PIME and YimeCore may be installed alone or together, and each remains independent of the other's runtime, installation, maintenance, writable state and recovery.
