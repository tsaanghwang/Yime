#include <windows.h>
#include <msctf.h>
#include <textstor.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <iostream>
#include <string>
#include <thread>

#include "YimeTextServiceIds.h"

namespace {

constexpr LANGID kLanguageId = MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_SIMPLIFIED);

void require(HRESULT result, const char* operation) {
    if (FAILED(result)) {
        throw std::runtime_error(std::string(operation) + " failed: " +
                                 std::to_string(static_cast<unsigned long>(result)));
    }
}

void pumpMessages() {
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
}

class ContextOwner final : public ITextStoreACP {
public:
    explicit ContextOwner(HWND window) noexcept : window_(window) {}
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, __uuidof(ITextStoreACP))) return E_NOINTERFACE;
        *object = static_cast<ITextStoreACP*>(this);
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG left = --references_;
        if (!left) delete this;
        return left;
    }
    STDMETHODIMP AdviseSink(REFIID iid, IUnknown* unknown, DWORD) override {
        if (!unknown || !IsEqualIID(iid, __uuidof(ITextStoreACPSink))) return E_INVALIDARG;
        ITextStoreACPSink* sink = nullptr;
        const HRESULT result = unknown->QueryInterface(iid, reinterpret_cast<void**>(&sink));
        if (FAILED(result)) return result;
        if (sink_) sink_->Release();
        sink_ = sink;
        return S_OK;
    }
    STDMETHODIMP UnadviseSink(IUnknown*) override {
        if (sink_) {
            sink_->Release();
            sink_ = nullptr;
        }
        return S_OK;
    }
    STDMETHODIMP RequestLock(DWORD flags, HRESULT* sessionResult) override {
        if (!sessionResult) return E_POINTER;
        if (!sink_) return E_UNEXPECTED;
        if (lockFlags_) {
            *sessionResult = (flags & TS_LF_SYNC) ? TS_E_SYNCHRONOUS : TS_S_ASYNC;
            return S_OK;
        }
        lockFlags_ = flags;
        *sessionResult = sink_->OnLockGranted(flags);
        lockFlags_ = 0;
        return S_OK;
    }
    STDMETHODIMP GetStatus(TS_STATUS* status) override {
        if (!status) return E_POINTER;
        status->dwDynamicFlags = 0;
        status->dwStaticFlags = TS_SS_NOHIDDENTEXT;
        return S_OK;
    }
    STDMETHODIMP QueryInsert(LONG start, LONG end, ULONG count, LONG* resultStart,
                             LONG* resultEnd) override {
        if (!resultStart || !resultEnd || !ValidRange(start, end)) return E_INVALIDARG;
        *resultStart = start;
        *resultEnd = start + static_cast<LONG>(count);
        return S_OK;
    }
    STDMETHODIMP GetSelection(ULONG index, ULONG count, TS_SELECTION_ACP* selection,
                              ULONG* fetched) override {
        if (!selection || !fetched || count == 0 || (index != TS_DEFAULT_SELECTION && index != 0)) return E_INVALIDARG;
        selection[0].acpStart = selectionStart_;
        selection[0].acpEnd = selectionEnd_;
        selection[0].style.ase = TS_AE_NONE;
        selection[0].style.fInterimChar = FALSE;
        *fetched = 1;
        return S_OK;
    }
    STDMETHODIMP SetSelection(ULONG count, const TS_SELECTION_ACP* selection) override {
        if (!selection || count != 1 || !ValidRange(selection[0].acpStart, selection[0].acpEnd)) return E_INVALIDARG;
        selectionStart_ = selection[0].acpStart;
        selectionEnd_ = selection[0].acpEnd;
        return S_OK;
    }
    STDMETHODIMP GetText(LONG start, LONG end, WCHAR* plain, ULONG plainCapacity,
                         ULONG* plainCount, TS_RUNINFO* runInfo, ULONG runInfoCapacity,
                         ULONG* runInfoCount, LONG* next) override {
        if (!plainCount || !runInfoCount || !next) return E_POINTER;
        if (end == -1) end = static_cast<LONG>(text_.size());
        if (!ValidRange(start, end)) return TS_E_INVALIDPOS;
        const ULONG available = static_cast<ULONG>(end - start);
        const ULONG copied = std::min(plainCapacity, available);
        if (copied && !plain) return E_POINTER;
        if (copied) CopyMemory(plain, text_.data() + start, copied * sizeof(wchar_t));
        *plainCount = copied;
        *runInfoCount = 0;
        if (runInfo && runInfoCapacity && copied) {
            runInfo[0].uCount = copied;
            runInfo[0].type = TS_RT_PLAIN;
            *runInfoCount = 1;
        }
        *next = start + static_cast<LONG>(copied);
        return S_OK;
    }
    STDMETHODIMP SetText(DWORD, LONG start, LONG end, const WCHAR* text, ULONG count,
                         TS_TEXTCHANGE* change) override {
        if (!change || (count && !text) || !ValidRange(start, end)) return E_INVALIDARG;
        return Replace(start, end, text, count, change);
    }
    STDMETHODIMP GetFormattedText(LONG, LONG, IDataObject** object) override {
        if (object) *object = nullptr;
        return E_NOTIMPL;
    }
    STDMETHODIMP GetEmbedded(LONG, REFGUID, REFIID, IUnknown** object) override {
        if (object) *object = nullptr;
        return E_NOTIMPL;
    }
    STDMETHODIMP QueryInsertEmbedded(const GUID*, const FORMATETC*, BOOL* insertable) override {
        if (!insertable) return E_POINTER;
        *insertable = FALSE;
        return S_OK;
    }
    STDMETHODIMP InsertEmbedded(DWORD, LONG, LONG, IDataObject*, TS_TEXTCHANGE*) override {
        return E_NOTIMPL;
    }
    STDMETHODIMP InsertTextAtSelection(DWORD flags, const WCHAR* text, ULONG count,
                                       LONG* start, LONG* end, TS_TEXTCHANGE* change) override {
        if ((count && !text) || !start || !end) return E_INVALIDARG;
        *start = selectionStart_;
        *end = selectionStart_ + static_cast<LONG>(count);
        if (flags & TS_IAS_QUERYONLY) return S_OK;
        if (!change) return E_POINTER;
        return Replace(selectionStart_, selectionEnd_, text, count, change);
    }
    STDMETHODIMP InsertEmbeddedAtSelection(DWORD, IDataObject*, LONG*, LONG*,
                                           TS_TEXTCHANGE*) override {
        return E_NOTIMPL;
    }
    STDMETHODIMP RequestSupportedAttrs(DWORD, ULONG, const TS_ATTRID*) override { return S_OK; }
    STDMETHODIMP RequestAttrsAtPosition(LONG, ULONG, const TS_ATTRID*, DWORD) override { return S_OK; }
    STDMETHODIMP RequestAttrsTransitioningAtPosition(LONG, ULONG, const TS_ATTRID*, DWORD) override { return S_OK; }
    STDMETHODIMP FindNextAttrTransition(LONG, LONG halt, ULONG, const TS_ATTRID*, DWORD,
                                        LONG* next, BOOL* found, LONG* offset) override {
        if (!next || !found || !offset) return E_POINTER;
        *next = halt;
        *found = FALSE;
        *offset = 0;
        return S_OK;
    }
    STDMETHODIMP RetrieveRequestedAttrs(ULONG, TS_ATTRVAL*, ULONG* fetched) override {
        if (!fetched) return E_POINTER;
        *fetched = 0;
        return S_OK;
    }
    STDMETHODIMP GetEndACP(LONG* end) override {
        if (!end) return E_POINTER;
        *end = static_cast<LONG>(text_.size());
        return S_OK;
    }
    STDMETHODIMP GetActiveView(TsViewCookie* view) override {
        if (!view) return E_POINTER;
        *view = 1;
        return S_OK;
    }
    STDMETHODIMP GetACPFromPoint(TsViewCookie, const POINT*, DWORD, LONG*) override { return E_NOTIMPL; }
    STDMETHODIMP GetTextExt(TsViewCookie, LONG, LONG, RECT* rectangle, BOOL* clipped) override {
        if (!rectangle || !clipped) return E_POINTER;
        RECT client{32, 42, 160, 66};
        POINT topLeft{client.left, client.top};
        POINT bottomRight{client.right, client.bottom};
        ClientToScreen(window_, &topLeft);
        ClientToScreen(window_, &bottomRight);
        *rectangle = {topLeft.x, topLeft.y, bottomRight.x, bottomRight.y};
        *clipped = FALSE;
        ++textExtentCalls_;
        return S_OK;
    }
    STDMETHODIMP GetScreenExt(TsViewCookie, RECT* rectangle) override {
        return rectangle && GetWindowRect(window_, rectangle) ? S_OK : E_INVALIDARG;
    }
    STDMETHODIMP GetWnd(TsViewCookie, HWND* window) override {
        if (!window) return E_POINTER;
        *window = window_;
        return S_OK;
    }
    unsigned TextExtentCalls() const noexcept { return textExtentCalls_; }

private:
    ~ContextOwner() {
        if (sink_) sink_->Release();
    }
    bool ValidRange(LONG start, LONG end) const noexcept {
        return start >= 0 && end >= start && end <= static_cast<LONG>(text_.size());
    }
    HRESULT Replace(LONG start, LONG end, const WCHAR* text, ULONG count,
                    TS_TEXTCHANGE* change) {
        change->acpStart = start;
        change->acpOldEnd = end;
        change->acpNewEnd = start + static_cast<LONG>(count);
        text_.replace(static_cast<size_t>(start), static_cast<size_t>(end - start),
                      text ? text : L"", count);
        selectionStart_ = change->acpNewEnd;
        selectionEnd_ = change->acpNewEnd;
        return S_OK;
    }
    std::atomic<ULONG> references_{1};
    HWND window_;
    ITextStoreACPSink* sink_ = nullptr;
    DWORD lockFlags_ = 0;
    std::wstring text_;
    LONG selectionStart_ = 0;
    LONG selectionEnd_ = 0;
    std::atomic<unsigned> textExtentCalls_{0};
};

class ReadSession final : public ITfEditSession {
public:
    explicit ReadSession(ITfContext* context) : context_(context) { context_->AddRef(); }
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, __uuidof(ITfEditSession))) return E_NOINTERFACE;
        *object = static_cast<ITfEditSession*>(this);
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG left = --references_;
        if (!left) delete this;
        return left;
    }
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
    const std::wstring& Text() const noexcept { return text_; }

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
    const std::wstring text = session->Text();
    session->Release();
    require(request, "request read session");
    require(sessionResult, "run read session");
    return text;
}

bool waitForForeground(ITfKeystrokeMgr* keystrokes) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    do {
        pumpMessages();
        CLSID foreground{};
        if (keystrokes->GetForeground(&foreground) == S_OK &&
            IsEqualGUID(foreground, CLSID_YimeTextServiceExperiment)) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    } while (std::chrono::steady_clock::now() < deadline);
    return false;
}

bool waitForVisibility(HWND window, bool visible) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    do {
        pumpMessages();
        if ((IsWindowVisible(window) != FALSE) == visible) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    } while (std::chrono::steady_clock::now() < deadline);
    return false;
}

void dispatchKey(ITfKeystrokeMgr* keystrokes, WPARAM key) {
    BOOL eaten = FALSE;
    require(keystrokes->TestKeyDown(key, 0, &eaten), "registered TestKeyDown");
    if (!eaten) throw std::runtime_error("registered key sink did not claim TestKeyDown");
    eaten = FALSE;
    require(keystrokes->KeyDown(key, 0, &eaten), "registered KeyDown");
    if (!eaten) throw std::runtime_error("registered key sink did not claim KeyDown");
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    ITfInputProcessorProfileMgr* profiles = nullptr;
    try {
        std::cout << std::unitbuf;
        std::cerr << std::unitbuf;
        if (argc != 2) throw std::runtime_error("usage: YimeRegisteredHostTests <pipe>");
        require(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED), "CoInitializeEx");
        SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", argv[1]);
        SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST", nullptr);

        WNDCLASSW windowClass{};
        windowClass.lpfnWndProc = DefWindowProcW;
        windowClass.hInstance = GetModuleHandleW(nullptr);
        windowClass.lpszClassName = L"YimeRegisteredHostTestWindow";
        RegisterClassW(&windowClass);
        HWND window = CreateWindowExW(0, windowClass.lpszClassName, L"Yime registered host test",
                                      WS_OVERLAPPEDWINDOW, 160, 160, 640, 240, nullptr, nullptr,
                                      windowClass.hInstance, nullptr);
        if (!window) throw std::runtime_error("create registered host window failed");
        ShowWindow(window, SW_SHOWNOACTIVATE);
        auto* owner = new ContextOwner(window);

        require(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                                 __uuidof(ITfInputProcessorProfileMgr), reinterpret_cast<void**>(&profiles)),
                "create profile manager");
        TF_INPUTPROCESSORPROFILE profile{};
        require(profiles->GetProfile(TF_PROFILETYPE_INPUTPROCESSOR, kLanguageId,
                                     CLSID_YimeTextServiceExperiment,
                                     GUID_YimeTextServiceExperimentProfile, nullptr, &profile),
                "get registered experiment profile");

        ITfThreadMgr* threadManager = nullptr;
        require(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER,
                                 __uuidof(ITfThreadMgr), reinterpret_cast<void**>(&threadManager)),
                "create thread manager");
        TfClientId clientId = TF_CLIENTID_NULL;
        require(threadManager->Activate(&clientId), "activate thread manager");
        ITfDocumentMgr* document = nullptr;
        require(threadManager->CreateDocumentMgr(&document), "create document manager");
        ITfContext* context = nullptr;
        TfEditCookie ownerCookie = 0;
        require(document->CreateContext(clientId, 0, owner, &context, &ownerCookie), "create owner context");
        require(document->Push(context), "push owner context");
        require(threadManager->SetFocus(document), "focus owner document");

        ITfKeystrokeMgr* keystrokes = nullptr;
        require(threadManager->QueryInterface(__uuidof(ITfKeystrokeMgr),
                                              reinterpret_cast<void**>(&keystrokes)),
                "query keystroke manager");
        ITfInputProcessorProfiles* languageProfiles = nullptr;
        require(profiles->QueryInterface(__uuidof(ITfInputProcessorProfiles),
                                         reinterpret_cast<void**>(&languageProfiles)),
                "query language profiles");
        const HRESULT changedLanguage = languageProfiles->ChangeCurrentLanguage(kLanguageId);
        const HRESULT enabledProfile = languageProfiles->EnableLanguageProfile(
            CLSID_YimeTextServiceExperiment, kLanguageId, GUID_YimeTextServiceExperimentProfile, TRUE);
        const HRESULT activatedProfile = languageProfiles->ActivateLanguageProfile(
            CLSID_YimeTextServiceExperiment, kLanguageId, GUID_YimeTextServiceExperimentProfile);
        LANGID currentLanguage = 0;
        const HRESULT currentLanguageResult = languageProfiles->GetCurrentLanguage(&currentLanguage);
        LANGID activeLanguage = 0;
        GUID activeProfile{};
        const HRESULT activeProfileResult = languageProfiles->GetActiveLanguageProfile(
            CLSID_YimeTextServiceExperiment, &activeLanguage, &activeProfile);
        std::cout << std::hex
                  << "change_language_hresult=0x" << static_cast<unsigned long>(changedLanguage) << '\n'
                  << "enable_profile_hresult=0x" << static_cast<unsigned long>(enabledProfile) << '\n'
                  << "activate_profile_hresult=0x" << static_cast<unsigned long>(activatedProfile) << '\n'
                  << "current_language_hresult=0x" << static_cast<unsigned long>(currentLanguageResult) << '\n'
                  << "current_language=0x" << currentLanguage << '\n'
                  << "active_profile_hresult=0x" << static_cast<unsigned long>(activeProfileResult) << '\n'
                  << "active_profile_language=0x" << activeLanguage << std::dec << '\n';
        if (changedLanguage != S_OK || enabledProfile != S_OK || activatedProfile != S_OK ||
            currentLanguageResult != S_OK || currentLanguage != kLanguageId ||
            activeProfileResult != S_OK || activeLanguage != kLanguageId ||
            !IsEqualGUID(activeProfile, GUID_YimeTextServiceExperimentProfile)) {
            throw std::runtime_error("registered profile did not become the active zh-CN profile");
        }
        SetFocus(window);
        threadManager->SetFocus(nullptr);
        require(threadManager->SetFocus(document), "refocus owner document after profile activation");
        if (!waitForForeground(keystrokes)) throw std::runtime_error("registered TIP did not become foreground");

        ITfLangBarItemMgr* languageBar = nullptr;
        require(threadManager->QueryInterface(__uuidof(ITfLangBarItemMgr),
                                              reinterpret_cast<void**>(&languageBar)),
                "query language bar manager");
        ITfLangBarItem* languageBarItem = nullptr;
        const HRESULT languageBarLookup =
            languageBar->GetItem(GUID_YimeTextServiceExperimentLangBar, &languageBarItem);
        const bool languageBarAccepted = languageBarLookup == S_OK && languageBarItem != nullptr;
        if (languageBarItem) languageBarItem->Release();

        const std::string code = "2jru";
        for (char character : code) {
            const WPARAM key = character >= 'a' ? static_cast<WPARAM>(character - 'a' + 'A')
                                                 : static_cast<WPARAM>(character);
            dispatchKey(keystrokes, key);
        }
        if (readContext(context, clientId) != L"2jru") {
            throw std::runtime_error("registered host composition mismatch");
        }
        HWND popup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (!popup || !IsWindowVisible(popup)) throw std::runtime_error("registered owned popup missing");
        if (!GetPropW(popup, L"YimeTextServiceExperimentTextExtentAnchor") || owner->TextExtentCalls() == 0) {
            throw std::runtime_error("registered host did not position popup through GetTextExt");
        }
        RECT popupBounds{};
        GetWindowRect(popup, &popupBounds);
        RECT expected{};
        BOOL clipped = FALSE;
        owner->GetTextExt(1, 0, 4, &expected, &clipped);
        if (popupBounds.left != expected.left || popupBounds.top != expected.bottom) {
            throw std::runtime_error("registered popup position does not follow the TSF text extent");
        }

        BYTE keyboard[256]{};
        GetKeyboardState(keyboard);
        BYTE shifted[256]{};
        CopyMemory(shifted, keyboard, sizeof(keyboard));
        shifted[VK_SHIFT] = 0x80;
        shifted[VK_LSHIFT] = 0x80;
        SetKeyboardState(shifted);
        dispatchKey(keystrokes, '1');
        SetKeyboardState(keyboard);
        if (readContext(context, clientId) != L"秋") throw std::runtime_error("registered candidate commit mismatch");

        dispatchKey(keystrokes, '2');
        popup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (!popup || !IsWindowVisible(popup)) {
            throw std::runtime_error("registered focus setup popup missing");
        }
        auto* otherOwner = new ContextOwner(window);
        ITfDocumentMgr* otherDocument = nullptr;
        require(threadManager->CreateDocumentMgr(&otherDocument), "create registered focus document");
        ITfContext* otherContext = nullptr;
        TfEditCookie otherOwnerCookie = 0;
        require(otherDocument->CreateContext(clientId, 0, otherOwner, &otherContext, &otherOwnerCookie),
                "create registered focus context");
        require(otherDocument->Push(otherContext), "push registered focus context");
        require(threadManager->SetFocus(otherDocument), "switch registered document focus");
        if (!waitForVisibility(popup, false)) {
            throw std::runtime_error("registered focus loss did not hide candidates");
        }
        BOOL crossContextEaten = TRUE;
        require(keystrokes->TestKeyDown('J', 0, &crossContextEaten), "registered cross-context TestKeyDown");
        if (crossContextEaten) {
            throw std::runtime_error("registered focus callback did not isolate the old composition");
        }
        const bool hostTerminatedComposition = !IsWindow(popup);
        require(threadManager->SetFocus(document), "restore registered document focus");
        if (hostTerminatedComposition) {
            BOOL postTerminationEaten = TRUE;
            require(keystrokes->TestKeyDown('J', 0, &postTerminationEaten),
                    "registered post-termination TestKeyDown");
            if (postTerminationEaten) {
                throw std::runtime_error("registered host termination left the Broker session active");
            }
        } else {
            if (!waitForVisibility(popup, true)) {
                throw std::runtime_error("registered focus restore did not show preserved candidates");
            }
            SetKeyboardState(shifted);
            dispatchKey(keystrokes, '1');
            SetKeyboardState(keyboard);
        }

        std::cout << "registered_key_sink_verified=true\n"
                  << "registered_language_bar_accepted=" << (languageBarAccepted ? "true" : "false") << '\n'
                  << "registered_text_extent_anchor=true\n"
                  << "registered_focus_callbacks_verified=true\n"
                  << "registered_focus_outcome="
                  << (hostTerminatedComposition ? "host_terminated_cleanly" : "composition_resumed") << '\n'
                  << "registered_candidate_commit=true\n"
                  << "architecture_bits=" << sizeof(void*) * 8 << '\n';

        profiles->DeactivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, kLanguageId,
                                    CLSID_YimeTextServiceExperiment,
                                    GUID_YimeTextServiceExperimentProfile, nullptr,
                                    TF_IPPMF_FORPROCESS);
        languageProfiles->Release();
        languageBar->Release();
        keystrokes->Release();
        otherDocument->Pop(TF_POPF_ALL);
        otherContext->Release();
        otherDocument->Release();
        otherOwner->Release();
        document->Pop(TF_POPF_ALL);
        context->Release();
        document->Release();
        threadManager->Deactivate();
        threadManager->Release();
        profiles->Release();
        profiles = nullptr;
        owner->Release();
        DestroyWindow(window);
        SetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_PIPE", nullptr);
        CoUninitialize();
        return 0;
    } catch (const std::exception& error) {
        if (profiles) profiles->Release();
        std::cerr << error.what() << '\n';
        return 1;
    }
}
