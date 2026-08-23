#include "SurfaceSession.h"

#include <array>

#include "ExperimentSettings.h"

namespace yime::experiment {

bool SurfaceSession::Connect(const std::wstring& pipeName, DWORD timeoutMs, std::string* error) {
    pipeName_ = pipeName;
    reconnectTimeoutMs_ = timeoutMs < 100 ? timeoutMs : 100;
    current_ = {};
    selectedCandidateIndex_ = 0;
    mutationSequence_ = 0;
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
    if (decision.route == KeyRoute::SelectCandidate || decision.route == KeyRoute::SelectCurrentCandidate) {
        const size_t candidateIndex = decision.route == KeyRoute::SelectCurrentCandidate
                                          ? selectedCandidateIndex_
                                          : static_cast<size_t>(decision.candidateOrdinal - 1);
        if (candidateIndex >= current_.candidates.size()) return outcome;
        const auto& candidate = current_.candidates[candidateIndex];
        const std::string mutation = "e6b2a-surface-" + std::to_string(GetCurrentProcessId()) + "-" + std::to_string(++mutationSequence_);
        outcome.handled = broker_.SelectCandidate(candidate.id, mutation, &outcome.update, &outcome.error);
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
        if (decision.route != KeyRoute::PreviousCandidate && decision.route != KeyRoute::NextCandidate) {
            selectedCandidateIndex_ = 0;
        }
        if (outcome.update.candidates.empty()) selectedCandidateIndex_ = 0;
        outcome.update.selectedCandidateIndex = selectedCandidateIndex_;
        current_ = outcome.update;
    }
    return outcome;
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
