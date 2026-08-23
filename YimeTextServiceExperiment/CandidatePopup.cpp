#include "CandidatePopup.h"

#include <algorithm>
#include <windowsx.h>

namespace {

HINSTANCE currentModule() noexcept {
    HMODULE module = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&currentModule), &module);
    return module;
}

}  // namespace

CandidatePopup::~CandidatePopup() { Destroy(); }

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
                            HWND owner, bool textExtentAnchor) noexcept {
    candidates_.assign(candidates.begin(),
                       candidates.begin() + static_cast<std::ptrdiff_t>(std::min<size_t>(9, candidates.size())));
    if (candidates_.empty()) {
        Destroy();
        return true;
    }
    if (!EnsureWindow(owner)) return false;
    SetPropW(window_, L"YimeTextServiceExperimentTextExtentAnchor",
             reinterpret_cast<HANDLE>(static_cast<UINT_PTR>(textExtentAnchor ? 1 : 0)));

    HDC dc = GetDC(window_);
    if (!dc) return false;
    HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
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
    SelectObject(dc, previous);
    ReleaseDC(window_, dc);
    width_ = std::clamp(textWidth + padding_ * 2, 160, 640);
    Reposition(anchor);
    InvalidateRect(window_, nullptr, TRUE);
    UpdateWindow(window_);
    return true;
}

void CandidatePopup::Reposition(const RECT& anchor) noexcept {
    if (!window_) return;
    const int height = rowHeight_ * static_cast<int>(candidates_.size()) + padding_ * 2;
    HMONITOR monitor = MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info)) info.rcWork = {0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
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
    if (window_) {
        DestroyWindow(window_);
        window_ = nullptr;
    }
    candidates_.clear();
    width_ = 0;
    rowHeight_ = 0;
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
    HGDIOBJ previous = SelectObject(dc, GetStockObject(DEFAULT_GUI_FONT));
    for (size_t index = 0; index < candidates_.size(); ++index) {
        RECT row{padding_, padding_ + static_cast<LONG>(index) * rowHeight_,
                 client.right - padding_, padding_ + static_cast<LONG>(index + 1) * rowHeight_};
        DrawTextW(dc, candidates_[index].c_str(), static_cast<int>(candidates_[index].size()),
                  &row, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
    }
    SelectObject(dc, previous);
    EndPaint(window_, &paint);
}

void CandidatePopup::SelectAt(LPARAM lParam) noexcept {
    if (!selectionHandler_ || rowHeight_ <= 0) return;
    const int x = GET_X_LPARAM(lParam);
    const int y = GET_Y_LPARAM(lParam);
    RECT client{};
    GetClientRect(window_, &client);
    if (x < padding_ || x >= client.right - padding_ || y < padding_) return;
    const size_t index = static_cast<size_t>((y - padding_) / rowHeight_);
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
