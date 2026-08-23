#pragma once

#include <msctf.h>

#include <atomic>

#include "CandidatePopup.h"
#include "SurfaceSession.h"

class CandidateListUIElement;
class LanguageBarItem;

class YimeTextService final : public ITfTextInputProcessorEx,
                              public ITfKeyEventSink,
                              public ITfCompositionSink {
public:
    YimeTextService() noexcept;

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    STDMETHODIMP Activate(ITfThreadMgr* threadManager, TfClientId clientId) override;
    STDMETHODIMP Deactivate() override;
    STDMETHODIMP ActivateEx(ITfThreadMgr* threadManager, TfClientId clientId, DWORD flags) override;

    STDMETHODIMP OnSetFocus(BOOL foreground) override;
    STDMETHODIMP OnTestKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
    STDMETHODIMP OnKeyDown(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
    STDMETHODIMP OnTestKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
    STDMETHODIMP OnKeyUp(ITfContext* context, WPARAM wParam, LPARAM lParam, BOOL* eaten) override;
    STDMETHODIMP OnPreservedKey(ITfContext* context, REFGUID guid, BOOL* eaten) override;
    STDMETHODIMP OnCompositionTerminated(TfEditCookie cookie, ITfComposition* composition) override;

private:
    ~YimeTextService();
    HRESULT SetKeyDecision(ITfContext* context, WPARAM virtualKey, BOOL* eaten) const noexcept;
    void UpdateCandidateUI(ITfContext* context, const yime::experiment::BrokerUpdate& update,
                           const RECT* compositionRect) noexcept;
    void EndCandidateUI() noexcept;
    void AddLanguageBar() noexcept;
    void RemoveLanguageBar() noexcept;
    void ShowCandidateUI(bool show) noexcept;
    bool CanAcceptKeys() const noexcept;
    bool ContextMatchesComposition(ITfContext* context) const noexcept;
    void RememberCompositionContext(ITfContext* context) noexcept;
    void ForgetCompositionContext() noexcept;
    void SelectCandidateFromPopup(unsigned ordinal) noexcept;
    static void CandidatePopupSelection(void* context, unsigned ordinal) noexcept;

    std::atomic<ULONG> references_{1};
    ITfThreadMgr* threadManager_ = nullptr;
    TfClientId clientId_ = TF_CLIENTID_NULL;
    DWORD activationFlags_ = 0;
    bool keySinkAdvised_ = false;
    bool keyEventFocused_ = true;
    yime::experiment::SurfaceSession surface_;
    ITfComposition* composition_ = nullptr;
    ITfContext* compositionContext_ = nullptr;
    ITfDocumentMgr* compositionDocument_ = nullptr;
    bool plannedCompositionTermination_ = false;
    CandidateListUIElement* candidateUI_ = nullptr;
    CandidatePopup candidatePopup_;
    DWORD candidateUIId_ = 0;
    bool candidateUIRegistered_ = false;
    bool ownedCandidatePopupRequested_ = false;
    LanguageBarItem* languageBarItem_ = nullptr;
    bool languageBarItemAdded_ = false;
};
