## Installed/software update - 2026-11-04 13:07 (UTC+08)

On the ASUS ProArt P16 ARM64 test PC, one running upgrade from the verified original .1 Runtime/Broker/GUI completed successfully at 12:51 (UTC+08), with installer exit code 0. The installed .4 manifest and all 20 product payload files matched the fixed package. Standard YimeCore, Rime/PIME, and the default input override remained unchanged.

After installation, the existing physical observation (the 100 mm reference line measured 57.5 mm) was saved as this product's display calibration. The installed registered TSF/frontend chain passed all 18 controlled software checkpoints. The test Job was confirmed empty before restoring and verifying the ordinary-user Runtime, Broker, and keyboard GUI processes.

Physical ruler remeasurement after calibration and real finger input into the Notepad document remain pending. Controlled software checks and keyboard preview are not evidence of that physical/application acceptance. The earlier .2/.3 failures remain preserved, and the specific owner or cause of the historical .3 Broker sharing violation is still unproven.

This timestamped update supersedes only the installation/software pending status in the original publication text below. The original text and all four release assets are retained unchanged.

---

18u ARM64 development package 0.2.0-18u-arm64.4.

Frozen source: `6cea24bc665a4ded31e083a42bebd5d2d039832d`.

Strengthens installer shutdown verification by requiring the held original process handle to become signaled before protected payload replacement. A private native ARM64 fixture demonstrated that exit code 37 can be observable while the process handle still returns WAIT_TIMEOUT; an exit-code observation alone does not prove completion. The cb77b675/.3 running-upgrade attempt stopped processes but then encountered sharing violation 32 on the Broker file before payload copying. The specific cause or owner of that historical sharing violation has not been determined. This .4 change closes the demonstrated wait-completion gap; it does not claim that the historical sharing violation has been causally explained or that an installed upgrade has passed. Previous failed attempts and packages remain preserved.

Includes the c9676d17 per-display ruler calibration and cold TIP loading validation. The ASUS 57.5 mm observation can be saved for normal startup at 3840 x 2400 / 250%, reducing only blank outer margins to fit the board. Key geometry and Windows scaling are unchanged; the user must still remeasure the ruler and complete real finger input in the application body.

Exact-source CI completed: 19 successful checks, 3 existing manual-only skips, no failures. See the attached CI receipt for workflows and direct URLs.

Local native ARM64 build and complete archive validation passed. Installed/software/physical acceptance of this .4 package is pending at publication. Run YimeMaintenance.exe -action Install from an ordinary user parent; the installer handles UAC. Only YimeCore 18u Touch is updated. Standard YimeCore and Rime/PIME retain separate fixed deliveries and the default input method is preserved. x64/x86/ARM64EC host compatibility is unverified. Development binaries are not trusted-signed public releases.

Assets:
- `yime-yimecore-18u-windows-arm64-6cea24bc665a.zip`: SHA256 `432db184c1a9fcb7a981522f08f5aa3bb6e933169e2e7961e51afb2f614d10be`, 219929065 bytes
- `yime-yimecore-18u-windows-arm64-6cea24bc665a.identity.json`: SHA256 `5df7ab584b57c42153f4efdf4ba9b772f0c5a8e731bb45b01fb526886c94394d`, 219346 bytes
- `native-build-6cea24bc.json`: SHA256 `8a49f7bdec985e3fd0a54c7d7fe8a6d2c01e2805026a9ab9b8323e03bf97e3fe`, 4400 bytes
- `source-ci-6cea24bc.json`: SHA256 `5ff159535d61e36d41c707dd2bcc9ded44d12091ab6b56319d97d1cd7e63a30b`, 14927 bytes
