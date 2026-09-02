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
                                    size_t selectedIndex, const std::string& annotationMode,
                                    const yime::experiment::BrokerCandidate* sentence) {
    if (document != document_) {
        if (document_) document_->Release();
        document_ = document;
        if (document_) document_->AddRef();
    }
    candidates_.clear();
    popupCandidateRows_.clear();
    sentenceDisplay_.clear();
	statusDisplay_.clear();
    description_ = YIME_PRODUCT_NAME L"候选";
    const auto& labels = yime::experiment::CandidateLabels();
    const bool hasSentence = sentence && !sentence->id.empty();
    const size_t available = candidates.size();
    const size_t count = std::min(available, labels.size());
    selectable_ = count != 0;
    if (hasSentence) sentenceDisplay_ = L"句: " + widen(sentence->text);
    const size_t visibleSelection = selectedIndex;
    selection_ = count == 0 ? 0u : static_cast<UINT>(std::min(visibleSelection, count - 1));
    candidates_.reserve(count);
    popupCandidateRows_.reserve(count);
    for (size_t index = 0; index < count; ++index) {
        const auto& candidate = candidates[index];
        std::string annotation;
        if (annotationMode == "yinyuan") {
            annotation = candidate.yinyuan;
        } else if (annotationMode == "standard_pinyin") {
            annotation = candidate.standardPinyin;
        } else if (annotationMode == "key_sequence") {
            annotation = candidate.code;
        }
        std::wstring display = std::wstring(labels[index]) + L"  " + widen(candidate.text);
        if (!annotation.empty()) display += L"  " + widen(annotation);
        popupCandidateRows_.push_back(display);
        candidates_.push_back(std::move(display));
    }
}

void CandidateListUIElement::UpdateEmpty(ITfDocumentMgr* document, std::wstring message) {
    if (document != document_) {
        if (document_) document_->Release();
        document_ = document;
        if (document_) document_->AddRef();
    }
    candidates_.clear();
    popupCandidateRows_.clear();
    sentenceDisplay_.clear();
	statusDisplay_ = std::move(message);
    description_ = YIME_PRODUCT_NAME L"候选";
    selection_ = 0;
    selectable_ = false;
}

void CandidateListUIElement::UpdatePalette(
    ITfDocumentMgr* document,
    const std::vector<yime::experiment::BrokerCandidate>& candidates,
    size_t selectedIndex, std::wstring status, std::wstring description) {
    Update(document, candidates, selectedIndex, "hidden", nullptr);
    statusDisplay_ = std::move(status);
    description_ = std::move(description);
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
STDMETHODIMP CandidateListUIElement::GetDescription(BSTR* description) { if (!description) return E_POINTER; *description = SysAllocString(description_.c_str()); return *description ? S_OK : E_OUTOFMEMORY; }
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
