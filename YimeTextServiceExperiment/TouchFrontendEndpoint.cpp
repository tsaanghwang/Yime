#include "TouchFrontendEndpoint.h"
#include "ModuleState.h"
#include <windows.h>
#include <sddl.h>
#include <wrl/client.h>
#include <nlohmann/json.hpp>
#include <atomic>
#include <memory>
#include <string>
#include <vector>
#include <stdexcept>
#include <algorithm>
#include <climits>

using Microsoft::WRL::ComPtr;
using json = nlohmann::json;
namespace {
constexpr DWORD MaxFrame = 16384;
void require(bool ok) { if (!ok) throw std::runtime_error("18u frontend request rejected"); }
struct Handle {
    HANDLE h = nullptr;
    ~Handle() { if (h && h != INVALID_HANDLE_VALUE) CloseHandle(h); }
};
std::vector<BYTE> userToken(HANDLE token) {
    DWORD n = 0; GetTokenInformation(token, TokenUser, nullptr, 0, &n);
    require(n && n < 65536); std::vector<BYTE> result(n);
    require(GetTokenInformation(token, TokenUser, result.data(), n, &n) != FALSE);
    return result;
}
std::wstring frontendImage() {
    HMODULE module = nullptr;
    require(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&frontendImage), &module) != FALSE);
    wchar_t path[32768]; DWORD n = GetModuleFileNameW(module, path, 32768);
    require(n && n < 32768);
    std::wstring root(path, n);
    auto split = root.find_last_of(L"\\/"); require(split != std::wstring::npos); root.resize(split);
    split = root.find_last_of(L"\\/"); require(split != std::wstring::npos); root.resize(split);
    return root + L"\\frontend\\YimeTouchKeyboard.exe";
}
HANDLE authenticate(HANDLE pipe, const char*& reason) {
    reason = "peer-process-unavailable";
    ULONG pid = 0; require(GetNamedPipeClientProcessId(pipe, &pid) && pid && pid != GetCurrentProcessId());
    Handle process; process.h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid);
    require(process.h && WaitForSingleObject(process.h, 0) == WAIT_TIMEOUT);
    wchar_t image[32768]; DWORD size = 32768;
    require(QueryFullProcessImageNameW(process.h, 0, image, &size) != FALSE);
    reason = "peer-image-mismatch";
    require(_wcsicmp(std::wstring(image, size).c_str(), frontendImage().c_str()) == 0);
    DWORD a = 0, b = 0;
    reason = "peer-session-mismatch";
    require(ProcessIdToSessionId(pid, &a) && ProcessIdToSessionId(GetCurrentProcessId(), &b) && a == b);
    Handle left, right;
    reason = "peer-token-unavailable";
    require(OpenProcessToken(process.h, TOKEN_QUERY, &left.h) && OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &right.h));
    auto lu = userToken(left.h), ru = userToken(right.h);
    reason = "peer-user-mismatch";
    require(EqualSid(reinterpret_cast<TOKEN_USER*>(lu.data())->User.Sid, reinterpret_cast<TOKEN_USER*>(ru.data())->User.Sid) != FALSE);
    TOKEN_STATISTICS ls{}, rs{}; DWORD n = 0;
    reason = "peer-token-unavailable";
    require(GetTokenInformation(left.h, TokenStatistics, &ls, sizeof(ls), &n) && n == sizeof(ls));
    require(GetTokenInformation(right.h, TokenStatistics, &rs, sizeof(rs), &n) && n == sizeof(rs));
    reason = "peer-logon-mismatch";
    require(ls.AuthenticationId.LowPart == rs.AuthenticationId.LowPart && ls.AuthenticationId.HighPart == rs.AuthenticationId.HighPart);
    // A normal frontend must not gain an elevated application's edit rights.
    auto integrity = [](HANDLE token) {
        DWORD size = 0; GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &size);
        require(size && size < 65536); std::vector<BYTE> buffer(size);
        require(GetTokenInformation(token, TokenIntegrityLevel, buffer.data(), size, &size) != FALSE);
        auto sid = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(buffer.data())->Label.Sid;
        require(IsValidSid(sid) && *GetSidSubAuthorityCount(sid) > 0);
        return *GetSidSubAuthority(sid, *GetSidSubAuthorityCount(sid) - 1);
    };
    reason = "peer-integrity-mismatch";
    require(integrity(left.h) == integrity(right.h));
    HANDLE result = process.h; process.h = nullptr; return result;
}
std::wstring wide(const std::string& text) {
    require(!text.empty() && text.size() <= 4096 && text.find('\0') == std::string::npos);
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
    require(n > 0); std::wstring result(n, L'\0');
    require(MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), &result[0], n) == n);
    return result;
}
struct ForegroundIdentity { HWND window; DWORD thread; DWORD process; HWND focus; HWND root; };
ForegroundIdentity foregroundIdentity() noexcept {
    HWND window = GetForegroundWindow(); DWORD process = 0;
    GUITHREADINFO gui{sizeof(gui)};
    if (!GetGUIThreadInfo(0, &gui)) return {window, 0, 0, nullptr, nullptr};
    DWORD thread = GetWindowThreadProcessId(gui.hwndFocus, &process);
    return {window, thread, process, gui.hwndFocus, GetAncestor(gui.hwndFocus, GA_ROOT)};
}
struct Eligibility;
const char* actualEligibility(const Eligibility&) noexcept;
struct Eligibility {
    ComPtr<ITfThreadMgr> manager;
    ComPtr<ITfInputProcessorProfileMgr> profiles;
    GUID clsid{}, profile{};
    bool alive = true, keyFocused = true, threadFocused = true;
    const char* (*query)(const Eligibility&) noexcept = actualEligibility;
    const char* rejection() const noexcept {
        if (!alive) return "activation-ended";
        if (!keyFocused) return "key-focus-missing";
        if (!threadFocused) return "thread-focus-missing";
        return query(*this);
    }
};
const char* actualEligibility(const Eligibility& state) noexcept {
    BOOL focused = FALSE;
    if (!state.manager || FAILED(state.manager->IsThreadFocus(&focused))) return "thread-focus-unavailable";
    if (!focused) return "thread-focus-missing";
    TF_INPUTPROCESSORPROFILE active{};
    if (!state.profiles) return "profile-unavailable";
    const HRESULT result = state.profiles->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &active);
    if (FAILED(result)) return "profile-unavailable";
    if (result != S_OK || active.dwProfileType != TF_PROFILETYPE_INPUTPROCESSOR ||
        !IsEqualGUID(active.clsid, state.clsid) || !IsEqualGUID(active.guidProfile, state.profile))
        return "profile-inactive";
    return nullptr;
}
struct SessionIdentity {
    std::string activationId;
    uint64_t generation = 1;
    bool exhausted = false;
    bool advance() noexcept {
        if (generation == UINT64_MAX) { exhausted = true; return false; }
        ++generation; return true;
    }
    const char* rejection(const json& request) const {
        if (exhausted) return "generation-exhausted";
        if (!request.contains("activationId") || !request["activationId"].is_string() ||
            request["activationId"].get<std::string>() != activationId) return "stale-activation";
        if (!request.contains("generation") || !request["generation"].is_number_unsigned() ||
            request["generation"].get<uint64_t>() != generation) return "stale-generation";
        return nullptr;
    }
};
struct Lease {
    ComPtr<ITfThreadMgr> manager;
    ComPtr<ITfDocumentMgr> document;
    ComPtr<ITfContext> context;
    std::shared_ptr<Eligibility> eligibility;
    DWORD thread = GetCurrentThreadId();
    HWND window = nullptr;
    HWND focus = nullptr;
    bool active = false, completed = false, attempted = false;
    HRESULT outcome = E_PENDING;
    ForegroundIdentity (*foreground)() noexcept = foregroundIdentity;
    const char* rejection() const noexcept {
        const auto current = foreground();
        if (!active) return "lease-inactive";
        if (GetCurrentThreadId() != thread) return "callback-thread-mismatch";
        if (!eligibility) return "profile-unavailable";
        if (const auto why = eligibility->rejection()) return why;
        if (current.window != window) return "foreground-changed";
        if (!focus || current.focus != focus || current.root != window) return "focus-changed";
        if (current.thread != thread || current.process != GetCurrentProcessId()) return "focus-owner-mismatch";
        ComPtr<ITfDocumentMgr> doc; ComPtr<ITfContext> top;
        if (!manager || FAILED(manager->GetFocus(&doc)) || !doc) return "no-focused-document";
        if (doc.Get() != document.Get()) return "document-changed";
        if (FAILED(doc->GetTop(&top)) || !top) return "no-top-context";
        if (top.Get() != context.Get()) return "context-changed";
        TF_STATUS status{};
        if (context->GetStatus(&status) != S_OK) return "context-status-unavailable";
        if (status.dwDynamicFlags & TS_SD_READONLY) return "context-read-only";
        if (status.dwDynamicFlags & TS_SD_LOADING) return "context-loading";
        // A host COM call above may reenter a TSF revocation notification.
        if (!active || !eligibility->alive) return "lease-inactive";
        return nullptr;
    }
    bool valid() const noexcept { return rejection() == nullptr; }
};
// Pure observation: querying status cannot bind, revive, advance a generation,
// perform an edit, or erase an uncertain outcome in the frontend.
const char* sessionRejection(const SessionIdentity& identity, const std::shared_ptr<Lease>& lease,
    const json& request) {
    if (const auto why = identity.rejection(request)) return why;
    return lease ? lease->rejection() : "lease-inactive";
}

// Navigation/deletion use Unicode scalar boundaries, not half a surrogate pair.
HRESULT step(ITfRange* range, TfEditCookie cookie, int direction) {
    ComPtr<ITfRange> probe; HRESULT hr = range->Clone(&probe); if (FAILED(hr)) return hr;
    LONG moved = 0;
    if (direction < 0) hr = probe->ShiftStart(cookie, -2, &moved, nullptr);
    else hr = probe->ShiftEnd(cookie, 2, &moved, nullptr);
    if (FAILED(hr)) return hr;
    WCHAR text[2]{}; ULONG count = 0;
    hr = probe->GetText(cookie, 0, text, 2, &count); if (FAILED(hr)) return hr;
    int width = count == 2 && text[0] >= 0xd800 && text[0] <= 0xdbff && text[1] >= 0xdc00 && text[1] <= 0xdfff ? 2 : 1;
    if (direction < 0) { hr = range->ShiftStart(cookie, -width, &moved, nullptr); if (SUCCEEDED(hr)) hr = range->Collapse(cookie, TF_ANCHOR_START); }
    else { hr = range->ShiftEnd(cookie, width, &moved, nullptr); if (SUCCEEDED(hr)) hr = range->Collapse(cookie, TF_ANCHOR_END); }
    return hr;
}

class Edit final : public ITfEditSession {
public:
    Edit(std::shared_ptr<Lease> lease, std::wstring text, std::string key, bool extend)
        : lease_(std::move(lease)), text_(std::move(text)), key_(std::move(key)), extend_(extend) { YimeModuleAddRef(); }
    ~Edit() { YimeModuleRelease(); }
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid != __uuidof(IUnknown) && iid != __uuidof(ITfEditSession)) return E_NOINTERFACE;
        *out = static_cast<ITfEditSession*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
    STDMETHODIMP_(ULONG) Release() override { auto n = --refs_; if (!n) delete this; return n; }
    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        HRESULT hr = E_ABORT;
        // This check is deliberately inside the actual edit callback.
        if (lease_->valid()) { lease_->attempted = true; hr = apply(cookie); }
        lease_->outcome = hr; lease_->completed = true; return hr;
    }
private:
    HRESULT apply(TfEditCookie cookie) noexcept {
        auto* context = lease_->context.Get();
        TF_SELECTION selection{}; ULONG fetched = 0;
        HRESULT hr = context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
        if (FAILED(hr) || fetched != 1 || !selection.range) return FAILED(hr) ? hr : E_FAIL;
        ComPtr<ITfRange> range; range.Attach(selection.range);
        auto select = [&](ITfRange* r, TfActiveSelEnd end) {
            if (!lease_->valid()) return E_ABORT;
            TF_SELECTION value{}; value.range = r; value.style.ase = end; value.style.fInterimChar = FALSE;
            return context->SetSelection(cookie, 1, &value);
        };
        if (!text_.empty()) {
            if (!lease_->valid()) return E_ABORT;
            hr = range->SetText(cookie, 0, text_.data(), static_cast<LONG>(text_.size()));
            if (SUCCEEDED(hr)) hr = range->Collapse(cookie, TF_ANCHOR_END);
            return SUCCEEDED(hr) ? select(range.Get(), TF_AE_END) : hr;
        }
        BOOL empty = FALSE; hr = range->IsEmpty(cookie, &empty); if (FAILED(hr)) return hr;
        if (key_ == "SelectAll") {
            ComPtr<ITfRange> start, end;
            hr = context->GetStart(cookie, &start); if (FAILED(hr)) return hr;
            hr = context->GetEnd(cookie, &end); if (FAILED(hr)) return hr;
            hr = start->ShiftEndToRange(cookie, end.Get(), TF_ANCHOR_END);
            return SUCCEEDED(hr) ? select(start.Get(), TF_AE_END) : hr;
        }
        if (key_ == "Backspace" || key_ == "Delete") {
            if (empty) {
                ComPtr<ITfRange> edge; hr = range->Clone(&edge); if (FAILED(hr)) return hr;
                hr = step(edge.Get(), cookie, key_ == "Backspace" ? -1 : 1); if (FAILED(hr)) return hr;
                hr = key_ == "Backspace" ? range->ShiftStartToRange(cookie, edge.Get(), TF_ANCHOR_START)
                    : range->ShiftEndToRange(cookie, edge.Get(), TF_ANCHOR_END);
                if (FAILED(hr)) return hr;
            }
            if (!lease_->valid()) return E_ABORT;
            hr = range->SetText(cookie, 0, L"", 0); if (FAILED(hr)) return hr;
            hr = range->Collapse(cookie, TF_ANCHOR_START);
            return SUCCEEDED(hr) ? select(range.Get(), TF_AE_END) : hr;
        }
        const bool back = key_ == "ArrowLeft" || key_ == "Home";
        ComPtr<ITfRange> caret; hr = range->Clone(&caret); if (FAILED(hr)) return hr;
        TfAnchor active = selection.style.ase == TF_AE_START ? TF_ANCHOR_START : TF_ANCHOR_END;
        hr = caret->Collapse(cookie, extend_ ? active : back ? TF_ANCHOR_START : TF_ANCHOR_END);
        if (FAILED(hr)) return hr;
        if (key_ == "Home" || key_ == "End") {
            // Defined as document boundaries for this TSF route, independent of visual wrapping.
            caret.Reset(); hr = back ? context->GetStart(cookie, &caret) : context->GetEnd(cookie, &caret);
        } else if (empty || extend_) hr = step(caret.Get(), cookie, back ? -1 : 1);
        if (FAILED(hr)) return hr;
        if (!extend_) return select(caret.Get(), TF_AE_END);
        ComPtr<ITfRange> anchor; hr = range->Clone(&anchor); if (FAILED(hr)) return hr;
        hr = anchor->Collapse(cookie, active == TF_ANCHOR_START ? TF_ANCHOR_END : TF_ANCHOR_START);
        if (FAILED(hr)) return hr;
        LONG order = 0; hr = caret->CompareStart(cookie, anchor.Get(), TF_ANCHOR_START, &order);
        if (FAILED(hr)) return hr;
        if (order < 0) { hr = caret->ShiftEndToRange(cookie, anchor.Get(), TF_ANCHOR_END); return SUCCEEDED(hr) ? select(caret.Get(), TF_AE_START) : hr; }
        hr = anchor->ShiftEndToRange(cookie, caret.Get(), TF_ANCHOR_END);
        return SUCCEEDED(hr) ? select(anchor.Get(), TF_AE_END) : hr;
    }
    std::atomic<ULONG> refs_{1};
    std::shared_ptr<Lease> lease_;
    std::wstring text_;
    std::string key_;
    bool extend_;
};
}

struct TouchFrontendEndpoint::Impl : std::enable_shared_from_this<TouchFrontendEndpoint::Impl> {
    enum class Phase { Connecting, Reading, Editing, Writing };
    ComPtr<ITfThreadMgr> manager;
    TfClientId client;
    HWND window = nullptr;
    HMODULE module = nullptr;
    HANDLE pipe = INVALID_HANDLE_VALUE, peer = nullptr;
    OVERLAPPED io{};
    bool pending = false, closeAfterWrite = false;
    Phase phase = Phase::Connecting;
    std::string input, output;
    char buffer[MaxFrame + 1]{};
    uint64_t sequence = 0;
    SessionIdentity identity;
    std::shared_ptr<Eligibility> eligibility = std::make_shared<Eligibility>();
    ULONGLONG deadline = 0;
    std::shared_ptr<Lease> lease;
#ifdef YIME_TOUCH_FRONTEND_MEMORY_TEST
    bool memoryOnly = false;
    json memoryResponse;
    ForegroundIdentity (*memoryForeground)() noexcept = nullptr;
    // No COM activation, pipe, timer, real focus, or authentication in this path.
    Impl(ITfThreadMgr* m, TfClientId c, std::shared_ptr<Eligibility> state,
        const std::string& activation, ForegroundIdentity (*foreground)() noexcept)
        : manager(m), client(c), eligibility(std::move(state)), memoryOnly(true), memoryForeground(foreground) {
        identity.activationId = activation; YimeModuleAddRef();
    }
#endif
    Impl(ITfThreadMgr* m, TfClientId c, REFCLSID clsid, REFGUID profile, bool keyFocused) : manager(m), client(c) {
        eligibility->manager = m; eligibility->clsid = clsid; eligibility->profile = profile;
        eligibility->keyFocused = keyFocused;
        require(SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&eligibility->profiles))));
        GUID activation{}; require(SUCCEEDED(CoCreateGuid(&activation)));
        wchar_t value[40]{}; require(StringFromGUID2(activation, value, 40) != 0);
        for (const auto* p = value; *p; ++p) identity.activationId.push_back(static_cast<char>(*p));
        io.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr); require(io.hEvent != nullptr);
        YimeModuleAddRef();
    }
    ~Impl() {
        eligibility->alive = false;
        invalidate(); closePipe();
        if (window) { KillTimer(window, 1); DestroyWindow(window); }
        if (module) UnregisterClassW(L"Yime18uFrontendThread.v1", module);
        if (io.hEvent) CloseHandle(io.hEvent);
        YimeModuleRelease();
    }
    void invalidate() noexcept {
        if (lease && lease->active) { lease->active = false; identity.advance(); }
    }
    void closePipe() noexcept {
        invalidate(); lease.reset();
        if (pipe != INVALID_HANDLE_VALUE) {
            if (pending) { CancelIoEx(pipe, &io); DWORD count = 0; GetOverlappedResult(pipe, &io, &count, TRUE); }
            CloseHandle(pipe); pipe = INVALID_HANDLE_VALUE;
        }
        if (peer) { CloseHandle(peer); peer = nullptr; }
        pending = false; input.clear(); output.clear(); sequence = 0; closeAfterWrite = false;
    }
    static LRESULT CALLBACK Proc(HWND h, UINT message, WPARAM w, LPARAM l) noexcept {
        auto* self = reinterpret_cast<Impl*>(GetWindowLongPtrW(h, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            self = static_cast<Impl*>(reinterpret_cast<CREATESTRUCTW*>(l)->lpCreateParams);
            SetWindowLongPtrW(h, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
        if (message == WM_TIMER && self && w == 1) {
            // RequestEditSession may synchronously reenter profile deactivation.
            // Pin the dispatcher until that entire host callback has returned.
            auto keep = self->weak_from_this().lock();
            if (keep) keep->tick();
            return 0;
        }
        if (message == WM_NCDESTROY) SetWindowLongPtrW(h, GWLP_USERDATA, 0);
        return DefWindowProcW(h, message, w, l);
    }
    void start() {
        require(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(&Proc), &module) != FALSE);
        WNDCLASSW cls{}; cls.lpfnWndProc = Proc; cls.hInstance = module; cls.lpszClassName = L"Yime18uFrontendThread.v1";
        require(RegisterClassW(&cls) || GetLastError() == ERROR_CLASS_ALREADY_EXISTS);
        window = CreateWindowExW(0, cls.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, module, this);
        require(window && SetTimer(window, 1, 10, nullptr));
        listen();
    }
    void resetIO() { require(!pending); ResetEvent(io.hEvent); io.Internal = io.InternalHigh = 0; io.Offset = io.OffsetHigh = 0; }
    void listen() {
#ifdef YIME_TOUCH_FRONTEND_MEMORY_TEST
        if (memoryOnly) { closePipe(); phase = Phase::Connecting; return; }
#endif
        closePipe(); resetIO();
        std::wstring name = L"\\\\.\\pipe\\Yime18u.Frontend.v2." + std::to_wstring(GetCurrentProcessId()) + L"." + std::to_wstring(GetCurrentThreadId());
        pipe = CreateNamedPipeW(name.c_str(), PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, MaxFrame, MaxFrame, 0, nullptr);
        require(pipe != INVALID_HANDLE_VALUE);
        phase = Phase::Connecting; deadline = 0;
        if (ConnectNamedPipe(pipe, &io)) SetEvent(io.hEvent);
        else { DWORD e = GetLastError(); if (e == ERROR_PIPE_CONNECTED) SetEvent(io.hEvent); else { require(e == ERROR_IO_PENDING); pending = true; } }
    }
    void read() {
        phase = Phase::Reading; resetIO(); DWORD n = 0;
        if (ReadFile(pipe, buffer, MaxFrame - static_cast<DWORD>(input.size()), &n, &io)) { io.InternalHigh = n; SetEvent(io.hEvent); }
        else { require(GetLastError() == ERROR_IO_PENDING); pending = true; }
    }
    void reply(bool ok, const char* outcome, const char* reason = nullptr) {
        json response{{"version", 2}, {"sequence", sequence}, {"ok", ok}, {"outcome", outcome}, {"retryAllowed", false},
            {"activationId", identity.activationId}, {"generation", identity.generation}};
        if (reason) response["reason"] = reason;
        output = response.dump() + "\n";
        phase = Phase::Writing;
#ifdef YIME_TOUCH_FRONTEND_MEMORY_TEST
        if (memoryOnly) { memoryResponse = json::parse(output); return; }
#endif
        resetIO(); DWORD n = 0;
        if (WriteFile(pipe, output.data(), static_cast<DWORD>(output.size()), &n, &io)) { io.InternalHigh = n; SetEvent(io.hEvent); }
        else { require(GetLastError() == ERROR_IO_PENDING); pending = true; }
    }
    void dispatch() {
        const auto q = json::parse(input); input.clear();
        require(q.is_object() && q.size() >= 3 && q.value("version", 0) == 2 &&
            q.at("sequence").is_number_unsigned() && sequence < UINT64_MAX && q.at("sequence").get<uint64_t>() == sequence + 1);
        ++sequence;
        const auto op = q.at("operation").get<std::string>();
        if (op == "bind") {
            require(sequence == 1 && q.size() == 5 && q.at("window").is_number_unsigned() && q.at("focus").is_number_unsigned());
            require(identity.advance());
            lease = std::make_shared<Lease>(); lease->manager = manager; lease->eligibility = eligibility;
#ifdef YIME_TOUCH_FRONTEND_MEMORY_TEST
            if (memoryOnly) lease->foreground = memoryForeground;
#endif
            lease->window = reinterpret_cast<HWND>(q.at("window").get<uint64_t>());
            lease->focus = reinterpret_cast<HWND>(q.at("focus").get<uint64_t>());
            auto reject = [&](const char* why) { invalidate(); closeAfterWrite = true; reply(false, "bind-rejected", why); };
            if (FAILED(manager->GetFocus(&lease->document)) || !lease->document) { reject("no-focused-document"); return; }
            if (FAILED(lease->document->GetTop(&lease->context)) || !lease->context) { reject("no-top-context"); return; }
            lease->active = true;
            if (const auto why = lease->rejection()) { reject(why); return; }
            reply(true, "bound"); return;
        }
        if (op == "status") {
            require(q.size() == 5);
            const auto why = sessionRejection(identity, lease, q);
            reply(true, why ? "unavailable" : "ready", why); return;
        }
        if (const auto why = sessionRejection(identity, lease, q)) {
            closeAfterWrite = true; reply(false, "failed", why); return;
        }
        if (op == "close") { require(q.size() == 5); closeAfterWrite = true; reply(true, "closed"); invalidate(); return; }
        require(op == "edit" && q.size() == 8);
        const auto text = q.at("text").get<std::string>();
        auto key = q.at("key").get<std::string>();
        const bool extend = q.at("extend").get<bool>();
        require(text.empty() != key.empty());
        std::wstring content;
        if (!text.empty()) { require(!extend); content = wide(text); }
        else {
            require(key == "Enter" || key == "Tab" || key == "Backspace" || key == "Delete" || key == "ArrowLeft" || key == "ArrowRight" || key == "Home" || key == "End" || key == "SelectAll");
            require(!extend || key == "ArrowLeft" || key == "ArrowRight" || key == "Home" || key == "End");
            if (key == "Enter") content = L"\r\n";
            if (key == "Tab") content = L"\t";
        }
        lease->completed = lease->attempted = false; lease->outcome = E_PENDING;
        auto* edit = new Edit(lease, std::move(content), key, extend);
        phase = Phase::Editing;
        HRESULT result = E_FAIL;
        const HRESULT request = lease->context->RequestEditSession(client, edit, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, &result);
        edit->Release();
        if (FAILED(request) || (result != TF_S_ASYNC && !lease->completed)) {
            lease->completed = true;
            lease->outcome = FAILED(request) ? request : FAILED(result) ? result : E_UNEXPECTED;
        }
    }
    void tick() noexcept {
        try {
            if (pipe == INVALID_HANDLE_VALUE
#ifdef YIME_TOUCH_FRONTEND_MEMORY_TEST
                && !memoryOnly
#endif
                ) return;
            if (lease && lease->active && !lease->valid()) invalidate();
            if (peer && WaitForSingleObject(peer, 0) != WAIT_TIMEOUT) { listen(); return; }
            if (deadline && GetTickCount64() > deadline) { listen(); return; }
            if (phase == Phase::Editing) {
                if (!lease || !lease->completed) return;
                const bool ok = lease->active && lease->outcome == S_OK;
                closeAfterWrite = !ok;
                reply(ok, ok ? "applied" : lease->attempted ? "unknown" : "failed"); return;
            }
#ifdef YIME_TOUCH_FRONTEND_MEMORY_TEST
            if (memoryOnly) return;
#endif
            if (WaitForSingleObject(io.hEvent, 0) != WAIT_OBJECT_0) return;
            DWORD n = static_cast<DWORD>(io.InternalHigh);
            if (pending) { require(GetOverlappedResult(pipe, &io, &n, FALSE) != FALSE); pending = false; }
            switch (phase) {
            case Phase::Connecting: {
                const char* reason = "peer-process-unavailable";
                deadline = GetTickCount64() + 5000;
                try { peer = authenticate(pipe, reason); }
                catch (...) {
                    // Fixed vocabulary only. No peer path, token, or document
                    // data is disclosed and no request is dispatched.
                    sequence = 1; closeAfterWrite = true;
                    reply(false, "bind-rejected", reason); break;
                }
                read(); break;
            }
            case Phase::Reading:
                if (!deadline) deadline = GetTickCount64() + 5000;
                require(n && input.size() + n <= MaxFrame); input.append(buffer, n);
                if (input.back() == '\n') { require(input.find('\n') == input.size() - 1); deadline = GetTickCount64() + 5000; dispatch(); }
                else { require(input.size() < MaxFrame); read(); }
                break;
            case Phase::Writing:
                require(n == output.size());
                if (closeAfterWrite) listen(); else { deadline = 0; read(); }
                break;
            default: break;
            }
        } catch (...) { closePipe(); try { listen(); } catch (...) { closePipe(); } }
    }
};
TouchFrontendEndpoint::TouchFrontendEndpoint(ITfThreadMgr* manager, TfClientId client,
    REFCLSID clsid, REFGUID profile, bool keyFocused)
    : impl_(std::make_shared<Impl>(manager, client, clsid, profile, keyFocused)) { impl_->start(); }
TouchFrontendEndpoint::~TouchFrontendEndpoint() { impl_->eligibility->alive = false; impl_->invalidate(); }
void TouchFrontendEndpoint::Invalidate() noexcept { impl_->invalidate(); }
void TouchFrontendEndpoint::SetKeyFocus(bool focused) noexcept {
    impl_->eligibility->keyFocused = focused;
    if (!focused) impl_->invalidate();
}
void TouchFrontendEndpoint::SetThreadFocus(bool focused) noexcept {
    impl_->eligibility->threadFocused = focused;
    impl_->invalidate();
}
