#include "TextService.h"

#include <iterator>
#include <new>

#include "CompositionEditSession.h"
#include "CandidateListUIElement.h"
#include "BrokerEndpoint.h"
#include "KeyContract.h"
#include "LanguageBarItem.h"
#include "ModuleState.h"

namespace {

HWND candidateOwnerAndFallbackAnchor(ITfContext* context, RECT* anchor) noexcept {
    if (!anchor) return nullptr;
    *anchor = {0, 0, 1, 20};
    HWND owner = nullptr;
    ITfContextView* view = nullptr;
    if (context && SUCCEEDED(context->GetActiveView(&view))) {
        view->GetWnd(&owner);
        view->Release();
    }
    if (owner) {
        GUITHREADINFO information{};
        information.cbSize = sizeof(information);
        const DWORD thread = GetWindowThreadProcessId(owner, nullptr);
        if (GetGUIThreadInfo(thread, &information) && information.hwndCaret) {
            *anchor = information.rcCaret;
            POINT topLeft{anchor->left, anchor->top};
            POINT bottomRight{anchor->right, anchor->bottom};
            ClientToScreen(information.hwndCaret, &topLeft);
            ClientToScreen(information.hwndCaret, &bottomRight);
            *anchor = {topLeft.x, topLeft.y, bottomRight.x, bottomRight.y};
            return owner;
        }
        POINT origin{8, 24};
        ClientToScreen(owner, &origin);
        *anchor = {origin.x, origin.y, origin.x + 1, origin.y + 20};
        return owner;
    }
    POINT cursor{};
    if (GetCursorPos(&cursor)) *anchor = {cursor.x, cursor.y, cursor.x + 1, cursor.y + 20};
    return nullptr;
}

}  // namespace

YimeTextService::YimeTextService() noexcept {
    YimeModuleAddRef();
    candidatePopup_.SetSelectionHandler(CandidatePopupSelection, this);
}

YimeTextService::~YimeTextService() {
    Deactivate();
    YimeModuleRelease();
}

STDMETHODIMP YimeTextService::QueryInterface(REFIID iid, void** object) {
    if (!object) return E_POINTER;
    *object = nullptr;
    if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, __uuidof(ITfTextInputProcessor)) ||
        IsEqualIID(iid, __uuidof(ITfTextInputProcessorEx))) {
        *object = static_cast<ITfTextInputProcessorEx*>(this);
    } else if (IsEqualIID(iid, __uuidof(ITfKeyEventSink))) {
        *object = static_cast<ITfKeyEventSink*>(this);
    } else if (IsEqualIID(iid, __uuidof(ITfCompositionSink))) {
        *object = static_cast<ITfCompositionSink*>(this);
    } else if (IsEqualIID(iid, __uuidof(ITfThreadMgrEventSink))) {
        *object = static_cast<ITfThreadMgrEventSink*>(this);
    } else {
        return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) YimeTextService::AddRef() { return ++references_; }

STDMETHODIMP_(ULONG) YimeTextService::Release() {
    const ULONG remaining = --references_;
    if (remaining == 0) delete this;
    return remaining;
}

STDMETHODIMP YimeTextService::Activate(ITfThreadMgr* threadManager, TfClientId clientId) {
    return ActivateEx(threadManager, clientId, 0);
}

STDMETHODIMP YimeTextService::ActivateEx(ITfThreadMgr* threadManager, TfClientId clientId, DWORD flags) {
    if (!threadManager || clientId == TF_CLIENTID_NULL) return E_INVALIDARG;
    if (threadManager_) return TF_E_ALREADY_EXISTS;
    threadManager_ = threadManager;
    threadManager_->AddRef();
    clientId_ = clientId;
    activationFlags_ = flags;
    keyEventFocused_ = true;
    HRESULT result = S_OK;
    const bool directTest = GetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST", nullptr, 0) > 0;
    if (!directTest) {
        ITfKeystrokeMgr* keystrokes = nullptr;
        result = threadManager_->QueryInterface(__uuidof(ITfKeystrokeMgr), reinterpret_cast<void**>(&keystrokes));
        if (SUCCEEDED(result)) {
            result = keystrokes->AdviseKeyEventSink(clientId_, this, TRUE);
            keySinkAdvised_ = SUCCEEDED(result);
            keystrokes->Release();
        }
    }
    if (FAILED(result)) {
        Deactivate();
        return result;
    }
    ITfSource* source = nullptr;
    if (SUCCEEDED(threadManager_->QueryInterface(__uuidof(ITfSource), reinterpret_cast<void**>(&source)))) {
        threadEventSinkAdvised_ = source->AdviseSink(
            __uuidof(ITfThreadMgrEventSink), static_cast<ITfThreadMgrEventSink*>(this),
            &threadEventSinkCookie_) == S_OK;
        source->Release();
    }
    AddLanguageBar();
    std::string ignoredError;
    surface_.Connect(yime::experiment::ResolveBrokerPipeName(), 2000, &ignoredError);
    return S_OK;
}

STDMETHODIMP YimeTextService::Deactivate() {
    if (!threadManager_) return S_OK;
    if (keySinkAdvised_) {
        ITfKeystrokeMgr* keystrokes = nullptr;
        if (SUCCEEDED(threadManager_->QueryInterface(__uuidof(ITfKeystrokeMgr), reinterpret_cast<void**>(&keystrokes)))) {
            keystrokes->UnadviseKeyEventSink(clientId_);
            keystrokes->Release();
        }
    }
    keySinkAdvised_ = false;
    if (threadEventSinkAdvised_) {
        ITfSource* source = nullptr;
        if (SUCCEEDED(threadManager_->QueryInterface(__uuidof(ITfSource), reinterpret_cast<void**>(&source)))) {
            source->UnadviseSink(threadEventSinkCookie_);
            source->Release();
        }
    }
    threadEventSinkAdvised_ = false;
    threadEventSinkCookie_ = TF_INVALID_COOKIE;
    RemoveLanguageBar();
    EndCandidateUI();
    surface_.Close();
    if (composition_) {
        composition_->Release();
        composition_ = nullptr;
    }
    ForgetCompositionContext();
    activationFlags_ = 0;
    clientId_ = TF_CLIENTID_NULL;
    keyEventFocused_ = false;
    compositionDocumentFocused_ = true;
    threadManager_->Release();
    threadManager_ = nullptr;
    return S_OK;
}

STDMETHODIMP YimeTextService::OnSetFocus(BOOL foreground) {
    keyEventFocused_ = foreground != FALSE;
    if (keyEventFocused_ && compositionDocument_ && threadManager_) {
        ITfDocumentMgr* focus = nullptr;
        compositionDocumentFocused_ = SUCCEEDED(threadManager_->GetFocus(&focus)) &&
                                      focus == compositionDocument_;
        if (focus) focus->Release();
    }
    ShowCandidateUI(CanAcceptKeys() && compositionDocumentFocused_);
    return S_OK;
}

STDMETHODIMP YimeTextService::OnInitDocumentMgr(ITfDocumentMgr*) { return S_OK; }

STDMETHODIMP YimeTextService::OnUninitDocumentMgr(ITfDocumentMgr* document) {
    if (document && document == compositionDocument_) {
        compositionDocumentFocused_ = false;
        ShowCandidateUI(false);
    }
    return S_OK;
}

STDMETHODIMP YimeTextService::OnSetFocus(ITfDocumentMgr* focus, ITfDocumentMgr*) {
    compositionDocumentFocused_ = !compositionDocument_ || focus == compositionDocument_;
    ShowCandidateUI(CanAcceptKeys() && compositionDocumentFocused_);
    return S_OK;
}

STDMETHODIMP YimeTextService::OnPushContext(ITfContext*) { return S_OK; }

STDMETHODIMP YimeTextService::OnPopContext(ITfContext*) { return S_OK; }

bool YimeTextService::CanAcceptKeys() const noexcept {
    return keyEventFocused_;
}

bool YimeTextService::ContextMatchesComposition(ITfContext* context) const noexcept {
    return !composition_ || !compositionContext_ || compositionContext_ == context;
}

HRESULT YimeTextService::SetKeyDecision(ITfContext* context, WPARAM virtualKey, BOOL* eaten) noexcept {
    if (!eaten) return E_POINTER;
    *eaten = FALSE;
    try {
        const bool shiftDown = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
        *eaten = context && CanAcceptKeys() && ContextMatchesComposition(context) &&
                         surface_.CanHandle(virtualKey, shiftDown) ? TRUE : FALSE;
    } catch (...) {
        surface_.DisconnectForRecovery();
    }
    return S_OK;
}

STDMETHODIMP YimeTextService::OnTestKeyDown(ITfContext* context, WPARAM wParam, LPARAM, BOOL* eaten) {
    return SetKeyDecision(context, wParam, eaten);
}

STDMETHODIMP YimeTextService::OnKeyDown(ITfContext* context, WPARAM wParam, LPARAM, BOOL* eaten) {
    if (!eaten) return E_POINTER;
    *eaten = FALSE;
    if (!context || !CanAcceptKeys() || !ContextMatchesComposition(context)) return S_OK;
    try {
        const bool shiftDown = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
        if (!surface_.CanHandle(wParam, shiftDown)) return S_OK;
        const auto outcome = surface_.HandleVirtualKey(wParam, shiftDown);
        if (!outcome.handled) return S_OK;
        RECT compositionRect{};
        bool compositionRectValid = false;
        const HRESULT edit = yime::experiment::ApplyBrokerUpdateToContext(
            context, clientId_, static_cast<ITfCompositionSink*>(this), &composition_,
            &plannedCompositionTermination_, outcome.update, &compositionRect, &compositionRectValid);
        if (FAILED(edit)) {
            surface_.DisconnectForRecovery();
            return S_OK;
        }
        if (composition_) RememberCompositionContext(context);
        UpdateCandidateUI(context, outcome.update, compositionRectValid ? &compositionRect : nullptr);
        *eaten = TRUE;
    } catch (...) {
        surface_.DisconnectForRecovery();
    }
    return S_OK;
}

STDMETHODIMP YimeTextService::OnTestKeyUp(ITfContext*, WPARAM, LPARAM, BOOL* eaten) {
    if (!eaten) return E_POINTER;
    *eaten = FALSE;
    return S_OK;
}

STDMETHODIMP YimeTextService::OnKeyUp(ITfContext*, WPARAM, LPARAM, BOOL* eaten) {
    if (!eaten) return E_POINTER;
    *eaten = FALSE;
    return S_OK;
}

STDMETHODIMP YimeTextService::OnPreservedKey(ITfContext*, REFGUID, BOOL* eaten) {
    if (!eaten) return E_POINTER;
    *eaten = FALSE;
    return S_OK;
}

STDMETHODIMP YimeTextService::OnCompositionTerminated(TfEditCookie, ITfComposition* composition) {
    if (composition_ == composition) {
        EndCandidateUI();
        composition_->Release();
        composition_ = nullptr;
        ForgetCompositionContext();
        if (!plannedCompositionTermination_) surface_.DisconnectForRecovery();
    }
    return S_OK;
}

void YimeTextService::RememberCompositionContext(ITfContext* context) noexcept {
    if (!context || compositionContext_) return;
    compositionContext_ = context;
    compositionContext_->AddRef();
    context->GetDocumentMgr(&compositionDocument_);
    if (threadManager_ && compositionDocument_) {
        ITfDocumentMgr* focus = nullptr;
        compositionDocumentFocused_ = SUCCEEDED(threadManager_->GetFocus(&focus)) &&
                                      focus == compositionDocument_;
        if (focus) focus->Release();
    }
}

void YimeTextService::ForgetCompositionContext() noexcept {
    if (compositionDocument_) {
        compositionDocument_->Release();
        compositionDocument_ = nullptr;
    }
    if (compositionContext_) {
        compositionContext_->Release();
        compositionContext_ = nullptr;
    }
    compositionDocumentFocused_ = true;
}

void YimeTextService::UpdateCandidateUI(ITfContext* context, const yime::experiment::BrokerUpdate& update,
                                        const RECT* compositionRect) noexcept {
    if (update.rawInput.empty()) {
        EndCandidateUI();
        return;
    }
    ITfDocumentMgr* document = nullptr;
    if (FAILED(context->GetDocumentMgr(&document))) return;
    if (!candidateUI_) candidateUI_ = new (std::nothrow) CandidateListUIElement();
    if (!candidateUI_) {
        document->Release();
        return;
    }
    if (update.candidates.empty()) {
        candidateUI_->UpdateEmpty(document, L"无匹配候选，按退格修改");
    } else {
        candidateUI_->Update(document, update.candidates, update.selectedCandidateIndex);
    }
    document->Release();
    RECT anchor{};
    HWND owner = candidateOwnerAndFallbackAnchor(context, &anchor);
    if (compositionRect) anchor = *compositionRect;
    ITfUIElementMgr* manager = nullptr;
    const bool hasManager = threadManager_ &&
        SUCCEEDED(threadManager_->QueryInterface(__uuidof(ITfUIElementMgr), reinterpret_cast<void**>(&manager)));
    if (!candidateUIRegistered_) {
        BOOL showOwned = TRUE;
        if (hasManager) {
            candidateUIRegistered_ = SUCCEEDED(manager->BeginUIElement(candidateUI_, &showOwned, &candidateUIId_));
        }
        ownedCandidatePopupRequested_ = !candidateUIRegistered_ || showOwned != FALSE;
        candidateUI_->Show(CanAcceptKeys() ? TRUE : FALSE);
    } else if (hasManager) {
        manager->UpdateUIElement(candidateUIId_);
    }
    if (manager) manager->Release();
    const size_t popupSelection = update.candidates.empty() ? static_cast<size_t>(-1)
                                                             : update.selectedCandidateIndex;
    if (ownedCandidatePopupRequested_ &&
        candidatePopup_.Update(candidateUI_->DisplayCandidates(), anchor, owner,
                               compositionRect != nullptr, popupSelection)) {
        candidatePopup_.Show(CanAcceptKeys());
    } else {
        candidatePopup_.Show(false);
    }
}

void YimeTextService::CandidatePopupSelection(void* context, unsigned ordinal) noexcept {
    if (context) static_cast<YimeTextService*>(context)->SelectCandidateFromPopup(ordinal);
}

void YimeTextService::SelectCandidateFromPopup(unsigned ordinal) noexcept {
    if (ordinal < 1 || ordinal > 9 || !compositionContext_ || !CanAcceptKeys()) return;
    ITfContext* context = compositionContext_;
    context->AddRef();
    const auto outcome = surface_.HandleVirtualKey(static_cast<WPARAM>('0' + ordinal), true);
    if (!outcome.handled) {
        context->Release();
        return;
    }
    RECT compositionRect{};
    bool compositionRectValid = false;
    const HRESULT edit = yime::experiment::ApplyBrokerUpdateToContext(
        context, clientId_, static_cast<ITfCompositionSink*>(this), &composition_,
        &plannedCompositionTermination_, outcome.update, &compositionRect, &compositionRectValid);
    if (FAILED(edit)) {
        surface_.DisconnectForRecovery();
        context->Release();
        return;
    }
    UpdateCandidateUI(context, outcome.update,
                      compositionRectValid ? &compositionRect : nullptr);
    context->Release();
}

void YimeTextService::EndCandidateUI() noexcept {
    if (candidateUIRegistered_ && threadManager_) {
        ITfUIElementMgr* manager = nullptr;
        if (SUCCEEDED(threadManager_->QueryInterface(__uuidof(ITfUIElementMgr), reinterpret_cast<void**>(&manager)))) {
            manager->EndUIElement(candidateUIId_);
            manager->Release();
        }
    }
    candidateUIRegistered_ = false;
    candidateUIId_ = 0;
    ownedCandidatePopupRequested_ = false;
    candidatePopup_.Destroy();
    if (candidateUI_) {
        candidateUI_->Show(FALSE);
        candidateUI_->Release();
        candidateUI_ = nullptr;
    }
}

void YimeTextService::ShowCandidateUI(bool show) noexcept {
    if (!candidateUI_) return;
    candidateUI_->Show(show ? TRUE : FALSE);
    candidatePopup_.Show(show && ownedCandidatePopupRequested_);
    if (!candidateUIRegistered_ || !threadManager_) return;
    ITfUIElementMgr* manager = nullptr;
    if (SUCCEEDED(threadManager_->QueryInterface(__uuidof(ITfUIElementMgr), reinterpret_cast<void**>(&manager)))) {
        manager->UpdateUIElement(candidateUIId_);
        manager->Release();
    }
}

void YimeTextService::AddLanguageBar() noexcept {
    if (languageBarItem_ || !threadManager_) return;
    languageBarItem_ = new (std::nothrow) LanguageBarItem();
    if (!languageBarItem_) return;
    ITfLangBarItemMgr* manager = nullptr;
    if (SUCCEEDED(threadManager_->QueryInterface(__uuidof(ITfLangBarItemMgr), reinterpret_cast<void**>(&manager)))) {
        languageBarItemAdded_ = manager->AddItem(languageBarItem_) == S_OK;
        manager->Release();
    }
}

void YimeTextService::RemoveLanguageBar() noexcept {
    if (!languageBarItem_) return;
    if (languageBarItemAdded_ && threadManager_) {
        ITfLangBarItemMgr* manager = nullptr;
        if (SUCCEEDED(threadManager_->QueryInterface(__uuidof(ITfLangBarItemMgr), reinterpret_cast<void**>(&manager)))) {
            manager->RemoveItem(languageBarItem_);
            manager->Release();
        }
    }
    languageBarItemAdded_ = false;
    languageBarItem_->Release();
    languageBarItem_ = nullptr;
}
