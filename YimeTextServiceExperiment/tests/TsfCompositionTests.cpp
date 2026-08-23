#include <windows.h>
#include <msctf.h>
#include <ctfutb.h>

#include <atomic>
#include <iostream>
#include <string>

#include "YimeTextServiceIds.h"

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

}  // namespace

int wmain(int argc, wchar_t** argv) {
    try {
        if (argc != 3) throw std::runtime_error("usage: YimeTsfCompositionTests <dll> <pipe>");
        require(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED), "CoInitializeEx");
        SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", argv[2]);
        SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST", L"1");
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
        const HRESULT languageBarLookup =
            languageBarManager->GetItem(GUID_YimeTextServiceExperimentLangBar, &languageBarItem);
        const bool languageBarManagerAccepted = languageBarLookup == S_OK && languageBarItem;
        if (languageBarManagerAccepted) {
            TF_LANGBARITEMINFO languageBarInfo{};
            require(languageBarItem->GetInfo(&languageBarInfo), "read experiment language bar item");
            if (!IsEqualGUID(languageBarInfo.clsidService, CLSID_YimeTextServiceExperiment) ||
                languageBarInfo.dwStyle != TF_LBI_STYLE_BTN_BUTTON) {
                throw std::runtime_error("experiment language bar identity or style mismatch");
            }
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
                    if (!navigationEaten || readContext(context, clientId) != L"2" || !hasComposition(context)) {
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
        if (!candidateElement) throw std::runtime_error("candidate UI exited on an invalid code");
        candidateCount = 0;
        require(candidateElement->GetCount(&candidateCount), "empty candidate UI count");
        candidateText = nullptr;
        require(candidateElement->GetString(0, &candidateText), "empty candidate UI status");
        const std::wstring emptyCandidateStatus(candidateText ? candidateText : L"");
        SysFreeString(candidateText);
        candidateElement->Release();
        if (candidateCount != 1 || emptyCandidateStatus != L"无匹配候选，按退格修改" ||
            !IsWindowVisible(candidatePopup)) {
            throw std::runtime_error("invalid-code candidate UI did not preserve a correction affordance");
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
            eaten = FALSE;
            require(keys->OnKeyDown(context, '2', 0, &eaten), "default-selection setup key down");
            if (!eaten || !hasComposition(context)) {
                throw std::runtime_error("default-selection setup did not create a composition");
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
                afterDefaultCommit.back() == L'2' || hasComposition(context)) {
                throw std::runtime_error("Enter/Space did not commit the first candidate");
            }
        }
        std::cout << "default_candidate_keys_verified=true\n";

        eaten = FALSE;
        require(keys->OnKeyDown(context, '2', 0, &eaten), "post-commit key down");
        const std::wstring preMouseComposition = readContext(context, clientId);
        if (!eaten || preMouseComposition.empty() || preMouseComposition.back() != L'2' || !hasComposition(context)) {
            throw std::runtime_error("normal commit incorrectly closed the Broker session");
        }
        candidatePopup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (!candidatePopup || !IsWindowVisible(candidatePopup)) {
            throw std::runtime_error("owned candidate popup missing before mouse selection");
        }
        RECT popupClient{};
        GetClientRect(candidatePopup, &popupClient);
        SendMessageW(candidatePopup, WM_LBUTTONUP, 0, MAKELPARAM(20, 10));
        const std::wstring secondCommit = readContext(context, clientId);
        if (secondCommit.size() <= preMouseComposition.size() - 1 || secondCommit.front() != L'秋' ||
            secondCommit.back() == L'2' || hasComposition(context)) {
            throw std::runtime_error("mouse-selected TSF commit mismatch");
        }
        std::cout << "mouse_candidate_selection_verified=true\n";

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
