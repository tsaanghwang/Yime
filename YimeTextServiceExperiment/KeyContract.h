#pragma once

#include <windows.h>

#include <array>
#include <string_view>

namespace yime::experiment {

enum class KeyRoute {
    PassThrough,
    AppendComposition,
    BackspaceComposition,
    PreviousCandidate,
    NextCandidate,
    PreviousCandidatePage,
    NextCandidatePage,
    SelectCurrentCandidate,
    SelectCandidate,
};

struct KeyDecision {
    KeyRoute route = KeyRoute::PassThrough;
    unsigned candidateOrdinal = 0;
};

KeyDecision ClassifyVirtualKey(WPARAM virtualKey, bool shiftDown) noexcept;
const std::array<std::wstring_view, 9>& CandidateLabels() noexcept;

}  // namespace yime::experiment
