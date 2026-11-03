#pragma once
// Compile-time target is authoritative: never accept emulation or an opposite PE.
#if defined(_M_ARM64) && !defined(_M_ARM64EC)
inline constexpr unsigned short kInstalled18uMachine = IMAGE_FILE_MACHINE_ARM64;
inline constexpr auto kInstalled18uDirectory = L"arm64";
inline constexpr auto kInstalled18uTarget = "windows-arm64";
inline constexpr auto kInstalled18uHostArchitecture = "arm64";
inline constexpr auto kInstalled18uTsfArchitecture = "arm64";
inline constexpr auto kInstalled18uDescriptorArchitecture = "native-arm64";
inline constexpr auto kInstalled18uDllMember = "arm64/YimeTextService18u.dll";
#elif defined(_M_X64) && !defined(_M_ARM64EC)
inline constexpr unsigned short kInstalled18uMachine = IMAGE_FILE_MACHINE_AMD64;
inline constexpr auto kInstalled18uDirectory = L"x64";
inline constexpr auto kInstalled18uTarget = "windows-amd64";
inline constexpr auto kInstalled18uHostArchitecture = "amd64";
inline constexpr auto kInstalled18uTsfArchitecture = "x64";
inline constexpr auto kInstalled18uDescriptorArchitecture = "native-x64";
inline constexpr auto kInstalled18uDllMember = "x64/YimeTextService18u.dll";
#else
#error Independent 18u maintenance requires native ARM64 or AMD64, not ARM64EC or x86.
#endif
