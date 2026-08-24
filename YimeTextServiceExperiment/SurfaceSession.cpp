#include "SurfaceSession.h"

#include <objbase.h>

#include <array>
#include <cstdio>
#include <string_view>

#include "ExperimentSettings.h"

namespace yime::experiment {

namespace {

size_t Utf8CodePointCount(std::string_view text) noexcept {
    size_t count = 0;
    for (const unsigned char byte : text) {
        if ((byte & 0xC0) != 0x80) ++count;
    }
    return count;
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
    connectedMode_ = LoadExperimentSettings().mode;
    if (!broker_.Connect(pipeName, timeoutMs, connectedMode_, error)) {
        connectedMode_.clear();
        return false;
    }
    return true;
}

bool SurfaceSession::EnsureConnected(std::string* error) {
    if (broker_.IsConnected()) {
        if (!current_.rawInput.empty()) return true;
    }
    const std::string desiredMode = LoadExperimentSettings().mode;
    if (broker_.IsConnected()) {
        if (desiredMode == connectedMode_) return true;
        broker_.Close();
        current_ = {};
        selectedCandidateIndex_ = 0;
        connectedMode_.clear();
    }
    if (pipeName_.empty()) {
        if (error) *error = "Broker endpoint is not configured";
        return false;
    }
    current_ = {};
    selectedCandidateIndex_ = 0;
    if (!broker_.Connect(pipeName_, reconnectTimeoutMs_, desiredMode, error)) return false;
    connectedMode_ = desiredMode;
    return true;
}

bool SurfaceSession::CanHandle(WPARAM virtualKey, bool shiftDown) {
    const KeyDecision decision = ClassifyVirtualKey(virtualKey, shiftDown);
    if (decision.route == KeyRoute::AppendComposition) {
        char ignored = 0;
        return TranslateCompositionKey(virtualKey, shiftDown, &ignored) && EnsureConnected(nullptr);
    }
    if (decision.route == KeyRoute::BackspaceComposition ||
        decision.route == KeyRoute::PreviousCandidatePage ||
        decision.route == KeyRoute::NextCandidatePage) {
        return broker_.IsConnected() && !current_.rawInput.empty();
    }
    if (decision.route == KeyRoute::PreviousCandidate || decision.route == KeyRoute::NextCandidate ||
        decision.route == KeyRoute::SelectCurrentCandidate) {
        return broker_.IsConnected() && !current_.candidates.empty();
    }
    return broker_.IsConnected() && decision.route == KeyRoute::SelectCandidate &&
           decision.candidateOrdinal > 0 && decision.candidateOrdinal <= current_.candidates.size();
}

SurfaceOutcome SurfaceSession::HandleVirtualKey(WPARAM virtualKey, bool shiftDown) {
    SurfaceOutcome outcome;
    const KeyDecision decision = ClassifyVirtualKey(virtualKey, shiftDown);
    if (decision.route == KeyRoute::AppendComposition) {
        char ignored = 0;
        if (!TranslateCompositionKey(virtualKey, shiftDown, &ignored)) return outcome;
        if (!EnsureConnected(&outcome.error)) return outcome;
    } else if (!CanHandle(virtualKey, shiftDown)) {
        if (!broker_.IsConnected()) outcome.error = "Broker session is not connected";
        return outcome;
    }
    if (decision.route == KeyRoute::SelectCurrentCandidate && current_.hasSentence) {
        return CommitSentence();
    }
    const bool preservesSentence = current_.hasSentence &&
        (decision.route == KeyRoute::PreviousCandidatePage || decision.route == KeyRoute::NextCandidatePage);
    const BrokerCandidate sentence = current_.sentence;
    const int activeStart = current_.activeSegmentStart;
    const int activeEnd = current_.activeSegmentEnd;
    if (decision.route == KeyRoute::SelectCandidate || decision.route == KeyRoute::SelectCurrentCandidate) {
        const size_t candidateIndex = decision.route == KeyRoute::SelectCurrentCandidate
                                          ? selectedCandidateIndex_
                                          : static_cast<size_t>(decision.candidateOrdinal - 1);
        if (candidateIndex >= current_.candidates.size()) return outcome;
        const auto& candidate = current_.candidates[candidateIndex];
        const std::string mutation = mutationPrefix_ + "-" + std::to_string(++mutationSequence_);
        BrokerUpdate selected;
        outcome.handled = broker_.SelectCandidate(candidate.id, mutation, &selected, &outcome.error) &&
                          PrepareDynamicSentence(std::move(selected), &outcome.update, &outcome.error,
                                                 activeStart, activeEnd);
    } else if (decision.route == KeyRoute::PreviousCandidate || decision.route == KeyRoute::NextCandidate) {
        if (decision.route == KeyRoute::PreviousCandidate) {
            if (selectedCandidateIndex_ > 0) --selectedCandidateIndex_;
        } else if (selectedCandidateIndex_ + 1 < current_.candidates.size()) {
            ++selectedCandidateIndex_;
        }
        outcome.handled = true;
        outcome.update = current_;
    } else if (decision.route == KeyRoute::BackspaceComposition) {
        BrokerUpdate changed;
        outcome.handled = broker_.Backspace(&changed, &outcome.error) &&
                          PrepareDynamicSentence(std::move(changed), &outcome.update, &outcome.error);
    } else if (decision.route == KeyRoute::PreviousCandidatePage) {
        outcome.handled = broker_.PreviousPage(&outcome.update, &outcome.error);
    } else if (decision.route == KeyRoute::NextCandidatePage) {
        outcome.handled = broker_.NextPage(&outcome.update, &outcome.error);
    } else {
        char code = 0;
        if (!TranslateCompositionKey(virtualKey, shiftDown, &code)) return outcome;
        BrokerUpdate changed;
        outcome.handled = broker_.ApplyCode(code, &changed, &outcome.error) &&
                          PrepareDynamicSentence(std::move(changed), &outcome.update, &outcome.error);
    }
    if (outcome.handled) {
		if (preservesSentence) {
			outcome.update.hasSentence = true;
			outcome.update.sentence = sentence;
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
    bool known = false;
    for (const auto& segment : current_.sentence.segments) {
        if (segment.start == start && segment.end == end) {
            known = true;
            break;
        }
    }
    if (!known) return outcome;
    outcome.handled = broker_.FocusSegment(current_.sentence.id, start, end,
                                           &outcome.update, &outcome.error);
    if (outcome.handled) {
        outcome.update.hasSentence = true;
        outcome.update.sentence = current_.sentence;
        selectedCandidateIndex_ = 0;
        outcome.update.selectedCandidateIndex = 0;
        current_ = outcome.update;
    }
    return outcome;
}

bool SurfaceSession::PrepareDynamicSentence(BrokerUpdate update, BrokerUpdate* prepared,
                                            std::string* error, int preferredStart,
                                            int preferredEnd) {
    if (!prepared) return false;
	// The Broker already ranks reviewed/system lexical words ahead of generated
	// fallback paths. Preserve that decision in the sentence row instead of
	// scanning past the first whole word to the first splittable candidate (the
	// old behavior turned 本地 into 本|的 even though 本地 ranked first).
	if (!update.candidates.empty()) {
		const BrokerCandidate& first = update.candidates.front();
		if (first.segments.empty() && Utf8CodePointCount(first.text) > 1) {
			update.hasSentence = true;
			update.sentence = first;
			*prepared = std::move(update);
			return true;
		}
	}
    const BrokerCandidate* sentence = nullptr;
    for (const auto& candidate : update.candidates) {
        if (candidate.segments.size() >= 2 && candidate.segments.front().start == 0 &&
            candidate.segments.front().end > 0) {
            sentence = &candidate;
            break;
        }
    }
    if (!sentence) {
        *prepared = std::move(update);
        return true;
    }
    const BrokerCandidate sentenceCopy = *sentence;
    BrokerSegment active = sentenceCopy.segments.front();
    for (const auto& segment : sentenceCopy.segments) {
        if (segment.start == preferredStart && segment.end == preferredEnd) {
            active = segment;
            break;
        }
    }
    BrokerUpdate focused;
    if (!broker_.FocusSegment(sentenceCopy.id, active.start, active.end, &focused, error)) return false;
    focused.hasSentence = true;
    focused.sentence = sentenceCopy;
    *prepared = std::move(focused);
    return true;
}

void SurfaceSession::DisconnectForRecovery() noexcept {
    broker_.Close();
    current_ = {};
    selectedCandidateIndex_ = 0;
    connectedMode_.clear();
}

void SurfaceSession::Close() noexcept {
    broker_.Close();
    current_ = {};
    selectedCandidateIndex_ = 0;
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
