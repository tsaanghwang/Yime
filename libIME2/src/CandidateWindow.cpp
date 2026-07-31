//
//    Copyright (C) 2013 - 2020 Hong Jen Yee (PCMan) <pcman.tw@gmail.com>
//
//    This library is free software; you can redistribute it and/or
//    modify it under the terms of the GNU Library General Public
//    License as published by the Free Software Foundation; either
//    version 2 of the License, or (at your option) any later version.
//
//    This library is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
//    Library General Public License for more details.
//
//    You should have received a copy of the GNU Library General Public
//    License along with this library; if not, write to the
//    Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
//    Boston, MA  02110-1301, USA.
//

#include "CandidateWindow.h"
#include "CandidateWindowClickPolicy.h"
#include "CompositionSegmentStrip.h"
#include "DrawUtils.h"
#include "TextService.h"
#include "EditSession.h"

#include <algorithm>
#include <cassert>

#include <tchar.h>
#include <windows.h>

using namespace std;

namespace Ime {

CandidateWindow::CandidateWindow(TextService* service, EditSession* session):
    ImeWindow(service),
    shown_(false),
    candPerRow_(1),
    textWidth_(0),
    itemHeight_(0),
    currentSel_(0),
    hasResult_(false),
    useCursor_(true),
    trackingCandidateClick_(false),
    trackingCompositionSegmentClick_(false),
    trackedCompositionSegment_(-1),
    compositionLabelWidth_(0),
    compositionStripHeight_(0),
    selKeyWidth_(0) {

    if(service->isImmersive()) { // windows 8 app mode
        margin_ = 10;
        rowSpacing_ = 8;
        colSpacing_ = 12;
    }
    else { // desktop mode
        margin_ = 5;
        rowSpacing_ = 4;
        colSpacing_ = 8;
    }

    HWND parent = service->compositionWindow(session);
    create(parent, WS_POPUP|WS_CLIPCHILDREN,
        WS_EX_TOOLWINDOW|WS_EX_TOPMOST|WS_EX_NOACTIVATE);
}

CandidateWindow::~CandidateWindow(void) {
}

// ITfUIElement
STDMETHODIMP CandidateWindow::GetDescription(BSTR *pbstrDescription) {
    if (!pbstrDescription)
        return E_INVALIDARG;
    *pbstrDescription = SysAllocString(L"Candidate window~");
    return S_OK;
}

// {BD7CCC94-57CD-41D3-A789-AF47890CEB29}
STDMETHODIMP CandidateWindow::GetGUID(GUID *pguid) {
    if (!pguid)
        return E_INVALIDARG;
    *pguid = { 0xbd7ccc94, 0x57cd, 0x41d3, { 0xa7, 0x89, 0xaf, 0x47, 0x89, 0xc, 0xeb, 0x29 } };
    return S_OK;
}

STDMETHODIMP CandidateWindow::Show(BOOL bShow) {
    shown_ = bShow;
    if (shown_)
        show();
    else
        hide();
    return S_OK;
}

STDMETHODIMP CandidateWindow::IsShown(BOOL *pbShow) {
    if (!pbShow)
        return E_INVALIDARG;
    *pbShow = shown_;
    return S_OK;
}

// ITfCandidateListUIElement
STDMETHODIMP CandidateWindow::GetUpdatedFlags(DWORD *pdwFlags) {
    if (!pdwFlags)
        return E_INVALIDARG;
    /// XXX update all!!!
    *pdwFlags = TF_CLUIE_DOCUMENTMGR | TF_CLUIE_COUNT | TF_CLUIE_SELECTION | TF_CLUIE_STRING | TF_CLUIE_PAGEINDEX | TF_CLUIE_CURRENTPAGE;
    return S_OK;
}

STDMETHODIMP CandidateWindow::GetDocumentMgr(ITfDocumentMgr **ppdim) {
    if (!textService_)
        return E_FAIL;
    return textService_->currentContext()->GetDocumentMgr(ppdim);
}

STDMETHODIMP CandidateWindow::GetCount(UINT *puCount) {
    if (!puCount)
        return E_INVALIDARG;
    *puCount = std::min<UINT>(10, items_.size());
    return S_OK;
}

STDMETHODIMP CandidateWindow::GetSelection(UINT *puIndex) {
    assert(currentSel_ >= 0);
    if (!puIndex)
        return E_INVALIDARG;
    *puIndex = static_cast<UINT>(currentSel_);
    return S_OK;
}

STDMETHODIMP CandidateWindow::GetString(UINT uIndex, BSTR *pbstr) {
    if (!pbstr)
        return E_INVALIDARG;
    if (uIndex >= items_.size())
        return E_INVALIDARG;
    *pbstr = SysAllocString(items_[uIndex].c_str());
    return S_OK;
}

STDMETHODIMP CandidateWindow::GetPageIndex(UINT *puIndex, UINT uSize, UINT *puPageCnt) {
    /// XXX Always return the same single page index.
    if (!puPageCnt)
        return E_INVALIDARG;
    *puPageCnt = 1;
    if (puIndex) {
        if (uSize < *puPageCnt) {
            return E_INVALIDARG;
        }
        puIndex[0] = 0;
    }
    return S_OK;
}

STDMETHODIMP CandidateWindow::SetPageIndex(UINT *puIndex, UINT uPageCnt) {
    /// XXX Do not let app set page indices.
    if (!puIndex)
        return E_INVALIDARG;
    return S_OK;
}

STDMETHODIMP CandidateWindow::GetCurrentPage(UINT *puPage) {
    if (!puPage)
        return E_INVALIDARG;
    *puPage = 0;
    return S_OK;
}

LRESULT CandidateWindow::wndProc(UINT msg, WPARAM wp , LPARAM lp) {
    switch (msg) {
        case WM_PAINT:
            onPaint(wp, lp);
            break;
        case WM_ERASEBKGND:
            return TRUE;
            break;
        case WM_LBUTTONDOWN:
            onLButtonDown(wp, lp);
            break;
        case WM_MOUSEMOVE:
            onMouseMove(wp, lp);
            break;
        case WM_LBUTTONUP:
            onLButtonUp(wp, lp);
            break;
        case WM_RBUTTONUP:
            onRButtonUp(wp, lp);
            break;
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;
        default:
            return Window::wndProc(msg, wp, lp);
    }
    return 0;
}

void CandidateWindow::onPaint(WPARAM wp, LPARAM lp) {
    // TODO: check isImmersive_, and draw the window differently
    // in Windows 8 app immersive mode to follow windows 8 UX guidelines
    PAINTSTRUCT ps;
    BeginPaint(hwnd_, &ps);
    HDC hDC = ps.hdc;
    HFONT oldFont;
    RECT rc;

    oldFont = (HFONT)SelectObject(hDC, font_);

    GetClientRect(hwnd_,&rc);
    SetTextColor(hDC, GetSysColor(COLOR_WINDOWTEXT));
    SetBkColor(hDC, GetSysColor(COLOR_WINDOW));

    // paint window background and border
    // draw a flat black border in Windows 8 app immersive mode
    // draw a 3d border in desktop mode
    if(isImmersive()) {
        HPEN pen = ::CreatePen(PS_SOLID, 3, RGB(0, 0, 0));
        HGDIOBJ oldPen = ::SelectObject(hDC, pen);
        ::Rectangle(hDC, rc.left, rc.top, rc.right, rc.bottom);
        ::SelectObject(hDC, oldPen);
        ::DeleteObject(pen);
    }
    else {
        // draw a 3d border in desktop mode
        ::FillSolidRect(ps.hdc, rc.left, rc.top, rc.right - rc.left, rc.bottom - rc.top, GetSysColor(COLOR_WINDOW));
        ::Draw3DBorder(hDC, &rc, GetSysColor(COLOR_3DFACE), 0);
    }

    paintCompositionSegments(hDC);

    // paint candidate items
    int col = 0;
    int x = margin_, y = candidateRowsTop();
    for(int i = 0, n = items_.size(); i < n; ++i) {
        paintItem(hDC, i, x, y);
        ++col; // go to next column
        if(col >= candPerRow_) {
            col = 0;
            x = margin_;
            y += itemHeight_ + rowSpacing_;
        }
        else {
            x += colSpacing_ + selKeyWidth_ + itemWidths_[i];
        }
    }
    SelectObject(hDC, oldFont);
    EndPaint(hwnd_, &ps);
}

void CandidateWindow::onLButtonDown(WPARAM wp, LPARAM lp) {
    POINTS point = MAKEPOINTS(lp);
    const auto target = candidateWindowClickTarget(
        compositionSegmentFromPoint(point), itemFromPoint(point));
    trackingCompositionSegmentClick_ =
        target.kind == CandidateWindowClickKind::CompositionSegment;
    trackingCandidateClick_ = target.kind == CandidateWindowClickKind::Candidate;
    trackedCompositionSegment_ = trackingCompositionSegmentClick_ ? target.index : -1;
    if(trackingCandidateClick_)
        setCurrentSel(target.index);
    if(trackingCompositionSegmentClick_ || trackingCandidateClick_) {
        SetCapture(hwnd_);
        return;
    }
    ImeWindow::onLButtonDown(wp, lp);
}

void CandidateWindow::onLButtonUp(WPARAM wp, LPARAM lp) {
    if(trackingCompositionSegmentClick_) {
        ReleaseCapture();
        trackingCompositionSegmentClick_ = false;
        int segment = compositionSegmentFromPoint(MAKEPOINTS(lp));
        if(segment >= 0 && segment == trackedCompositionSegment_)
            textService_->onCompositionSegmentSelected(
                compositionSegmentStarts_[segment],
                compositionSegmentEnds_[segment]);
        trackedCompositionSegment_ = -1;
        return;
    }
    if(trackingCandidateClick_) {
        ReleaseCapture();
        trackingCandidateClick_ = false;
        int item = itemFromPoint(MAKEPOINTS(lp));
        if(item >= 0) {
            setCurrentSel(item);
            textService_->onCandidateSelected(currentSel_);
        }
        return;
    }
    ImeWindow::onLButtonUp(wp, lp);
}

void CandidateWindow::onRButtonUp(WPARAM wp, LPARAM lp) {
    if(!textService_->canForgetCandidate())
        return;
    POINTS clientPoint = MAKEPOINTS(lp);
    const int item = candidateWindowForgetTarget(
        compositionSegmentFromPoint(clientPoint), itemFromPoint(clientPoint));
    if(item < 0)
        return;

    setCurrentSel(item);
    HMENU menu = ::CreatePopupMenu();
    if(!menu)
        return;
    constexpr UINT forgetCommand = 1;
    ::AppendMenuW(menu, MF_STRING, forgetCommand,
        L"\u5feb\u901f\u9057\u5fd8\uff08\u6e05\u9664\u5b66\u4e60\uff09");
    POINT screenPoint = { clientPoint.x, clientPoint.y };
    ::ClientToScreen(hwnd_, &screenPoint);
    const UINT command = ::TrackPopupMenu(
        menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        screenPoint.x, screenPoint.y, 0, hwnd_, nullptr);
    ::DestroyMenu(menu);
    if(command == forgetCommand)
        textService_->onCandidateForgetRequested(item);
}

void CandidateWindow::onMouseMove(WPARAM wp, LPARAM lp) {
    if(trackingCompositionSegmentClick_)
        return;
    if(trackingCandidateClick_) {
        int item = itemFromPoint(MAKEPOINTS(lp));
        if(item >= 0) {
            setCurrentSel(item);
        }
        return;
    }
    ImeWindow::onMouseMove(wp, lp);
}

void CandidateWindow::recalculateSize() {
    if(items_.empty() && compositionCells_.empty()) {
        resize(margin_ * 2, margin_ * 2);
        return;
    }

    HDC hDC = ::GetWindowDC(hwnd());
    int height = 0;
    int width = 0;
    selKeyWidth_ = 0;
    textWidth_ = 0;
    itemHeight_ = 0;
    itemWidths_.clear();
    itemWidths_.reserve(items_.size());
    compositionCellWidths_.clear();
    compositionCellWidths_.reserve(compositionCells_.size());

    HGDIOBJ oldFont = ::SelectObject(hDC, font_);
    vector<wstring>::const_iterator it;
    for(int i = 0, n = items_.size(); i < n; ++i) {
        SIZE selKeySize;
        int lineHeight = 0;
        // the selection key string
        std::wstring selLabel;
        if(i < selLabels_.size() && !selLabels_[i].empty())
            selLabel = selLabels_[i] + L" ";
        else
            selLabel = std::wstring(1, selKeys_[i]) + L". ";
        ::GetTextExtentPoint32W(hDC, selLabel.c_str(), static_cast<int>(selLabel.length()), &selKeySize);
        if(selKeySize.cx > selKeyWidth_)
            selKeyWidth_ = selKeySize.cx;

        // the candidate string
        SIZE candidateSize;
        wstring& item = items_.at(i);
        ::GetTextExtentPoint32W(hDC, item.c_str(), item.length(), &candidateSize);
        itemWidths_.push_back(candidateSize.cx);
        if(candidateSize.cx > textWidth_)
            textWidth_ = candidateSize.cx;
        int itemHeight = max(candidateSize.cy, selKeySize.cy);
        if(itemHeight > itemHeight_)
            itemHeight_ = itemHeight;
    }

    SIZE labelSize = {};
    const wchar_t* compositionLabel = compositionSegmentStripLabel();
    ::GetTextExtentPoint32W(hDC, compositionLabel, lstrlenW(compositionLabel), &labelSize);
    compositionLabelWidth_ = labelSize.cx;
    compositionStripHeight_ = labelSize.cy + 6;
    int compositionWidth = margin_ * 2 + compositionLabelWidth_;
    for(const auto& cell : compositionCells_) {
        SIZE cellSize = {};
        ::GetTextExtentPoint32W(hDC, cell.c_str(), static_cast<int>(cell.length()), &cellSize);
        int cellWidth = max(cellSize.cx + 8, compositionStripHeight_);
        compositionCellWidths_.push_back(cellWidth);
        compositionWidth += cellWidth;
    }
    ::SelectObject(hDC, oldFont);
    ::ReleaseDC(hwnd(), hDC);

    int rowWidth = margin_ * 2;
    int rowCount = items_.empty() ? 0 : 1;
    for(int i = 0, n = items_.size(); i < n; ++i) {
        if(i > 0 && i % candPerRow_ == 0) {
            if(rowWidth > width)
                width = rowWidth;
            rowWidth = margin_ * 2;
            ++rowCount;
        }
        else if(i % candPerRow_ > 0) {
            rowWidth += colSpacing_;
        }
        rowWidth += selKeyWidth_ + itemWidths_[i];
    }
    if(rowWidth > width)
        width = rowWidth;
    width = max(width, compositionWidth);
    height = margin_ * 2;
    if(!compositionCells_.empty())
        height += compositionStripHeight_;
    if(rowCount > 0) {
        if(!compositionCells_.empty())
            height += rowSpacing_;
        height += itemHeight_ * rowCount + rowSpacing_ * (rowCount - 1);
    }
    resize(width, height);
}

void CandidateWindow::setCompositionSegments(
    const std::vector<CompositionSegmentItem>& segments) {
    compositionCells_.clear();
    compositionSegmentStarts_.clear();
    compositionSegmentEnds_.clear();
    compositionSegmentActive_.clear();
    for(const auto& segment : segments) {
        compositionCells_.push_back(compositionSegmentDisplayText(segment));
        compositionSegmentStarts_.push_back(segment.start);
        compositionSegmentEnds_.push_back(segment.end);
        compositionSegmentActive_.push_back(segment.active);
    }
    recalculateSize();
    refresh();
}

void CandidateWindow::setCandPerRow(int n) {
    if(n != candPerRow_) {
        candPerRow_ = n;
        recalculateSize();
    }
}

bool CandidateWindow::filterKeyEvent(KeyEvent& keyEvent) {
    // select item with arrow keys
    int oldSel = currentSel_;
    switch(keyEvent.keyCode()) {
    case VK_UP:
        if(currentSel_ - candPerRow_ >=0)
            currentSel_ -= candPerRow_;
        break;
    case VK_DOWN:
        if(currentSel_ + candPerRow_ < items_.size())
            currentSel_ += candPerRow_;
        break;
    case VK_LEFT:
        if(currentSel_ - 1 >=0)
            --currentSel_;
        break;
    case VK_RIGHT:
        if(currentSel_ + 1 < items_.size())
            ++currentSel_;
        break;
    case VK_RETURN:
    case VK_SPACE:
        hasResult_ = true;
        return true;
    default:
        return false;
    }
    // if currently selected item is changed, redraw
    if(currentSel_ != oldSel) {
        // repaint the old and new items
        RECT rect;
        itemRect(oldSel, rect);
        ::InvalidateRect(hwnd_, &rect, TRUE);
        itemRect(currentSel_, rect);
        ::InvalidateRect(hwnd_, &rect, TRUE);
        return true;
    }
    return false;
}

void CandidateWindow::setCurrentSel(int sel) {
    if(sel >= items_.size())
        sel = 0;
    if (currentSel_ != sel) {
        currentSel_ = sel;
        if (isVisible())
            ::InvalidateRect(hwnd_, NULL, TRUE);
    }
}

void CandidateWindow::clear() {
    items_.clear();
    selKeys_.clear();
    selLabels_.clear();
    itemWidths_.clear();
    currentSel_ = 0;
    hasResult_ = false;
}

void CandidateWindow::setUseCursor(bool use) {
    useCursor_ = use;
    if(isVisible())
        ::InvalidateRect(hwnd_, NULL, TRUE);
}

void CandidateWindow::paintItem(HDC hDC, int i,  int x, int y) {
    RECT textRect = {x, y, 0, y + itemHeight_};
    std::wstring selLabel;
    if(i < selLabels_.size() && !selLabels_[i].empty())
        selLabel = selLabels_[i] + L" ";
    else
        selLabel = std::wstring(1, selKeys_[i]) + L". ";
    textRect.right = textRect.left + selKeyWidth_;
    bool selected = useCursor_ && i == currentSel_;
    COLORREF oldColor = ::SetTextColor(hDC, selected ? GetSysColor(COLOR_HIGHLIGHTTEXT) : RGB(0, 0, 255));
    COLORREF oldBkColor = ::SetBkColor(hDC, selected ? GetSysColor(COLOR_HIGHLIGHT) : GetSysColor(COLOR_WINDOW));
    // paint the selection key
    ::ExtTextOut(hDC, textRect.left, textRect.top, ETO_OPAQUE, &textRect, selLabel.c_str(), static_cast<UINT>(selLabel.length()), NULL);

    // paint the candidate string
    wstring& item = items_.at(i);
    textRect.left += selKeyWidth_;
    textRect.right = textRect.left + itemWidths_[i];
    if(!selected)
        ::SetTextColor(hDC, GetSysColor(COLOR_WINDOWTEXT));
    // paint the candidate string
    ::ExtTextOut(hDC, textRect.left, textRect.top, ETO_OPAQUE, &textRect, item.c_str(), item.length(), NULL);

    ::SetTextColor(hDC, oldColor);
    ::SetBkColor(hDC, oldBkColor);
}

void CandidateWindow::paintCompositionSegments(HDC hDC) {
    if(compositionCells_.empty())
        return;
    RECT labelRect = {
        margin_, margin_, margin_ + compositionLabelWidth_, margin_ + compositionStripHeight_
    };
    const wchar_t* compositionLabel = compositionSegmentStripLabel();
    ::DrawTextW(hDC, compositionLabel, lstrlenW(compositionLabel), &labelRect,
        DT_LEFT|DT_VCENTER|DT_SINGLELINE);
    for(int i = 0; i < static_cast<int>(compositionCells_.size()); ++i) {
        RECT rect;
        compositionSegmentRect(i, rect);
        bool active = compositionSegmentActive_[i];
        ::SetTextColor(hDC, GetSysColor(active ? COLOR_HIGHLIGHTTEXT : COLOR_BTNTEXT));
        ::SetBkColor(hDC, GetSysColor(active ? COLOR_HIGHLIGHT : COLOR_BTNFACE));
        ::ExtTextOutW(hDC, rect.left, rect.top + 3, ETO_OPAQUE, &rect,
            compositionCells_[i].c_str(),
            static_cast<UINT>(compositionCells_[i].length()), NULL);
        ::FrameRect(hDC, &rect, (HBRUSH)::GetStockObject(GRAY_BRUSH));
    }
    ::SetTextColor(hDC, GetSysColor(COLOR_WINDOWTEXT));
    ::SetBkColor(hDC, GetSysColor(COLOR_WINDOW));
}

int CandidateWindow::candidateRowsTop() const {
    return margin_ + (compositionCells_.empty() ? 0 : compositionStripHeight_ + rowSpacing_);
}

void CandidateWindow::itemRect(int i, RECT& rect) {
    int row, col;
    row = i / candPerRow_;
    col = i % candPerRow_;
    rect.left = margin_;
    int first = row * candPerRow_;
    for(int j = first; j < i; ++j) {
        rect.left += selKeyWidth_ + itemWidths_[j] + colSpacing_;
    }
    rect.top = candidateRowsTop() + row * (itemHeight_ + rowSpacing_);
    rect.right = rect.left + (selKeyWidth_ + itemWidths_[i]);
    rect.bottom = rect.top + itemHeight_;
}

void CandidateWindow::compositionSegmentRect(int i, RECT& rect) {
    rect.left = margin_ + compositionLabelWidth_;
    for(int j = 0; j < i; ++j)
        rect.left += compositionCellWidths_[j];
    rect.top = margin_;
    rect.right = rect.left + compositionCellWidths_[i];
    rect.bottom = rect.top + compositionStripHeight_;
}

int CandidateWindow::compositionSegmentFromPoint(POINTS pt) {
    for(int i = 0; i < static_cast<int>(compositionCells_.size()); ++i) {
        RECT rect;
        compositionSegmentRect(i, rect);
        if(pt.x >= rect.left && pt.x < rect.right && pt.y >= rect.top && pt.y < rect.bottom)
            return i;
    }
    return -1;
}

int CandidateWindow::itemFromPoint(POINTS pt) {
    for(int i = 0, n = items_.size(); i < n; ++i) {
        RECT rect;
        itemRect(i, rect);
        if(pt.x >= rect.left && pt.x < rect.right && pt.y >= rect.top && pt.y < rect.bottom) {
            return i;
        }
    }
    return -1;
}


} // namespace Ime
