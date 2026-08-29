#include <windows.h>
#include <msctf.h>
#include <ctfutb.h>

#include <atomic>
#include <iostream>
#include <string>

#include "YimeTextServiceIds.h"
#include "ExperimentSettings.h"

namespace {

using GetClassObject = HRESULT(__stdcall*)(REFCLSID, REFIID, void**);

void require(HRESULT result, const char* operation);

class ReadSession final : public ITfEditSession {
public:
    explicit ReadSession(ITfContext* context) : context_(context) { context_->AddRef(); }
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, __uuidof(ITfEditSession))) return E_NOINTERFACE;
        *object = static_cast<ITfEditSession*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override { const ULONG left = --references_; if (!left) delete this; return left; }
    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        ITfRange* start = nullptr;
        ITfRange* end = nullptr;
        HRESULT result = context_->GetStart(cookie, &start);
        if (SUCCEEDED(result)) result = context_->GetEnd(cookie, &end);
        if (SUCCEEDED(result)) result = start->ShiftEndToRange(cookie, end, TF_ANCHOR_END);
        wchar_t buffer[256]{};
        ULONG count = 0;
        if (SUCCEEDED(result)) result = start->GetText(cookie, 0, buffer, 255, &count);
        if (SUCCEEDED(result)) text_.assign(buffer, count);
        if (end) end->Release();
        if (start) start->Release();
        return result;
    }
    const std::wstring& text() const noexcept { return text_; }
private:
    ~ReadSession() { context_->Release(); }
    std::atomic<ULONG> references_{1};
    ITfContext* context_;
    std::wstring text_;
};

std::wstring readContext(ITfContext* context, TfClientId clientId) {
    auto* session = new ReadSession(context);
    HRESULT sessionResult = E_FAIL;
    const HRESULT request = context->RequestEditSession(clientId, session, TF_ES_SYNC | TF_ES_READ, &sessionResult);
    const std::wstring text = session->text();
    session->Release();
    if (FAILED(request) || FAILED(sessionResult)) throw std::runtime_error("read edit session failed");
    return text;
}

bool hasComposition(ITfContext* context) {
    ITfContextComposition* compositions = nullptr;
    if (FAILED(context->QueryInterface(__uuidof(ITfContextComposition), reinterpret_cast<void**>(&compositions)))) return false;
    IEnumITfCompositionView* values = nullptr;
    HRESULT result = compositions->EnumCompositions(&values);
    compositions->Release();
    if (FAILED(result)) return false;
    ITfCompositionView* value = nullptr;
    ULONG fetched = 0;
    result = values->Next(1, &value, &fetched);
    if (value) value->Release();
    values->Release();
    return result == S_OK && fetched == 1;
}

void terminateActiveComposition(ITfContext* context) {
    ITfContextOwnerCompositionServices* owner = nullptr;
    require(context->QueryInterface(__uuidof(ITfContextOwnerCompositionServices),
                                    reinterpret_cast<void**>(&owner)), "query composition owner");
    IEnumITfCompositionView* values = nullptr;
    require(owner->EnumCompositions(&values), "enumerate compositions");
    ITfCompositionView* value = nullptr;
    ULONG fetched = 0;
    const HRESULT next = values->Next(1, &value, &fetched);
    values->Release();
    if (next != S_OK || fetched != 1 || !value) {
        owner->Release();
        throw std::runtime_error("active composition missing before forced termination");
    }
    const HRESULT result = owner->TerminateComposition(value);
    value->Release();
    owner->Release();
    require(result, "terminate composition");
}

ITfCandidateListUIElement* findCandidateElement(ITfThreadMgr* threadManager) {
    ITfUIElementMgr* manager = nullptr;
    if (FAILED(threadManager->QueryInterface(__uuidof(ITfUIElementMgr), reinterpret_cast<void**>(&manager)))) return nullptr;
    IEnumTfUIElements* values = nullptr;
    const HRESULT enumerated = manager->EnumUIElements(&values);
    manager->Release();
    if (FAILED(enumerated)) return nullptr;
    ITfCandidateListUIElement* found = nullptr;
    for (;;) {
        ITfUIElement* element = nullptr;
        ULONG fetched = 0;
        if (values->Next(1, &element, &fetched) != S_OK || fetched != 1) break;
        GUID guid{};
        if (SUCCEEDED(element->GetGUID(&guid)) && IsEqualGUID(guid, GUID_YimeTextServiceExperimentCandidateList)) {
            element->QueryInterface(__uuidof(ITfCandidateListUIElement), reinterpret_cast<void**>(&found));
        }
        element->Release();
        if (found) break;
    }
    values->Release();
    return found;
}

void require(HRESULT result, const char* operation) {
    if (FAILED(result)) throw std::runtime_error(std::string(operation) + " failed: " + std::to_string(static_cast<unsigned long>(result)));
}

void pumpPendingMessages() {
    for (int attempt = 0; attempt < 10; ++attempt) {
        MSG message{};
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        Sleep(10);
    }
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    try {
        if (argc != 3 && argc != 4) {
            throw std::runtime_error("usage: YimeTsfCompositionTests <dll> <pipe> [long-session-code]");
        }
        std::string longSessionCode;
        if (argc == 4) {
            for (const wchar_t* cursor = argv[3]; *cursor; ++cursor) {
                if (*cursor < 0x20 || *cursor > 0x7e) {
                    throw std::runtime_error("long-session code must be printable ASCII");
                }
                longSessionCode.push_back(static_cast<char>(*cursor));
            }
        }
        require(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED), "CoInitializeEx");
        SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", argv[2]);
        SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST", L"1");
        wchar_t tempDirectory[MAX_PATH]{};
        GetTempPathW(MAX_PATH, tempDirectory);
        const std::wstring localAppData = std::wstring(tempDirectory) + L"yime-tsf-language-bar-" +
                                          std::to_wstring(GetCurrentProcessId());
        CreateDirectoryW(localAppData.c_str(), nullptr);
        SetEnvironmentVariableW(L"LOCALAPPDATA", localAppData.c_str());
        yime::experiment::ExperimentSettings seededSettings;
        if (!yime::experiment::ApplyExperimentSettingsCommand(
                yime::experiment::ExperimentSettingsCommand::Chinese,
                yime::experiment::ResolveExperimentSettingsPath(), &seededSettings)) {
            throw std::runtime_error("could not seed Chinese language-bar state");
        }
        HMODULE module = LoadLibraryW(argv[1]);
        if (!module) throw std::runtime_error("LoadLibraryW failed");
        const auto getClassObject = reinterpret_cast<GetClassObject>(GetProcAddress(module, "DllGetClassObject"));
        if (!getClassObject) throw std::runtime_error("DllGetClassObject missing");

        ITfThreadMgr* threadManager = nullptr;
        require(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER,
                                 __uuidof(ITfThreadMgr), reinterpret_cast<void**>(&threadManager)), "create thread manager");
        TfClientId clientId = TF_CLIENTID_NULL;
        require(threadManager->Activate(&clientId), "activate thread manager");
        ITfClientId* clientIds = nullptr;
        require(threadManager->QueryInterface(__uuidof(ITfClientId), reinterpret_cast<void**>(&clientIds)), "query client IDs");
        TfClientId serviceClientId = TF_CLIENTID_NULL;
        require(clientIds->GetClientId(CLSID_YimeTextServiceExperiment, &serviceClientId), "allocate service client ID");
        clientIds->Release();
        ITfDocumentMgr* document = nullptr;
        require(threadManager->CreateDocumentMgr(&document), "create document manager");
        ITfContext* context = nullptr;
        TfEditCookie ownerCookie = 0;
        require(document->CreateContext(clientId, 0, nullptr, &context, &ownerCookie), "create context");
        require(document->Push(context), "push context");
        require(threadManager->SetFocus(document), "focus document");

        IClassFactory* factory = nullptr;
        require(getClassObject(CLSID_YimeTextServiceExperiment, IID_IClassFactory, reinterpret_cast<void**>(&factory)), "get class factory");
        ITfTextInputProcessorEx* processor = nullptr;
        require(factory->CreateInstance(nullptr, __uuidof(ITfTextInputProcessorEx), reinterpret_cast<void**>(&processor)), "create processor");
        factory->Release();
        require(processor->ActivateEx(threadManager, serviceClientId, 0), "activate processor");
        ITfLangBarItemMgr* languageBarManager = nullptr;
        require(threadManager->QueryInterface(__uuidof(ITfLangBarItemMgr),
                                              reinterpret_cast<void**>(&languageBarManager)),
                "query language bar manager");
        ITfLangBarItem* languageBarItem = nullptr;
        ITfLangBarItemButton* languageModeButton = nullptr;
        const HRESULT languageBarLookup =
            languageBarManager->GetItem(GUID_YimeTextServiceExperimentLangBar, &languageBarItem);
        const bool languageBarManagerAccepted = languageBarLookup == S_OK && languageBarItem;
        if (languageBarManagerAccepted) {
            TF_LANGBARITEMINFO languageBarInfo{};
            require(languageBarItem->GetInfo(&languageBarInfo), "read experiment language bar item");
            if (!IsEqualGUID(languageBarInfo.clsidService, CLSID_YimeTextServiceExperiment) ||
                (languageBarInfo.dwStyle & TF_LBI_STYLE_BTN_BUTTON) == 0 ||
                (languageBarInfo.dwStyle & TF_LBI_STYLE_SHOWNINTRAY) != 0) {
                throw std::runtime_error("experiment language bar identity or style mismatch");
            }
            require(languageBarItem->QueryInterface(__uuidof(ITfLangBarItemButton),
                                                    reinterpret_cast<void**>(&languageModeButton)),
                    "query experiment input-mode button");
            HICON taskbarModeIcon = nullptr;
            require(languageModeButton->GetIcon(&taskbarModeIcon), "get taskbar input-mode icon");
            if (!taskbarModeIcon) throw std::runtime_error("taskbar input-mode icon is empty");
            DestroyIcon(taskbarModeIcon);
            languageBarItem->Release();
            languageBarItem = nullptr;
        } else if (languageBarLookup != S_FALSE || languageBarItem != nullptr) {
            throw std::runtime_error("unexpected unregistered language bar lookup result");
        }
        std::cout << "language_bar_manager_accepted=" << (languageBarManagerAccepted ? "true" : "false") << '\n';
        ITfKeyEventSink* keys = nullptr;
        require(processor->QueryInterface(__uuidof(ITfKeyEventSink), reinterpret_cast<void**>(&keys)), "query key sink");

        const std::string code = "2jru";
        for (size_t index = 0; index < code.size(); ++index) {
            const char character = code[index];
            const WPARAM key = character >= 'a' ? static_cast<WPARAM>(character - 'a' + 'A') : static_cast<WPARAM>(character);
            BOOL testEaten = FALSE;
            require(keys->OnTestKeyDown(context, key, 0, &testEaten), "test key down");
            if (!testEaten) throw std::runtime_error("composition key was not claimed");
            BOOL eaten = FALSE;
            require(keys->OnKeyDown(context, key, 0, &eaten), "key down");
            if (!eaten) throw std::runtime_error("successful composition edit was not eaten");
            const std::wstring expected(code.begin(), code.begin() + static_cast<std::ptrdiff_t>(index + 1));
            if (readContext(context, clientId) != expected || !hasComposition(context)) {
                throw std::runtime_error("TSF composition text mismatch");
            }
            if (index == 0) {
                ITfCandidateListUIElement* firstKeyElement = findCandidateElement(threadManager);
                UINT firstKeyCount = 0;
                if (!firstKeyElement || FAILED(firstKeyElement->GetCount(&firstKeyCount)) || firstKeyCount == 0) {
                    if (firstKeyElement) firstKeyElement->Release();
                    throw std::runtime_error("first composition key did not publish candidate UI");
                }
                firstKeyElement->Release();
                HWND firstKeyPopup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
                if (!firstKeyPopup || !IsWindowVisible(firstKeyPopup)) {
                    throw std::runtime_error("first composition key did not show the owned candidate popup");
                }
            }
            if (index + 1 == code.size()) {
                ITfCandidateListUIElement* navigationElement = findCandidateElement(threadManager);
                if (!navigationElement) throw std::runtime_error("candidate navigation UI missing");
                UINT navigationCount = 0;
                require(navigationElement->GetCount(&navigationCount), "candidate navigation count");
                navigationElement->Release();
                if (navigationCount < 2) throw std::runtime_error("candidate navigation needs two candidates");
                BOOL navigationEaten = FALSE;
                require(keys->OnKeyDown(context, VK_DOWN, 0, &navigationEaten), "Down candidate key");
                navigationElement = findCandidateElement(threadManager);
                UINT navigationSelection = 0;
                if (!navigationEaten || !navigationElement ||
                    FAILED(navigationElement->GetSelection(&navigationSelection)) || navigationSelection != 1) {
                    if (navigationElement) navigationElement->Release();
                    throw std::runtime_error("Down did not move TSF candidate selection");
                }
                navigationElement->Release();
                navigationEaten = FALSE;
                require(keys->OnKeyDown(context, VK_UP, 0, &navigationEaten), "Up candidate key");
                navigationElement = findCandidateElement(threadManager);
                navigationSelection = 99;
                if (!navigationEaten || !navigationElement ||
                    FAILED(navigationElement->GetSelection(&navigationSelection)) || navigationSelection != 0) {
                    if (navigationElement) navigationElement->Release();
                    throw std::runtime_error("Up did not restore TSF candidate selection");
                }
                navigationElement->Release();
                for (const WPARAM pageKey : {static_cast<WPARAM>(VK_RIGHT), static_cast<WPARAM>(VK_PRIOR)}) {
                    navigationEaten = FALSE;
                    require(keys->OnKeyDown(context, pageKey, 0, &navigationEaten), "candidate page key");
                    if (!navigationEaten || readContext(context, clientId) != L"2jru" || !hasComposition(context)) {
                        throw std::runtime_error("candidate page key escaped into the TSF host");
                    }
                }
                std::cout << "candidate_direction_and_page_keys_verified=true\n";
            }
        }
        ITfCandidateListUIElement* candidateElement = findCandidateElement(threadManager);
        if (!candidateElement) throw std::runtime_error("TSF candidate UI element was not registered");
        UINT candidateCount = 0;
        require(candidateElement->GetCount(&candidateCount), "candidate UI count");
        if (candidateCount == 0 || candidateCount > 9) throw std::runtime_error("candidate UI count exceeds Shift ordinals");
        BSTR candidateText = nullptr;
        require(candidateElement->GetString(0, &candidateText), "candidate UI first string");
        const std::wstring firstCandidate(candidateText ? candidateText : L"");
        SysFreeString(candidateText);
        candidateElement->Release();
        if (firstCandidate != L"⇧1  秋  2jru") throw std::runtime_error("candidate UI Shift label, text or default key-sequence encoding mismatch");
        HWND candidatePopup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (!candidatePopup || !IsWindowVisible(candidatePopup)) {
            throw std::runtime_error("owned candidate popup was not visible");
        }
        const LONG_PTR popupStyles = GetWindowLongPtrW(candidatePopup, GWL_EXSTYLE);
        if ((popupStyles & (WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW)) !=
            (WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW)) {
            throw std::runtime_error("owned candidate popup activation contract mismatch");
        }
        std::cout << "owned_candidate_popup_visible=true\n";
        std::cout << "text_extent_anchor="
                  << (GetPropW(candidatePopup, L"YimeTextServiceExperimentTextExtentAnchor") ? "true" : "false")
                  << '\n';

        BOOL invalidEaten = FALSE;
        require(keys->OnKeyDown(context, 'Z', 0, &invalidEaten), "invalid-code key down");
        if (!invalidEaten || readContext(context, clientId) != L"2jruz" || !hasComposition(context)) {
            throw std::runtime_error("invalid code terminated or desynchronized the TSF composition");
        }
        candidateElement = findCandidateElement(threadManager);
        if (!candidateElement) {
            throw std::runtime_error("invalid code removed the empty correction UI state");
        }
        candidateCount = 99;
        require(candidateElement->GetCount(&candidateCount), "empty correction candidate count");
        UINT emptySelection = 99;
        if (candidateCount != 0 || candidateElement->GetSelection(&emptySelection) != E_FAIL ||
            emptySelection != 0) {
            candidateElement->Release();
            throw std::runtime_error("invalid code exposed a selectable synthetic candidate");
        }
        candidateElement->Release();
        if (!IsWindow(candidatePopup) || !IsWindowVisible(candidatePopup)) {
            throw std::runtime_error("invalid code did not keep the owned correction status visible");
        }
        BOOL backspaceTestEaten = FALSE;
        require(keys->OnTestKeyDown(context, VK_BACK, 0, &backspaceTestEaten), "Backspace test key down");
        if (!backspaceTestEaten) throw std::runtime_error("Backspace was not claimed for active raw input");
        BOOL backspaceEaten = FALSE;
        require(keys->OnKeyDown(context, VK_BACK, 0, &backspaceEaten), "Backspace key down");
        if (!backspaceEaten || readContext(context, clientId) != L"2jru" || !hasComposition(context)) {
            throw std::runtime_error("Backspace did not restore the pre-error Broker state");
        }
        backspaceEaten = FALSE;
        require(keys->OnKeyDown(context, VK_BACK, 0, &backspaceEaten), "second Backspace key down");
        invalidEaten = FALSE;
        require(keys->OnKeyDown(context, 'U', 0, &invalidEaten), "continued input after Backspace");
        if (!backspaceEaten || !invalidEaten || readContext(context, clientId) != L"2jru" ||
            !hasComposition(context)) {
            throw std::runtime_error("deleted code resurrected after continued TSF input");
        }
        candidatePopup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (!candidatePopup || !IsWindowVisible(candidatePopup)) {
            throw std::runtime_error("candidate UI did not recover after Backspace correction");
        }
        std::cout << "invalid_code_backspace_recovery_verified=true\n";
        BOOL escapeTestEaten = FALSE;
        require(keys->OnTestKeyDown(context, VK_ESCAPE, 0, &escapeTestEaten), "Escape test key down");
        BOOL escapeEaten = FALSE;
        require(keys->OnKeyDown(context, VK_ESCAPE, 0, &escapeEaten), "Escape key down");
        if (!escapeTestEaten || !escapeEaten || !readContext(context, clientId).empty() ||
            hasComposition(context) || IsWindowVisible(candidatePopup)) {
            throw std::runtime_error("Escape did not cancel the active TSF composition");
        }
        for (const WPARAM key : {static_cast<WPARAM>('2'), static_cast<WPARAM>('J'),
                               static_cast<WPARAM>('R'), static_cast<WPARAM>('U')}) {
            BOOL restartEaten = FALSE;
            require(keys->OnKeyDown(context, key, 0, &restartEaten), "post-Escape composition key");
            if (!restartEaten) throw std::runtime_error("post-Escape composition key was not handled");
        }
        candidatePopup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (readContext(context, clientId) != L"2jru" || !hasComposition(context) ||
            !candidatePopup || !IsWindowVisible(candidatePopup)) {
            throw std::runtime_error("composition did not restart after Escape cancellation");
        }
        std::cout << "escape_cancellation_verified=true\n";

        require(keys->OnSetFocus(FALSE), "lose key-sink focus");
        candidateElement = findCandidateElement(threadManager);
        if (!candidateElement) throw std::runtime_error("candidate UI element disappeared instead of hiding on focus loss");
        BOOL candidateShown = TRUE;
        require(candidateElement->IsShown(&candidateShown), "read candidate focus-loss visibility");
        candidateElement->Release();
        if (candidateShown) throw std::runtime_error("candidate UI remained shown after focus loss");
        if (IsWindowVisible(candidatePopup)) throw std::runtime_error("owned candidate popup remained visible after focus loss");
        BOOL focusEaten = TRUE;
        require(keys->OnTestKeyDown(context, 'J', 0, &focusEaten), "focus-loss test key");
        if (focusEaten) throw std::runtime_error("focus-loss test key was claimed");
        focusEaten = TRUE;
        require(keys->OnKeyDown(context, 'J', 0, &focusEaten), "focus-loss key");
        if (focusEaten || readContext(context, clientId) != L"2jru" || !hasComposition(context)) {
            throw std::runtime_error("focus-loss key changed the active composition");
        }
        ITfDocumentMgr* otherDocument = nullptr;
        require(threadManager->CreateDocumentMgr(&otherDocument), "create cross-context document manager");
        ITfContext* otherContext = nullptr;
        TfEditCookie otherOwnerCookie = 0;
        require(otherDocument->CreateContext(clientId, 0, nullptr, &otherContext, &otherOwnerCookie),
                "create cross-context context");
        require(otherDocument->Push(otherContext), "push cross-context context");
        require(threadManager->SetFocus(otherDocument), "focus cross-context document");
        require(keys->OnSetFocus(TRUE), "focus key sink on cross-context document");
        focusEaten = TRUE;
        require(keys->OnTestKeyDown(otherContext, 'J', 0, &focusEaten), "cross-context test key");
        if (focusEaten) throw std::runtime_error("cross-context test key was claimed by the old composition");
        focusEaten = TRUE;
        require(keys->OnKeyDown(otherContext, 'J', 0, &focusEaten), "cross-context key");
        if (focusEaten || !readContext(otherContext, clientId).empty() ||
            readContext(context, clientId) != L"2jru" || !hasComposition(context)) {
            throw std::runtime_error("cross-context key contaminated a TSF document");
        }
        candidateElement = findCandidateElement(threadManager);
        if (!candidateElement) throw std::runtime_error("candidate UI element missing during cross-context isolation");
        candidateShown = TRUE;
        require(candidateElement->IsShown(&candidateShown), "read cross-context candidate visibility");
        candidateElement->Release();
        if (candidateShown) throw std::runtime_error("old candidate UI was shown on a different document");
        if (IsWindowVisible(candidatePopup)) throw std::runtime_error("owned candidate popup was shown on a different document");
        std::cout << "cross_context_isolation_verified=true\n";
        require(keys->OnSetFocus(FALSE), "leave cross-context key focus");
        require(threadManager->SetFocus(document), "restore composition document focus");
        require(keys->OnSetFocus(TRUE), "restore key-sink focus");
        candidateElement = findCandidateElement(threadManager);
        if (!candidateElement) throw std::runtime_error("candidate UI element missing after focus restore");
        candidateShown = FALSE;
        require(candidateElement->IsShown(&candidateShown), "read candidate focus-restore visibility");
        candidateElement->Release();
        if (!candidateShown) throw std::runtime_error("candidate UI did not return after focus restore");
        if (!IsWindowVisible(candidatePopup)) throw std::runtime_error("owned candidate popup did not return after focus restore");
        std::cout << "key_focus_transition_verified=true\n";
        otherDocument->Pop(TF_POPF_ALL);
        otherContext->Release();
        otherDocument->Release();

        BYTE keyboard[256]{};
        GetKeyboardState(keyboard);
        BYTE shifted[256]{};
        CopyMemory(shifted, keyboard, sizeof(keyboard));
        shifted[VK_SHIFT] = 0x80;
        shifted[VK_LSHIFT] = 0x80;
        SetKeyboardState(shifted);
        BOOL eaten = FALSE;
        require(keys->OnKeyDown(context, '1', 0, &eaten), "candidate key down");
        SetKeyboardState(keyboard);
        if (!eaten) throw std::runtime_error("candidate commit was not eaten");
        if (readContext(context, clientId) != L"秋" || hasComposition(context)) {
            throw std::runtime_error("TSF committed text or composition termination mismatch");
        }
        if (ITfCandidateListUIElement* residual = findCandidateElement(threadManager)) {
            residual->Release();
            throw std::runtime_error("candidate UI remained after commit");
        }

        for (const WPARAM defaultSelectionKey : {static_cast<WPARAM>(VK_SPACE), static_cast<WPARAM>(VK_RETURN)}) {
            const std::wstring beforeDefaultCommit = readContext(context, clientId);
            for (const char character : code) {
                const WPARAM key = character >= 'a'
                    ? static_cast<WPARAM>(character - 'a' + 'A')
                    : static_cast<WPARAM>(character);
                eaten = FALSE;
                require(keys->OnKeyDown(context, key, 0, &eaten), "default-selection setup key down");
                if (!eaten || !hasComposition(context)) {
                    throw std::runtime_error("default-selection setup did not create a composition");
                }
            }
            BOOL testEaten = FALSE;
            require(keys->OnTestKeyDown(context, defaultSelectionKey, 0, &testEaten),
                    "default-selection test key down");
            if (!testEaten) throw std::runtime_error("Enter/Space selection was not claimed");
            eaten = FALSE;
            require(keys->OnKeyDown(context, defaultSelectionKey, 0, &eaten),
                    "default-selection key down");
            const std::wstring afterDefaultCommit = readContext(context, clientId);
            if (!eaten || afterDefaultCommit.size() <= beforeDefaultCommit.size() ||
                afterDefaultCommit.back() == L'u' || hasComposition(context)) {
                throw std::runtime_error("Enter/Space did not commit the first candidate");
            }
        }
        std::cout << "default_candidate_keys_verified=true\n";

        const std::wstring beforeMouseCommit = readContext(context, clientId);
        for (const char character : code) {
            const WPARAM key = character >= 'a'
                ? static_cast<WPARAM>(character - 'a' + 'A')
                : static_cast<WPARAM>(character);
            eaten = FALSE;
            require(keys->OnKeyDown(context, key, 0, &eaten), "post-commit key down");
            if (!eaten || !hasComposition(context)) {
                throw std::runtime_error("mouse-selection setup did not create a composition");
            }
        }
        const std::wstring preMouseComposition = readContext(context, clientId);
        if (preMouseComposition != beforeMouseCommit + L"2jru" || !hasComposition(context)) {
            throw std::runtime_error("normal commit incorrectly closed the Broker session");
        }
        candidatePopup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (!candidatePopup || !IsWindowVisible(candidatePopup)) {
            throw std::runtime_error("owned candidate popup missing before mouse selection");
        }
        candidateElement = findCandidateElement(threadManager);
        candidateCount = 0;
        if (!candidateElement || FAILED(candidateElement->GetCount(&candidateCount)) || candidateCount == 0) {
            if (candidateElement) candidateElement->Release();
            throw std::runtime_error("candidate UI did not recover before mouse selection");
        }
        candidateElement->Release();
        RECT popupClient{};
        GetClientRect(candidatePopup, &popupClient);
        const bool hasSentenceRow =
            GetPropW(candidatePopup, L"YimeTextServiceExperimentSentenceRow") != nullptr;
        const int popupRows = static_cast<int>(candidateCount) + (hasSentenceRow ? 1 : 0);
        const int rowHeight = (popupClient.bottom - 16) / popupRows;
        const int candidateRowY = 8 + rowHeight * (hasSentenceRow ? 1 : 0) + rowHeight / 2;
        SendMessageW(candidatePopup, WM_LBUTTONUP, 0, MAKELPARAM(20, candidateRowY));
        for (int attempt = 0; attempt < 100; ++attempt) {
            MSG message{};
            while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
                TranslateMessage(&message);
                DispatchMessageW(&message);
            }
            if (!IsWindowVisible(candidatePopup)) break;
            Sleep(10);
        }
        for (int attempt = 0; attempt < 10; ++attempt) {
            MSG message{};
            while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
                TranslateMessage(&message);
                DispatchMessageW(&message);
            }
            Sleep(10);
        }
        const std::wstring secondCommit = readContext(context, clientId);
        if (secondCommit != beforeMouseCommit + L"秋" || hasComposition(context)) {
            throw std::runtime_error("mouse-selected TSF commit mismatch");
        }
        std::cout << "mouse_candidate_selection_verified=true\n";

        if (!yime::experiment::ApplyExperimentSettingsCommand(
                yime::experiment::ExperimentSettingsCommand::PunctuationChinese,
                yime::experiment::ResolveExperimentSettingsPath(), &seededSettings)) {
            throw std::runtime_error("could not seed Chinese punctuation palette state");
        }
        auto openPunctuationPalette = [&]() {
            BYTE unshiftedState[256]{};
            GetKeyboardState(unshiftedState);
            BYTE shiftedState[256]{};
            CopyMemory(shiftedState, unshiftedState, sizeof(unshiftedState));
            shiftedState[VK_SHIFT] = 0x80;
            shiftedState[VK_LSHIFT] = 0x80;
            SetKeyboardState(shiftedState);
            BOOL leaderTestEaten = FALSE;
                require(keys->OnTestKeyDown(context, VK_OEM_5, 0, &leaderTestEaten),
                    "punctuation leader test key");
            BOOL leaderEaten = FALSE;
                require(keys->OnKeyDown(context, VK_OEM_5, 0, &leaderEaten),
                    "punctuation leader key");
            SetKeyboardState(unshiftedState);
            if (!leaderTestEaten || !leaderEaten) {
                throw std::runtime_error("Shift+backslash did not open the punctuation palette");
            }
        };

        const std::wstring beforePaletteMouse = readContext(context, clientId);
        openPunctuationPalette();
        candidateElement = findCandidateElement(threadManager);
        candidateCount = 0;
        BSTR paletteDescription = nullptr;
        BSTR paletteFirst = nullptr;
        if (!candidateElement || FAILED(candidateElement->GetCount(&candidateCount)) ||
            candidateCount != 9 || FAILED(candidateElement->GetDescription(&paletteDescription)) ||
            !paletteDescription || std::wstring_view(paletteDescription).find(L"标点（中文）") ==
                                       std::wstring_view::npos ||
            FAILED(candidateElement->GetString(0, &paletteFirst)) || !paletteFirst ||
            std::wstring_view(paletteFirst) != L"⇧1  ！") {
            if (paletteFirst) SysFreeString(paletteFirst);
            if (paletteDescription) SysFreeString(paletteDescription);
            if (candidateElement) candidateElement->Release();
            throw std::runtime_error("Chinese punctuation palette UI contract mismatch");
        }
        SysFreeString(paletteFirst);
        SysFreeString(paletteDescription);
        candidateElement->Release();
        candidatePopup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (!candidatePopup || !IsWindowVisible(candidatePopup)) {
            throw std::runtime_error("punctuation palette owned popup is not visible");
        }
        const int punctuationRowHeight = static_cast<int>(reinterpret_cast<UINT_PTR>(
            GetPropW(candidatePopup, L"YimeTextServiceExperimentCandidateRowHeight")));
        if (punctuationRowHeight <= 0) {
            throw std::runtime_error("punctuation palette row geometry is unavailable");
        }
        const int firstPunctuationY = 8 + punctuationRowHeight + punctuationRowHeight / 2;
        SendMessageW(candidatePopup, WM_LBUTTONUP, 0, MAKELPARAM(20, firstPunctuationY));
        pumpPendingMessages();
        if (readContext(context, clientId) != beforePaletteMouse + L"！" ||
            hasComposition(context) || IsWindowVisible(candidatePopup)) {
            throw std::runtime_error("mouse-selected punctuation did not commit once and close");
        }

        const std::wstring beforeAtomicPunctuation = readContext(context, clientId);
        for (const char character : code) {
            const WPARAM key = character >= 'a'
                ? static_cast<WPARAM>(character - 'a' + 'A')
                : static_cast<WPARAM>(character);
            eaten = FALSE;
            require(keys->OnKeyDown(context, key, 0, &eaten),
                    "punctuation composition setup key");
            if (!eaten || !hasComposition(context)) {
                throw std::runtime_error("punctuation composition setup failed");
            }
        }
        openPunctuationPalette();
        eaten = FALSE;
        require(keys->OnKeyDown(context, VK_OEM_COMMA, 0, &eaten),
                "composition punctuation direct key");
        if (!eaten || readContext(context, clientId) != beforeAtomicPunctuation + L"秋，" ||
            hasComposition(context)) {
            throw std::runtime_error("candidate text and punctuation were not one TSF commit");
        }

        const std::wstring beforeReclassification = readContext(context, clientId);
        openPunctuationPalette();
        eaten = FALSE;
        require(keys->OnKeyDown(context, '2', 0, &eaten),
                "punctuation undefined-key reclassification");
        if (!eaten || readContext(context, clientId) != beforeReclassification + L"2" ||
            !hasComposition(context)) {
            throw std::runtime_error("punctuation layer did not reclassify a base composition key");
        }
        eaten = FALSE;
        require(keys->OnKeyDown(context, VK_ESCAPE, 0, &eaten),
                "punctuation reclassification cleanup");
        if (!eaten || hasComposition(context) ||
            readContext(context, clientId) != beforeReclassification) {
            throw std::runtime_error("punctuation reclassification cleanup failed");
        }
        std::cout << "punctuation_palette_and_atomic_commit_verified=true\n";

        if (!longSessionCode.empty()) {
            const std::wstring beforeLongSession = readContext(context, clientId);
            for (const char character : longSessionCode) {
                const WPARAM key = character >= 'a' && character <= 'z'
                    ? static_cast<WPARAM>(character - 'a' + 'A')
                    : static_cast<WPARAM>(character);
                eaten = FALSE;
                require(keys->OnKeyDown(context, key, 0, &eaten), "long-session setup key");
                if (!eaten) throw std::runtime_error("long-session setup key was not eaten");
            }
            const std::wstring rawLongSession(longSessionCode.begin(), longSessionCode.end());
            const std::wstring expectedComposition = beforeLongSession + rawLongSession;
            if (readContext(context, clientId) != expectedComposition || !hasComposition(context)) {
                throw std::runtime_error("long-session setup did not preserve raw composition");
            }
            if (longSessionCode.size() % 3 != 0) {
                throw std::runtime_error("long-session code must contain three equal spans");
            }
            const int spanLength = static_cast<int>(longSessionCode.size() / 3);
            constexpr int cycles = 25;
            for (int cycle = 0; cycle < cycles; ++cycle) {
                for (int targetIndex = 0; targetIndex < 3; ++targetIndex) {
                    candidatePopup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
                    if (!candidatePopup || !IsWindowVisible(candidatePopup)) {
                        throw std::runtime_error("long-session sentence popup disappeared");
                    }
                    const int segmentRowHeight = static_cast<int>(reinterpret_cast<UINT_PTR>(
                        GetPropW(candidatePopup, L"YimeTextServiceExperimentCandidateRowHeight")));
                    const int textColumnLeft = static_cast<int>(reinterpret_cast<UINT_PTR>(
                        GetPropW(candidatePopup, L"YimeTextServiceExperimentTextColumnLeft")));
                    const size_t segmentCount = static_cast<size_t>(reinterpret_cast<UINT_PTR>(
                        GetPropW(candidatePopup, L"YimeTextServiceExperimentSentenceSegmentCount")));
                    if (segmentRowHeight <= 0 || textColumnLeft <= 0 || segmentCount != 3) {
                        throw std::runtime_error("long-session sentence geometry is incomplete");
                    }
                    const int segmentX = textColumnLeft + targetIndex * segmentRowHeight +
                                         segmentRowHeight / 2;
                    const int segmentY = 8 + segmentRowHeight / 2;
                    SendMessageW(candidatePopup, WM_LBUTTONDOWN, 0, MAKELPARAM(segmentX, segmentY));
                    SendMessageW(candidatePopup, WM_LBUTTONUP, 0, MAKELPARAM(segmentX, segmentY));
                    pumpPendingMessages();
                    const int activeStart = static_cast<int>(reinterpret_cast<UINT_PTR>(GetPropW(
                        candidatePopup, L"YimeTextServiceExperimentActiveSegmentStart"))) - 1;
                    const int activeEnd = static_cast<int>(reinterpret_cast<UINT_PTR>(GetPropW(
                        candidatePopup, L"YimeTextServiceExperimentActiveSegmentEnd"))) - 1;
                    if (activeStart != targetIndex * spanLength ||
                        activeEnd != (targetIndex + 1) * spanLength) {
                        throw std::runtime_error("long-session popup activated the wrong raw span");
                    }
                    ITfCandidateListUIElement* segmentCandidates = findCandidateElement(threadManager);
                    UINT segmentCandidateCount = 0;
                    if (!segmentCandidates ||
                        FAILED(segmentCandidates->GetCount(&segmentCandidateCount)) ||
                        segmentCandidateCount < 2) {
                        if (segmentCandidates) segmentCandidates->Release();
                        throw std::runtime_error("long-session segment candidates are incomplete");
                    }
                    segmentCandidates->Release();
                    BYTE longKeyboard[256]{};
                    GetKeyboardState(longKeyboard);
                    BYTE longShifted[256]{};
                    CopyMemory(longShifted, longKeyboard, sizeof(longKeyboard));
                    longShifted[VK_SHIFT] = 0x80;
                    longShifted[VK_LSHIFT] = 0x80;
                    SetKeyboardState(longShifted);
                    eaten = FALSE;
                    require(keys->OnKeyDown(context, '2', 0, &eaten), "long-session segment selection");
                    SetKeyboardState(longKeyboard);
                    pumpPendingMessages();
                    if (!eaten || readContext(context, clientId) != expectedComposition ||
                        !hasComposition(context)) {
                        throw std::runtime_error("long-session segment selection committed early");
                    }
                }
            }
            ITfCandidateListUIElement* sentenceOnly = findCandidateElement(threadManager);
            UINT residualCandidateCount = 0;
            if (!sentenceOnly || FAILED(sentenceOnly->GetCount(&residualCandidateCount)) ||
                residualCandidateCount != 0) {
                if (sentenceOnly) sentenceOnly->Release();
                throw std::runtime_error("long-session probe unexpectedly has a global exact candidate");
            }
            sentenceOnly->Release();
            eaten = FALSE;
            require(keys->OnKeyDown(context, VK_RETURN, 0, &eaten), "long-session sentence commit");
            const std::wstring afterLongSession = readContext(context, clientId);
            if (!eaten || hasComposition(context) ||
                afterLongSession.size() != beforeLongSession.size() + 3 ||
                afterLongSession.compare(0, beforeLongSession.size(), beforeLongSession) != 0 ||
                afterLongSession == expectedComposition) {
                throw std::runtime_error("long-session sentence did not commit atomically");
            }
            std::cout << "long_segment_session_verified=true\n";
        }

        eaten = FALSE;
        require(keys->OnKeyDown(context, '2', 0, &eaten), "forced-termination setup key");
        if (!eaten || !hasComposition(context)) throw std::runtime_error("forced-termination setup failed");
        terminateActiveComposition(context);
        if (hasComposition(context)) throw std::runtime_error("host-forced composition remained active");
        BOOL testEaten = FALSE;
        require(keys->OnTestKeyDown(context, 'J', 0, &testEaten), "post-termination test key");
        if (!testEaten) throw std::runtime_error("host-forced termination did not reconnect the Broker session");
        eaten = FALSE;
        require(keys->OnKeyDown(context, 'J', 0, &eaten), "post-termination key");
        const std::wstring recoveredText = readContext(context, clientId);
        if (!eaten || recoveredText.empty() || recoveredText.back() != L'j' || !hasComposition(context)) {
            throw std::runtime_error("post-termination key did not start a fresh composition");
        }
        std::cout << "host_termination_recovery_verified=true\n";

        if (!languageModeButton) throw std::runtime_error("input-mode language-bar button was not registered");
        BSTR languageText = nullptr;
        require(languageModeButton->GetText(&languageText), "read Chinese input-mode label");
        if (!languageText || std::wstring_view(languageText) != L"中") {
            SysFreeString(languageText);
            throw std::runtime_error("Chinese input-mode label is not 中");
        }
        SysFreeString(languageText);
        require(languageModeButton->OnClick(TF_LBI_CLK_LEFT, {}, nullptr), "toggle input mode to English");
        languageText = nullptr;
        require(languageModeButton->GetText(&languageText), "read English input-mode label");
        if (!languageText || std::wstring_view(languageText) != L"英") {
            SysFreeString(languageText);
            throw std::runtime_error("English input-mode label is not 英");
        }
        SysFreeString(languageText);

        // The click records the new global target but must not move the live
        // composition to another engine halfway through the text.
        testEaten = FALSE;
        require(keys->OnTestKeyDown(context, 'K', 0, &testEaten), "English transition live-composition probe");
        if (!testEaten) throw std::runtime_error("English switch abandoned a live composition");
        eaten = FALSE;
        require(keys->OnKeyDown(context, 'K', 0, &eaten), "English transition live-composition key");
        if (!eaten || !hasComposition(context)) {
            throw std::runtime_error("live composition did not remain on its original engine");
        }
        for (unsigned attempt = 0; attempt < 8 && hasComposition(context); ++attempt) {
            eaten = FALSE;
            require(keys->OnKeyDown(context, VK_BACK, 0, &eaten),
                    "finish original composition before English pass-through");
            if (!eaten) throw std::runtime_error("original composition backspace was not handled");
        }
        if (hasComposition(context)) throw std::runtime_error("original composition did not reach idle");
        testEaten = TRUE;
        require(keys->OnTestKeyDown(context, 'L', 0, &testEaten), "English pass-through test key");
        if (testEaten) throw std::runtime_error("English mode swallowed an idle host key");
        eaten = TRUE;
        require(keys->OnKeyDown(context, 'L', 0, &eaten), "English pass-through key");
        if (eaten) throw std::runtime_error("English mode handled an idle host key");

        // English mode still belongs to this TIP when output transforms are
        // enabled. Exercise the complete ITfKeyEventSink -> edit-session path,
        // rather than only the pure virtual-key mapping helper.
        if (!yime::experiment::ApplyExperimentSettingsCommand(
                yime::experiment::ExperimentSettingsCommand::PunctuationChinese,
                yime::experiment::ResolveExperimentSettingsPath(), &seededSettings)) {
            throw std::runtime_error("could not enable Chinese punctuation");
        }
        const std::wstring beforeChinesePunctuation = readContext(context, clientId);
        testEaten = FALSE;
        require(keys->OnTestKeyDown(context, VK_OEM_COMMA, 0, &testEaten),
                "Chinese punctuation direct-output probe");
        if (!testEaten) throw std::runtime_error("Chinese punctuation was not claimed in English mode");
        eaten = FALSE;
        require(keys->OnKeyDown(context, VK_OEM_COMMA, 0, &eaten),
                "Chinese punctuation direct output");
        if (!eaten) throw std::runtime_error("Chinese punctuation direct output was not eaten");
        if (readContext(context, clientId) != beforeChinesePunctuation + L"，") {
            throw std::runtime_error("Chinese punctuation did not commit through the TSF edit session");
        }
        if (!yime::experiment::ApplyExperimentSettingsCommand(
                yime::experiment::ExperimentSettingsCommand::PunctuationEnglish,
                yime::experiment::ResolveExperimentSettingsPath(), &seededSettings)) {
            throw std::runtime_error("could not restore English punctuation");
        }
        testEaten = TRUE;
        require(keys->OnTestKeyDown(context, VK_OEM_COMMA, 0, &testEaten),
                "English punctuation pass-through probe");
        if (testEaten) throw std::runtime_error("English punctuation was swallowed in English mode");
        if (!yime::experiment::ApplyExperimentSettingsCommand(
                yime::experiment::ExperimentSettingsCommand::ShapeFull,
                yime::experiment::ResolveExperimentSettingsPath(), &seededSettings)) {
            throw std::runtime_error("could not enable full-width output");
        }
        const std::wstring beforeFullWidth = readContext(context, clientId);
        testEaten = FALSE;
        require(keys->OnTestKeyDown(context, 'A', 0, &testEaten),
                "full-width direct-output probe");
        if (!testEaten) throw std::runtime_error("full-width letter was not claimed in English mode");
        eaten = FALSE;
        require(keys->OnKeyDown(context, 'A', 0, &eaten), "full-width direct output");
        if (!eaten) throw std::runtime_error("full-width direct output was not eaten");
        const std::wstring afterFullWidth = readContext(context, clientId);
        if (afterFullWidth != beforeFullWidth + L"ａ") {
            std::cerr << "full_width_before_size=" << beforeFullWidth.size()
                      << " after_size=" << afterFullWidth.size()
                      << " last_codepoint=0x" << std::hex
                      << (afterFullWidth.empty() ? 0u : static_cast<unsigned>(afterFullWidth.back()))
                      << std::dec << '\n';
            throw std::runtime_error("full-width letter did not commit through the TSF edit session");
        }
        if (!yime::experiment::ApplyExperimentSettingsCommand(
                yime::experiment::ExperimentSettingsCommand::ShapeHalf,
                yime::experiment::ResolveExperimentSettingsPath(), &seededSettings)) {
            throw std::runtime_error("could not restore half-width output");
        }

        require(languageModeButton->OnClick(TF_LBI_CLK_LEFT, {}, nullptr), "toggle input mode to Chinese");
        testEaten = FALSE;
        require(keys->OnTestKeyDown(context, 'L', 0, &testEaten), "Chinese mode test key");
        if (!testEaten) throw std::runtime_error("Chinese mode did not reclaim composition keys");
        eaten = FALSE;
        require(keys->OnKeyDown(context, 'L', 0, &eaten), "Chinese mode key");
        if (!eaten || !hasComposition(context)) throw std::runtime_error("Chinese mode did not start composition");
        terminateActiveComposition(context);
        std::cout << "language_bar_chinese_english_transition_verified=true\n";

        languageModeButton->Release();
        keys->Release();
        require(processor->Deactivate(), "deactivate processor");
        languageBarItem = nullptr;
        const HRESULT removed = languageBarManager->GetItem(GUID_YimeTextServiceExperimentLangBar, &languageBarItem);
        if (removed == S_OK || languageBarItem != nullptr) {
            if (removed == S_OK && languageBarItem) languageBarItem->Release();
            throw std::runtime_error("experiment language bar item remained after deactivation");
        }
        languageBarManager->Release();
        processor->Release();
        document->Pop(TF_POPF_ALL);
        context->Release();
        document->Release();
        threadManager->Deactivate();
        threadManager->Release();
        FreeLibrary(module);
        SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", nullptr);
        SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST", nullptr);
        CoUninitialize();
        std::cout << "YimeTextService E6-B2b TSF composition passed architecture_bits=" << sizeof(void*) * 8 << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
