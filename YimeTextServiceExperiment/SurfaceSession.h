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
    SurfaceSession();
    bool Connect(const std::wstring& pipeName, DWORD timeoutMs, std::string* error);
    bool IsConnected() const noexcept { return broker_.IsConnected(); }
    bool CanHandle(WPARAM virtualKey, bool shiftDown);
    SurfaceOutcome HandleVirtualKey(WPARAM virtualKey, bool shiftDown);
    SurfaceOutcome CommitSentence();
    SurfaceOutcome FocusSentenceSegment(int start, int end);
    void DisconnectForRecovery() noexcept;
    void Close() noexcept;

private:
    static bool TranslateCompositionKey(WPARAM virtualKey, bool shiftDown, char* code) noexcept;
    bool EnsureConnected(std::string* error);
    bool PrepareDynamicSentence(BrokerUpdate update, BrokerUpdate* prepared,
                                std::string* error, int preferredStart = -1,
                                int preferredEnd = -1);

    BrokerClient broker_;
    BrokerUpdate current_;
    size_t selectedCandidateIndex_ = 0;
    uint64_t mutationSequence_ = 0;
    std::string mutationPrefix_;
    std::wstring pipeName_;
    DWORD reconnectTimeoutMs_ = 100;
    std::string connectedMode_;
};

}  // namespace yime::experiment
