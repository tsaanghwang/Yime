#include "CandidatePopup.h"

#include <algorithm>
#include <filesystem>
#include <windowsx.h>

namespace {

HINSTANCE currentModule() noexcept {
    HMODULE module = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&currentModule), &module);
    return module;
}

std::wstring widen(const std::string& value) {
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                           static_cast<int>(value.size()), nullptr, 0);
    if (length <= 0) return {};
    std::wstring result(static_cast<size_t>(length), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                            static_cast<int>(value.size()), result.data(), length) != length) return {};
    return result;
}

}  // namespace

CandidatePopup::~CandidatePopup() { Destroy(); }

void CandidatePopup::SetFontPoints(int points) noexcept {
    const int normalized = points == 10 || points == 16 ? points : 12;
    if (fontPoints_ == normalized) return;
    fontPoints_ = normalized;
    if (font_) {
        DeleteObject(font_);
        font_ = nullptr;
    }
}

void CandidatePopup::SetUseYinyuanFont(bool useYinyuan) noexcept {
    if (useYinyuanFont_ == useYinyuan) return;
    useYinyuanFont_ = useYinyuan;
    if (font_) {
        DeleteObject(font_);
        font_ = nullptr;
    }
    if (useYinyuanFont_) {
        EnsurePrivateYinyuanFont();
    } else {
        ReleasePrivateYinyuanFont();
    }
}

void CandidatePopup::EnsurePrivateYinyuanFont() noexcept {
    if (privateYinyuanFontAdded_) return;
    wchar_t modulePath[MAX_PATH]{};
    const DWORD length = GetModuleFileNameW(currentModule(), modulePath, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) return;
    const auto root = std::filesystem::path(modulePath).parent_path().parent_path();
    privateYinyuanFontPath_ =
        (root / L"data" / L"fonts" / L"YinYuan-Regular.ttf").wstring();
    if (AddFontResourceExW(privateYinyuanFontPath_.c_str(), FR_PRIVATE, nullptr) > 0) {
        privateYinyuanFontAdded_ = true;
    } else {
        privateYinyuanFontPath_.clear();
    }
}

void CandidatePopup::ReleasePrivateYinyuanFont() noexcept {
    if (privateYinyuanFontAdded_) {
        RemoveFontResourceExW(privateYinyuanFontPath_.c_str(), FR_PRIVATE, nullptr);
    }
    privateYinyuanFontAdded_ = false;
    privateYinyuanFontPath_.clear();
}

HFONT CandidatePopup::EnsureFont() noexcept {
    if (font_) return font_;
    if (useYinyuanFont_) EnsurePrivateYinyuanFont();
    UINT dpi = 96;
    if (window_) dpi = GetDpiForWindow(window_);
    const int height = -MulDiv(fontPoints_, static_cast<int>(dpi), 72);
    font_ = CreateFontW(height, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
                        useYinyuanFont_ ? L"YinYuan" : L"Microsoft YaHei UI");
    return font_ ? font_ : static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
}

bool CandidatePopup::EnsureWindow(HWND owner) noexcept {
    if (window_) {
        SetWindowLongPtrW(window_, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner));
        return true;
    }
    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.style = CS_HREDRAW | CS_VREDRAW;
    windowClass.lpfnWndProc = WindowProcedure;
    windowClass.hInstance = currentModule();
    windowClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    windowClass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    windowClass.lpszClassName = ClassName();
    if (!RegisterClassExW(&windowClass) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
    window_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
                              ClassName(), L"", WS_POPUP | WS_BORDER, 0, 0, 0, 0,
                              owner, nullptr, windowClass.hInstance, this);
    return window_ != nullptr;
}

bool CandidatePopup::Update(const std::vector<std::wstring>& candidates, const RECT& anchor,
                            HWND owner, bool textExtentAnchor, size_t selectedIndex,
                            const yime::experiment::BrokerCandidate* sentence,
                            int activeSegmentStart, int activeSegmentEnd) noexcept {
    candidates_.assign(candidates.begin(),
                       candidates.begin() + static_cast<std::ptrdiff_t>(std::min<size_t>(9, candidates.size())));
    sentenceSegments_.clear();
    if (sentence) {
        for (const auto& segment : sentence->segments) {
            sentenceSegments_.push_back({segment.start, segment.end, widen(segment.text),
                                         segment.start == activeSegmentStart &&
                                             segment.end == activeSegmentEnd,
                                          0});
        }
		if (sentence->segments.empty() && !sentence->text.empty()) {
			// A system-lexicon whole word is a committable sentence row but has
			// no editable subsegments. Render one inert cell so it stays visibly
			// whole and cannot be mistaken for a character-by-character fallback.
			sentenceSegments_.push_back({-1, -1, widen(sentence->text), false, 0});
		}
    }
    if (candidates_.empty() && sentenceSegments_.empty()) {
        Destroy();
        return true;
    }
    selectedIndex_ = selectedIndex;
    if (!EnsureWindow(owner)) return false;
    SetPropW(window_, L"YimeTextServiceExperimentTextExtentAnchor",
             reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(textExtentAnchor ? 1 : 0)));

    HDC dc = GetDC(window_);
    if (!dc) return false;
    HFONT font = EnsureFont();
    HGDIOBJ previous = SelectObject(dc, font);
    TEXTMETRICW metrics{};
    GetTextMetricsW(dc, &metrics);
    rowHeight_ = std::max(20, static_cast<int>(metrics.tmHeight) + 6);
    int textWidth = 0;
    for (const auto& candidate : candidates_) {
        SIZE extent{};
        if (GetTextExtentPoint32W(dc, candidate.c_str(), static_cast<int>(candidate.size()), &extent)) {
            textWidth = std::max(textWidth, static_cast<int>(extent.cx));
        }
    }
    static constexpr wchar_t sentenceLabel[] = L"句:";
    SIZE labelExtent{};
    GetTextExtentPoint32W(dc, sentenceLabel, 2, &labelExtent);
    sentenceLabelWidth_ = labelExtent.cx;
    int sentenceWidth = sentenceLabelWidth_;
    for (auto& segment : sentenceSegments_) {
        SIZE extent{};
        GetTextExtentPoint32W(dc, segment.text.c_str(), static_cast<int>(segment.text.size()), &extent);
        segment.width = std::max(rowHeight_, static_cast<int>(extent.cx) + 8);
        sentenceWidth += segment.width;
    }
    SelectObject(dc, previous);
    ReleaseDC(window_, dc);
    textWidth = std::max(textWidth, sentenceWidth);
    width_ = std::max(1, textWidth + padding_ * 2);
    Reposition(anchor);
    InvalidateRect(window_, nullptr, TRUE);
    UpdateWindow(window_);
    return true;
}

void CandidatePopup::Reposition(const RECT& anchor) noexcept {
    if (!window_) return;
    const int height = rowHeight_ * static_cast<int>(RowCount()) + padding_ * 2;
    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info)) info.rcWork = {0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
    width_ = std::min(width_, static_cast<int>(info.rcWork.right - info.rcWork.left));
    int x = anchor.left;
    int y = anchor.bottom;
    if (y + height > info.rcWork.bottom && anchor.top - height >= info.rcWork.top) y = anchor.top - height;
    x = std::clamp(x, static_cast<int>(info.rcWork.left),
                   std::max(static_cast<int>(info.rcWork.left), static_cast<int>(info.rcWork.right) - width_));
    y = std::clamp(y, static_cast<int>(info.rcWork.top),
                   std::max(static_cast<int>(info.rcWork.top), static_cast<int>(info.rcWork.bottom) - height));
    SetWindowPos(window_, HWND_TOPMOST, x, y, width_, height, SWP_NOACTIVATE);
}

void CandidatePopup::Show(bool show) noexcept {
    if (!window_) return;
    ShowWindow(window_, show ? SW_SHOWNOACTIVATE : SW_HIDE);
}

void CandidatePopup::Destroy() noexcept {
    if (window_ && GetCapture() == window_) ReleaseCapture();
    if (window_) {
        DestroyWindow(window_);
        window_ = nullptr;
    }
    candidates_.clear();
    sentenceSegments_.clear();
    sentenceLabelWidth_ = 0;
    trackedSegment_ = -1;
    width_ = 0;
    rowHeight_ = 0;
    selectedIndex_ = 0;
    if (font_) {
        DeleteObject(font_);
        font_ = nullptr;
    }
    ReleasePrivateYinyuanFont();
}

RECT CandidatePopup::Bounds() const noexcept {
    RECT bounds{};
    if (window_) GetWindowRect(window_, &bounds);
    return bounds;
}

void CandidatePopup::Paint() noexcept {
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window_, &paint);
    if (!dc) return;
    RECT client{};
    GetClientRect(window_, &client);
    FillRect(dc, &client, GetSysColorBrush(COLOR_WINDOW));
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT));
    HGDIOBJ previous = SelectObject(dc, EnsureFont());
    size_t rowIndex = 0;
    if (!sentenceSegments_.empty()) {
        static constexpr wchar_t sentenceLabel[] = L"句:";
        RECT label{padding_, padding_, padding_ + sentenceLabelWidth_, padding_ + rowHeight_};
        DrawTextW(dc, sentenceLabel, 2, &label,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
        int left = label.right;
        for (const auto& segment : sentenceSegments_) {
            RECT cell{left, padding_, left + segment.width, padding_ + rowHeight_};
            FillRect(dc, &cell, GetSysColorBrush(segment.active ? COLOR_HIGHLIGHT : COLOR_BTNFACE));
            SetTextColor(dc, GetSysColor(segment.active ? COLOR_HIGHLIGHTTEXT : COLOR_BTNTEXT));
            DrawTextW(dc, segment.text.c_str(), static_cast<int>(segment.text.size()), &cell,
                      DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
            FrameRect(dc, &cell, static_cast<HBRUSH>(GetStockObject(GRAY_BRUSH)));
            left = cell.right;
        }
        rowIndex = 1;
    }
    for (size_t index = 0; index < candidates_.size(); ++index) {
        RECT row{padding_, padding_ + static_cast<LONG>(rowIndex + index) * rowHeight_,
                 client.right - padding_, padding_ + static_cast<LONG>(rowIndex + index + 1) * rowHeight_};
        if (index == selectedIndex_) {
            FillRect(dc, &row, GetSysColorBrush(COLOR_HIGHLIGHT));
            SetTextColor(dc, GetSysColor(COLOR_HIGHLIGHTTEXT));
        } else {
            SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT));
        }
        DrawTextW(dc, candidates_[index].c_str(), static_cast<int>(candidates_[index].size()),
                  &row, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
    }
    SelectObject(dc, previous);
    EndPaint(window_, &paint);
}

int CandidatePopup::SegmentAt(int x, int y) const noexcept {
    if (sentenceSegments_.empty() || y < padding_ || y >= padding_ + rowHeight_) return -1;
    int left = padding_ + sentenceLabelWidth_;
    for (size_t index = 0; index < sentenceSegments_.size(); ++index) {
        const int right = left + sentenceSegments_[index].width;
		if (sentenceSegments_[index].start >= 0 &&
			sentenceSegments_[index].end > sentenceSegments_[index].start &&
			x >= left && x < right) return static_cast<int>(index);
        left = right;
    }
    return -1;
}

void CandidatePopup::TrackAt(LPARAM lParam) noexcept {
    trackedSegment_ = SegmentAt(GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));
    if (trackedSegment_ >= 0) SetCapture(window_);
}

void CandidatePopup::SelectAt(LPARAM lParam) noexcept {
    if (rowHeight_ <= 0) return;
    const int x = GET_X_LPARAM(lParam);
    const int y = GET_Y_LPARAM(lParam);
    if (trackedSegment_ >= 0) {
        const int released = SegmentAt(x, y);
        const int tracked = trackedSegment_;
        trackedSegment_ = -1;
        if (GetCapture() == window_) ReleaseCapture();
        if (released == tracked && segmentHandler_ &&
            tracked < static_cast<int>(sentenceSegments_.size())) {
            const auto& segment = sentenceSegments_[tracked];
            segmentHandler_(segmentContext_, segment.start, segment.end);
        }
        return;
    }
    if (!selectionHandler_) return;
    RECT client{};
    GetClientRect(window_, &client);
    if (x < padding_ || x >= client.right - padding_ || y < padding_) return;
    const size_t row = static_cast<size_t>((y - padding_) / rowHeight_);
    if (!sentenceSegments_.empty() && row == 0) return;
    const size_t index = row - (sentenceSegments_.empty() ? 0 : 1);
    if (index >= candidates_.size()) return;
    selectionHandler_(selectionContext_, static_cast<unsigned>(index + 1));
}

LRESULT CALLBACK CandidatePopup::WindowProcedure(HWND window, UINT message, WPARAM wParam,
                                                  LPARAM lParam) noexcept {
    auto* self = reinterpret_cast<CandidatePopup*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
        self = static_cast<CandidatePopup*>(create->lpCreateParams);
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    switch (message) {
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;
        case WM_ERASEBKGND:
            return 1;
        case WM_PAINT:
            if (self) self->Paint();
            return 0;
        case WM_LBUTTONDOWN:
            if (self) self->TrackAt(lParam);
            return 0;
        case WM_LBUTTONUP:
            if (self) self->SelectAt(lParam);
            return 0;
        case WM_NCDESTROY:
            SetWindowLongPtrW(window, GWLP_USERDATA, 0);
            break;
        default:
            break;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}
