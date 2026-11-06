#pragma once
#include <windows.h>
#include <cstddef>

// The compiled target owns this contract. A matching pointer width alone does
// not identify native ARM64, and neither ARM64EC nor emulation is admitted.
#if defined(_M_ARM64) && !defined(_M_ARM64EC)
inline constexpr USHORT kInstalled18uMachine = IMAGE_FILE_MACHINE_ARM64;
inline constexpr auto kInstalled18uDirectory = L"arm64";
inline constexpr auto kInstalled18uTarget = "windows-arm64";
inline constexpr auto kInstalled18uHostArchitecture = "arm64";
inline constexpr auto kInstalled18uTsfArchitecture = "arm64";
inline constexpr auto kInstalled18uDescriptorArchitecture = "native-arm64";
inline constexpr auto kInstalled18uDllMember = "arm64/YimeTextService18u.dll";
#elif defined(_M_X64) && !defined(_M_ARM64EC)
inline constexpr USHORT kInstalled18uMachine = IMAGE_FILE_MACHINE_AMD64;
inline constexpr auto kInstalled18uDirectory = L"x64";
inline constexpr auto kInstalled18uTarget = "windows-amd64";
inline constexpr auto kInstalled18uHostArchitecture = "amd64";
inline constexpr auto kInstalled18uTsfArchitecture = "x64";
inline constexpr auto kInstalled18uDescriptorArchitecture = "native-x64";
inline constexpr auto kInstalled18uDllMember = "x64/YimeTextService18u.dll";
#else
#error Independent 18u requires native ARM64 or AMD64, not ARM64EC or x86.
#endif

inline constexpr bool Installed18uNativeMachine(bool queried, USHORT process,
    USHORT native, size_t pointerBytes = sizeof(void*)) noexcept {
    return queried && process == IMAGE_FILE_MACHINE_UNKNOWN &&
        native == kInstalled18uMachine && pointerBytes == 8;
}

inline bool Installed18uNativeProcess(HANDLE process) noexcept {
    USHORT processMachine = 0, nativeMachine = 0;
    const bool queried = IsWow64Process2(process, &processMachine, &nativeMachine) != FALSE;
    return Installed18uNativeMachine(queried, processMachine, nativeMachine);
}
