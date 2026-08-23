#include <windows.h>
#include <msctf.h>

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
        if (firstCandidate != L"⇧1  秋") throw std::runtime_error("candidate UI Shift label or text mismatch");

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

        eaten = FALSE;
        require(keys->OnKeyDown(context, '2', 0, &eaten), "post-commit key down");
        if (!eaten || readContext(context, clientId) != L"秋2" || !hasComposition(context)) {
            throw std::runtime_error("normal commit incorrectly closed the Broker session");
        }
        SetKeyboardState(shifted);
        eaten = FALSE;
        require(keys->OnKeyDown(context, '1', 0, &eaten), "second candidate key down");
        SetKeyboardState(keyboard);
        const std::wstring secondCommit = readContext(context, clientId);
        if (!eaten || secondCommit.size() != 2 || secondCommit.front() != L'秋' ||
            secondCommit.back() == L'2' || hasComposition(context)) {
            throw std::runtime_error("second TSF commit mismatch");
        }

        eaten = FALSE;
        require(keys->OnKeyDown(context, '2', 0, &eaten), "forced-termination setup key");
        if (!eaten || !hasComposition(context)) throw std::runtime_error("forced-termination setup failed");
        terminateActiveComposition(context);
        if (hasComposition(context)) throw std::runtime_error("host-forced composition remained active");
        BOOL testEaten = TRUE;
        require(keys->OnTestKeyDown(context, 'J', 0, &testEaten), "post-termination test key");
        if (testEaten) throw std::runtime_error("host-forced termination did not close the Broker session");
        eaten = TRUE;
        require(keys->OnKeyDown(context, 'J', 0, &eaten), "post-termination key");
        if (eaten) throw std::runtime_error("post-termination key was swallowed");

        keys->Release();
        require(processor->Deactivate(), "deactivate processor");
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
