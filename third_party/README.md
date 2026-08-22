# Vendored build dependencies

This directory contains build-time source dependencies required to configure a
fresh Yime checkout without network access.

- `corrosion/` is Corrosion v0.6.1 from upstream commit
  `1499b14e4906a2890f5cee1547c8848db261753d`.
- Upstream: <https://github.com/corrosion-rs/corrosion>
- License: MIT; the authoritative text remains in `corrosion/LICENSE`.
- The complete copied source tree is content-locked by
  `tools/verify_vendored_build_dependencies.py`.

Do not update this snapshot independently of `CMakeLists.txt`, the verifier,
the Win32 build guard, and a clean offline configure/build test.
