#pragma once

#include <windows.h>

#include <cstddef>
#include <string>
#include <vector>

#include "BrokerClient.h"

namespace yime::experiment {

enum class PunctuationRoute {
    Unrelated,
    Cancel,
    PreviousPage,
    NextPage,
    PreviousCandidate,
    NextCandidate,
    SelectCurrent,
    SelectOrdinal,
    DirectCommit,
    Reclassify,
};

struct PunctuationDecision {
    PunctuationRoute route = PunctuationRoute::Unrelated;
    unsigned ordinal = 0;
    std::string commit;
};

class PunctuationPalette final {
public:
    void Open(bool asciiPunctuation, bool fullShape, std::string frozenCandidateId);
    void Cancel() noexcept;

    bool IsActive() const noexcept { return active_; }
    int PageIndex() const noexcept { return pageIndex_; }
    size_t SelectedIndex() const noexcept { return selectedIndex_; }
    const std::string& FrozenCandidateId() const noexcept { return frozenCandidateId_; }
    const std::vector<BrokerCandidate>& Candidates() const noexcept;
    std::wstring StatusText() const;
    std::wstring Description() const;

    PunctuationDecision Preview(WPARAM virtualKey, bool shiftDown,
                                bool controlDown = false, bool altDown = false) const noexcept;
    bool ApplyNavigation(const PunctuationDecision& decision) noexcept;
    bool Resolve(const PunctuationDecision& decision, std::string* commit) const noexcept;
    bool ResolveOrdinal(unsigned ordinal, std::string* commit) const noexcept;

private:
    void BuildPages();

    bool active_ = false;
    bool asciiPunctuation_ = false;
    bool fullShape_ = false;
    int pageIndex_ = 0;
    size_t selectedIndex_ = 0;
    std::string frozenCandidateId_;
    std::vector<BrokerCandidate> pages_[2];
};

}  // namespace yime::experiment
