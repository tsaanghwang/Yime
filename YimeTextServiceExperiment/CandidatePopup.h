#pragma once

#include <windows.h>

#include <string>
#include <vector>

#include "BrokerClient.h"

class CandidatePopup final {
public:
    using SelectionHandler = void (*)(void* context, unsigned ordinal) noexcept;
    using SegmentHandler = void (*)(void* context, int start, int end) noexcept;

    CandidatePopup() noexcept = default;
    ~CandidatePopup();

    CandidatePopup(const CandidatePopup&) = delete;
    CandidatePopup& operator=(const CandidatePopup&) = delete;

    bool Update(const std::vector<std::wstring>& candidates, const RECT& anchor, HWND owner,
                bool textExtentAnchor = false, size_t selectedIndex = 0,
                const yime::experiment::BrokerCandidate* sentence = nullptr,
                int activeSegmentStart = -1, int activeSegmentEnd = -1) noexcept;
    void SetSelectionHandler(SelectionHandler handler, void* context) noexcept {
        selectionHandler_ = handler;
        selectionContext_ = context;
    }
    void SetSegmentHandler(SegmentHandler handler, void* context) noexcept {
        segmentHandler_ = handler;
        segmentContext_ = context;
    }
    void Show(bool show) noexcept;
    void Destroy() noexcept;
    void SetFontPoints(int points) noexcept;
    void SetUseYinyuanFont(bool useYinyuan) noexcept;

    HWND Window() const noexcept { return window_; }
    size_t Count() const noexcept { return candidates_.size(); }
    size_t RowCount() const noexcept { return candidates_.size() + (sentenceSegments_.empty() ? 0 : 1); }
    int FontPoints() const noexcept { return fontPoints_; }
    bool UsesYinyuanFont() const noexcept { return useYinyuanFont_; }
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
    int SegmentAt(int x, int y) const noexcept;
    HFONT EnsureFont() noexcept;
    void EnsurePrivateYinyuanFont() noexcept;
    void ReleasePrivateYinyuanFont() noexcept;

    HWND window_ = nullptr;
    std::vector<std::wstring> candidates_;
    struct SentenceSegmentCell {
        int start;
        int end;
        std::wstring text;
        bool active;
        int width;
    };
    std::vector<SentenceSegmentCell> sentenceSegments_;
    int sentenceLabelWidth_ = 0;
    int trackedSegment_ = -1;
    int width_ = 0;
    int rowHeight_ = 0;
    int padding_ = 8;
    int fontPoints_ = 12;
    HFONT font_ = nullptr;
    bool useYinyuanFont_ = false;
    bool privateYinyuanFontAdded_ = false;
    std::wstring privateYinyuanFontPath_;
    size_t selectedIndex_ = 0;
    SelectionHandler selectionHandler_ = nullptr;
    void* selectionContext_ = nullptr;
    SegmentHandler segmentHandler_ = nullptr;
    void* segmentContext_ = nullptr;
};
