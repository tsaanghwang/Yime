#pragma once

#include <windows.h>

#include <cstddef>
#include <cstdint>
#include <iterator>

namespace yime::experiment {

inline constexpr wchar_t kSelectionKeyDiagnosticsEnvironment[] =
    L"YIME_TEXTSERVICE_EXPERIMENT_KEY_DIAGNOSTICS";
inline constexpr std::uint64_t kSelectionKeyDiagnosticMaxBytes = 1024ULL * 1024ULL;

inline bool SelectionKeyDiagnosticsEnabled() noexcept {
    wchar_t value[2]{};
    const DWORD length = GetEnvironmentVariableW(
        kSelectionKeyDiagnosticsEnvironment, value, static_cast<DWORD>(std::size(value)));
    return length == 1 && value[0] == L'1';
}

inline bool SelectionKeyDiagnosticCanAppend(std::uint64_t currentBytes,
                                            std::size_t recordBytes) noexcept {
    return currentBytes <= kSelectionKeyDiagnosticMaxBytes &&
           recordBytes <= kSelectionKeyDiagnosticMaxBytes - currentBytes;
}

}  // namespace yime::experiment
