#include "PunctuationPalette.h"

#include <algorithm>
#include <array>
#include <utility>

#include "OutputTransform.h"
#include "ProductIdentity.h"

namespace yime::experiment {
namespace {

BrokerCandidate Entry(std::string id, std::string text) {
    BrokerCandidate candidate;
    candidate.id = std::move(id);
    candidate.text = std::move(text);
    return candidate;
}

bool IsCompositionPrintable(WPARAM virtualKey) noexcept {
    return (virtualKey >= '0' && virtualKey <= '9') ||
           (virtualKey >= 'A' && virtualKey <= 'Z');
}

bool IsOemPunctuationKey(WPARAM virtualKey) noexcept {
    return virtualKey == VK_OEM_1 || virtualKey == VK_OEM_PLUS ||
           virtualKey == VK_OEM_COMMA || virtualKey == VK_OEM_MINUS ||
           virtualKey == VK_OEM_PERIOD || virtualKey == VK_OEM_2 ||
           virtualKey == VK_OEM_3 || virtualKey == VK_OEM_4 ||
           virtualKey == VK_OEM_5 || virtualKey == VK_OEM_6 ||
           virtualKey == VK_OEM_7;
}

std::string ResolveAsciiKey(WPARAM virtualKey, bool shiftDown,
                            bool fullShape) {
    std::string output;
    TranslatePunctuationKey(virtualKey, shiftDown, true, fullShape, &output);
    return output;
}

}  // namespace

void PunctuationPalette::Open(bool asciiPunctuation, bool fullShape,
                              std::string frozenCandidateId) {
    active_ = true;
    asciiPunctuation_ = asciiPunctuation;
    fullShape_ = fullShape;
    pageIndex_ = 0;
    selectedIndex_ = 0;
    frozenCandidateId_ = std::move(frozenCandidateId);
    BuildPages();
}

void PunctuationPalette::Cancel() noexcept {
    active_ = false;
    pageIndex_ = 0;
    selectedIndex_ = 0;
    frozenCandidateId_.clear();
    pages_[0].clear();
    pages_[1].clear();
}

const std::vector<BrokerCandidate>& PunctuationPalette::Candidates() const noexcept {
    static const std::vector<BrokerCandidate> empty;
    if (!active_ || pageIndex_ < 0 || pageIndex_ > 1) return empty;
    return pages_[pageIndex_];
}

std::wstring PunctuationPalette::StatusText() const {
    if (!active_) return {};
    return std::wstring(L"标点（") + (asciiPunctuation_ ? L"英文" : L"中文") +
           L"） · " + std::to_wstring(pageIndex_ + 1) + L"/2";
}

std::wstring PunctuationPalette::Description() const {
    if (!active_) return YIME_PRODUCT_NAME L"候选";
    return std::wstring(L"Yime 标点（") + (asciiPunctuation_ ? L"英文" : L"中文") +
           L"）第 " + std::to_wstring(pageIndex_ + 1) + L" 页";
}

PunctuationDecision PunctuationPalette::Preview(WPARAM virtualKey, bool shiftDown,
                                                bool controlDown, bool altDown) const noexcept {
    if (!active_ || controlDown || altDown) return {};
    if (shiftDown && virtualKey == VK_OEM_5) {
        return {PunctuationRoute::Cancel, 0, {}};
    }
    if (virtualKey == VK_ESCAPE || virtualKey == VK_BACK) {
        return {PunctuationRoute::Cancel, 0, {}};
    }
    if (virtualKey == VK_PRIOR || virtualKey == VK_LEFT) {
        return {PunctuationRoute::PreviousPage, 0, {}};
    }
    if (virtualKey == VK_NEXT || virtualKey == VK_RIGHT) {
        return {PunctuationRoute::NextPage, 0, {}};
    }
    if (virtualKey == VK_UP) return {PunctuationRoute::PreviousCandidate, 0, {}};
    if (virtualKey == VK_DOWN) return {PunctuationRoute::NextCandidate, 0, {}};
    if (!shiftDown && (virtualKey == VK_RETURN || virtualKey == VK_SPACE)) {
        return {PunctuationRoute::SelectCurrent, 0, {}};
    }
    if (shiftDown && virtualKey >= '1' && virtualKey <= '9') {
        return {PunctuationRoute::SelectOrdinal,
                static_cast<unsigned>(virtualKey - '0'), {}};
    }
    if (shiftDown && virtualKey == '0') {
        std::string output;
        if (TranslatePunctuationKey(virtualKey, true, asciiPunctuation_, fullShape_, &output)) {
            return {PunctuationRoute::DirectCommit, 0, std::move(output)};
        }
    }
    if (IsOemPunctuationKey(virtualKey)) {
        std::string output;
        if (TranslatePunctuationKey(virtualKey, shiftDown, asciiPunctuation_, fullShape_, &output)) {
            return {PunctuationRoute::DirectCommit, 0, std::move(output)};
        }
    }
    if (IsCompositionPrintable(virtualKey)) {
        return {PunctuationRoute::Reclassify, 0, {}};
    }
    return {};
}

bool PunctuationPalette::ApplyNavigation(const PunctuationDecision& decision) noexcept {
    if (!active_) return false;
    switch (decision.route) {
    case PunctuationRoute::PreviousPage:
        if (pageIndex_ == 0) return false;
        pageIndex_ = 0;
        selectedIndex_ = 0;
        return true;
    case PunctuationRoute::NextPage:
        if (pageIndex_ == 1) return false;
        pageIndex_ = 1;
        selectedIndex_ = 0;
        return true;
    case PunctuationRoute::PreviousCandidate:
        if (selectedIndex_ == 0) return false;
        --selectedIndex_;
        return true;
    case PunctuationRoute::NextCandidate:
        if (selectedIndex_ + 1 >= Candidates().size()) return false;
        ++selectedIndex_;
        return true;
    default:
        return false;
    }
}

bool PunctuationPalette::Resolve(const PunctuationDecision& decision,
                                 std::string* commit) const noexcept {
    if (!commit || !active_) return false;
    commit->clear();
    if (decision.route == PunctuationRoute::DirectCommit) {
        *commit = decision.commit;
        return !commit->empty();
    }
    if (decision.route == PunctuationRoute::SelectCurrent) {
        return ResolveOrdinal(static_cast<unsigned>(selectedIndex_ + 1), commit);
    }
    if (decision.route == PunctuationRoute::SelectOrdinal) {
        return ResolveOrdinal(decision.ordinal, commit);
    }
    return false;
}

bool PunctuationPalette::ResolveOrdinal(unsigned ordinal, std::string* commit) const noexcept {
    if (!commit || !active_ || ordinal == 0) return false;
    const auto& candidates = Candidates();
    const size_t index = static_cast<size_t>(ordinal - 1);
    if (index >= candidates.size()) return false;
    *commit = candidates[index].text;
    return !commit->empty();
}

void PunctuationPalette::BuildPages() {
    pages_[0].clear();
    pages_[1].clear();
    const std::string prefix = asciiPunctuation_ ? "punct:ascii:" : "punct:zh:";
    pages_[0].reserve(9);
    static constexpr std::array<const char*, 9> firstPageIds = {
        "digit-1", "digit-2", "digit-3", "digit-4", "digit-5",
        "digit-6", "digit-7", "digit-8", "digit-9",
    };
    if (!asciiPunctuation_) {
        static constexpr std::array<const char*, 9> values = {
            u8"！", u8"＠", u8"＃", u8"￥", u8"％", u8"……", u8"＆", u8"＊", u8"（",
        };
        for (size_t index = 0; index < values.size(); ++index) {
            pages_[0].push_back(Entry(prefix + firstPageIds[index], values[index]));
        }
    } else {
        for (size_t index = 0; index < firstPageIds.size(); ++index) {
            pages_[0].push_back(Entry(prefix + firstPageIds[index],
                                      ResolveAsciiKey(static_cast<WPARAM>('1' + index), true,
                                                      fullShape_)));
        }
    }

    pages_[1].reserve(9);
    if (!asciiPunctuation_) {
        static constexpr std::array<const char*, 9> values = {
            u8"（", u8"）", u8"“", u8"”", u8"‘", u8"’", u8"《", u8"》", u8"·",
        };
        static constexpr std::array<const char*, 9> ids = {
            "open-paren", "close-paren", "open-double-quote", "close-double-quote",
            "open-single-quote", "close-single-quote", "open-title", "close-title", "middle-dot",
        };
        for (size_t index = 0; index < values.size(); ++index) {
            pages_[1].push_back(Entry(prefix + ids[index], values[index]));
        }
        return;
    }

    const std::array<std::pair<WPARAM, bool>, 8> keys = {{
        {'9', true}, {'0', true}, {VK_OEM_7, true}, {VK_OEM_7, false},
        {VK_OEM_COMMA, true}, {VK_OEM_PERIOD, true}, {VK_OEM_4, false}, {VK_OEM_6, false},
    }};
    static constexpr std::array<const char*, 9> ids = {
        "open-paren", "close-paren", "double-quote", "single-quote",
        "less-than", "greater-than", "open-bracket", "close-bracket", "middle-dot",
    };
    for (size_t index = 0; index < keys.size(); ++index) {
        pages_[1].push_back(Entry(prefix + ids[index],
                                  ResolveAsciiKey(keys[index].first, keys[index].second, fullShape_)));
    }
    pages_[1].push_back(Entry(prefix + ids.back(), u8"·"));
}

}  // namespace yime::experiment
