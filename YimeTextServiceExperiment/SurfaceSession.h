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
    bool CanHandle(WPARAM virtualKey, bool shiftDown);
    SurfaceOutcome HandleVirtualKey(WPARAM virtualKey, bool shiftDown);
    void DisconnectForRecovery() noexcept;
    void Close() noexcept;

private:
    static bool TranslateCompositionKey(WPARAM virtualKey, bool shiftDown, char* code) noexcept;
    bool EnsureConnected(std::string* error);

    BrokerClient broker_;
    BrokerUpdate current_;
    size_t selectedCandidateIndex_ = 0;
    uint64_t mutationSequence_ = 0;
    std::wstring pipeName_;
    DWORD reconnectTimeoutMs_ = 100;
    std::string connectedMode_;
};

}  // namespace yime::experiment
