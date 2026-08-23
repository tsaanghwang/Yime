#include "KeyContract.h"

namespace yime::experiment {

KeyDecision ClassifyVirtualKey(WPARAM virtualKey, bool shiftDown) noexcept {
    if (!shiftDown && (virtualKey == VK_RETURN || virtualKey == VK_SPACE)) {
        return {KeyRoute::SelectCandidate, 1};
    }
    if (shiftDown && virtualKey >= '1' && virtualKey <= '9') {
        return {KeyRoute::SelectCandidate, static_cast<unsigned>(virtualKey - '0')};
    }
    if ((virtualKey >= '0' && virtualKey <= '9') || (virtualKey >= 'A' && virtualKey <= 'Z') ||
        virtualKey == VK_OEM_1 || virtualKey == VK_OEM_PLUS || virtualKey == VK_OEM_COMMA ||
        virtualKey == VK_OEM_MINUS || virtualKey == VK_OEM_PERIOD || virtualKey == VK_OEM_2 ||
        virtualKey == VK_OEM_3 || virtualKey == VK_OEM_4 || virtualKey == VK_OEM_5 ||
        virtualKey == VK_OEM_6 || virtualKey == VK_OEM_7) {
        return {KeyRoute::AppendComposition, 0};
    }
    return {};
}

const std::array<std::wstring_view, 9>& CandidateLabels() noexcept {
    static constexpr std::array<std::wstring_view, 9> labels = {
        L"⇧1", L"⇧2", L"⇧3", L"⇧4", L"⇧5", L"⇧6", L"⇧7", L"⇧8", L"⇧9",
    };
    return labels;
}

}  // namespace yime::experiment
