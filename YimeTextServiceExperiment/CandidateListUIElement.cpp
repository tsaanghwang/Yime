#include "CandidateListUIElement.h"

#include <algorithm>
#include <utility>

#include "KeyContract.h"
#include "YimeTextServiceIds.h"

namespace {

std::wstring widen(const std::string& value) {
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                           static_cast<int>(value.size()), nullptr, 0);
    if (length <= 0) return {};
    std::wstring result(static_cast<size_t>(length), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
                            result.data(), length) != length) return {};
    return result;
}

}  // namespace

CandidateListUIElement::~CandidateListUIElement() {
    if (document_) document_->Release();
}

void CandidateListUIElement::Update(ITfDocumentMgr* document,
                                    const std::vector<yime::experiment::BrokerCandidate>& candidates,
                                    size_t selectedIndex) {
    if (document != document_) {
        if (document_) document_->Release();
        document_ = document;
        if (document_) document_->AddRef();
    }
    candidates_.clear();
    const auto& labels = yime::experiment::CandidateLabels();
    const size_t count = std::min(candidates.size(), labels.size());
    selectable_ = count != 0;
    selection_ = count == 0 ? 0u : static_cast<UINT>(std::min(selectedIndex, count - 1));
    candidates_.reserve(count);
    for (size_t index = 0; index < count; ++index) {
        candidates_.push_back(std::wstring(labels[index]) + L"  " + widen(candidates[index].text));
    }
}

void CandidateListUIElement::UpdateEmpty(ITfDocumentMgr* document, std::wstring message) {
    if (document != document_) {
        if (document_) document_->Release();
        document_ = document;
        if (document_) document_->AddRef();
    }
    candidates_.clear();
    candidates_.push_back(std::move(message));
    selection_ = 0;
    selectable_ = false;
}

STDMETHODIMP CandidateListUIElement::QueryInterface(REFIID iid, void** object) {
    if (!object) return E_POINTER;
    *object = nullptr;
    if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, __uuidof(ITfUIElement)) &&
        !IsEqualIID(iid, __uuidof(ITfCandidateListUIElement))) return E_NOINTERFACE;
    *object = static_cast<ITfCandidateListUIElement*>(this);
    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) CandidateListUIElement::AddRef() { return ++references_; }
STDMETHODIMP_(ULONG) CandidateListUIElement::Release() { const ULONG left = --references_; if (!left) delete this; return left; }
STDMETHODIMP CandidateListUIElement::GetDescription(BSTR* description) { if (!description) return E_POINTER; *description = SysAllocString(L"Yime 自研栈试验版候选"); return *description ? S_OK : E_OUTOFMEMORY; }
STDMETHODIMP CandidateListUIElement::GetGUID(GUID* guid) { if (!guid) return E_POINTER; *guid = GUID_YimeTextServiceExperimentCandidateList; return S_OK; }
STDMETHODIMP CandidateListUIElement::Show(BOOL show) { shown_ = show; return S_OK; }
STDMETHODIMP CandidateListUIElement::IsShown(BOOL* show) { if (!show) return E_POINTER; *show = shown_; return S_OK; }
STDMETHODIMP CandidateListUIElement::GetUpdatedFlags(DWORD* flags) { if (!flags) return E_POINTER; *flags = TF_CLUIE_DOCUMENTMGR | TF_CLUIE_COUNT | TF_CLUIE_SELECTION | TF_CLUIE_STRING | TF_CLUIE_PAGEINDEX | TF_CLUIE_CURRENTPAGE; return S_OK; }
STDMETHODIMP CandidateListUIElement::GetDocumentMgr(ITfDocumentMgr** document) { if (!document) return E_POINTER; *document = document_; if (!document_) return E_FAIL; document_->AddRef(); return S_OK; }
STDMETHODIMP CandidateListUIElement::GetCount(UINT* count) { if (!count) return E_POINTER; *count = static_cast<UINT>(candidates_.size()); return S_OK; }
STDMETHODIMP CandidateListUIElement::GetSelection(UINT* index) { if (!index) return E_POINTER; *index = selection_; return selectable_ ? S_OK : E_FAIL; }
STDMETHODIMP CandidateListUIElement::GetString(UINT index, BSTR* text) { if (!text) return E_POINTER; *text = nullptr; if (index >= candidates_.size()) return E_INVALIDARG; *text = SysAllocString(candidates_[index].c_str()); return *text ? S_OK : E_OUTOFMEMORY; }
STDMETHODIMP CandidateListUIElement::GetPageIndex(UINT* indices, UINT size, UINT* pageCount) { if (!pageCount) return E_POINTER; *pageCount = candidates_.empty() ? 0u : 1u; if (*pageCount && (!indices || size < 1)) return E_INVALIDARG; if (*pageCount) indices[0] = 0; return S_OK; }
STDMETHODIMP CandidateListUIElement::SetPageIndex(UINT* indices, UINT pageCount) { if (pageCount != 1 || !indices || indices[0] != 0) return E_INVALIDARG; return S_OK; }
STDMETHODIMP CandidateListUIElement::GetCurrentPage(UINT* page) { if (!page) return E_POINTER; *page = 0; return candidates_.empty() ? E_FAIL : S_OK; }
