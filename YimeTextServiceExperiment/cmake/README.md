# ARM64X TSF build

The normal x64, Win32 and ARM64 configurations are unchanged. The optional
`YIME_ARM64X_STAGE` builds one current-identity TSF DLL for both native ARM64
and emulated x64/ARM64EC hosts on Windows on Arm. Registrars and test hosts
remain architecture-specific; never register an x64 DLL over the shared
64-bit COM entry on an ARM64 machine.

Use MSVC 19.41 or newer, an ARM64/ARM64EC-capable SDK/toolset, and a Visual
Studio CMake generator that supports ARM64EC. Both stages use Release, C++17
and the static release C runtime. The opt-in configuration list contains
only Release to prevent combining incompatible runtime configurations.

1. Configure a new ARM64 build with `-DYIME_LOCAL_PRODUCT=ON` and
   `-DYIME_ARM64X_STAGE=ARM64`, then build Release. It creates
   `<native-build>/arm64x/YimeTextServiceExperiment.rsp` with absolute native
   linker inputs.
2. Configure a separate ARM64EC build with `-DYIME_LOCAL_PRODUCT=ON`,
   `-DYIME_ARM64X_STAGE=ARM64EC` and
   `-DYIME_ARM64X_NATIVE_LINK_RSP=<absolute native response-file path>`.
   Build the `YimeTextServiceExperiment` target in Release. Its DLL contains
   both ABIs. Keep the native build's objects and libraries until this link
   completes. Never combine input response files from another source build.
3. Inspect the resulting DLL and test the same file from both native ARM64
   and x64 hosts. A plain `AA64` header is insufficient: record ARM64X hybrid
   metadata and dynamic relocation evidence. A final `8664` image marked
   ARM64X can be ARM64EC-only and must not be accepted as the dual-ABI DLL.

The implementation follows Microsoft's
[ARM64X CMake build procedure](https://learn.microsoft.com/en-us/windows/arm/arm64x-build).
The lowercase `/machine:arm64x` spelling is intentional: with CMake 3.31 and
MSVC 19.44, uppercase `/MACHINE:ARM64X` is converted into a VS property before
the injected `/machine:ARM64EC` argument, which would override it. The two
real host loads protect against confusing those outputs.

This build is not installation or registered-host acceptance. A complete
ARM64 package also needs its native Runtime/Broker, architecture-specific
maintenance tools, independent x86 TSF surface, assets, and package checks.
