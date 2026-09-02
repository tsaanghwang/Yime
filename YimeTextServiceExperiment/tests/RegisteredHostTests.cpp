#include <windows.h>
#include <msctf.h>
#include <textstor.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <iostream>
#include <string>
#include <thread>

#include "ExperimentSettings.h"
#include "LanguageBarItem.h"
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
        if (rejectSynchronousWrites_ && (flags & TS_LF_SYNC) &&
            (flags & TS_LF_READWRITE) == TS_LF_READWRITE) {
            ++rejectedSynchronousWrites_;
            *sessionResult = TS_E_SYNCHRONOUS;
            return S_OK;
        }
        if (lockFlags_) {
            *sessionResult = (flags & TS_LF_SYNC) ? TS_E_SYNCHRONOUS : TS_S_ASYNC;
            return S_OK;
        }
        if (delayAsynchronousWrites_ && !(flags & TS_LF_SYNC) &&
            (flags & TS_LF_READWRITE) == TS_LF_READWRITE) {
            pendingLockFlags_ = flags;
            *sessionResult = TS_S_ASYNC;
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
        if (failWrites_) {
            failWrites_ = false;
            ++failedWrites_;
            return E_FAIL;
        }
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
        if (failWrites_ && !(flags & TS_IAS_QUERYONLY)) {
            failWrites_ = false;
            ++failedWrites_;
            return E_FAIL;
        }
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
    void RejectSynchronousWrites(bool reject) noexcept { rejectSynchronousWrites_ = reject; }
    unsigned RejectedSynchronousWrites() const noexcept { return rejectedSynchronousWrites_; }
    unsigned FailedWrites() const noexcept { return failedWrites_; }
    void DelayAsynchronousWrites(bool delay) noexcept { delayAsynchronousWrites_ = delay; }
    bool HasPendingLock() const noexcept { return pendingLockFlags_ != 0; }
    HRESULT CompletePendingLock(bool failWrites) noexcept {
        if (!sink_ || !pendingLockFlags_) return E_UNEXPECTED;
        const DWORD flags = pendingLockFlags_;
        pendingLockFlags_ = 0;
        delayAsynchronousWrites_ = false;
        failWrites_ = failWrites;
        lockFlags_ = flags;
        const HRESULT result = sink_->OnLockGranted(flags);
        lockFlags_ = 0;
        return result;
    }

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
    bool rejectSynchronousWrites_ = false;
    unsigned rejectedSynchronousWrites_ = 0;
    bool delayAsynchronousWrites_ = false;
    bool failWrites_ = false;
    unsigned failedWrites_ = 0;
    DWORD pendingLockFlags_ = 0;
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

ITfCandidateListUIElement* findCandidateElement(ITfThreadMgr* threadManager) {
    ITfUIElementMgr* manager = nullptr;
    if (FAILED(threadManager->QueryInterface(__uuidof(ITfUIElementMgr),
                                             reinterpret_cast<void**>(&manager)))) return nullptr;
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
        if (SUCCEEDED(element->GetGUID(&guid)) &&
            IsEqualGUID(guid, GUID_YimeTextServiceExperimentCandidateList)) {
            element->QueryInterface(__uuidof(ITfCandidateListUIElement),
                                    reinterpret_cast<void**>(&found));
        }
        element->Release();
        if (found) break;
    }
    values->Release();
    return found;
}

std::wstring candidateTextFromRow(const std::wstring& row) {
    const size_t labelEnd = row.find(L"  ");
    if (labelEnd == std::wstring::npos) return {};
    const size_t textStart = labelEnd + 2;
    const size_t textEnd = row.find(L"  ", textStart);
    return row.substr(textStart, textEnd == std::wstring::npos ? std::wstring::npos
                                                               : textEnd - textStart);
}

bool waitForForeground(ITfKeystrokeMgr* keystrokes) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
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
        ShowWindow(window, SW_SHOW);
        SetForegroundWindow(window);
        SetFocus(window);
        UpdateWindow(window);
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
        const HRESULT activatedProcessProfile = profiles->ActivateProfile(
            TF_PROFILETYPE_INPUTPROCESSOR, kLanguageId, CLSID_YimeTextServiceExperiment,
            GUID_YimeTextServiceExperimentProfile, nullptr, TF_IPPMF_FORPROCESS);
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
                  << "activate_process_profile_hresult=0x"
                  << static_cast<unsigned long>(activatedProcessProfile) << '\n'
                  << "current_language_hresult=0x" << static_cast<unsigned long>(currentLanguageResult) << '\n'
                  << "current_language=0x" << currentLanguage << '\n'
                  << "active_profile_hresult=0x" << static_cast<unsigned long>(activeProfileResult) << '\n'
                  << "active_profile_language=0x" << activeLanguage << std::dec << '\n';
        if (changedLanguage != S_OK || enabledProfile != S_OK || activatedProfile != S_OK ||
            activatedProcessProfile != S_OK ||
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

        wchar_t toolMenuSmokeValue[8]{};
        const bool runToolMenuSmoke =
            GetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_TOOL_MENU_SMOKE",
                                    toolMenuSmokeValue, _countof(toolMenuSmokeValue)) != 0;

        // Reproduce the registered-host sequence used by Word: the TIP sees
        // Shift down and the test callback for a pass-through key, but it does
        // not receive KeyDown for that key after returning eaten=FALSE.
        yime::experiment::ExperimentSettings shiftChordSettings;
        if (!yime::experiment::ApplyExperimentSettingsCommand(
                yime::experiment::ExperimentSettingsCommand::PunctuationEnglish,
                yime::experiment::ResolveExperimentSettingsPath(), &shiftChordSettings) ||
            !yime::experiment::ApplyExperimentSettingsCommand(
                yime::experiment::ExperimentSettingsCommand::ShapeHalf,
                yime::experiment::ResolveExperimentSettingsPath(), &shiftChordSettings) ||
            !yime::experiment::ApplyExperimentSettingsCommand(
                yime::experiment::ExperimentSettingsCommand::English,
                yime::experiment::ResolveExperimentSettingsPath(), &shiftChordSettings)) {
            throw std::runtime_error("could not seed registered English Shift-chord state");
        }
        auto verifyRegisteredEnglishShiftPassThrough = [&](WPARAM key, bool controlDown,
                                                           bool altDown) {
            BOOL shiftEaten = FALSE;
            require(keystrokes->TestKeyDown(VK_SHIFT, 0, &shiftEaten),
                    "registered English Shift probe");
            if (!shiftEaten) throw std::runtime_error("registered English mode did not claim Shift down");
            shiftEaten = FALSE;
            require(keystrokes->KeyDown(VK_SHIFT, 0, &shiftEaten),
                    "registered English Shift down");
            if (!shiftEaten) throw std::runtime_error("registered English mode did not handle Shift down");

            BYTE keyboard[256]{};
            GetKeyboardState(keyboard);
            BYTE modified[256]{};
            CopyMemory(modified, keyboard, sizeof(keyboard));
            modified[VK_SHIFT] = 0x80;
            modified[VK_LSHIFT] = 0x80;
            if (controlDown) modified[VK_CONTROL] = 0x80;
            if (altDown) modified[VK_MENU] = 0x80;
            SetKeyboardState(modified);
            BOOL chordEaten = TRUE;
            require(keystrokes->TestKeyDown(key, 0, &chordEaten),
                    "registered English Shift-chord pass-through probe");
            SetKeyboardState(keyboard);
            if (chordEaten) {
                throw std::runtime_error("registered English Shift chord did not pass through");
            }

            BOOL shiftUpEaten = FALSE;
            require(keystrokes->TestKeyUp(VK_SHIFT, 0, &shiftUpEaten),
                    "registered English Shift-up probe");
            if (!shiftUpEaten) throw std::runtime_error("registered English mode did not claim Shift up");
            shiftUpEaten = FALSE;
            require(keystrokes->KeyUp(VK_SHIFT, 0, &shiftUpEaten),
                    "registered English Shift up");
            if (!shiftUpEaten) throw std::runtime_error("registered English mode did not handle Shift up");
            if (!yime::experiment::LoadExperimentSettings().asciiMode) {
                throw std::runtime_error("registered English Shift chord toggled back to Chinese");
            }
        };
        for (const WPARAM key : {static_cast<WPARAM>('T'), static_cast<WPARAM>('1'),
                                 static_cast<WPARAM>(VK_OEM_COMMA), static_cast<WPARAM>(VK_SPACE),
                                 static_cast<WPARAM>(VK_TAB), static_cast<WPARAM>(VK_LEFT),
                                 static_cast<WPARAM>(VK_F1)}) {
            verifyRegisteredEnglishShiftPassThrough(key, false, false);
        }
        verifyRegisteredEnglishShiftPassThrough('Z', true, false);
        verifyRegisteredEnglishShiftPassThrough(VK_TAB, false, true);
        std::cout << "registered_english_shift_passthrough_verified=true\n";
        if (!yime::experiment::ApplyExperimentSettingsCommand(
                yime::experiment::ExperimentSettingsCommand::Chinese,
                yime::experiment::ResolveExperimentSettingsPath(), &shiftChordSettings)) {
            throw std::runtime_error("could not restore registered Chinese mode");
        }

        const std::string code = "2jru";
        for (size_t index = 0; index < code.size(); ++index) {
            const char character = code[index];
            const WPARAM key = character >= 'a' ? static_cast<WPARAM>(character - 'a' + 'A')
                                                 : static_cast<WPARAM>(character);
            dispatchKey(keystrokes, key);
            if (index == 0) {
                ITfCandidateListUIElement* firstKeyElement = findCandidateElement(threadManager);
                UINT firstKeyCount = 0;
                if (!firstKeyElement || FAILED(firstKeyElement->GetCount(&firstKeyCount)) || firstKeyCount == 0) {
                    if (firstKeyElement) firstKeyElement->Release();
                    throw std::runtime_error("registered first key did not publish candidate UI");
                }
                firstKeyElement->Release();
                HWND firstKeyPopup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
                if (!firstKeyPopup || !IsWindowVisible(firstKeyPopup)) {
                    throw std::runtime_error("registered first key did not show the owned candidate popup");
                }
            }
            if (index + 1 == code.size()) {
                for (const WPARAM navigationKey : {static_cast<WPARAM>(VK_DOWN), static_cast<WPARAM>(VK_UP),
                                                   static_cast<WPARAM>(VK_NEXT), static_cast<WPARAM>(VK_LEFT)}) {
                    dispatchKey(keystrokes, navigationKey);
                    if (readContext(context, clientId) != L"2jru") {
                        throw std::runtime_error("registered direction/page key escaped into host text");
                    }
                }
            }
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

        dispatchKey(keystrokes, 'Z');
        if (readContext(context, clientId) != L"2jruz" || !IsWindow(popup) || !IsWindowVisible(popup)) {
            throw std::runtime_error("registered invalid code did not keep correction status visible");
        }
        dispatchKey(keystrokes, VK_BACK);
		popup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (readContext(context, clientId) != L"2jru" || !IsWindowVisible(popup)) {
            throw std::runtime_error("registered Backspace did not restore candidates");
        }
        dispatchKey(keystrokes, VK_BACK);
        dispatchKey(keystrokes, 'U');
        if (readContext(context, clientId) != L"2jru" || !IsWindowVisible(popup)) {
            throw std::runtime_error("registered deleted code resurrected after continued input");
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

        for (const WPARAM defaultSelectionKey : {static_cast<WPARAM>(VK_SPACE), static_cast<WPARAM>(VK_RETURN)}) {
            const std::wstring beforeDefaultCommit = readContext(context, clientId);
            dispatchKey(keystrokes, '2');
            dispatchKey(keystrokes, defaultSelectionKey);
            const std::wstring afterDefaultCommit = readContext(context, clientId);
            popup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
            if (afterDefaultCommit.size() <= beforeDefaultCommit.size() || afterDefaultCommit.back() == L'2' ||
                (popup && IsWindowVisible(popup))) {
                throw std::runtime_error("registered Enter/Space did not commit the first candidate");
            }
        }

        const std::wstring beforeMouseCommit = readContext(context, clientId);
        for (const char character : code) {
            const WPARAM key = character >= 'a'
                ? static_cast<WPARAM>(character - 'a' + 'A')
                : static_cast<WPARAM>(character);
            dispatchKey(keystrokes, key);
        }
        popup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (!popup || !IsWindowVisible(popup)) {
            throw std::runtime_error("registered mouse-selection popup missing");
        }
        ITfCandidateListUIElement* mouseCandidates = findCandidateElement(threadManager);
        if (!mouseCandidates) throw std::runtime_error("registered mouse candidate UI missing");
        UINT mouseCandidateCount = 0;
        require(mouseCandidates->GetCount(&mouseCandidateCount), "registered mouse candidate count");
        if (mouseCandidateCount < 2) {
            mouseCandidates->Release();
            throw std::runtime_error("registered mouse test needs a second candidate");
        }
        BSTR secondCandidateRow = nullptr;
        require(mouseCandidates->GetString(1, &secondCandidateRow), "registered second mouse candidate");
        const std::wstring expectedMouseCommit =
            candidateTextFromRow(secondCandidateRow ? secondCandidateRow : L"");
        SysFreeString(secondCandidateRow);
        mouseCandidates->Release();
        if (expectedMouseCommit.empty()) {
            throw std::runtime_error("registered second mouse candidate text was empty");
        }
        const int rowHeight = static_cast<int>(reinterpret_cast<UINT_PTR>(
            GetPropW(popup, L"YimeTextServiceExperimentCandidateRowHeight")));
        const bool hasSentenceRow = GetPropW(popup, L"YimeTextServiceExperimentSentenceRow") != nullptr;
        RECT popupClient{};
        GetClientRect(popup, &popupClient);
        if (rowHeight <= 0 || popupClient.right <= 16) {
            throw std::runtime_error("registered mouse popup geometry missing");
        }
        POINT clickPoint{popupClient.right / 2,
                         8 + rowHeight * (hasSentenceRow ? 2 : 1) + rowHeight / 2};
        ClientToScreen(popup, &clickPoint);
        owner->RejectSynchronousWrites(true);
        owner->DelayAsynchronousWrites(true);
        SetCursorPos(clickPoint.x, clickPoint.y);
        INPUT mouseInput[2]{};
        mouseInput[0].type = INPUT_MOUSE;
        mouseInput[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
        mouseInput[1].type = INPUT_MOUSE;
        mouseInput[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
        if (SendInput(2, mouseInput, sizeof(INPUT)) != 2) {
            owner->RejectSynchronousWrites(false);
            throw std::runtime_error("registered physical mouse click injection failed");
        }
        for (int attempt = 0; attempt < 100 && !owner->HasPendingLock(); ++attempt) {
            pumpMessages();
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        if (!owner->HasPendingLock() || !IsWindowVisible(popup) ||
            readContext(context, clientId) != beforeMouseCommit + L"2jru") {
            owner->RejectSynchronousWrites(false);
            throw std::runtime_error("registered asynchronous edit completed before the host granted its lock");
        }
        require(owner->CompletePendingLock(false), "grant delayed asynchronous edit lock");
        for (int attempt = 0; attempt < 10; ++attempt) {
            pumpMessages();
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        owner->RejectSynchronousWrites(false);
        const std::wstring afterMouseCommit = readContext(context, clientId);
        if (afterMouseCommit != beforeMouseCommit + expectedMouseCommit ||
            IsWindowVisible(popup)) {
            std::cerr << "registered physical mouse completion mismatch"
                      << " text_matches="
                      << (afterMouseCommit == beforeMouseCommit + expectedMouseCommit ? "true" : "false")
                      << " expected_length=" << (beforeMouseCommit.size() + expectedMouseCommit.size())
                      << " actual_length=" << afterMouseCommit.size()
                      << " popup_visible=" << (IsWindowVisible(popup) ? "true" : "false")
                      << "\n";
            throw std::runtime_error("registered physical mouse candidate did not use an asynchronous edit session");
        }
        std::cout << "physical_mouse_candidate_selection_verified=true\n";
        std::cout << "delayed_async_edit_completion_verified=true\n";

        const unsigned punctuationExtentCalls = owner->TextExtentCalls();
        BYTE punctuationKeyboard[256]{};
        GetKeyboardState(punctuationKeyboard);
        BYTE punctuationShifted[256]{};
        CopyMemory(punctuationShifted, punctuationKeyboard, sizeof(punctuationKeyboard));
        punctuationShifted[VK_SHIFT] = 0x80;
        punctuationShifted[VK_LSHIFT] = 0x80;
        SetKeyboardState(punctuationShifted);
        dispatchKey(keystrokes, VK_OEM_5);
        SetKeyboardState(punctuationKeyboard);
        popup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (!popup || !IsWindowVisible(popup) ||
            !GetPropW(popup, L"YimeTextServiceExperimentTextExtentAnchor") ||
            owner->TextExtentCalls() <= punctuationExtentCalls) {
            throw std::runtime_error("registered punctuation popup did not use the host focus text extent");
        }
        GetWindowRect(popup, &popupBounds);
        owner->GetTextExt(1, 0, 0, &expected, &clipped);
        if (popupBounds.left != expected.left || popupBounds.top != expected.bottom) {
            throw std::runtime_error("registered punctuation popup moved away from the host input focus");
        }
        dispatchKey(keystrokes, VK_ESCAPE);
        if (IsWindowVisible(popup)) {
            throw std::runtime_error("registered punctuation popup remained visible after cancellation");
        }
        std::cout << "punctuation_text_extent_anchor_verified=true\n";

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
        const bool hostTerminatedComposition = !IsWindow(popup);
        BOOL crossContextEaten = TRUE;
        require(keystrokes->TestKeyDown('J', 0, &crossContextEaten), "registered cross-context TestKeyDown");
        if (hostTerminatedComposition ? !crossContextEaten : crossContextEaten) {
            throw std::runtime_error(hostTerminatedComposition
                ? "registered host termination did not reconnect for the new context"
                : "registered focus callback did not isolate the preserved composition");
        }
        require(threadManager->SetFocus(document), "restore registered document focus");
        if (hostTerminatedComposition) {
            BOOL postTerminationEaten = FALSE;
            require(keystrokes->TestKeyDown('J', 0, &postTerminationEaten),
                    "registered post-termination TestKeyDown");
            if (!postTerminationEaten) {
                throw std::runtime_error("registered host termination did not recover the Broker session");
            }
            dispatchKey(keystrokes, 'J');
            const std::wstring recoveredText = readContext(context, clientId);
            if (recoveredText.empty() || recoveredText.back() != L'j') {
                throw std::runtime_error("registered host recovery did not apply a fresh composition");
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
                  << "registered_default_candidate_keys_verified=true\n"
                  << "registered_invalid_code_backspace_recovery_verified=true\n"
                  << "registered_direction_and_page_keys_verified=true\n"
                  << "architecture_bits=" << sizeof(void*) * 8 << '\n';

            dispatchKey(keystrokes, VK_ESCAPE);
            pumpMessages();
        const std::wstring beforeFailedAsyncCommit = readContext(context, clientId);
        for (const char character : code) {
            const WPARAM key = character >= 'a'
                ? static_cast<WPARAM>(character - 'a' + 'A')
                : static_cast<WPARAM>(character);
            dispatchKey(keystrokes, key);
        }
        popup = FindWindowW(L"YimeTextServiceExperimentCandidatePopup", nullptr);
        if (!popup || !IsWindowVisible(popup)) {
            throw std::runtime_error("failed asynchronous edit setup popup missing");
        }
        ITfCandidateListUIElement* failedCandidates = findCandidateElement(threadManager);
        if (!failedCandidates) {
            throw std::runtime_error("failed asynchronous edit candidate UI missing");
        }
        UINT failedCandidateCount = 0;
        require(failedCandidates->GetCount(&failedCandidateCount),
                "failed asynchronous edit candidate count");
        failedCandidates->Release();
        if (failedCandidateCount == 0) {
            throw std::runtime_error("failed asynchronous edit setup has no candidates");
        }
        const int failedRowHeight = static_cast<int>(reinterpret_cast<UINT_PTR>(
            GetPropW(popup, L"YimeTextServiceExperimentCandidateRowHeight")));
        RECT failedPopupClient{};
        GetClientRect(popup, &failedPopupClient);
        if (failedRowHeight <= 0 || failedPopupClient.right <= 16) {
            throw std::runtime_error("failed asynchronous edit popup geometry missing");
        }
        POINT failedClickPoint{
            failedPopupClient.right / 2,
            failedPopupClient.bottom - 8 - failedRowHeight / 2};
        owner->DelayAsynchronousWrites(true);
        SendMessageW(popup, WM_LBUTTONUP, 0,
                     MAKELPARAM(failedClickPoint.x, failedClickPoint.y));
        for (int attempt = 0; attempt < 100 && !owner->HasPendingLock(); ++attempt) {
            pumpMessages();
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        if (!owner->HasPendingLock() || !IsWindowVisible(popup)) {
            throw std::runtime_error("failed asynchronous edit was not queued by the host");
        }
        require(owner->CompletePendingLock(true), "fail delayed asynchronous edit lock");
        for (int attempt = 0; attempt < 100 && IsWindowVisible(popup); ++attempt) {
            pumpMessages();
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        const std::wstring afterFailedAsyncCommit = readContext(context, clientId);
        const bool failedTextUnchanged =
            afterFailedAsyncCommit == beforeFailedAsyncCommit + L"2jru";
        const bool failedPopupVisible = IsWindowVisible(popup) != FALSE;
        if (!failedTextUnchanged || owner->FailedWrites() != 1 || failedPopupVisible) {
            std::cerr << "failed asynchronous edit recovery mismatch"
                      << " text_unchanged=" << (failedTextUnchanged ? "true" : "false")
                      << " failed_writes=" << owner->FailedWrites()
                      << " candidate_count=" << failedCandidateCount
                      << " expected_length=" << (beforeFailedAsyncCommit.size() + 4)
                      << " actual_length=" << afterFailedAsyncCommit.size()
                      << " popup_visible=" << (failedPopupVisible ? "true" : "false")
                      << "\n";
            throw std::runtime_error("failed asynchronous edit changed text or retained candidate UI");
        }
        std::cout << "failed_async_edit_recovery_verified=true\n";

        if (runToolMenuSmoke) {
            if (!languageBarItem) {
                throw std::runtime_error(
                    "registered language-bar item unavailable for tool-menu smoke test");
            }
            ITfLangBarItemButton* languageBarButton = nullptr;
            require(languageBarItem->QueryInterface(
                        __uuidof(ITfLangBarItemButton),
                        reinterpret_cast<void**>(&languageBarButton)),
                    "query registered language-bar button");
            for (const UINT command : {YIME_LBI_INPUT_TOOLBAR, YIME_LBI_REVERSE_LOOKUP,
                                       YIME_LBI_USER_LEXICON, YIME_LBI_SETTINGS_TOOL,
                                       YIME_LBI_TRAINER_TOOL, YIME_LBI_TOOL_CENTER}) {
                require(languageBarButton->OnMenuSelect(command),
                        "invoke registered language-bar tool command");
            }
            languageBarButton->Release();
            std::cout << "registered_tool_menu_commands_verified=true\n";
        }

        profiles->DeactivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, kLanguageId,
                                    CLSID_YimeTextServiceExperiment,
                                    GUID_YimeTextServiceExperimentProfile, nullptr,
                                    TF_IPPMF_FORPROCESS);
        if (languageBarItem) {
            yime::experiment::ExperimentSettings updatedSettings;
            if (!yime::experiment::ApplyExperimentSettingsCommand(
                    yime::experiment::ExperimentSettingsCommand::ShapeFull,
                    yime::experiment::ResolveExperimentSettingsPath(), &updatedSettings)) {
                throw std::runtime_error("could not update settings after language-bar deactivation");
            }
            for (int attempt = 0; attempt < 30; ++attempt) {
                pumpMessages();
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
            DWORD retainedStatus = 0;
            require(languageBarItem->GetStatus(&retainedStatus),
                    "query host-retained language bar after deactivation");
            languageBarItem->Release();
            languageBarItem = nullptr;
            std::cout << "retained_language_bar_after_deactivation_verified=true\n";
        }
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
