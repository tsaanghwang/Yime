#pragma once

#include <windows.h>

#include <string>
#include <vector>

class CandidatePopup final {
public:
    using SelectionHandler = void (*)(void* context, unsigned ordinal) noexcept;

    CandidatePopup() noexcept = default;
    ~CandidatePopup();

    CandidatePopup(const CandidatePopup&) = delete;
    CandidatePopup& operator=(const CandidatePopup&) = delete;

    bool Update(const std::vector<std::wstring>& candidates, const RECT& anchor, HWND owner,
                bool textExtentAnchor = false, size_t selectedIndex = 0) noexcept;
    void SetSelectionHandler(SelectionHandler handler, void* context) noexcept {
        selectionHandler_ = handler;
        selectionContext_ = context;
    }
    void Show(bool show) noexcept;
    void Destroy() noexcept;

    HWND Window() const noexcept { return window_; }
    size_t Count() const noexcept { return candidates_.size(); }
    RECT Bounds() const noexcept;

    static constexpr const wchar_t* ClassName() noexcept {
        return L"YimeTextServiceExperimentCandidatePopup";
    }

private:
    static LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam) noexcept;
    bool EnsureWindow(HWND owner) noexcept;
    void Reposition(const RECT& anchor) noexcept;
    void Paint() noexcept;
    void SelectAt(LPARAM lParam) noexcept;

    HWND window_ = nullptr;
    std::vector<std::wstring> candidates_;
    int width_ = 0;
    int rowHeight_ = 0;
    int padding_ = 8;
    size_t selectedIndex_ = 0;
    SelectionHandler selectionHandler_ = nullptr;
    void* selectionContext_ = nullptr;
};
