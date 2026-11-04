Installation update, 2026-11-04: one running-upgrade attempt restored and verified the intact old .1 Runtime/Broker/GUI before invoking this package. The corrected process-stop stage passed. The next exclusive ReadWrite file check failed for old YimeBroker18u.exe with sharing violation 32; Restart Manager reported zero users. This does not identify the historical holder. No unregister/copy occurred: the old .1 payload remains intact, its processes stopped, and standard YimeCore/Rime/PIME/default input override were unchanged. No calibration was saved and no physical acceptance passed. The failed attempt is preserved. Further work is checking the process-exit waiting boundary; this package is not a passed running-upgrade delivery. Existing assets remain unchanged.

---

18u ARM64 development package 0.2.0-18u-arm64.3.

Frozen source: `cb77b675ff6964c7b069294222200a5060316bd2`.

Corrects the installer process-exit race observed while upgrading a running .1 installation to c9676d17/.2. Runtime shutdown can terminate Broker before the installer's old process snapshot reaches its owner query. The correction retains original process handles and accepts the narrowly identified disappearance only when the original process is proven exited. Other-user and live-process/provider errors remain failures. A targeted isolated regression covers this failure path. The previous failed installation and package remain preserved.

Includes the c9676d17 per-display ruler calibration and cold TIP loading validation. The ASUS 57.5 mm observation can be saved for normal startup at 3840 x 2400 / 250%, reducing only blank outer margins to fit the board. Key geometry and Windows scaling are unchanged; the user must still remeasure the ruler and complete real finger input in the application body.

Exact-source CI completed: 19 successful checks, 3 existing manual-only skips, no failures. See the attached CI receipt for workflows and direct URLs.

Local native ARM64 build and complete archive validation passed. Installed/software/physical acceptance of this .3 package is pending at publication. Run YimeMaintenance.exe -action Install from an ordinary user parent; the installer handles UAC. Only YimeCore 18u Touch is updated. Standard YimeCore and Rime/PIME retain separate fixed deliveries and the default input method is preserved. x64/x86/ARM64EC host compatibility is unverified. Development binaries are not trusted-signed public releases.

Assets:
- `yime-yimecore-18u-windows-arm64-cb77b675ff69.zip`: SHA256 `e38b82c8b492cb93595dbca66c14fbda6019e48e131d8869477997f1bc474997`, 219928908 bytes
- `yime-yimecore-18u-windows-arm64-cb77b675ff69.identity.json`: SHA256 `0a0792016bdc75edaac038061b836e4b54e91eb166584c9ccb4e6962e6c689f3`, 219346 bytes
- `native-build-cb77b675.json`: SHA256 `fbb9e6b88c7babe7107193205c5d68fc8a851ae729912e79d927c2a9076551c0`, 4400 bytes
- `source-ci-cb77b675.json`: SHA256 `3af474a6d08c96460dadc68957c508b6680859142249376faef90cf12ea99cfd`, 14829 bytes
