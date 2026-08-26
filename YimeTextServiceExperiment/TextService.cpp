#include "TextService.h"

#include <cstdio>
#include <filesystem>
#include <iterator>
#include <new>
#include <utility>

#include "CompositionEditSession.h"
#include "CandidateListUIElement.h"
#include "BrokerEndpoint.h"
#include "ExperimentSettings.h"
#include "KeyContract.h"
#include "LanguageBarItem.h"
#include "ModuleState.h"
#include "OutputTransform.h"
#include "YimeTextServiceIds.h"

namespace {

bool IsSelectionDiagnosticKey(WPARAM key) noexcept {
    return key == VK_RETURN || key == VK_SPACE || key == VK_UP || key == VK_DOWN ||
           (key >= '1' && key <= '9');
}

void RecordSelectionKeyHostResult(const char* stage, WPARAM key, bool shiftDown,
                                  bool controlDown, bool altDown, bool keyFocused,
                                  bool asciiMode, bool hasComposition, bool contextMatches,
                                  bool canHandle, bool handled, HRESULT editResult,
                                  std::string errorText = {}) noexcept {
    if (!stage || !IsSelectionDiagnosticKey(key)) return;
    for (char& character : errorText) {
        if (character == '\r' || character == '\n' || character == '|') character = '_';
    }
    wchar_t localAppData[MAX_PATH]{};
    const DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData,
                                                  static_cast<DWORD>(std::size(localAppData)));
    if (!length || length >= std::size(localAppData)) return;
    std::error_code directoryError;
    const std::filesystem::path evidence = std::filesystem::path(localAppData) /
        L"YimeCore Experimental Trial" / L"evidence";
    std::filesystem::create_directories(evidence, directoryError);
    if (directoryError) return;
    HANDLE file = CreateFileW((evidence / L"tsf-key-host.log").c_str(), FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    SYSTEMTIME now{};
    GetSystemTime(&now);
    char line[1024]{};
    const int bytes = std::snprintf(
        line, std::size(line),
        "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ|pid=%lu|tid=%lu|stage=%s|vk=%llu|shift=%d|ctrl=%d|alt=%d|focus=%d|ascii=%d|composition=%d|context=%d|can_handle=%d|handled=%d|edit=0x%08lX|error=%s\r\n",
        now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
        now.wMilliseconds, static_cast<unsigned long>(GetCurrentProcessId()),
        static_cast<unsigned long>(GetCurrentThreadId()), stage,
        static_cast<unsigned long long>(key), shiftDown ? 1 : 0, controlDown ? 1 : 0,
        altDown ? 1 : 0, keyFocused ? 1 : 0, asciiMode ? 1 : 0,
        hasComposition ? 1 : 0, contextMatches ? 1 : 0, canHandle ? 1 : 0,
        handled ? 1 : 0, static_cast<unsigned long>(editResult), errorText.c_str());
    if (bytes > 0 && static_cast<size_t>(bytes) < std::size(line)) {
        DWORD written = 0;
        WriteFile(file, line, static_cast<DWORD>(bytes), &written, nullptr);
    }
    CloseHandle(file);
}

void RecordLanguageBarHostResult(HRESULT managerResult, HRESULT addResult,
                                 HRESULT statusResult, DWORD managerStatus) noexcept {
    wchar_t localAppData[MAX_PATH]{};
    const DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData,
                                                  static_cast<DWORD>(std::size(localAppData)));
    if (!length || length >= std::size(localAppData)) return;
    std::error_code error;
    const std::filesystem::path evidence = std::filesystem::path(localAppData) /
        L"YimeCore Experimental Trial" / L"evidence";
    std::filesystem::create_directories(evidence, error);
    if (error) return;
    HANDLE file = CreateFileW((evidence / L"language-bar-host.log").c_str(), FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    char line[256]{};
    const int bytes = std::snprintf(
        line, std::size(line),
        "pid=%lu architecture_bits=%zu manager_hresult=0x%08lX add_hresult=0x%08lX status_hresult=0x%08lX manager_status=0x%08lX\r\n",
        GetCurrentProcessId(), sizeof(void*) * 8,
        static_cast<unsigned long>(managerResult), static_cast<unsigned long>(addResult),
        static_cast<unsigned long>(statusResult), static_cast<unsigned long>(managerStatus));
    if (bytes > 0) {
        DWORD written = 0;
        WriteFile(file, line, static_cast<DWORD>(bytes), &written, nullptr);
    }
    CloseHandle(file);
}

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
    candidatePopup_.SetSegmentHandler(CandidatePopupSegmentSelection, this);
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

bool YimeTextService::ShouldHandleCompositionKeys() noexcept {
    if (languageBarItem_) languageBarItem_->Refresh();
    // A state change never migrates or abandons a live composition. English
    // pass-through begins as soon as that composition reaches its idle state.
    return CanAcceptKeys() && (!experimentSettings_.Get().asciiMode || composition_ != nullptr);
}

bool YimeTextService::ContextMatchesComposition(ITfContext* context) const noexcept {
    return !composition_ || !compositionContext_ || compositionContext_ == context;
}

HRESULT YimeTextService::SetKeyDecision(ITfContext* context, WPARAM virtualKey, BOOL* eaten) noexcept {
    if (!eaten) return E_POINTER;
    *eaten = FALSE;
    try {
        if (virtualKey == VK_SHIFT || virtualKey == VK_LSHIFT || virtualKey == VK_RSHIFT) {
            *eaten = context && CanAcceptKeys() ? TRUE : FALSE;
            return S_OK;
        }
        const bool shiftDown = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
        const bool controlDown = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        const bool altDown = (GetKeyState(VK_MENU) & 0x8000) != 0;
        std::string directCommit;
        if (!controlDown && !altDown && !composition_ &&
            yime::experiment::TryDirectOutputKey(virtualKey, shiftDown,
                                                  experimentSettings_.Get(), &directCommit)) {
            *eaten = context && CanAcceptKeys() ? TRUE : FALSE;
            return S_OK;
        }
        const bool modeAllows = ShouldHandleCompositionKeys();
        const bool contextMatches = ContextMatchesComposition(context);
        const bool canHandle = modeAllows && contextMatches &&
            surface_.CanHandle(virtualKey, shiftDown, controlDown, altDown);
        *eaten = context && canHandle ? TRUE : FALSE;
        RecordSelectionKeyHostResult(
            "test", virtualKey, shiftDown, controlDown, altDown, CanAcceptKeys(),
            experimentSettings_.Get().asciiMode, composition_ != nullptr, contextMatches,
            canHandle, *eaten == TRUE, S_OK);
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
    if (wParam == VK_SHIFT || wParam == VK_LSHIFT || wParam == VK_RSHIFT) {
        if (context && CanAcceptKeys()) {
            shiftTap_.OnKeyDown(wParam);
            *eaten = TRUE;
        }
        return S_OK;
    }
    shiftTap_.OnKeyDown(wParam);
    if (!context || !CanAcceptKeys()) {
        RecordSelectionKeyHostResult("down-no-focus", wParam, false, false, false,
                                     CanAcceptKeys(), experimentSettings_.Get().asciiMode,
                                     composition_ != nullptr, false, false, false, S_OK);
        return S_OK;
    }
    try {
        const bool shiftDown = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
        const bool controlDown = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
        const bool altDown = (GetKeyState(VK_MENU) & 0x8000) != 0;
        std::string directCommit;
        if (!controlDown && !altDown && !composition_ &&
            yime::experiment::TryDirectOutputKey(wParam, shiftDown,
                                                  experimentSettings_.Get(), &directCommit)) {
            yime::experiment::BrokerUpdate direct;
            direct.commit = std::move(directCommit);
            const HRESULT edit = yime::experiment::ApplyBrokerUpdateToContext(
                context, clientId_, static_cast<ITfCompositionSink*>(this), &composition_,
                &plannedCompositionTermination_, direct, nullptr, nullptr);
            if (SUCCEEDED(edit)) *eaten = TRUE;
            return S_OK;
        }
        const bool modeAllows = ShouldHandleCompositionKeys();
        const bool contextMatches = ContextMatchesComposition(context);
        if (!modeAllows || !contextMatches) {
            RecordSelectionKeyHostResult("down-mode-context", wParam, shiftDown, controlDown,
                                         altDown, CanAcceptKeys(), experimentSettings_.Get().asciiMode,
                                         composition_ != nullptr, contextMatches, false, false, S_OK);
            return S_OK;
        }
        const bool canHandle = surface_.CanHandle(wParam, shiftDown, controlDown, altDown);
        if (!canHandle) {
            RecordSelectionKeyHostResult("down-cannot-handle", wParam, shiftDown, controlDown,
                                         altDown, CanAcceptKeys(), experimentSettings_.Get().asciiMode,
                                         composition_ != nullptr, contextMatches, false, false, S_OK);
            return S_OK;
        }
        const auto outcome = surface_.HandleVirtualKey(wParam, shiftDown, controlDown, altDown);
        if (!outcome.handled) {
            RecordSelectionKeyHostResult("down-outcome", wParam, shiftDown, controlDown, altDown,
                                         CanAcceptKeys(), experimentSettings_.Get().asciiMode,
                                         composition_ != nullptr, contextMatches, canHandle, false,
                                         S_OK, outcome.error);
            return S_OK;
        }
        auto renderedUpdate = outcome.update;
        if (experimentSettings_.Get().traditionalization) {
            yime::experiment::ApplyTraditionalization(&renderedUpdate);
        }
        RECT compositionRect{};
        bool compositionRectValid = false;
        const HRESULT edit = yime::experiment::ApplyBrokerUpdateToContext(
            context, clientId_, static_cast<ITfCompositionSink*>(this), &composition_,
            &plannedCompositionTermination_, renderedUpdate, &compositionRect, &compositionRectValid);
        if (FAILED(edit)) {
            RecordSelectionKeyHostResult("down-edit", wParam, shiftDown, controlDown, altDown,
                                         CanAcceptKeys(), experimentSettings_.Get().asciiMode,
                                         composition_ != nullptr, contextMatches, canHandle, true,
                                         edit, outcome.error);
            surface_.DisconnectForRecovery();
            return S_OK;
        }
        if (composition_) RememberCompositionContext(context);
        UpdateCandidateUI(context, renderedUpdate, compositionRectValid ? &compositionRect : nullptr);
        *eaten = TRUE;
        RecordSelectionKeyHostResult("down-success", wParam, shiftDown, controlDown, altDown,
                                     CanAcceptKeys(), experimentSettings_.Get().asciiMode,
                                     composition_ != nullptr, contextMatches, canHandle, true,
                                     edit, outcome.error);
    } catch (...) {
        surface_.DisconnectForRecovery();
    }
    return S_OK;
}

STDMETHODIMP YimeTextService::OnTestKeyUp(ITfContext* context, WPARAM wParam, LPARAM, BOOL* eaten) {
    if (!eaten) return E_POINTER;
    *eaten = context && CanAcceptKeys() &&
             (wParam == VK_SHIFT || wParam == VK_LSHIFT || wParam == VK_RSHIFT) ? TRUE : FALSE;
    return S_OK;
}

STDMETHODIMP YimeTextService::OnKeyUp(ITfContext* context, WPARAM wParam, LPARAM, BOOL* eaten) {
    if (!eaten) return E_POINTER;
    *eaten = FALSE;
    if (!context || !CanAcceptKeys() ||
        (wParam != VK_SHIFT && wParam != VK_LSHIFT && wParam != VK_RSHIFT)) return S_OK;
    const bool toggle = shiftTap_.OnKeyUp(wParam);
    *eaten = TRUE;
    if (toggle) {
        yime::experiment::ExperimentSettings updated;
        if (yime::experiment::ApplyExperimentSettingsCommand(
                yime::experiment::ExperimentSettingsCommand::ToggleAscii,
                yime::experiment::ResolveExperimentSettingsPath(), &updated) && languageBarItem_) {
            languageBarItem_->Refresh();
        }
    }
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
    const auto& displaySettings = experimentSettings_.Get();
    if (update.candidates.empty() && !update.hasSentence) {
		document->Release();
		EndCandidateUI();
		return;
    } else {
        candidateUI_->Update(document, update.candidates, update.selectedCandidateIndex,
                             displaySettings.candidateAnnotation,
                             update.hasSentence ? &update.sentence : nullptr);
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
    candidatePopup_.SetFontPoints(displaySettings.candidateFontPoints);
    candidatePopup_.SetUseYinyuanFont(displaySettings.candidateAnnotation == "yinyuan");
    if (ownedCandidatePopupRequested_ &&
        candidatePopup_.Update(candidateUI_->PopupCandidateRows(), anchor, owner,
                               compositionRect != nullptr, popupSelection,
                               update.hasSentence ? &update.sentence : nullptr,
                               update.activeSegmentStart, update.activeSegmentEnd)) {
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
    auto renderedUpdate = outcome.update;
    if (experimentSettings_.Get().traditionalization) {
        yime::experiment::ApplyTraditionalization(&renderedUpdate);
    }
    const HRESULT edit = yime::experiment::ApplyBrokerUpdateToContext(
        context, clientId_, static_cast<ITfCompositionSink*>(this), &composition_,
        &plannedCompositionTermination_, renderedUpdate, nullptr, nullptr, true);
    if (FAILED(edit)) {
        surface_.DisconnectForRecovery();
        context->Release();
        return;
    }
    UpdateCandidateUI(context, renderedUpdate, nullptr);
    context->Release();
}

void YimeTextService::CandidatePopupSegmentSelection(void* context, int start, int end) noexcept {
    if (context) static_cast<YimeTextService*>(context)->FocusSentenceSegmentFromPopup(start, end);
}

void YimeTextService::FocusSentenceSegmentFromPopup(int start, int end) noexcept {
    if (!compositionContext_ || !CanAcceptKeys() || start < 0 || end <= start) return;
    ITfContext* context = compositionContext_;
    context->AddRef();
    const auto outcome = surface_.FocusSentenceSegment(start, end);
    if (!outcome.handled) {
        context->Release();
        return;
    }
    auto renderedUpdate = outcome.update;
    if (experimentSettings_.Get().traditionalization) {
        yime::experiment::ApplyTraditionalization(&renderedUpdate);
    }
    const HRESULT edit = yime::experiment::ApplyBrokerUpdateToContext(
        context, clientId_, static_cast<ITfCompositionSink*>(this), &composition_,
        &plannedCompositionTermination_, renderedUpdate, nullptr, nullptr, true);
    if (FAILED(edit)) {
        surface_.DisconnectForRecovery();
        context->Release();
        return;
    }
    UpdateCandidateUI(context, renderedUpdate, nullptr);
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
    const HRESULT managerResult = threadManager_->QueryInterface(
        __uuidof(ITfLangBarItemMgr), reinterpret_cast<void**>(&manager));
    HRESULT addResult = E_NOINTERFACE;
    HRESULT statusResult = E_NOINTERFACE;
    DWORD managerStatus = 0;
    if (SUCCEEDED(managerResult)) {
        addResult = manager->AddItem(languageBarItem_);
        languageBarItemAdded_ = addResult == S_OK;
        if (languageBarItemAdded_) {
            statusResult = manager->GetItemsStatus(1, &GUID_YimeTextServiceExperimentLangBar,
                                                   &managerStatus);
        }
        manager->Release();
    }
    RecordLanguageBarHostResult(managerResult, addResult, statusResult, managerStatus);
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
