#pragma once

#include <msctf.h>

#include <atomic>

#include "CandidatePopup.h"
#include "ExperimentSettings.h"
#include "PunctuationPalette.h"
#include "SurfaceSession.h"

class CandidateListUIElement;
class LanguageBarItem;

class YimeTextService final : public ITfTextInputProcessorEx,
                              public ITfKeyEventSink,
                              public ITfCompositionSink,
                              public ITfThreadMgrEventSink {
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

    STDMETHODIMP OnInitDocumentMgr(ITfDocumentMgr* document) override;
    STDMETHODIMP OnUninitDocumentMgr(ITfDocumentMgr* document) override;
    STDMETHODIMP OnSetFocus(ITfDocumentMgr* focus, ITfDocumentMgr* previous) override;
    STDMETHODIMP OnPushContext(ITfContext* context) override;
    STDMETHODIMP OnPopContext(ITfContext* context) override;

private:
    ~YimeTextService();
    HRESULT SetKeyDecision(ITfContext* context, WPARAM virtualKey, BOOL* eaten) noexcept;
    void UpdateCandidateUI(ITfContext* context, const yime::experiment::BrokerUpdate& update,
                           const RECT* compositionRect) noexcept;
    void UpdatePunctuationUI(ITfContext* context) noexcept;
    bool OpenPunctuationPalette(ITfContext* context) noexcept;
    void CancelPunctuationPalette(bool restoreCompositionUI = true) noexcept;
    bool CommitPunctuation(ITfContext* context, const std::string& punctuation,
                           bool asynchronous = false) noexcept;
    void EndCandidateUI() noexcept;
    void AddLanguageBar() noexcept;
    void RemoveLanguageBar() noexcept;
    void ShowCandidateUI(bool show) noexcept;
    bool CanAcceptKeys() const noexcept;
    bool ShouldHandleCompositionKeys() noexcept;
    bool ContextMatchesComposition(ITfContext* context) const noexcept;
    void RememberCompositionContext(ITfContext* context) noexcept;
    void ForgetCompositionContext() noexcept;
    void SelectCandidateFromPopup(unsigned ordinal) noexcept;
    void ForgetCandidateFromPopup(unsigned ordinal) noexcept;
    void SelectSentenceFromPopup() noexcept;
    void FocusSentenceSegmentFromPopup(int start, int end) noexcept;
    void ExpandSentenceSegmentFromPopup(int start, int end) noexcept;
    static void CandidatePopupSelection(void* context, unsigned ordinal) noexcept;
    static void CandidatePopupForget(void* context, unsigned ordinal) noexcept;
    static void CandidatePopupSentenceSelection(void* context) noexcept;
    static void CandidatePopupSegmentSelection(void* context, int start, int end) noexcept;
    static void CandidatePopupSegmentExpansion(void* context, int start, int end) noexcept;
    static void LiveSettingsChanged(
        void* context, const yime::experiment::ExperimentSettings& settings) noexcept;
    void RefreshLiveSettings(
        const yime::experiment::ExperimentSettings& settings) noexcept;

    std::atomic<ULONG> references_{1};
    ITfThreadMgr* threadManager_ = nullptr;
    TfClientId clientId_ = TF_CLIENTID_NULL;
    DWORD activationFlags_ = 0;
    bool keySinkAdvised_ = false;
    bool threadEventSinkAdvised_ = false;
    DWORD threadEventSinkCookie_ = TF_INVALID_COOKIE;
    bool keyEventFocused_ = true;
    bool compositionDocumentFocused_ = true;
    yime::experiment::SurfaceSession surface_;
    yime::experiment::PunctuationPalette punctuationPalette_;
    ITfContext* punctuationContext_ = nullptr;
    ITfComposition* composition_ = nullptr;
    ITfContext* compositionContext_ = nullptr;
    ITfDocumentMgr* compositionDocument_ = nullptr;
    bool plannedCompositionTermination_ = false;
    CandidateListUIElement* candidateUI_ = nullptr;
    CandidatePopup candidatePopup_;
    yime::experiment::ExperimentSettingsCache experimentSettings_;
    DWORD candidateUIId_ = 0;
    bool candidateUIRegistered_ = false;
    bool ownedCandidatePopupRequested_ = false;
    LanguageBarItem* languageBarItem_ = nullptr;
    bool languageBarItemAdded_ = false;
    yime::experiment::ShiftTapTracker shiftTap_;
};
