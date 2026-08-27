#include "KeyContract.h"

namespace yime::experiment {

KeyDecision ClassifyVirtualKey(WPARAM virtualKey, bool shiftDown,
                               bool controlDown, bool altDown) noexcept {
    // Editing and application shortcuts belong to the host. In particular,
    // Ctrl+A/C/V/X/Y/Z and Ctrl+Shift+Z must never turn their letter into a
    // Yime composition code while a candidate window is visible.
    if (altDown) {
        return {};
    }
    if (controlDown) {
        if (!shiftDown && virtualKey == VK_LEFT) {
            return {KeyRoute::PreviousSentenceSegment, 0};
        }
        if (!shiftDown && virtualKey == VK_RIGHT) {
            return {KeyRoute::NextSentenceSegment, 0};
        }
        if (!shiftDown && virtualKey == VK_DELETE) {
            return {KeyRoute::ForgetCurrentCandidate, 0};
        }
        return {};
    }
    if (virtualKey == VK_BACK) {
        return {KeyRoute::BackspaceComposition, 0};
    }
	if (virtualKey == VK_ESCAPE) {
		return {KeyRoute::ClearComposition, 0};
	}
    if (virtualKey == VK_PRIOR) {
        return {KeyRoute::PreviousCandidatePage, 0};
    }
    if (virtualKey == VK_NEXT) {
        return {KeyRoute::NextCandidatePage, 0};
    }
    if (virtualKey == VK_UP) {
        return {KeyRoute::PreviousCandidate, 0};
    }
    if (virtualKey == VK_DOWN) {
        return {KeyRoute::NextCandidate, 0};
    }
    if (virtualKey == VK_LEFT) {
        return {KeyRoute::PreviousCandidatePage, 0};
    }
    if (virtualKey == VK_RIGHT) {
        return {KeyRoute::NextCandidatePage, 0};
    }
    if (!shiftDown && (virtualKey == VK_RETURN || virtualKey == VK_SPACE)) {
        return {KeyRoute::SelectCurrentCandidate, 0};
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

bool ShiftTapTracker::OnKeyDown(WPARAM virtualKey) noexcept {
    if (virtualKey == VK_SHIFT || virtualKey == VK_LSHIFT || virtualKey == VK_RSHIFT) {
        armed_ = true;
        return true;
    }
    armed_ = false;
    return false;
}

bool ShiftTapTracker::OnKeyUp(WPARAM virtualKey) noexcept {
    if (virtualKey != VK_SHIFT && virtualKey != VK_LSHIFT && virtualKey != VK_RSHIFT) {
        return false;
    }
    const bool toggle = armed_;
    armed_ = false;
    return toggle;
}

const std::array<std::wstring_view, 9>& CandidateLabels() noexcept {
    static constexpr std::array<std::wstring_view, 9> labels = {
        L"⇧1", L"⇧2", L"⇧3", L"⇧4", L"⇧5", L"⇧6", L"⇧7", L"⇧8", L"⇧9",
    };
    return labels;
}

}  // namespace yime::experiment
