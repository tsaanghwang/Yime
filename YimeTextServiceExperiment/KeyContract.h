#pragma once

#include <windows.h>

#include <array>
#include <string_view>

namespace yime::experiment {

enum class KeyRoute {
    PassThrough,
    OpenPunctuationPalette,
    AppendComposition,
    BackspaceComposition,
	ClearComposition,
    PreviousCandidate,
    NextCandidate,
    PreviousCandidatePage,
    NextCandidatePage,
    PreviousSentenceSegment,
    NextSentenceSegment,
    ForgetCurrentCandidate,
    SelectCurrentCandidate,
    SelectCandidate,
};

struct KeyDecision {
    KeyRoute route = KeyRoute::PassThrough;
    unsigned candidateOrdinal = 0;
};

KeyDecision ClassifyVirtualKey(WPARAM virtualKey, bool shiftDown,
                               bool controlDown = false, bool altDown = false) noexcept;
const std::array<std::wstring_view, 9>& CandidateLabels() noexcept;

class ShiftTapTracker final {
public:
    bool OnKeyDown(WPARAM virtualKey) noexcept;
    bool OnKeyUp(WPARAM virtualKey) noexcept;
    void Reset() noexcept { armed_ = false; }

private:
    bool armed_ = false;
};

}  // namespace yime::experiment
