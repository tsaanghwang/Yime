#include "TextService.h"

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
    ITfKeystrokeMgr* keystrokes = nullptr;
    HRESULT result = threadManager_->QueryInterface(__uuidof(ITfKeystrokeMgr), reinterpret_cast<void**>(&keystrokes));
    if (SUCCEEDED(result)) {
        result = keystrokes->AdviseKeyEventSink(clientId_, this, TRUE);
        keySinkAdvised_ = SUCCEEDED(result);
        keystrokes->Release();
    }
    if (FAILED(result)) {
        Deactivate();
        return result;
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
    activationFlags_ = 0;
    clientId_ = TF_CLIENTID_NULL;
    threadManager_->Release();
    threadManager_ = nullptr;
    return S_OK;
}

STDMETHODIMP YimeTextService::OnSetFocus(BOOL) { return S_OK; }

HRESULT YimeTextService::SetKeyDecision(WPARAM virtualKey, BOOL* eaten) const noexcept {
    if (!eaten) return E_POINTER;
    // B1 proves routing only. B2 will set TRUE after a Broker operation and TSF
    // edit session have both succeeded, so this inert shell cannot swallow keys.
    const bool shiftDown = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
    const auto decision = yime::experiment::ClassifyVirtualKey(virtualKey, shiftDown);
    (void)decision;
    *eaten = FALSE;
    return S_OK;
}

STDMETHODIMP YimeTextService::OnTestKeyDown(ITfContext*, WPARAM wParam, LPARAM, BOOL* eaten) {
    return SetKeyDecision(wParam, eaten);
}

STDMETHODIMP YimeTextService::OnKeyDown(ITfContext*, WPARAM wParam, LPARAM, BOOL* eaten) {
    return SetKeyDecision(wParam, eaten);
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
