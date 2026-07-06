# Yime for Windows

Yime for Windows is a Windows Chinese phonetic input method project built on top of the [PIME](https://github.com/EasyIME/PIME) text-service framework and powered by the Rime engine.

This repository is the Windows integration and host-side implementation of Yime. It is distinct from the separate `Yime-prototype` repository, which is used for encoding, API, lexicon, and experiment-heavy prototype work.

## Project Scope

This repository focuses on the Windows product and integration layer:

- TSF host integration through the PIME-based text service.
- Rime-backed runtime behavior for the Yime input method.
- Go backend services under `go-backend`.
- Windows packaging, deployment, and runtime validation.
- Host-facing behavior such as language-bar commands, menu handling, candidate paging, and regression coverage.

In this repository:

- `PIMETextService` contains the Windows text service host implementation.
- `go-backend` contains the backend services, including the Yime integration that drives Rime.
- `python` and `node` contain supporting runtime components inherited from the broader PIME architecture where still applicable.
- `installer`, build scripts, and deployment assets support packaging and local installation workflows.

## Repository Layout

- `go-backend/`: Go services and Yime-specific backend logic.
- `PIMETextService/`: TSF text service host implementation.
- `PIMELauncher/`: launcher and runtime process management.
- `python/`: Python-side support components.
- `node/`: Node-side support components.
- `installer/`: installer assets and packaging output.
- `libIME2/`, `libchewing/`, `McBopomofoWeb/`: upstream or related components preserved in the Windows host tree.

## Development Status

The project is currently organized around these branches:

- `main`: stable baseline for the Windows repository.
- `yime-on-pime`: active Windows integration branch.

The prototype and transition-oriented reference materials live in the separate `Yime-prototype` repository.

## Build Requirements

- [CMake](http://www.cmake.org/) 3.0 or later
- [Visual Studio 2019](https://visualstudio.microsoft.com/vs)
- [Rust Toolchain](https://rustup.rs/) with `i686-pc-windows-msvc`
- [Git](https://git-scm.com/)
- [Node.js](https://nodejs.org/)

## Build

Clone the repository and initialize submodules:

```powershell
git clone <your-fork-url>/Yime.git
cd Yime
git submodule update --init
```

Install the 32-bit Rust target if needed:

```powershell
rustup target add i686-pc-windows-msvc
```

Build the 32-bit host:

```powershell
cmake . -Bbuild -G "Visual Studio 16 2019" -A Win32
cmake --build build --config Release
```

Build the 64-bit text service host for 64-bit applications:

```powershell
cmake . -Bbuild64 -G "Visual Studio 16 2019" -A x64
cmake --build build64 --config Release --target PIMETextService
```

Generated installer artifacts are placed under the installer output path after packaging.

## Initial Checklist

Use this checklist for a first local bring-up or when validating that a fresh sync is still healthy:

- [ ] Clone the repository, initialize submodules, and confirm the required toolchain is installed.
- [ ] Run `Build.cmd` from the repository root to build the Windows host components.
- [ ] Run `cmd /c build.bat` from `go-backend` to rebuild the Go backend package.
- [ ] If Yime Rime data changed, deploy or refresh it with `tools\deploy-yime-rime-data.ps1` as described in [docs/YIME_RIME_INTEGRATION.md](/C:/dev/Yime/docs/YIME_RIME_INTEGRATION.md:1).
- [ ] Reinstall the local test runtime with `Reinstall-PIME-Test.cmd` from an elevated prompt.
- [ ] Switch to Yime and sanity-check activation, candidate display, settings, and reverse lookup behavior.
- [ ] Run `go test ./input_methods/yime/...` from `go-backend` before shipping backend-facing changes.

For deeper Yime/Rime data maintenance steps, including the vendored `pinyin_normalized.json` flow, see the maintainer checklist in [docs/YIME_RIME_INTEGRATION.md](/C:/dev/Yime/docs/YIME_RIME_INTEGRATION.md:100).

## Install Notes

Typical local installation requires:

- placing `PIMETextService.dll` under both `x86` and `x64` runtime directories
- copying required runtime folders such as `python` and `node`
- registering the text service with `regsvr32` as Administrator

Example registration commands:

```powershell
regsvr32 "C:\Program Files (x86)\YIME\x86\PIMETextService.dll"
regsvr32 "C:\Program Files (x86)\YIME\x64\PIMETextService.dll"
```

To unregister:

```powershell
regsvr32 /u "C:\Program Files (x86)\YIME\x86\PIMETextService.dll"
regsvr32 /u "C:\Program Files (x86)\YIME\x64\PIMETextService.dll"
```

## Debugging

To run the launcher with a console window:

```powershell
PIMELauncher.exe /console
```

This is useful when investigating backend startup, host callbacks, menu commands, and runtime integration issues.

## Issues

Report repository-specific issues in this repository.

Framework-level issues that also affect upstream PIME may also need cross-reference against [EasyIME/PIME](https://github.com/EasyIME/PIME).

## License

This repository follows the licensing inherited from the upstream project tree. See the license files in the repository root for details.
