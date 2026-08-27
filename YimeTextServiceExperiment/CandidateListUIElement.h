#pragma once

#include <msctf.h>

#include <atomic>
#include <string>
#include <vector>

#include "BrokerClient.h"

class CandidateListUIElement final : public ITfCandidateListUIElement {
public:
    CandidateListUIElement() noexcept = default;
    void Update(ITfDocumentMgr* document, const std::vector<yime::experiment::BrokerCandidate>& candidates,
                size_t selectedIndex = 0, const std::string& annotationMode = "key_sequence",
                const yime::experiment::BrokerCandidate* sentence = nullptr);
    void UpdateEmpty(ITfDocumentMgr* document, std::wstring message);
    const std::vector<std::wstring>& DisplayCandidates() const noexcept { return candidates_; }
    const std::vector<std::wstring>& PopupCandidateRows() const noexcept { return popupCandidateRows_; }
    const std::wstring& SentenceDisplay() const noexcept { return sentenceDisplay_; }
	const std::wstring& StatusDisplay() const noexcept { return statusDisplay_; }

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
    std::vector<std::wstring> popupCandidateRows_;
    std::wstring sentenceDisplay_;
	std::wstring statusDisplay_;
    UINT selection_ = 0;
    bool selectable_ = false;
    BOOL shown_ = FALSE;
};
