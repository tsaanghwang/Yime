#include "TextService.h"

#include <iterator>
#include <new>

#include "CompositionEditSession.h"
#include "CandidateListUIElement.h"
#include "KeyContract.h"
#include "ModuleState.h"

YimeTextService::YimeTextService() noexcept { YimeModuleAddRef(); }

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
    const bool directTest = GetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST", nullptr, 0) > 0;
    HRESULT result = S_OK;
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
    wchar_t pipeName[256]{};
    const DWORD pipeLength = GetEnvironmentVariableW(
        L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", pipeName, static_cast<DWORD>(std::size(pipeName)));
    if (pipeLength > 0 && pipeLength < std::size(pipeName)) {
        std::string ignoredError;
        surface_.Connect(pipeName, 2000, &ignoredError);
    }
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
    EndCandidateUI();
    surface_.Close();
    if (composition_) {
        composition_->Release();
        composition_ = nullptr;
    }
    activationFlags_ = 0;
    clientId_ = TF_CLIENTID_NULL;
    threadManager_->Release();
    threadManager_ = nullptr;
    return S_OK;
}

STDMETHODIMP YimeTextService::OnSetFocus(BOOL) { return S_OK; }

HRESULT YimeTextService::SetKeyDecision(ITfContext* context, WPARAM virtualKey, BOOL* eaten) const noexcept {
    if (!eaten) return E_POINTER;
    const bool shiftDown = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
    *eaten = context && surface_.CanHandle(virtualKey, shiftDown) ? TRUE : FALSE;
    return S_OK;
}

STDMETHODIMP YimeTextService::OnTestKeyDown(ITfContext* context, WPARAM wParam, LPARAM, BOOL* eaten) {
    return SetKeyDecision(context, wParam, eaten);
}

STDMETHODIMP YimeTextService::OnKeyDown(ITfContext* context, WPARAM wParam, LPARAM, BOOL* eaten) {
    if (!eaten) return E_POINTER;
    *eaten = FALSE;
    if (!context) return S_OK;
    const bool shiftDown = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
    if (!surface_.CanHandle(wParam, shiftDown)) return S_OK;
    const auto outcome = surface_.HandleVirtualKey(wParam, shiftDown);
    if (!outcome.handled) return S_OK;
    const HRESULT edit = yime::experiment::ApplyBrokerUpdateToContext(
        context, clientId_, static_cast<ITfCompositionSink*>(this), &composition_,
        &plannedCompositionTermination_, outcome.update);
    if (FAILED(edit)) {
        surface_.Close();
        return S_OK;
    }
    UpdateCandidateUI(context, outcome.update);
    *eaten = TRUE;
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
        if (!plannedCompositionTermination_) surface_.Close();
    }
    return S_OK;
}

void YimeTextService::UpdateCandidateUI(ITfContext* context, const yime::experiment::BrokerUpdate& update) noexcept {
    if (update.rawInput.empty() || update.candidates.empty()) {
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
    candidateUI_->Update(document, update.candidates);
    document->Release();
    ITfUIElementMgr* manager = nullptr;
    if (FAILED(threadManager_->QueryInterface(__uuidof(ITfUIElementMgr), reinterpret_cast<void**>(&manager)))) return;
    if (!candidateUIRegistered_) {
        BOOL showOwned = TRUE;
        candidateUIRegistered_ = SUCCEEDED(manager->BeginUIElement(candidateUI_, &showOwned, &candidateUIId_));
        if (candidateUIRegistered_) candidateUI_->Show(showOwned);
    } else {
        manager->UpdateUIElement(candidateUIId_);
    }
    manager->Release();
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
    if (candidateUI_) {
        candidateUI_->Show(FALSE);
        candidateUI_->Release();
        candidateUI_ = nullptr;
    }
}
