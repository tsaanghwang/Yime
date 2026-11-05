18u ARM64 development package 0.2.0-18u-arm64.5.

Frozen source: `636cef681ee995a21a9c45fd750f8cb4b0acb4a1`. This package rebuilds the matching frontend, Broker and TIP from that source. Package version .5 is an explicit process-local build parameter; the source constant .4 was not modified. The attached version configuration records that distinction.

Fixes the installed Broker path's assumption that the foreground top-level window and focused text control share a thread. Discovery, routing and final TSF edits now check the exact focused control, its root/process/thread, context and lease. GUI errors preserve available rejection stages and backend detail instead of replacing everything with a generic preview-session error. Some native failures still lack a detailed error field; error messages are not a persistent diagnostic log.

Exact-source CI: four successful workflows, 21 successful jobs, three specified existing manual-only skips, zero failures. Direct workflow URLs and job identities are in the attached CI receipt. Local native ARM64 source build and per-member complete-archive hash verification passed.

Installed upgrade and real Notepad body input for this .5 package are PENDING at publication. Source/substitute-TSF checks do not establish the cause of the historical ASUS failure or physical acceptance. The existing ASUS ruler result and older successful/failed records remain separate. Standard YimeCore, Rime/PIME, the default input method and user data are outside this package update; no installation has been performed by publishing.

This is the complete matching ARM64 maintenance package. Do not replace only the DLL or mix .4/.5 frontend/Broker/TIP files. Development prerelease; not the latest stable release. Native ARM64 is the target; no new x64/x86/ARM64EC host acceptance is claimed.

Assets:
- `yime-yimecore-18u-windows-arm64-636cef681ee9.zip`: SHA-256 `e482200ea81a8241a4780feaa07b01a53bb8b177ec62b5c2496e158a7b00b36c`, 219933775 bytes
- `yime-yimecore-18u-windows-arm64-636cef681ee9.identity.json`: SHA-256 `d94ac9817f5e4c6b2090ec64bad6ff79a124efe9d71c086876c348207287ceb1`, 219346 bytes
- `native-build-636cef68.json`: SHA-256 `8b41c11ad60812a50f5d1a82473cea57525d47c889b66c7e16150563543c8258`, 5474 bytes
- `source-ci-636cef68.json`: SHA-256 `f4784a222ee87b257395557acd3dccb208c7121848276c03dea617b884ad27ad`, 5682 bytes
- `complete-package-636cef68.json`: SHA-256 `52e72a0e063b2eaf5f1080f107dd4c9e42ae87ac75886c24b560b3d50b2b43b2`, 1723 bytes
- `version-configuration-636cef68.json`: SHA-256 `76c6190ef69c04ebd830ed9a44d1f1f35ebcb077faca339fe5f709bd47e66c05`, 279 bytes
