#pragma once

#include <windows.h>

#include <string>
#include <vector>

#include "BrokerClient.h"

class CandidatePopup final {
public:
    using SelectionHandler = void (*)(void* context, unsigned ordinal) noexcept;
    using ForgetHandler = void (*)(void* context, unsigned ordinal) noexcept;
    using SentenceHandler = void (*)(void* context) noexcept;
    using SegmentHandler = void (*)(void* context, int start, int end) noexcept;
    using PopupPresenter = UINT (*)(HMENU menu, POINT point, HWND owner,
                                    void* context) noexcept;

    CandidatePopup() noexcept = default;
    ~CandidatePopup();

    CandidatePopup(const CandidatePopup&) = delete;
    CandidatePopup& operator=(const CandidatePopup&) = delete;

    bool Update(const std::vector<std::wstring>& candidates, const RECT& anchor, HWND owner,
                bool textExtentAnchor = false, size_t selectedIndex = 0,
                const yime::experiment::BrokerCandidate* sentence = nullptr,
                int activeSegmentStart = -1, int activeSegmentEnd = -1,
				const std::wstring* status = nullptr) noexcept;
    void SetSelectionHandler(SelectionHandler handler, void* context) noexcept {
        selectionHandler_ = handler;
        selectionContext_ = context;
    }
    void SetForgetHandler(ForgetHandler handler, void* context) noexcept {
        forgetHandler_ = handler;
        forgetContext_ = context;
    }
    void SetForgetMenuPresenter(PopupPresenter presenter, void* context) noexcept {
        popupPresenter_ = presenter;
        popupPresenterContext_ = context;
    }
    void SetSentenceHandler(SentenceHandler handler, void* context) noexcept {
        sentenceHandler_ = handler;
        sentenceContext_ = context;
    }
    void SetSegmentHandler(SegmentHandler handler, void* context) noexcept {
        segmentHandler_ = handler;
        segmentContext_ = context;
    }
    void SetSegmentExpandHandler(SegmentHandler handler, void* context) noexcept {
        segmentExpandHandler_ = handler;
        segmentExpandContext_ = context;
    }
    void Show(bool show) noexcept;
    void Destroy() noexcept;
    void SetFontPoints(int points) noexcept;
    void SetUseYinyuanFont(bool useYinyuan) noexcept;
    void SetHorizontal(bool horizontal) noexcept { horizontal_ = horizontal; }

    HWND Window() const noexcept { return window_; }
    size_t Count() const noexcept { return candidates_.size(); }
    size_t RowCount() const noexcept {
        return (candidates_.empty() ? 0 : horizontal_ ? 1 : candidates_.size()) +
			   (sentenceSegments_.empty() ? 0 : 1) + (status_.empty() ? 0 : 1);
    }
    int FontPoints() const noexcept { return fontPoints_; }
    bool UsesYinyuanFont() const noexcept { return useYinyuanFont_; }
    bool IsHorizontal() const noexcept { return horizontal_; }
    int TextColumnLeft() const noexcept { return padding_ + textColumnOffset_; }
    RECT Bounds() const noexcept;

    static constexpr const wchar_t* ClassName() noexcept {
        return L"YimeTextServiceExperimentCandidatePopup";
    }

private:
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam) noexcept;
    bool EnsureWindow(HWND owner) noexcept;
    void Reposition(const RECT& anchor) noexcept;
    void Paint() noexcept;
    void TrackAt(LPARAM lParam) noexcept;
    void SelectAt(LPARAM lParam) noexcept;
    void ForgetAt(LPARAM lParam) noexcept;
    void ExpandAt(LPARAM lParam) noexcept;
    int SegmentAt(int x, int y) const noexcept;
    int CandidateAt(int x, int y) const noexcept;
    static UINT PresentPopup(HMENU menu, POINT point, HWND owner, void* context) noexcept;
    HFONT EnsureFont() noexcept;
    void EnsurePrivateYinyuanFont() noexcept;
    void ReleasePrivateYinyuanFont() noexcept;

    HWND window_ = nullptr;
    std::vector<std::wstring> candidates_;
    std::vector<int> candidateWidths_;
    struct SentenceSegmentCell {
        int start;
        int end;
        std::wstring text;
        bool active;
        int width;
    };
    std::vector<SentenceSegmentCell> sentenceSegments_;
	std::wstring status_;
    int textColumnOffset_ = 0;
    int trackedSegment_ = -1;
    int width_ = 0;
    int rowHeight_ = 0;
    int padding_ = 8;
    int fontPoints_ = 12;
    HFONT font_ = nullptr;
    bool useYinyuanFont_ = false;
    bool horizontal_ = false;
    bool privateYinyuanFontAdded_ = false;
    std::wstring privateYinyuanFontPath_;
    size_t selectedIndex_ = 0;
    SelectionHandler selectionHandler_ = nullptr;
    void* selectionContext_ = nullptr;
    ForgetHandler forgetHandler_ = nullptr;
    void* forgetContext_ = nullptr;
    PopupPresenter popupPresenter_ = nullptr;
    void* popupPresenterContext_ = nullptr;
    SentenceHandler sentenceHandler_ = nullptr;
    void* sentenceContext_ = nullptr;
    SegmentHandler segmentHandler_ = nullptr;
    void* segmentContext_ = nullptr;
    SegmentHandler segmentExpandHandler_ = nullptr;
    void* segmentExpandContext_ = nullptr;
};
