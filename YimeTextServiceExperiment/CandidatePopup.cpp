#include "CandidatePopup.h"

#include <algorithm>
#include <filesystem>
#include <windowsx.h>

#include "KeyContract.h"

namespace {

constexpr wchar_t kSentenceLabel[] = L"句:";
constexpr wchar_t kQuickForgetLabel[] = L"快速遗忘（清除学习）";
constexpr UINT kQuickForgetCommand = 1;
constexpr UINT kSettingsRefreshMilliseconds = 250;

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

void CandidatePopup::SetFontFamily(const std::wstring& family) noexcept {
    const std::wstring normalized = family == L"system-ui" || family == L"YinYuan"
        ? family : L"Microsoft YaHei UI";
    if (fontFamily_ == normalized) return;
    const bool previouslyUsedYinyuan = UsesYinyuanFont();
    fontFamily_ = normalized;
    if (font_) {
        DeleteObject(font_);
        font_ = nullptr;
    }
    if (UsesYinyuanFont()) {
        EnsurePrivateYinyuanFont();
    } else if (previouslyUsedYinyuan) {
        ReleasePrivateYinyuanFont();
    }
}

void CandidatePopup::SetUseYinyuanFont(bool useYinyuan) noexcept {
    if (useYinyuanFont_ == useYinyuan) return;
    const bool previouslyUsedYinyuan = UsesYinyuanFont();
    useYinyuanFont_ = useYinyuan;
    if (font_) {
        DeleteObject(font_);
        font_ = nullptr;
    }
    if (UsesYinyuanFont()) {
        EnsurePrivateYinyuanFont();
    } else if (previouslyUsedYinyuan) {
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
    const bool useYinyuan = UsesYinyuanFont();
    if (useYinyuan) EnsurePrivateYinyuanFont();
    UINT dpi = 96;
    if (window_) dpi = GetDpiForWindow(window_);
    const int height = -MulDiv(fontPoints_, static_cast<int>(dpi), 72);
    std::wstring family = fontFamily_;
    if (family == L"system-ui") {
        NONCLIENTMETRICSW metrics{};
        metrics.cbSize = sizeof(metrics);
        if (SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof(metrics), &metrics, 0)) {
            family = metrics.lfMessageFont.lfFaceName;
        } else {
            family = L"Microsoft YaHei UI";
        }
    }
    font_ = CreateFontW(height, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                        CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
                        useYinyuan ? L"YinYuan" : family.c_str());
    return font_ ? font_ : static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
}

bool CandidatePopup::EnsureWindow(HWND owner) noexcept {
    if (window_) {
        SetWindowLongPtrW(window_, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner));
        return true;
    }
    WNDCLASSEXW windowClass{};
    windowClass.cbSize = sizeof(windowClass);
    windowClass.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
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
                            int activeSegmentStart, int activeSegmentEnd,
							const std::wstring* status) noexcept {
    candidates_.assign(candidates.begin(),
                       candidates.begin() + static_cast<std::ptrdiff_t>(std::min<size_t>(9, candidates.size())));
    sentenceSegments_.clear();
	status_ = status ? *status : std::wstring();
    if (sentence) {
        for (const auto& segment : sentence->segments) {
            sentenceSegments_.push_back({segment.start, segment.end, widen(segment.text),
                                         segment.start == activeSegmentStart &&
                                             segment.end == activeSegmentEnd,
                                          0});
        }
		if (sentence->segments.empty() && !sentence->text.empty()) {
            const int codeEnd = sentence->code.empty() ? -1 : static_cast<int>(sentence->code.size());
            sentenceSegments_.push_back({codeEnd < 0 ? -1 : 0, codeEnd,
                                         widen(sentence->text), false, 0});
		}
    }
    if (candidates_.empty() && sentenceSegments_.empty() && status_.empty()) {
        Destroy();
        return true;
    }
    selectedIndex_ = selectedIndex;
    if (!EnsureWindow(owner)) return false;
    anchor_ = anchor;
    SetPropW(window_, L"YimeTextServiceExperimentTextExtentAnchor",
             reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(textExtentAnchor ? 1 : 0)));
    SetPropW(window_, L"YimeTextServiceExperimentSentenceRow",
             reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(sentenceSegments_.empty() ? 0 : 1)));
    SetPropW(window_, L"YimeTextServiceExperimentSentenceSegmentCount",
             reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(sentenceSegments_.size())));
    SetPropW(window_, L"YimeTextServiceExperimentActiveSegmentStart",
             reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(activeSegmentStart + 1)));
    SetPropW(window_, L"YimeTextServiceExperimentActiveSegmentEnd",
             reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(activeSegmentEnd + 1)));
    RefreshLayout(anchor_);
    return true;
}

void CandidatePopup::RefreshDisplaySettings() noexcept {
    const auto& settings = liveSettings_.Get();
    if (settings.candidateFontPoints == fontPoints_) return;
    SetFontPoints(settings.candidateFontPoints);
    RefreshLayout(anchor_);
}

void CandidatePopup::RefreshLayout(const RECT& anchor) noexcept {
    if (!window_) return;
    HDC dc = GetDC(window_);
    if (!dc) return;
    HFONT font = EnsureFont();
    HGDIOBJ previous = SelectObject(dc, font);
    TEXTMETRICW metrics{};
    GetTextMetricsW(dc, &metrics);
    rowHeight_ = std::max(20, static_cast<int>(metrics.tmHeight) + 6);
    SetPropW(window_, L"YimeTextServiceExperimentCandidateRowHeight",
             reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(rowHeight_)));
    int textWidth = 0;
    candidateWidths_.clear();
    candidateWidths_.reserve(candidates_.size());
    for (const auto& candidate : candidates_) {
        SIZE extent{};
        if (GetTextExtentPoint32W(dc, candidate.c_str(), static_cast<int>(candidate.size()), &extent)) {
            const int candidateWidth = std::max(rowHeight_, static_cast<int>(extent.cx) + 12);
            candidateWidths_.push_back(candidateWidth);
            if (horizontal_) {
                textWidth += candidateWidth;
            } else {
                textWidth = std::max(textWidth, static_cast<int>(extent.cx));
            }
        } else {
            candidateWidths_.push_back(rowHeight_);
        }
    }
    std::wstring candidatePrefix(yime::experiment::CandidateLabels().front());
    candidatePrefix += L"  ";
    SIZE candidatePrefixExtent{};
    GetTextExtentPoint32W(dc, candidatePrefix.c_str(), static_cast<int>(candidatePrefix.size()),
                          &candidatePrefixExtent);
    textColumnOffset_ = candidatePrefixExtent.cx;
    SetPropW(window_, L"YimeTextServiceExperimentTextColumnLeft",
             reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(padding_ + textColumnOffset_)));
    int sentenceWidth = textColumnOffset_;
    for (auto& segment : sentenceSegments_) {
        SIZE extent{};
        GetTextExtentPoint32W(dc, segment.text.c_str(), static_cast<int>(segment.text.size()), &extent);
        segment.width = std::max(rowHeight_, static_cast<int>(extent.cx) + 8);
        sentenceWidth += segment.width;
    }
    SIZE statusExtent{};
    if (!status_.empty() &&
        GetTextExtentPoint32W(dc, status_.c_str(), static_cast<int>(status_.size()), &statusExtent)) {
        textWidth = std::max(textWidth, static_cast<int>(statusExtent.cx));
    }
    SelectObject(dc, previous);
    ReleaseDC(window_, dc);
    textWidth = std::max(textWidth, sentenceWidth);
    width_ = std::max(1, textWidth + padding_ * 2);
    Reposition(anchor);
    InvalidateRect(window_, nullptr, TRUE);
    UpdateWindow(window_);
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
    if (show) {
        SetTimer(window_, SettingsRefreshTimerId, kSettingsRefreshMilliseconds, nullptr);
    } else {
        KillTimer(window_, SettingsRefreshTimerId);
    }
    ShowWindow(window_, show ? SW_SHOWNOACTIVATE : SW_HIDE);
}

void CandidatePopup::Destroy() noexcept {
    if (window_ && GetCapture() == window_) ReleaseCapture();
    if (window_) {
        KillTimer(window_, SettingsRefreshTimerId);
        DestroyWindow(window_);
        window_ = nullptr;
    }
    candidates_.clear();
    candidateWidths_.clear();
    sentenceSegments_.clear();
	status_.clear();
    textColumnOffset_ = 0;
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
        RECT label{padding_, padding_, padding_ + textColumnOffset_, padding_ + rowHeight_};
        DrawTextW(dc, kSentenceLabel, lstrlenW(kSentenceLabel), &label,
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
    if (!status_.empty()) {
        RECT statusRow{padding_, padding_ + static_cast<LONG>(rowIndex) * rowHeight_,
            client.right - padding_, padding_ + static_cast<LONG>(rowIndex + 1) * rowHeight_};
        SetTextColor(dc, GetSysColor(COLOR_GRAYTEXT));
        DrawTextW(dc, status_.c_str(), static_cast<int>(status_.size()), &statusRow,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
        ++rowIndex;
    }
    int candidateLeft = padding_;
    for (size_t index = 0; index < candidates_.size(); ++index) {
        const LONG top = padding_ + static_cast<LONG>(rowIndex + (horizontal_ ? 0 : index)) * rowHeight_;
        RECT row{horizontal_ ? candidateLeft : padding_, top,
                 horizontal_ ? candidateLeft + candidateWidths_[index] : client.right - padding_,
                 top + rowHeight_};
        if (index == selectedIndex_) {
            FillRect(dc, &row, GetSysColorBrush(COLOR_HIGHLIGHT));
            SetTextColor(dc, GetSysColor(COLOR_HIGHLIGHTTEXT));
        } else {
            SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT));
        }
        DrawTextW(dc, candidates_[index].c_str(), static_cast<int>(candidates_[index].size()),
                  &row, (horizontal_ ? DT_CENTER : DT_LEFT) | DT_VCENTER | DT_SINGLELINE |
                            DT_END_ELLIPSIS | DT_NOPREFIX);
        if (horizontal_) {
            FrameRect(dc, &row, static_cast<HBRUSH>(GetStockObject(LTGRAY_BRUSH)));
            candidateLeft = row.right;
        }
    }
    SelectObject(dc, previous);
    EndPaint(window_, &paint);
}

int CandidatePopup::SegmentAt(int x, int y) const noexcept {
    if (sentenceSegments_.empty() || y < padding_ || y >= padding_ + rowHeight_) return -1;
    int left = padding_ + textColumnOffset_;
    for (size_t index = 0; index < sentenceSegments_.size(); ++index) {
        const int right = left + sentenceSegments_[index].width;
		if (sentenceSegments_[index].start >= 0 &&
			sentenceSegments_[index].end > sentenceSegments_[index].start &&
			x >= left && x < right) return static_cast<int>(index);
        left = right;
    }
    return -1;
}

int CandidatePopup::CandidateAt(int x, int y) const noexcept {
    if (rowHeight_ <= 0) return -1;
    RECT client{};
    GetClientRect(window_, &client);
    if (x < padding_ || x >= client.right - padding_ || y < padding_) return -1;
    const size_t row = static_cast<size_t>((y - padding_) / rowHeight_);
    const size_t leadingRows = (sentenceSegments_.empty() ? 0 : 1) + (status_.empty() ? 0 : 1);
    if (row < leadingRows) return -1;
    size_t index = row - leadingRows;
    if (horizontal_) {
        if (index != 0) return -1;
        int left = padding_;
        index = candidates_.size();
        for (size_t candidateIndex = 0; candidateIndex < candidateWidths_.size(); ++candidateIndex) {
            const int right = left + candidateWidths_[candidateIndex];
            if (x >= left && x < right) {
                index = candidateIndex;
                break;
            }
            left = right;
        }
    }
    return index < candidates_.size() ? static_cast<int>(index) : -1;
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
    if (!sentenceSegments_.empty() && y >= padding_ && y < padding_ + rowHeight_ &&
        x >= padding_ && x < padding_ + textColumnOffset_) {
        if (sentenceHandler_) sentenceHandler_(sentenceContext_);
        return;
    }
    if (!selectionHandler_) return;
    const int index = CandidateAt(x, y);
    if (index < 0) return;
    selectionHandler_(selectionContext_, static_cast<unsigned>(index + 1));
}

UINT CandidatePopup::PresentPopup(HMENU menu, POINT point, HWND owner, void*) noexcept {
    return TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                          point.x, point.y, 0, owner, nullptr);
}

void CandidatePopup::ForgetAt(LPARAM lParam) noexcept {
    if (!forgetEnabled_ || !forgetHandler_) return;
    const int index = CandidateAt(GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));
    if (index < 0) return;
    selectedIndex_ = static_cast<size_t>(index);
    InvalidateRect(window_, nullptr, TRUE);
    UpdateWindow(window_);
    HMENU menu = CreatePopupMenu();
    if (!menu) return;
    if (!AppendMenuW(menu, MF_STRING, kQuickForgetCommand, kQuickForgetLabel)) {
        DestroyMenu(menu);
        return;
    }
    POINT point{GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)};
    ClientToScreen(window_, &point);
    const auto presenter = popupPresenter_ ? popupPresenter_ : PresentPopup;
    const UINT command = presenter(menu, point, window_, popupPresenterContext_);
    DestroyMenu(menu);
    if (command == kQuickForgetCommand) {
        forgetHandler_(forgetContext_, static_cast<unsigned>(index + 1));
    }
}

void CandidatePopup::ExpandAt(LPARAM lParam) noexcept {
    const int index = SegmentAt(GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));
    if (index < 0 || !segmentExpandHandler_ ||
        index >= static_cast<int>(sentenceSegments_.size())) return;
    const auto& segment = sentenceSegments_[index];
    segmentExpandHandler_(segmentExpandContext_, segment.start, segment.end);
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
        case WM_TIMER:
            if (self && wParam == SettingsRefreshTimerId) self->RefreshDisplaySettings();
            return 0;
        case WM_LBUTTONDOWN:
            if (self) self->TrackAt(lParam);
            return 0;
        case WM_LBUTTONUP:
            if (self) self->SelectAt(lParam);
            return 0;
        case WM_LBUTTONDBLCLK:
            if (self) self->ExpandAt(lParam);
            return 0;
        case WM_RBUTTONUP:
            if (self) self->ForgetAt(lParam);
            return 0;
        case WM_NCDESTROY:
            SetWindowLongPtrW(window, GWLP_USERDATA, 0);
            break;
        default:
            break;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}
