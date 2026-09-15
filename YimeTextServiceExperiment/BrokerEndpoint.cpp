#include "BrokerEndpoint.h"

#include <windows.h>

#include <array>

namespace yime::experiment {

std::wstring ResolveBrokerPipeName() {
    std::array<wchar_t, 512> configured{};
    const DWORD length = GetEnvironmentVariableW(
        L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", configured.data(),
        static_cast<DWORD>(configured.size()));
    if (length > 0 && length < configured.size()) {
        return std::wstring(configured.data(), length);
    }
    return kDefaultBrokerPipe;
}

}  // namespace yime::experiment
