# CI pinned i686 host installation compatibility

Run `34340996821`, source `5016de1524b6dcff43db77e4acbd1536ca76ad51`, failed in `native-build` job `102431823839` before any native compile. Rustup rejected `stable-i686-pc-windows-msvc` as a non-host toolchain and required `--force-non-host`. The quick Rust job succeeded independently; it does not change the failed native job outcome. Downstream contract and package jobs were skipped.

Both Windows jobs now inspect `rustup toolchain install --help`, add `--force-non-host` only if that installed rustup advertises it, and keep the pinned i686 host and minimal profile. Older rustup versions receive their original argument vector. Installation failure stops the step; a separate `rustup run stable-i686-pc-windows-msvc cargo --version` must also execute successfully before the build. No target-only substitution, host change, skip or relaxed aggregate was added.

The local Rustup help advertises this option. The [Rustup non-host toolchains documentation](https://github.com/rust-lang/rustup/wiki/Non-host-toolchains) explains the distinction between the architecture running the toolchain and the targets it compiles for. This repository requires the i686 host because using an x64 Rust host for the Win32 Corrosion build previously mixed host and target MSVC libraries.

Local validation: workflow scheduling and mutation regressions 9/9; actionlint and `tools/validate-build-contract.ps1` passed. These checks do not claim the new remote run or an actual fresh Rust installation passed. The failed run's result remains failure.
