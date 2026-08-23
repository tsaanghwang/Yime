#pragma once

#include <string>

namespace yime::experiment {

inline constexpr wchar_t kDefaultBrokerPipe[] = L"\\\\.\\pipe\\YimeBroker.YimeCoreTrial.v1";

std::wstring ResolveBrokerPipeName();

}  // namespace yime::experiment
