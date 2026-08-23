#include "LanguageBarItem.h"

#include <cwchar>

#include "YimeTextServiceIds.h"

namespace {

constexpr wchar_t kDescription[] = L"Yime 自研栈试验版";

BSTR copyText(const wchar_t* text) {
    return SysAllocString(text);
}

}  // namespace

STDMETHODIMP LanguageBarItem::QueryInterface(REFIID iid, void** object) {
    if (!object) return E_POINTER;
    *object = nullptr;
    if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, __uuidof(ITfLangBarItem)) &&
        !IsEqualIID(iid, __uuidof(ITfLangBarItemButton))) return E_NOINTERFACE;
    *object = static_cast<ITfLangBarItemButton*>(this);
    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) LanguageBarItem::AddRef() { return ++references_; }

STDMETHODIMP_(ULONG) LanguageBarItem::Release() {
    const ULONG remaining = --references_;
    if (!remaining) delete this;
    return remaining;
}

STDMETHODIMP LanguageBarItem::GetInfo(TF_LANGBARITEMINFO* info) {
    if (!info) return E_POINTER;
    *info = {};
    info->clsidService = CLSID_YimeTextServiceExperiment;
    info->guidItem = GUID_YimeTextServiceExperimentLangBar;
    info->dwStyle = TF_LBI_STYLE_BTN_BUTTON;
    info->ulSort = 0;
    wcsncpy_s(info->szDescription, kDescription, _TRUNCATE);
    return S_OK;
}

STDMETHODIMP LanguageBarItem::GetStatus(DWORD* status) {
    if (!status) return E_POINTER;
    *status = status_;
    return S_OK;
}

STDMETHODIMP LanguageBarItem::Show(BOOL show) {
    if (show) {
        status_ &= ~TF_LBI_STATUS_HIDDEN;
    } else {
        status_ |= TF_LBI_STATUS_HIDDEN;
    }
    return S_OK;
}

STDMETHODIMP LanguageBarItem::GetTooltipString(BSTR* tooltip) {
    if (!tooltip) return E_POINTER;
    *tooltip = copyText(kDescription);
    return *tooltip ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP LanguageBarItem::OnClick(TfLBIClick, POINT, const RECT*) { return S_OK; }

STDMETHODIMP LanguageBarItem::InitMenu(ITfMenu*) { return E_NOTIMPL; }

STDMETHODIMP LanguageBarItem::OnMenuSelect(UINT) { return E_INVALIDARG; }

STDMETHODIMP LanguageBarItem::GetIcon(HICON* icon) {
    if (!icon) return E_POINTER;
    *icon = nullptr;
    return E_NOTIMPL;
}

STDMETHODIMP LanguageBarItem::GetText(BSTR* text) {
    if (!text) return E_POINTER;
    *text = copyText(kDescription);
    return *text ? S_OK : E_OUTOFMEMORY;
}
