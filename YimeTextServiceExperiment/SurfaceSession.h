#pragma once

#include "BrokerClient.h"
#include "ExperimentSettings.h"
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
    bool CanHandle(WPARAM virtualKey, bool shiftDown,
                   bool controlDown = false, bool altDown = false);
    SurfaceOutcome HandleVirtualKey(WPARAM virtualKey, bool shiftDown,
                                    bool controlDown = false, bool altDown = false);
    SurfaceOutcome ForgetCandidate(size_t candidateIndex);
    SurfaceOutcome CommitSentence();
    bool CaptureCommitTarget(std::string* candidateId) const noexcept;
    SurfaceOutcome CommitCapturedCandidateWithSuffix(const std::string& candidateId,
                                                      const std::string& suffix);
    SurfaceOutcome FocusSentenceSegment(int start, int end);
    SurfaceOutcome ExpandSentenceSegment(int start, int end);
    void DisconnectForRecovery() noexcept;
    void Close() noexcept;
    const BrokerUpdate& CurrentUpdate() const noexcept { return current_; }

private:
    static bool TranslateCompositionKey(WPARAM virtualKey, bool shiftDown, char* code) noexcept;
    bool FindAdjacentSentenceSegment(bool previous, BrokerSegment* target) const noexcept;
    bool EnsureConnected(std::string* error);

    BrokerClient broker_;
	ExperimentSettingsCache settings_;
    BrokerUpdate current_;
    size_t selectedCandidateIndex_ = 0;
    uint64_t mutationSequence_ = 0;
    std::string mutationPrefix_;
    std::wstring pipeName_;
    DWORD reconnectTimeoutMs_ = 100;
    std::string connectedMode_;
    int connectedCandidateLimit_ = 0;
    int navigationSegmentStart_ = -1;
    int navigationSegmentEnd_ = -1;
};

}  // namespace yime::experiment
