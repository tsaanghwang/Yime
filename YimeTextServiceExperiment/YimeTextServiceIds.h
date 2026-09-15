#pragma once

#include <guiddef.h>

// The historical service/profile identifiers stay independent from PIME.
// Current-PC local x64 builds generate a second identity from the canonical
// product descriptor so the frozen x86 profile remains byte-for-byte owned by
// the historical identifiers.
// Its language item deliberately uses Windows' reserved input-mode GUID so
// the host replaces CH/EN and exposes the same slot in the docked taskbar.
#ifdef YIME_LOCAL_PRODUCT
#include "LocalProductIdentity.h"
#else
inline constexpr GUID CLSID_YimeTextServiceExperiment =
    {0x41ec6c9b, 0xe8d2, 0x4e1e, {0x9e, 0x7c, 0x5c, 0xa3, 0xda, 0xf0, 0xf6, 0x6b}};
inline constexpr GUID GUID_YimeTextServiceExperimentProfile =
    {0x607895a8, 0x9504, 0x4a2e, {0x9b, 0xb1, 0x2c, 0x15, 0x9e, 0x3a, 0x17, 0x57}};
#endif
inline constexpr GUID GUID_YimeTextServiceExperimentLangBar =
    {0x2c77a81e, 0x41cc, 0x4178, {0xa3, 0xa7, 0x5f, 0x8a, 0x98, 0x75, 0x68, 0xe6}};
inline constexpr GUID GUID_YimeTextServiceExperimentCandidateList =
    {0x88920717, 0xb33e, 0x4471, {0xbf, 0x91, 0x9c, 0x8b, 0x6c, 0xd2, 0xf6, 0x74}};

// Windows 8+ TIP capabilities used by the built-in taskbar input indicator.
// Older SDKs did not publish names for these GUIDs, so keep the values local
// just as the production PIME host does.
inline constexpr GUID GUID_YimeTipcapImmersiveSupport =
    {0x13a016df, 0x560b, 0x46cd, {0x94, 0x7a, 0x4c, 0x3a, 0xf1, 0xe0, 0xe3, 0x5d}};
inline constexpr GUID GUID_YimeTipcapSystraySupport =
    {0x25504fb4, 0x7bab, 0x4bc1, {0x9c, 0x69, 0xcf, 0x81, 0x89, 0x0f, 0x0e, 0xf5}};
