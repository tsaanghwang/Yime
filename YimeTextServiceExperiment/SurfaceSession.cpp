#include "SurfaceSession.h"

#include <array>

namespace yime::experiment {

bool SurfaceSession::Connect(const std::wstring& pipeName, DWORD timeoutMs, std::string* error) {
    pipeName_ = pipeName;
    reconnectTimeoutMs_ = timeoutMs < 100 ? timeoutMs : 100;
    current_ = {};
    mutationSequence_ = 0;
    return broker_.Connect(pipeName, timeoutMs, error);
}

bool SurfaceSession::EnsureConnected(std::string* error) {
    if (broker_.IsConnected()) return true;
    if (pipeName_.empty()) {
        if (error) *error = "Broker endpoint is not configured";
        return false;
    }
    current_ = {};
    return broker_.Connect(pipeName_, reconnectTimeoutMs_, error);
}

bool SurfaceSession::CanHandle(WPARAM virtualKey, bool shiftDown) {
    const KeyDecision decision = ClassifyVirtualKey(virtualKey, shiftDown);
    if (decision.route == KeyRoute::AppendComposition) {
        char ignored = 0;
        return TranslateCompositionKey(virtualKey, shiftDown, &ignored) && EnsureConnected(nullptr);
    }
    return broker_.IsConnected() && decision.route == KeyRoute::SelectCandidate && decision.candidateOrdinal > 0 &&
           decision.candidateOrdinal <= current_.candidates.size();
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
    if (decision.route == KeyRoute::SelectCandidate) {
        if (decision.candidateOrdinal == 0 || decision.candidateOrdinal > current_.candidates.size()) return outcome;
        const auto& candidate = current_.candidates[decision.candidateOrdinal - 1];
        const std::string mutation = "e6b2a-surface-" + std::to_string(GetCurrentProcessId()) + "-" + std::to_string(++mutationSequence_);
        outcome.handled = broker_.SelectCandidate(candidate.id, mutation, &outcome.update, &outcome.error);
    } else {
        char code = 0;
        if (!TranslateCompositionKey(virtualKey, shiftDown, &code)) return outcome;
        outcome.handled = broker_.ApplyCode(code, &outcome.update, &outcome.error);
    }
    if (outcome.handled) current_ = outcome.update;
    return outcome;
}

void SurfaceSession::DisconnectForRecovery() noexcept {
    broker_.Close();
    current_ = {};
}

void SurfaceSession::Close() noexcept {
    broker_.Close();
    current_ = {};
    pipeName_.clear();
    reconnectTimeoutMs_ = 100;
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
