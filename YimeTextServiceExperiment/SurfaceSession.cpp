#include "SurfaceSession.h"

#include <objbase.h>

#include <array>
#include <cstdio>

#include "ExperimentSettings.h"

namespace yime::experiment {

namespace {

bool IsKnownSentenceSegment(const BrokerCandidate& sentence, int start, int end) noexcept {
    for (const auto& segment : sentence.segments) {
        if (segment.start == start && segment.end == end) return true;
    }
    return sentence.segments.empty() && !sentence.text.empty() && start == 0 &&
           end == static_cast<int>(sentence.code.size());
}

}  // namespace

SurfaceSession::SurfaceSession() {
    GUID value{};
    char buffer[96]{};
    if (SUCCEEDED(CoCreateGuid(&value))) {
        std::snprintf(buffer, sizeof(buffer), "e6c-%08lx-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                      static_cast<unsigned long>(value.Data1), value.Data2, value.Data3,
                      value.Data4[0], value.Data4[1], value.Data4[2], value.Data4[3],
                      value.Data4[4], value.Data4[5], value.Data4[6], value.Data4[7]);
    } else {
        std::snprintf(buffer, sizeof(buffer), "e6c-fallback-%lu-%llu-%p",
                      static_cast<unsigned long>(GetCurrentProcessId()),
                      static_cast<unsigned long long>(GetTickCount64()), static_cast<void*>(this));
    }
    mutationPrefix_ = buffer;
}

bool SurfaceSession::Connect(const std::wstring& pipeName, DWORD timeoutMs, std::string* error) {
    pipeName_ = pipeName;
    reconnectTimeoutMs_ = timeoutMs < 100 ? timeoutMs : 100;
    current_ = {};
    selectedCandidateIndex_ = 0;
    navigationSegmentStart_ = -1;
    navigationSegmentEnd_ = -1;
    const auto settings = LoadExperimentSettings();
    connectedMode_ = settings.mode;
    connectedCandidateLimit_ = settings.candidatePageSize;
    if (!broker_.Connect(pipeName, timeoutMs, connectedMode_, connectedCandidateLimit_, error)) {
        connectedMode_.clear();
        connectedCandidateLimit_ = 0;
        return false;
    }
    return true;
}

bool SurfaceSession::EnsureConnected(std::string* error) {
    if (broker_.IsConnected()) {
        if (!current_.rawInput.empty()) return true;
    }
    const auto settings = LoadExperimentSettings();
    const std::string desiredMode = settings.mode;
    const int desiredCandidateLimit = settings.candidatePageSize;
    if (broker_.IsConnected()) {
        if (desiredMode == connectedMode_ && desiredCandidateLimit == connectedCandidateLimit_) return true;
        broker_.Close();
        current_ = {};
        selectedCandidateIndex_ = 0;
        navigationSegmentStart_ = -1;
        navigationSegmentEnd_ = -1;
        connectedMode_.clear();
        connectedCandidateLimit_ = 0;
    }
    if (pipeName_.empty()) {
        if (error) *error = "Broker endpoint is not configured";
        return false;
    }
    current_ = {};
    selectedCandidateIndex_ = 0;
    navigationSegmentStart_ = -1;
    navigationSegmentEnd_ = -1;
    if (!broker_.Connect(pipeName_, reconnectTimeoutMs_, desiredMode, desiredCandidateLimit, error)) return false;
    connectedMode_ = desiredMode;
    connectedCandidateLimit_ = desiredCandidateLimit;
    return true;
}

bool SurfaceSession::CanHandle(WPARAM virtualKey, bool shiftDown,
                               bool controlDown, bool altDown) {
    const KeyDecision decision = ClassifyVirtualKey(virtualKey, shiftDown, controlDown, altDown);
    if (decision.route == KeyRoute::AppendComposition) {
        char ignored = 0;
        return TranslateCompositionKey(virtualKey, shiftDown, &ignored) && EnsureConnected(nullptr);
    }
        if (decision.route == KeyRoute::BackspaceComposition ||
		decision.route == KeyRoute::ClearComposition ||
        decision.route == KeyRoute::PreviousCandidatePage ||
        decision.route == KeyRoute::NextCandidatePage) {
        return broker_.IsConnected() && !current_.rawInput.empty();
    }
    if (decision.route == KeyRoute::PreviousCandidate || decision.route == KeyRoute::NextCandidate ||
        decision.route == KeyRoute::SelectCurrentCandidate) {
        return broker_.IsConnected() &&
               ((decision.route == KeyRoute::SelectCurrentCandidate && current_.hasSentence) ||
                !current_.candidates.empty());
    }
    if (decision.route == KeyRoute::PreviousSentenceSegment ||
        decision.route == KeyRoute::NextSentenceSegment) {
        BrokerSegment ignored;
        return broker_.IsConnected() &&
               FindAdjacentSentenceSegment(decision.route == KeyRoute::PreviousSentenceSegment,
                                           &ignored);
    }
    if (decision.route == KeyRoute::ForgetCurrentCandidate) {
        return broker_.IsConnected() &&
               (selectedCandidateIndex_ < current_.candidates.size() ||
                current_.candidates.empty() && current_.hasSentence && !current_.sentence.id.empty());
    }
    if (!broker_.IsConnected() || decision.route != KeyRoute::SelectCandidate ||
        decision.candidateOrdinal == 0 || decision.candidateOrdinal > 9) {
        return false;
    }
    const size_t candidateIndex = static_cast<size_t>(decision.candidateOrdinal - 1);
    return candidateIndex < current_.candidates.size();
}

SurfaceOutcome SurfaceSession::HandleVirtualKey(WPARAM virtualKey, bool shiftDown,
                                                bool controlDown, bool altDown) {
    SurfaceOutcome outcome;
    const KeyDecision decision = ClassifyVirtualKey(virtualKey, shiftDown, controlDown, altDown);
    if (decision.route == KeyRoute::AppendComposition) {
        char ignored = 0;
        if (!TranslateCompositionKey(virtualKey, shiftDown, &ignored)) return outcome;
        if (!EnsureConnected(&outcome.error)) return outcome;
    } else if (!CanHandle(virtualKey, shiftDown, controlDown, altDown)) {
        if (!broker_.IsConnected()) outcome.error = "Broker session is not connected";
        return outcome;
    }
    if (decision.route == KeyRoute::SelectCurrentCandidate && current_.candidates.empty() &&
        current_.hasSentence) {
        return CommitSentence();
    }
    if (decision.route == KeyRoute::PreviousSentenceSegment ||
        decision.route == KeyRoute::NextSentenceSegment) {
        BrokerSegment target;
        if (!FindAdjacentSentenceSegment(decision.route == KeyRoute::PreviousSentenceSegment,
                                         &target)) {
            return outcome;
        }
        return FocusSentenceSegment(target.start, target.end);
    }
    if (decision.route == KeyRoute::ForgetCurrentCandidate) {
        if (selectedCandidateIndex_ < current_.candidates.size()) {
            return ForgetCandidate(selectedCandidateIndex_);
        }
        outcome.handled = broker_.ForgetCandidate(current_.sentence.id, &outcome.update, &outcome.error);
    } else
    if (decision.route == KeyRoute::SelectCandidate || decision.route == KeyRoute::SelectCurrentCandidate) {
        const size_t candidateIndex = decision.route == KeyRoute::SelectCurrentCandidate
                                ? selectedCandidateIndex_
                                : static_cast<size_t>(decision.candidateOrdinal - 1);
        if (candidateIndex >= current_.candidates.size()) return outcome;
        const auto& candidate = current_.candidates[candidateIndex];
        const std::string mutation = mutationPrefix_ + "-" + std::to_string(++mutationSequence_);
        outcome.handled = broker_.SelectCandidate(candidate.id, mutation,
                              &outcome.update, &outcome.error);
    } else if (decision.route == KeyRoute::PreviousCandidate || decision.route == KeyRoute::NextCandidate) {
        if (decision.route == KeyRoute::PreviousCandidate) {
            if (selectedCandidateIndex_ > 0) --selectedCandidateIndex_;
        } else if (selectedCandidateIndex_ + 1 < current_.candidates.size()) {
            ++selectedCandidateIndex_;
        }
        outcome.handled = true;
        outcome.update = current_;
    } else if (decision.route == KeyRoute::BackspaceComposition) {
        outcome.handled = broker_.Backspace(&outcome.update, &outcome.error);
	} else if (decision.route == KeyRoute::ClearComposition) {
		outcome.handled = broker_.Clear(&outcome.update, &outcome.error);
    } else if (decision.route == KeyRoute::PreviousCandidatePage) {
        outcome.handled = broker_.PreviousPage(&outcome.update, &outcome.error);
    } else if (decision.route == KeyRoute::NextCandidatePage) {
        outcome.handled = broker_.NextPage(&outcome.update, &outcome.error);
    } else {
        char code = 0;
        if (!TranslateCompositionKey(virtualKey, shiftDown, &code)) return outcome;
        outcome.handled = broker_.ApplyCode(code, &outcome.update, &outcome.error);
    }
    if (outcome.handled) {
        if (outcome.update.rawInput.empty() || outcome.update.rawInput != current_.rawInput) {
            navigationSegmentStart_ = -1;
            navigationSegmentEnd_ = -1;
        }
        if (outcome.update.activeSegmentStart >= 0 &&
            outcome.update.activeSegmentEnd > outcome.update.activeSegmentStart) {
            navigationSegmentStart_ = outcome.update.activeSegmentStart;
            navigationSegmentEnd_ = outcome.update.activeSegmentEnd;
        }
        if (decision.route != KeyRoute::PreviousCandidate && decision.route != KeyRoute::NextCandidate) {
            selectedCandidateIndex_ = 0;
        }
        if (outcome.update.candidates.empty()) selectedCandidateIndex_ = 0;
        outcome.update.selectedCandidateIndex = selectedCandidateIndex_;
        current_ = outcome.update;
    }
    return outcome;
}

SurfaceOutcome SurfaceSession::ForgetCandidate(size_t candidateIndex) {
    SurfaceOutcome outcome;
    if (!broker_.IsConnected() || candidateIndex >= current_.candidates.size()) return outcome;
    outcome.handled = broker_.ForgetCandidate(current_.candidates[candidateIndex].id,
                                               &outcome.update, &outcome.error);
    if (outcome.handled) {
        selectedCandidateIndex_ = 0;
        outcome.update.selectedCandidateIndex = 0;
        current_ = outcome.update;
    }
    return outcome;
}

SurfaceOutcome SurfaceSession::CommitSentence() {
    SurfaceOutcome outcome;
    if (!broker_.IsConnected() || !current_.hasSentence || current_.sentence.id.empty()) return outcome;
    const std::string mutation = mutationPrefix_ + "-" + std::to_string(++mutationSequence_);
    outcome.handled = broker_.SelectCandidate(current_.sentence.id, mutation,
                                               &outcome.update, &outcome.error);
    if (outcome.handled) {
        selectedCandidateIndex_ = 0;
        outcome.update.selectedCandidateIndex = 0;
        current_ = outcome.update;
    }
    return outcome;
}

SurfaceOutcome SurfaceSession::FocusSentenceSegment(int start, int end) {
    SurfaceOutcome outcome;
    if (!broker_.IsConnected() || !current_.hasSentence || start < 0 || end <= start) return outcome;
    if (!IsKnownSentenceSegment(current_.sentence, start, end)) return outcome;
    outcome.handled = broker_.FocusSegment(current_.sentence.id, start, end,
                                           &outcome.update, &outcome.error);
    if (outcome.handled) {
        navigationSegmentStart_ = start;
        navigationSegmentEnd_ = end;
        selectedCandidateIndex_ = 0;
        outcome.update.selectedCandidateIndex = 0;
        current_ = outcome.update;
    }
    return outcome;
}

SurfaceOutcome SurfaceSession::ExpandSentenceSegment(int start, int end) {
    SurfaceOutcome outcome;
    if (!broker_.IsConnected() || !current_.hasSentence || start < 0 || end <= start) return outcome;
    if (!IsKnownSentenceSegment(current_.sentence, start, end)) return outcome;
    outcome.handled = broker_.ExpandSegment(current_.sentence.id, start, end,
                                            &outcome.update, &outcome.error);
    if (outcome.handled) {
        navigationSegmentStart_ = outcome.update.activeSegmentStart;
        navigationSegmentEnd_ = outcome.update.activeSegmentEnd;
        selectedCandidateIndex_ = 0;
        outcome.update.selectedCandidateIndex = 0;
        current_ = outcome.update;
    }
    return outcome;
}

bool SurfaceSession::FindAdjacentSentenceSegment(bool previous, BrokerSegment* target) const noexcept {
    if (!target || !current_.hasSentence || current_.sentence.segments.empty()) return false;
    const auto& segments = current_.sentence.segments;
    size_t anchor = segments.size();
    for (size_t index = 0; index < segments.size(); ++index) {
        if (segments[index].start == navigationSegmentStart_ &&
            segments[index].end == navigationSegmentEnd_) {
            anchor = index;
            break;
        }
    }
    if (anchor == segments.size()) {
        *target = previous ? segments.back() : segments.front();
        return true;
    }
    if (previous) {
        if (anchor == 0) return false;
        *target = segments[anchor - 1];
        return true;
    }
    if (anchor + 1 >= segments.size()) return false;
    *target = segments[anchor + 1];
    return true;
}

void SurfaceSession::DisconnectForRecovery() noexcept {
    broker_.Close();
    current_ = {};
    selectedCandidateIndex_ = 0;
    navigationSegmentStart_ = -1;
    navigationSegmentEnd_ = -1;
    connectedMode_.clear();
    connectedCandidateLimit_ = 0;
}

void SurfaceSession::Close() noexcept {
    broker_.Close();
    current_ = {};
    selectedCandidateIndex_ = 0;
    navigationSegmentStart_ = -1;
    navigationSegmentEnd_ = -1;
    pipeName_.clear();
    reconnectTimeoutMs_ = 100;
    connectedMode_.clear();
}

bool SurfaceSession::TranslateCompositionKey(WPARAM virtualKey, bool shiftDown, char* code) noexcept {
    if (!code) return false;
    if (virtualKey >= 'A' && virtualKey <= 'Z') {
        *code = static_cast<char>(shiftDown ? virtualKey : virtualKey - 'A' + 'a');
        return true;
    }
    if (virtualKey >= '0' && virtualKey <= '9') {
        static constexpr char shiftedDigits[] = ")!@#$%^&*(";
        *code = shiftDown ? shiftedDigits[virtualKey - '0'] : static_cast<char>(virtualKey);
        return true;
    }
    struct Mapping { WPARAM key; char plain; char shifted; };
    static constexpr std::array<Mapping, 11> mappings = {{
        {VK_OEM_1, ';', ':'}, {VK_OEM_PLUS, '=', '+'}, {VK_OEM_COMMA, ',', '<'},
        {VK_OEM_MINUS, '-', '_'}, {VK_OEM_PERIOD, '.', '>'}, {VK_OEM_2, '/', '?'},
        {VK_OEM_3, '`', '~'}, {VK_OEM_4, '[', '{'}, {VK_OEM_5, '\\', '|'},
        {VK_OEM_6, ']', '}'}, {VK_OEM_7, '\'', '"'},
    }};
    for (const auto& mapping : mappings) {
        if (mapping.key == virtualKey) {
            *code = shiftDown ? mapping.shifted : mapping.plain;
            return true;
        }
    }
    return false;
}

}  // namespace yime::experiment
