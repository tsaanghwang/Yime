#pragma once

#include "BrokerClient.h"
#include "KeyContract.h"

#include <string>

namespace yime::experiment {

struct SurfaceOutcome {
    bool handled = false;
    BrokerUpdate update;
    std::string error;
};

class SurfaceSession {
public:
    bool Connect(const std::wstring& pipeName, DWORD timeoutMs, std::string* error);
    bool IsConnected() const noexcept { return broker_.IsConnected(); }
    bool CanHandle(WPARAM virtualKey, bool shiftDown) const noexcept;
    SurfaceOutcome HandleVirtualKey(WPARAM virtualKey, bool shiftDown);
    void Close() noexcept { broker_.Close(); }

private:
    static bool TranslateCompositionKey(WPARAM virtualKey, bool shiftDown, char* code) noexcept;

    BrokerClient broker_;
    BrokerUpdate current_;
    uint64_t mutationSequence_ = 0;
};

}  // namespace yime::experiment
