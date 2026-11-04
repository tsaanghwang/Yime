18u ARM64 development package 0.2.0-18u-arm64.2.

Frozen source: `c9676d17e7ac396aba294980bc183c2bb4b08fca`.

Adds per-display physical ruler calibration, validated against the installed manifest and persisted for normal launches. The ASUS report was 57.5 mm for a nominal 100 mm line at 3840 x 2400 / 250%. This package can apply that measurement while fitting the 18u board by reducing only blank outer margins. Key geometry and Windows scaling are unchanged. Physical length must still be remeasured by the user.

Registered-host validation now observes Windows loading the TIP instead of preloading the expected DLL. The earlier activation-only observation passed on the previously installed package; it does not prove Notepad binding or physical input acceptance. The instructions identify the exact profile: 音元拼音·18u触摸.

Exact-source CI: four workflows, 21 successful checks, three existing manual-only skips, no failures. The attached JSON includes direct run URLs. Local native ARM64 build and package assembly passed. Installed and human finger acceptance remain pending at publication.

Run YimeMaintenance.exe -action Install from an ordinary user parent; the helper handles UAC. This package updates only YimeCore 18u Touch. Standard YimeCore and Rime/PIME remain on their separately fixed deliveries. Native ARM64 hosts are the tested target; x64/x86/ARM64EC application compatibility is unverified. Development binaries are not trusted-signed public releases.

Assets:
- `yime-yimecore-18u-windows-arm64-c9676d17e7ac.zip`: SHA256 `3f31f089a8526c369521003242ec092e54eaa9ec621b43e29a9826dd85c2d01f`, 219928196 bytes
- `yime-yimecore-18u-windows-arm64-c9676d17e7ac.identity.json`: SHA256 `058f2f0aee9e4e1c806c23c28d4bb6d51b44fa460a18517b31907a8c5539e62b`, 219346 bytes
- `source-ci-c9676d17.json`: SHA256 `f62a2b7a3f1de7966dfa201f9d1cc96828f3c91b367be42c7d40df47424c6e07`, 15442 bytes
- `native-build-c9676d17.json`: SHA256 `ebbfa7e872f16142d5895e6cb46a50c08934f52de8256d22f075fc725605c4d9`, 4300 bytes
