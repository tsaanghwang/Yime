#pragma once

#include <msctf.h>

#include <atomic>
#include <string>
#include <vector>

#include "BrokerClient.h"

class CandidateListUIElement final : public ITfCandidateListUIElement {
public:
    CandidateListUIElement() noexcept = default;
    void Update(ITfDocumentMgr* document, const std::vector<yime::experiment::BrokerCandidate>& candidates);
    const std::vector<std::wstring>& DisplayCandidates() const noexcept { return candidates_; }

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;
    STDMETHODIMP GetDescription(BSTR* description) override;
    STDMETHODIMP GetGUID(GUID* guid) override;
    STDMETHODIMP Show(BOOL show) override;
    STDMETHODIMP IsShown(BOOL* show) override;
    STDMETHODIMP GetUpdatedFlags(DWORD* flags) override;
    STDMETHODIMP GetDocumentMgr(ITfDocumentMgr** document) override;
    STDMETHODIMP GetCount(UINT* count) override;
    STDMETHODIMP GetSelection(UINT* index) override;
    STDMETHODIMP GetString(UINT index, BSTR* text) override;
    STDMETHODIMP GetPageIndex(UINT* indices, UINT size, UINT* pageCount) override;
    STDMETHODIMP SetPageIndex(UINT* indices, UINT pageCount) override;
    STDMETHODIMP GetCurrentPage(UINT* page) override;

private:
    ~CandidateListUIElement();
    std::atomic<ULONG> references_{1};
    ITfDocumentMgr* document_ = nullptr;
    std::vector<std::wstring> candidates_;
    BOOL shown_ = FALSE;
};
