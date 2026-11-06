#pragma once

#include <windows.h>
#include <stdexcept>
#include <string>

namespace yime::nativehost {

// Query is RegGetValueW in the host and an injected, non-registry fixture in the
// offline suite. Keep both calls, the REG_SZ restriction and the 64-bit view in
// this shared path so the fixture exercises the actual preflight algorithm.
template<class Query>
std::wstring ReadRegisteredDll(HKEY root, const std::wstring& key, bool optional, Query&& query) {
    const auto require = [](bool valid, const char* message) {
        if (!valid) throw std::runtime_error(message);
    };
    constexpr DWORD flags = RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY;
    DWORD bytes = 0;
    LSTATUS status = query(root, key.c_str(), nullptr, flags, nullptr, nullptr, &bytes);
    if (optional && (status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND)) return {};
    require(status == ERROR_SUCCESS && bytes >= sizeof(wchar_t) && bytes < 65536 &&
        bytes % sizeof(wchar_t) == 0, "registered DLL query");
    const DWORD capacityBytes = bytes;
    std::wstring value(capacityBytes / sizeof(wchar_t), L'\0');
    status = query(root, key.c_str(), nullptr, flags, nullptr, value.data(), &bytes);
    require(status == ERROR_SUCCESS && bytes >= sizeof(wchar_t) && bytes <= capacityBytes &&
        bytes % sizeof(wchar_t) == 0, "registered DLL value");

    // RegGetValueW may report a larger required capacity than the bytes it
    // actually returns. Validate only the returned value, not unused padding.
    value.resize(bytes / sizeof(wchar_t));
    require(value.back() == L'\0', "registered DLL value");
    value.pop_back();
    require(!value.empty() && value.find(L'\0') == std::wstring::npos, "registered DLL path");
    return value;
}

} // namespace yime::nativehost
