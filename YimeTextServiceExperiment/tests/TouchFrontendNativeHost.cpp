// Explicit, manual Phase A host. Merely building or starting without --run-native
// never initializes COM, creates a window, activates a profile, or sends input.
#include "TouchFrontendNativeTextStore.h"
#include "TouchFrontendNativeHostSafety.h"
#include "TouchFrontendNativeHostPaths.h"
#include "YimeTextServiceIds.h"
#include <bcrypt.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <thread>
#include <cstdio>

using Microsoft::WRL::ComPtr;
using nlohmann::json;
using namespace yime::nativehost;
namespace fs = std::filesystem;
namespace {
void require(bool yes, const char* stage) { if (!yes) throw std::runtime_error(stage); }
struct NativeFailure : std::runtime_error {
    HRESULT result;
    NativeFailure(const char* stage, HRESULT hr) : std::runtime_error(stage), result(hr) {}
};
void check(HRESULT hr, const char* stage) { if (hr != S_OK) throw NativeFailure(stage, hr); }
struct Handle {
    HANDLE value = INVALID_HANDLE_VALUE;
    Handle() = default;
    explicit Handle(HANDLE h) : value(h) {}
    ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
    Handle(Handle&& other) noexcept : value(other.value) { other.value = INVALID_HANDLE_VALUE; }
    Handle& operator=(Handle&& other) noexcept { std::swap(value, other.value); return *this; }
    Handle(const Handle&) = delete;
};
std::wstring wide(const std::string& s) {
    const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), static_cast<int>(s.size()), nullptr, 0);
    require(n > 0, "UTF8 conversion"); std::wstring result(n, 0);
    require(MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), static_cast<int>(s.size()), result.data(), n) == n, "UTF8 conversion"); return result;
}
std::string utf8(const std::wstring& s) {
    if (s.empty()) return {};
    const int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, s.data(), static_cast<int>(s.size()), nullptr, 0, nullptr, nullptr);
    require(n > 0, "UTF16 conversion"); std::string result(n, 0);
    require(WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, s.data(), static_cast<int>(s.size()), result.data(), n, nullptr, nullptr) == n, "UTF16 conversion"); return result;
}
class Hash {
    BCRYPT_ALG_HANDLE algorithm_ = nullptr;
    BCRYPT_HASH_HANDLE hash_ = nullptr;
    std::vector<BYTE> object_;
public:
    Hash() {
        require(BCryptOpenAlgorithmProvider(&algorithm_, BCRYPT_SHA256_ALGORITHM, nullptr, 0) >= 0, "SHA256 provider");
        DWORD size = 0, received = 0;
        require(BCryptGetProperty(algorithm_, BCRYPT_OBJECT_LENGTH, reinterpret_cast<BYTE*>(&size), sizeof(size), &received, 0) >= 0 && size, "SHA256 size");
        object_.resize(size);
        require(BCryptCreateHash(algorithm_, &hash_, object_.data(), size, nullptr, 0, 0) >= 0, "SHA256 create");
    }
    ~Hash() { if (hash_) BCryptDestroyHash(hash_); if (algorithm_) BCryptCloseAlgorithmProvider(algorithm_, 0); }
    void add(const void* data, size_t size) {
        require(size <= ULONG_MAX && BCryptHashData(hash_, reinterpret_cast<BYTE*>(const_cast<void*>(data)), static_cast<ULONG>(size), 0) >= 0, "SHA256 data");
    }
    std::string finish() {
        BYTE result[32]; require(BCryptFinishHash(hash_, result, sizeof(result), 0) >= 0, "SHA256 finish");
        static const char hex[] = "0123456789abcdef"; std::string value;
        for (BYTE b : result) { value += hex[b >> 4]; value += hex[b & 15]; } return value;
    }
};
std::string digest(const std::string& value) { Hash h; h.add(value.data(), value.size()); return h.finish(); }
std::string textDigest(const std::wstring& value) { static_assert(sizeof(wchar_t) == 2); Hash h; h.add(value.data(), value.size() * 2); return h.finish(); }
std::wstring full(const fs::path& p) {
    wchar_t buffer[32768]; const auto n = GetFullPathNameW(p.c_str(), 32768, buffer, nullptr);
    require(n && n < 32768, "absolute path"); return std::wstring(buffer, n);
}
bool samePath(const fs::path& a, const fs::path& b) { return _wcsicmp(full(a).c_str(), full(b).c_str()) == 0; }
void noLinks(const fs::path& path) {
    const fs::path resolved(full(path)); fs::path part;
    for (const auto& component : resolved) {
        part /= component;
        if (part == resolved.root_name()) continue;
        const DWORD attrs = GetFileAttributesW(part.c_str());
        require(attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_REPARSE_POINT), "missing or linked path");
    }
}
std::string readFile(const fs::path& path, size_t limit) {
    std::ifstream stream(path, std::ios::binary); require(stream.good(), "read file");
    std::string raw; char buffer[4096];
    while (stream.read(buffer, sizeof(buffer)) || stream.gcount()) {
        raw.append(buffer, static_cast<size_t>(stream.gcount())); require(raw.size() <= limit, "file size limit");
    }
    require(stream.eof(), "read file completion"); return raw;
}
std::string hashFile(const fs::path& path, std::vector<Handle>& retained) {
    noLinks(path);
    Handle file(CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr));
    require(file.value != INVALID_HANDLE_VALUE, "open immutable file");
    Hash hash; BYTE buffer[65536]; DWORD n = 0;
    for (;;) { require(ReadFile(file.value, buffer, sizeof(buffer), &n, nullptr) != FALSE, "hash file read"); if (!n) break; hash.add(buffer, n); }
    const auto result = hash.finish(); retained.push_back(std::move(file)); return result;
}
void writeNew(const fs::path& path, const std::string& data) {
    Handle file(CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr));
    if (file.value == INVALID_HANDLE_VALUE) throw NativeFailure("create evidence file", HRESULT_FROM_WIN32(GetLastError()));
    require(data.size() <= MAXDWORD, "evidence size limit");
    DWORD written = 0;
    if (!WriteFile(file.value, data.data(), static_cast<DWORD>(data.size()), &written, nullptr))
        throw NativeFailure("write evidence", HRESULT_FROM_WIN32(GetLastError()));
    if (written != data.size()) throw NativeFailure("short evidence write", HRESULT_FROM_WIN32(ERROR_WRITE_FAULT));
    if (!FlushFileBuffers(file.value)) throw NativeFailure("flush evidence", HRESULT_FROM_WIN32(GetLastError()));
}
std::wstring guidText(REFGUID guid) { wchar_t value[40]; require(StringFromGUID2(guid, value, 40) != 0, "GUID string"); return value; }
std::wstring registeredDll(HKEY root, const std::wstring& key, bool optional) {
    DWORD bytes = 0;
    LSTATUS status = RegGetValueW(root, key.c_str(), nullptr, RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, nullptr, &bytes);
    if (optional && (status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND)) return {};
    require(status == ERROR_SUCCESS && bytes >= sizeof(wchar_t) && bytes < 65536, "registered DLL query");
    std::wstring value(bytes / sizeof(wchar_t), 0);
    status = RegGetValueW(root, key.c_str(), nullptr, RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, value.data(), &bytes);
    require(status == ERROR_SUCCESS && !value.empty() && value.back() == 0, "registered DLL value"); value.pop_back();
    require(value.find(L'\0') == std::wstring::npos && !value.empty(), "registered DLL path"); return value;
}
void verifyRegistration(const fs::path& expected) {
    const std::wstring suffix = L"CLSID\\" + guidText(CLSID_YimeTextServiceExperiment) + L"\\InprocServer32";
    require(samePath(registeredDll(HKEY_CLASSES_ROOT, suffix, false), expected), "effective registration mismatch");
    for (HKEY root : {HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE}) {
        const auto value = registeredDll(root, L"Software\\Classes\\" + suffix, true);
        require(value.empty() || samePath(value, expected), "registration overlay mismatch");
    }
}
struct Inputs {
    std::vector<Handle> locks;
    fs::path root, tip, frontend;
    std::string planHash, hostHash;
};
Inputs preflight(const Plan& p, const std::string& raw) {
    RequireNormalTsfActivationEnvironment();
    Inputs input; input.root = wide(p.installedRoot); input.tip = input.root / L"x64/YimeTextService18u.dll";
    input.frontend = input.root / L"frontend/YimeTouchKeyboard.exe"; input.planHash = digest(raw);
    using Wow = BOOL(WINAPI*)(HANDLE, USHORT*, USHORT*);
    const auto query = reinterpret_cast<Wow>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "IsWow64Process2"));
    USHORT process = 0, native = 0;
    require(query && query(GetCurrentProcess(), &process, &native) && !process && native == IMAGE_FILE_MACHINE_AMD64, "native x64 required");
    wchar_t computer[MAX_COMPUTERNAME_LENGTH + 1]; DWORD length = MAX_COMPUTERNAME_LENGTH + 1;
    require(GetComputerNameW(computer, &length) && _wcsicmp(computer, wide(p.machine).c_str()) == 0, "machine mismatch");
    Handle token; token.value = nullptr;
    require(OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token.value) != FALSE, "process token");
    TOKEN_ELEVATION elevated{}; DWORD got = 0;
    require(GetTokenInformation(token.value, TokenElevation, &elevated, sizeof(elevated), &got) && !elevated.TokenIsElevated, "non-elevated host required");
    wchar_t own[32768]; const DWORD n = GetModuleFileNameW(nullptr, own, 32768); require(n && n < 32768, "host module");
    input.hostHash = hashFile(own, input.locks); require(input.hostHash == p.hostHash, "host hash mismatch");
    const auto descriptorPath = input.root / L"installed-18u-product.json";
    require(hashFile(descriptorPath, input.locks) == DescriptorHash, "descriptor hash mismatch");
    const auto descriptor = parsePlanJson(readFile(descriptorPath, 32768));
    require(descriptor.at("sourceCommit") == SourceCommit && descriptor.at("product") == "yimecore-18u", "descriptor product/source");
    bool hasTip = false, hasFrontend = false;
    for (const auto& row : descriptor.at("files")) {
        const auto name = row.at("path").get<std::string>();
        if (name == "x64/YimeTextService18u.dll") { require(row.at("sha256") == TipHash, "descriptor TIP hash"); hasTip = true; }
        if (name == "frontend/YimeTouchKeyboard.exe") { require(row.at("sha256") == FrontendHash, "descriptor frontend hash"); hasFrontend = true; }
    }
    require(hasTip && hasFrontend, "descriptor file identity");
    require(hashFile(input.tip, input.locks) == TipHash && hashFile(input.frontend, input.locks) == FrontendHash, "installed binary mismatch");
    // Verify the registered path BEFORE any thread manager/profile activation.
    verifyRegistration(input.tip);
    return input;
}

class Reader final : public ITfEditSession {
    std::atomic<ULONG> refs_{1}; ComPtr<ITfContext> context_;
public:
    bool completed = false; std::wstring text;
    explicit Reader(ITfContext* context) : context_(context) {}
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override { if (!out) return E_POINTER; *out = nullptr; if (iid != IID_IUnknown && iid != __uuidof(ITfEditSession)) return E_NOINTERFACE; *out = static_cast<ITfEditSession*>(this); AddRef(); return S_OK; }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
    STDMETHODIMP_(ULONG) Release() override { auto n = --refs_; if (!n) delete this; return n; }
    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        ComPtr<ITfRange> first, last;
        HRESULT hr = context_->GetStart(cookie, &first);
        if (hr == S_OK && !first) return E_UNEXPECTED;
        if (hr == S_OK) hr = context_->GetEnd(cookie, &last);
        if (hr == S_OK && !last) return E_UNEXPECTED;
        if (hr == S_OK) hr = first->ShiftEndToRange(cookie, last.Get(), TF_ANCHOR_END);
        wchar_t buffer[4097]; ULONG n = 0;
        if (hr == S_OK) hr = first->GetText(cookie, 0, buffer, 4097, &n);
        if (hr == S_OK && n > 4096) return E_BOUNDS;
        if (hr == S_OK) {
            try { text.assign(buffer, n); }
            catch (...) { return E_OUTOFMEMORY; }
            completed = true;
        }
        return hr;
    }
};
std::wstring readContext(ITfContext* context, TfClientId client) {
    ComPtr<Reader> reader; reader.Attach(new Reader(context)); HRESULT result = E_FAIL;
    check(context->RequestEditSession(client, reader.Get(), TF_ES_SYNC | TF_ES_READ, &result), "independent read request");
    check(result, "independent read result"); require(reader->completed, "independent read callback missing"); return reader->text;
}
class EditObserver final : public ITfTextEditSink {
    std::atomic<ULONG> refs_{1}; ComPtr<TextStore> store_; ComPtr<IUnknown> identity_;
public:
    unsigned count = 0, mutationsAtLastEnd = 0;
    EditObserver(TextStore* store, ITfContext* context) : store_(store) { check(context->QueryInterface(IID_PPV_ARGS(&identity_)), "context identity"); }
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override { if (!out) return E_POINTER; *out = nullptr; if (iid != IID_IUnknown && iid != __uuidof(ITfTextEditSink)) return E_NOINTERFACE; *out = static_cast<ITfTextEditSink*>(this); AddRef(); return S_OK; }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
    STDMETHODIMP_(ULONG) Release() override { auto n = --refs_; if (!n) delete this; return n; }
    STDMETHODIMP OnEndEdit(ITfContext* context, TfEditCookie, ITfEditRecord*) override {
        ComPtr<IUnknown> actual;
        if (!context || context->QueryInterface(IID_PPV_ARGS(&actual)) != S_OK || actual.Get() != identity_.Get()) {
            store_->Record("foreign-on-end-edit", 0, E_ABORT); store_->Close(); return E_ABORT;
        }
        ++count; mutationsAtLastEnd = store_->MutationCount();
        return store_->Record("on-end-edit") ? S_OK : E_ABORT;
    }
};

class Host {
    const Plan& plan_; const Inputs& inputs_;
    HWND window_ = nullptr;
    ComPtr<ITfThreadMgr> manager_; ComPtr<ITfDocumentMgr> document_; ComPtr<ITfContext> context_;
    ComPtr<IUnknown> contextIdentity_; ComPtr<ITfInputProcessorProfileMgr> profiles_;
    ComPtr<ITfSource> source_; ComPtr<EditObserver> observer_; ComPtr<TextStore> store_;
    TfClientId client_ = TF_CLIENTID_NULL; DWORD observerCookie_ = TF_INVALID_COOKIE;
    bool managerActive_ = false, profileActive_ = false, ready_ = false, armed_ = false;
    bool sealed_ = false, failed_ = false, busy_ = false, cleanupVerified_ = false;
    RunBoundary boundary_;
    bool cleanupAttempted_ = false, nativeTsfAttempted_ = false;
    ULONGLONG started_ = 0, armedAt_ = 0, heldAt_ = 0, triggeredAt_ = 0;
    unsigned editCountAtArm_ = 0;
    const char* cleanupFailureStage_ = nullptr;
    HRESULT cleanupFailureResult_ = S_OK;
    json failureDetail_ = nullptr;
    std::string reason_ = "not-armed", readHash_; std::wstring instruction_;
    static constexpr UINT_PTR Timer = 0x18a1;
    static LRESULT CALLBACK Proc(HWND window, UINT message, WPARAM w, LPARAM l) {
        auto* host = reinterpret_cast<Host*>(GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) { host = static_cast<Host*>(reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams); SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(host)); }
        if (!host) return DefWindowProcW(window, message, w, l);
        try {
            if (message == WM_KEYDOWN && w == VK_F8) { host->arm(); return 0; }
            if (message == WM_CLOSE) { host->requestClose(); return 0; }
            if (message == WM_TIMER && w == Timer) { host->tick(); return 0; }
            if (message == WM_PAINT) {
                PAINTSTRUCT paint{}; HDC dc = BeginPaint(window, &paint); RECT rect{}; GetClientRect(window, &rect); rect.left += 20; rect.top += 20;
                const std::wstring display = host->instruction_ + L"\n\nSynthetic document: " + (host->store_ ? host->store_->Text() : L"");
                DrawTextW(dc, display.c_str(), -1, &rect, DT_LEFT | DT_WORDBREAK); EndPaint(window, &paint); return 0;
            }
            if (message == WM_NCDESTROY) {
                SetWindowLongPtrW(window, GWLP_USERDATA, 0);
                if (host->window_ == window) host->window_ = nullptr;
                host->requestClose();
            }
        } catch (const std::exception& error) { host->failure(error); }
          catch (...) { host->stop("host-callback-error"); }
        return DefWindowProcW(window, message, w, l);
    }
    bool eligible() {
        if (!window_ || GetForegroundWindow() != window_ || GetFocus() != window_) return false;
        BOOL focused = FALSE; if (manager_->IsThreadFocus(&focused) != S_OK || !focused) return false;
        TF_INPUTPROCESSORPROFILE active{};
        if (profiles_->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &active) != S_OK || active.dwProfileType != TF_PROFILETYPE_INPUTPROCESSOR ||
            !IsEqualGUID(active.clsid, CLSID_YimeTextServiceExperiment) || !IsEqualGUID(active.guidProfile, GUID_YimeTextServiceExperimentProfile)) return false;
        ComPtr<ITfDocumentMgr> doc; ComPtr<ITfContext> top; ComPtr<IUnknown> identity;
        return manager_->GetFocus(&doc) == S_OK && doc.Get() == document_.Get() && doc->GetTop(&top) == S_OK &&
            top->QueryInterface(IID_PPV_ARGS(&identity)) == S_OK && identity.Get() == contextIdentity_.Get();
    }
    void stop(const char* reason) noexcept {
        failed_ = true; ready_ = false;
        if (store_) { store_->Record(reason, 0, E_ABORT); store_->Close(); }
        try {
            reason_ = reason;
            instruction_ = L"Stopped. Do not repeat input or recovery. Close this host to save evidence.";
        } catch (...) { /* The fixed event above preserves the stop even under allocation failure. */ }
        if (window_) InvalidateRect(window_, nullptr, TRUE);
    }
    bool allowRun(uint64_t now) {
        if (store_ && store_->Triggered() && !triggeredAt_) triggeredAt_ = now;
        const bool allowed = boundary_.Allow(now, [&](RunBoundary::Reason reason) {
            ready_ = false;
            if (!sealed_ && !failed_) stop(reason == RunBoundary::Reason::Deadline
                ? (armed_ ? "scenario-timeout" : "arm-timeout") : "close-requested");
            else if (store_ && !store_->Stopped()) store_->Close();
        });
        return allowed && !failed_ && !cleanupAttempted_;
    }
    void requestClose() {
        boundary_.RequestClose();
        allowRun(GetTickCount64()); // Disarm/cancel pending immediately, even within a message batch.
    }
    void arm() {
        if (!allowRun(GetTickCount64())) return;
        if (!ready_ || armed_ || sealed_ || failed_ || busy_) return;
        busy_ = true;
        struct Busy { bool& flag; ~Busy() { flag = false; } } guard{busy_};
        require(eligible(), "arm target/profile not eligible");
        require(readContext(context_.Get(), client_).empty() && store_->Text().empty() &&
            store_->MutationCount() == 0 && store_->WriteCallCount() == 0 &&
            store_->Selection() == std::make_pair(0L, 0L) && !store_->HasPendingLock() && !store_->Stopped(),
            "arm baseline not empty or previously written");
        require(eligible(), "arm target/profile changed during readback");
        if (!allowRun(GetTickCount64())) return;
        require(store_->Arm(plan_.scenario, wide(plan_.text)), "one-shot arm refused");
        editCountAtArm_ = observer_->count;
        armed_ = true; armedAt_ = GetTickCount64(); reason_ = "armed";
        instruction_ = L"ARMED ONCE. Confirm the planned text once using the normal installed touchscreen frontend.\nDo not repeat, change focus, or click recovery.";
        InvalidateRect(window_, nullptr, TRUE);
    }
    void tick() {
        if (busy_) return; busy_ = true;
        struct Busy { bool& flag; ~Busy() { flag = false; } } guard{busy_};
        const auto now = GetTickCount64();
        if (!allowRun(now)) return;
        if (!armed_ && !failed_ && store_->WriteCallCount()) { stop("write-before-arm"); return; }
        if (armed_ && !sealed_ && !failed_) {
            if (!eligible()) { stop("target-or-profile-changed"); return; }
            if (store_->Stopped()) { stop("textstore-stopped"); return; }
            if (store_->DelayPending()) {
                if (!heldAt_) { heldAt_ = now; require(store_->Text().empty() && store_->MutationCount() == 0, "delay baseline changed"); store_->Record("delay-baseline-unchanged"); }
                if (now - heldAt_ >= plan_.delayMs) {
                    // Eligibility queries can pump callbacks or consume the remaining time.
                    if (!allowRun(GetTickCount64())) return;
                    const HRESULT hr = store_->GrantPending(); store_->Record("explicit-grant-return", 0, hr);
                    require(hr == S_OK, "delayed grant failed");
                }
            }
            if (store_->Triggered() && !store_->HasPendingLock()) {
                const bool writeEndObserved = observer_->count > editCountAtArm_ && observer_->mutationsAtLastEnd == 1;
                const auto text = readContext(context_.Get(), client_);
                require(text == store_->Text(), "independent read mismatch");
                const bool expected = plan_.scenario == Scenario::DelayWrite
                    ? text == wide(plan_.text) && store_->MutationCount() == 1 && store_->FailureCount() == 0 && writeEndObserved
                    : text.empty() && store_->MutationCount() == 0 && store_->FailureCount() == 1;
                require(expected, "scenario host observations mismatch");
                if (!allowRun(GetTickCount64())) return;
                readHash_ = textDigest(text);
                require(store_->Record("independent-readback-sealed"), "readback evidence overflow"); sealed_ = true;
                reason_ = "host-observations-sealed-manual-outcome-unobserved";
                instruction_ = L"Host observations sealed; this is NOT an overall PASS.\nKeep the host open while observing the frontend result. No recovery or second submission in this run.\nClose after the frontend has returned; evidence records manual checks as NOT_RUN.";
                InvalidateRect(window_, nullptr, TRUE);
            }
        }
        if (sealed_ && !failed_ && (store_->Stopped() || store_->MutationCount() > (plan_.scenario == Scenario::DelayWrite ? 1u : 0u))) stop("additional-mutation-or-store-error");
    }
public:
    Host(const Plan& p, const Inputs& input) : plan_(p), inputs_(input) {}
    ~Host() { if (!cleanup()) preserveFailure(); }
    void initialize() {
        nativeTsfAttempted_ = true;
        check(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&profiles_)), "profile manager");
        ComPtr<ITfInputProcessorProfiles> languages; check(profiles_.As(&languages), "language query interface");
        BOOL enabled = FALSE; check(languages->IsEnabledLanguageProfile(CLSID_YimeTextServiceExperiment, 0x0804, GUID_YimeTextServiceExperimentProfile, &enabled), "profile enabled query");
        require(enabled, "profile not already enabled");
        LANGID language = 0; check(languages->GetCurrentLanguage(&language), "current language query");
        require(language == 0x0804 && LOWORD(reinterpret_cast<ULONG_PTR>(GetKeyboardLayout(0))) == 0x0804, "current language precondition");
        WNDCLASSW klass{}; klass.lpfnWndProc = Proc; klass.hInstance = GetModuleHandleW(nullptr); klass.lpszClassName = L"Yime18uNativePhaseAHost";
        klass.hCursor = LoadCursorW(nullptr, IDC_ARROW); klass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        require(RegisterClassW(&klass) != 0, "register own window class");
        window_ = CreateWindowExW(0, klass.lpszClassName, L"18u Phase A — self-owned synthetic document", WS_OVERLAPPEDWINDOW,
            100, 100, 800, 300, nullptr, nullptr, klass.hInstance, this); require(window_ != nullptr, "create own window");
        store_.Attach(new TextStore(window_, 2048));
        check(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&manager_)), "thread manager");
        ComPtr<ITfThreadMgrEx> extended; check(manager_.As(&extended), "extended manager");
        check(extended->ActivateEx(&client_, TF_TMAE_NOACTIVATETIP | TF_TMAE_NOACTIVATEKEYBOARDLAYOUT), "own manager activation"); managerActive_ = true;
        check(manager_->CreateDocumentMgr(&document_), "own document"); TfEditCookie ownerCookie = 0;
        check(document_->CreateContext(client_, 0, store_.Get(), &context_, &ownerCookie), "own text-store context");
        check(context_.As(&contextIdentity_), "canonical context identity"); check(document_->Push(context_.Get()), "push own context");
        check(context_.As(&source_), "text edit source"); observer_.Attach(new EditObserver(store_.Get(), context_.Get()));
        check(source_->AdviseSink(__uuidof(ITfTextEditSink), observer_.Get(), &observerCookie_), "advise edit observer");
        ComPtr<ITfDocumentMgr> previous; check(manager_->AssociateFocus(window_, document_.Get(), &previous), "associate own window");
        ShowWindow(window_, SW_SHOWNORMAL); SetForegroundWindow(window_); SetFocus(window_);
        require(GetForegroundWindow() == window_ && GetFocus() == window_, "own foreground refused");
        check(manager_->SetFocus(document_.Get()), "focus own document");
        // The registry path and bytes were verified before creating ThreadMgr.
        check(profiles_->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, 0x0804, CLSID_YimeTextServiceExperiment,
            GUID_YimeTextServiceExperimentProfile, nullptr, TF_IPPMF_FORPROCESS), "process-only profile activation"); profileActive_ = true;
        ComPtr<ITfFunctionProvider> provider;
        const auto end = GetTickCount64() + 1500;
        do {
            MSG message{}; while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) { if (message.message == WM_QUIT) throw std::runtime_error("quit during activation"); TranslateMessage(&message); DispatchMessageW(&message); }
            if (manager_->GetFunctionProvider(CLSID_YimeTextServiceExperiment, &provider) == S_OK && provider) break;
            MsgWaitForMultipleObjects(0, nullptr, FALSE, 10, QS_ALLINPUT);
        } while (GetTickCount64() < end);
        require(provider != nullptr, "actual activated provider unavailable");
        HMODULE module = nullptr; const auto address = (*reinterpret_cast<void***>(provider.Get()))[0];
        require(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(address), &module) != FALSE, "actual TIP module");
        wchar_t loaded[32768]; const auto size = GetModuleFileNameW(module, loaded, 32768);
        require(size && size < 32768 && samePath(loaded, inputs_.tip), "actual activated DLL mismatch");
        // Inputs retains a no-write-sharing handle with the verified hash.
        require(eligible(), "actual profile/context not eligible");
        require(!boundary_.Closing(), "close during activation");
        store_->Record("actual-profile-and-module-verified"); started_ = GetTickCount64();
        boundary_.Start(started_, plan_.durationMs); ready_ = true;
        instruction_ = L"Existing profile and original test.12 DLL verified.\nEnsure the normal installed frontend is ready, then press F8 HERE once to arm.\nCase: " + wide(plan_.caseId) + L". Planned synthetic text: " + wide(plan_.text);
        require(SetTimer(window_, Timer, 20, nullptr) != 0, "host timer"); InvalidateRect(window_, nullptr, TRUE);
    }
    void run() {
        while (true) {
            MSG message{};
            // A bounded message batch keeps timeout/close observable even if a
            // window is externally destroyed or messages arrive continuously.
            for (unsigned count = 0; count < 64; ++count) {
                allowRun(GetTickCount64());
                if (!PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) break;
                allowRun(GetTickCount64()); // Cancel before dispatch, including a queued timer.
                if (message.message == WM_QUIT) { stop("quit-received"); requestClose(); break; }
                TranslateMessage(&message); DispatchMessageW(&message);
            }
            const auto now = GetTickCount64();
            allowRun(now);
            if (!window_) { if (!failed_) stop("own-window-destroyed"); requestClose(); }
            // Never truncate the pending completion merely because a host-side
            // failure/readback was observed. Allow the normal five-second I/O
            // observation window before honoring close/timeout after a trigger.
            if (boundary_.Closing() && (!triggeredAt_ || now - triggeredAt_ >= 6000)) break;
            if (MsgWaitForMultipleObjectsEx(0, nullptr, 20, QS_ALLINPUT, MWMO_INPUTAVAILABLE) == WAIT_FAILED) {
                const NativeFailure error("message wait failed", HRESULT_FROM_WIN32(GetLastError()));
                failure(error); break;
            }
        }
    }
    bool cleanup() noexcept {
        if (cleanupAttempted_) return cleanupVerified_;
        cleanupAttempted_ = true;
        bool ok = true;
        auto observe = [&](const char* stage, HRESULT result) -> bool {
            if (result != S_OK) {
                ok = false;
                if (!cleanupFailureStage_) { cleanupFailureStage_ = stage; cleanupFailureResult_ = result; }
            }
            if (store_ && !store_->Record(stage, 0, result)) {
                ok = false;
                if (!cleanupFailureStage_) { cleanupFailureStage_ = "cleanup-evidence-overflow"; cleanupFailureResult_ = E_ABORT; }
            }
            return ok;
        };
        if (window_) KillTimer(window_, Timer);
        if (store_) store_->Close();
        // Stop at the first unverified cleanup boundary. Retain all remaining
        // COM/window references; never leave a live window pointing at a dead Host.
        if (source_ && observerCookie_ != TF_INVALID_COOKIE) {
            if (!observe("cleanup-unadvise", source_->UnadviseSink(observerCookie_))) return false;
            observerCookie_ = TF_INVALID_COOKIE;
        }
        observer_.Reset(); source_.Reset();
        if (manager_ && window_) {
            ComPtr<ITfDocumentMgr> previous;
            if (!observe("cleanup-associate-focus", manager_->AssociateFocus(window_, nullptr, &previous))) return false;
        }
        if (manager_ && !observe("cleanup-focus", manager_->SetFocus(nullptr))) return false;
        if (profileActive_) {
            if (!observe("cleanup-profile", profiles_->DeactivateProfile(TF_PROFILETYPE_INPUTPROCESSOR, 0x0804, CLSID_YimeTextServiceExperiment,
                GUID_YimeTextServiceExperimentProfile, nullptr, TF_IPPMF_FORPROCESS))) return false;
            profileActive_ = false;
        }
        if (document_ && !observe("cleanup-pop", document_->Pop(TF_POPF_ALL))) return false;
        contextIdentity_.Reset(); context_.Reset(); document_.Reset();
        if (managerActive_) {
            if (!observe("cleanup-manager", manager_->Deactivate())) return false;
            managerActive_ = false;
        }
        manager_.Reset(); profiles_.Reset();
        if (window_) {
            const BOOL destroyed = DestroyWindow(window_); const DWORD error = destroyed ? 0 : GetLastError();
            if (!observe("cleanup-window", destroyed ? S_OK : error ? HRESULT_FROM_WIN32(error) : E_FAIL)) return false;
            window_ = nullptr;
        }
        cleanupVerified_ = ok; return ok;
    }
    [[noreturn]] void preserveFailure() noexcept {
        // This is an explicit forensic stop, never a retry of cleanup or a test
        // operation. Keep this object alive until an operator decides what to do.
        stop("cleanup-unverified-preserved");
        std::fprintf(stderr, "cleanup_unverified: stage=%s HRESULT=0x%08lx; resources retained; no automatic retry or process termination\n",
            cleanupFailureStage_ ? cleanupFailureStage_ : "unspecified", static_cast<unsigned long>(cleanupFailureResult_));
        std::fflush(stderr);
        try {
            instruction_ = L"CLEANUP UNVERIFIED. This process is intentionally retained.\nDo not retry input, recovery, or cleanup. Preserve the evidence and request manual disposition.";
        } catch (...) {}
        if (window_) InvalidateRect(window_, nullptr, TRUE);
        for (;;) {
            MSG message{}; const BOOL next = GetMessageW(&message, nullptr, 0, 0);
            if (next > 0) { TranslateMessage(&message); DispatchMessageW(&message); }
            else Sleep(INFINITE); // Retain ownership even if the message queue closes.
        }
    }
    CleanupState cleanupState() const noexcept {
        return {cleanupVerified_, cleanupFailureStage_, static_cast<uint32_t>(cleanupFailureResult_)};
    }
    json summary() const {
        return {{"schemaVersion", "yime-18u-native-host-result-v1"}, {"runId", plan_.runId}, {"caseId", plan_.caseId},
            {"status", failed_ ? "FAIL" : "INCONCLUSIVE"}, {"reason", reason_}, {"sourceCommit", SourceCommit},
            {"packageSourceCommit", SourceCommit}, {"hostSourceCommit", nullptr},
            {"hostSourceIdentity", "hostSha256 plus external source-diff/build record"},
            {"hostSha256", inputs_.hostHash}, {"planSha256", inputs_.planHash}, {"evidenceLevel", "registered-own-textstore-observation"},
            {"nativeTsfExecuted", nativeTsfAttempted_}, {"registrationChanged", false},
            {"hostObservationsSealed", sealed_}, {"manualFrontendAndRecovery", "NOT_RUN"}, {"cleanupVerified", cleanupVerified_},
            {"failureDetail", failureDetail_}, {"cleanupFailureStage", cleanupFailureStage_ ? json(cleanupFailureStage_) : json(nullptr)},
            {"cleanupFailureHRESULT", cleanupFailureStage_ ? json(static_cast<uint32_t>(cleanupFailureResult_)) : json(nullptr)},
            {"readbackUtf16Sha256", readHash_.empty() ? json(nullptr) : json(readHash_)},
            {"textStoreWriteCalls", store_ ? json(store_->WriteCallCount()) : json(nullptr)},
            {"textStoreMutations", store_ ? json(store_->MutationCount()) : json(nullptr)},
            {"injectedFailures", store_ ? json(store_->FailureCount()) : json(nullptr)},
            {"evidenceOverflow", store_ && store_->EvidenceOverflow()}, {"v2EditCount", nullptr}, {"tipDoEditSessionResult", nullptr},
            {"tipRequestEditSessionResult", nullptr}, {"frontendBlocked", nullptr}, {"outputId", nullptr},
            {"sessionId", nullptr}, {"deliveryEpoch", nullptr}, {"cancelGeneration", nullptr}, {"clientError", nullptr}};
    }
    std::string events() const {
        std::string output; LARGE_INTEGER frequency{}; QueryPerformanceFrequency(&frequency);
        if (store_) for (const auto& event : store_->Events()) output += json{{"producer", "native-textstore-host"},
            {"producerSequence", event.sequence}, {"monotonicTicks", event.ticks}, {"frequency", frequency.QuadPart},
            {"caseId", plan_.caseId}, {"runId", plan_.runId}, {"contextIdentity", "owned-context-1"},
            {"event", event.name}, {"flags", event.flags}, {"hresult", static_cast<uint32_t>(event.result)}}.dump() + "\n";
        return output;
    }
    void failure(const std::exception& error) noexcept {
        try {
            failureDetail_ = {{"stage", error.what()}, {"kind", "assertion"}, {"hresult", nullptr}};
            if (const auto* native = dynamic_cast<const NativeFailure*>(&error)) {
                failureDetail_["kind"] = "hresult"; failureDetail_["hresult"] = static_cast<uint32_t>(native->result);
            }
        } catch (...) { /* Preserve the fixed stop event if evidence allocation fails. */ }
        stop("native-host-failed");
    }
};
struct Apartment {
    Apartment() { check(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED), "initialize STA"); }
    ~Apartment() { CoUninitialize(); }
};
void help() {
    std::cout << "Phase A design implementation; no activation by default.\n"
        "  --validate-plan <json> [--case D1|D2]   offline only; never reads installation\n"
        "  --run-native --plan <json> --case D1|D2 --output <new-directory>\n"
        "Native execution requires separately authorized installed-profile testing.\n"
        "This program does not install, register, enable profiles, launch the frontend, or send edits.\n";
}
} // namespace

int wmain(int argc, wchar_t** argv) {
    try {
        if (argc == 1 || (argc == 2 && std::wstring(argv[1]) == L"--help")) { help(); return 0; }
        bool run = false, validate = false; fs::path planFile, output; std::string selected; std::set<std::wstring> seen;
        for (int i = 1; i < argc; ++i) {
            const std::wstring key = argv[i]; require(seen.insert(key).second, "duplicate argument");
            if (key == L"--run-native") { run = true; continue; }
            require(i + 1 < argc, "missing argument value"); const std::wstring value = argv[++i];
            if (key == L"--validate-plan") { validate = true; planFile = value; }
            else if (key == L"--plan") planFile = value;
            else if (key == L"--case") selected = utf8(value);
            else if (key == L"--output") output = value;
            else throw std::runtime_error("unknown argument");
        }
        require(run != validate && !planFile.empty(), "explicit execution mode required");
        require(validate ? (!seen.count(L"--plan") && output.empty()) : (!selected.empty() && !output.empty() && seen.count(L"--plan")), "mode arguments");
        const auto raw = readFile(planFile, 32768); const auto plan = parsePlan(raw, selected);
        require(textDigest(wide(plan.text)) == plan.textHash, "expected UTF16-LE text hash mismatch");
        if (validate) {
            std::cout << json{{"status", "NOT_RUN"}, {"planValid", true}, {"planSha256", digest(raw)}, {"caseId", plan.caseId},
                {"evidenceLevel", "offline-plan-validation"}, {"nativeTsfExecuted", false}, {"registrationChanged", false}}.dump() << '\n'; return 0;
        }
        // Everything above is offline. No native activation is reachable without
        // the exact --run-native mode, machine, original package and host checks.
        auto inputs = preflight(plan, raw);
        require(output.is_absolute() && localAbsoluteRoot(utf8(output.wstring())) &&
            !fs::exists(output) && fs::exists(output.parent_path()), "new local absolute output directory required");
        noLinks(output.parent_path());
        EvidenceDirectoryBoundary outputBoundary(inputs.root, output);
        output = outputBoundary.OutputPath();
        require(fs::create_directory(output), "create fresh evidence directory");
        outputBoundary.VerifyCreated();
        writeNew(output / L"plan.json", raw);
        Apartment apartment; Host host(plan, inputs);
        try { host.initialize(); host.run(); }
        catch (const std::exception& error) { host.failure(error); }
        const bool cleaned = host.cleanup();
        const char* evidenceStage = "summary-serialization";
        int resultCode = 2;
        const bool published = PublishEvidenceSafely(host.cleanupState(), [&] {
            auto result = host.summary();
            if (!cleaned) { result["status"] = "INCONCLUSIVE"; result["reason"] = "cleanup-unverified"; }
            evidenceStage = "events-serialization";
            const auto eventBytes = host.events();
            evidenceStage = "events.jsonl"; writeNew(output / L"events.jsonl", eventBytes);
            evidenceStage = "summary-serialization";
            result["eventsSha256"] = digest(eventBytes); const auto summaryBytes = result.dump(2) + "\n";
            evidenceStage = "summary.json"; writeNew(output / L"summary.json", summaryBytes);
            evidenceStage = "evidence-index.json";
            writeNew(output / L"evidence-index.json", json{{"plan.json", digest(raw)}, {"events.jsonl", digest(eventBytes)}, {"summary.json", digest(summaryBytes)}}.dump(2) + "\n");
            evidenceStage = "stdout-summary"; std::cout << result.dump() << '\n' << std::flush;
            require(std::cout.good(), "summary stdout write");
            resultCode = result["status"] == "FAIL" ? 1 : 2;
        }, [&](CleanupState cleanup, bool evidenceFailed, const std::exception* error) noexcept {
            // No JSON allocation and no attempt to rewrite partial evidence. Emit
            // both failures while Host still owns every retained COM/window ref.
            std::fprintf(stderr, "phase_a_evidence: cleanupVerified=%s cleanupStage=%s cleanupHRESULT=0x%08lx evidenceFailed=%s evidenceStage=%s error=%s",
                cleanup.verified ? "true" : "false", cleanup.stage ? cleanup.stage : "none",
                static_cast<unsigned long>(cleanup.result), evidenceFailed ? "true" : "false",
                evidenceFailed ? evidenceStage : "none", error ? error->what() : evidenceFailed ? "non-standard exception" : "none");
            if (const auto* native = dynamic_cast<const NativeFailure*>(error))
                std::fprintf(stderr, " evidenceHRESULT=0x%08lx", static_cast<unsigned long>(native->result));
            std::fprintf(stderr, " retryAllowed=false\n"); std::fflush(stderr);
        }, [&]() noexcept { host.preserveFailure(); });
        return published ? resultCode : 1;
    } catch (const std::exception& error) {
        std::cerr << json{{"status", "BLOCKED"}, {"error", error.what()}, {"retryAllowed", false}}.dump() << '\n'; return 1;
    }
}
