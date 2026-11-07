#include "TouchFrontendEndpoint.h"
#include "TouchFrontendDiagnostic.h"
#include "ModuleState.h"
#include <windows.h>
#include <sddl.h>
#include <wrl/client.h>
#include <nlohmann/json.hpp>
#include <atomic>
#include <memory>
#include <string>
#include <string_view>
#include <vector>
#include <stdexcept>
#include <algorithm>
#include <climits>

using Microsoft::WRL::ComPtr;
using json = nlohmann::json;
namespace td = yime::touchdiag;
namespace {
void observe(td::Recorder* recorder, td::Record record) noexcept {
    if (recorder) recorder->emit(record);
}
td::Action diagnosticAction(const std::string& key, bool hasText) noexcept {
    if (hasText) return td::Action::Insert;
    if (key == "Backspace") return td::Action::Backspace;
    if (key == "Delete") return td::Action::Delete;
    if (key == "ArrowLeft") return td::Action::ArrowLeft;
    if (key == "ArrowRight") return td::Action::ArrowRight;
    if (key == "Home") return td::Action::Home;
    if (key == "End") return td::Action::End;
    if (key == "SelectAll") return td::Action::SelectAll;
    if (key == "Enter") return td::Action::Enter;
    if (key == "Tab") return td::Action::Tab;
    return td::Action::None;
}
int diagnosticRejection(const char* reason) noexcept {
    if (!reason) return 0;
    // Stable numeric vocabulary only; never emit arbitrary reason strings.
    constexpr const char* reasons[] = {
        "activation-ended", "key-focus-missing", "thread-focus-missing", "thread-focus-unavailable",
        "profile-unavailable", "profile-inactive", "lease-inactive", "callback-thread-mismatch",
        "foreground-changed", "focus-changed", "focus-owner-mismatch", "no-focused-document",
        "document-changed", "no-top-context", "context-changed", "context-status-unavailable",
        "context-read-only", "context-loading", "generation-exhausted", "stale-activation", "stale-generation"
    };
    for (int i = 0; i < static_cast<int>(std::size(reasons)); ++i)
        if (std::string_view(reason) == reasons[i]) return i + 1;
    return -1;
}
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
const char* observedEligibility(const Eligibility&, td::Recorder*) noexcept;
struct Eligibility {
    ComPtr<ITfThreadMgr> manager;
    ComPtr<ITfInputProcessorProfileMgr> profiles;
    GUID clsid{}, profile{};
    bool alive = true, keyFocused = true, threadFocused = true;
    const char* (*query)(const Eligibility&) noexcept = actualEligibility;
    const char* rejection(td::Recorder* diagnostic = nullptr) const noexcept {
        observe(diagnostic, {td::Stage::Eligibility, S_OK, false, 0, 0, 0,
            (alive ? 1ULL : 0ULL) | (keyFocused ? 2ULL : 0ULL) | (threadFocused ? 4ULL : 0ULL)});
        if (!alive) return "activation-ended";
        if (!keyFocused) return "key-focus-missing";
        if (!threadFocused) return "thread-focus-missing";
        return query == actualEligibility ? observedEligibility(*this, diagnostic) : query(*this);
    }
};
const char* actualEligibility(const Eligibility& state) noexcept {
    return observedEligibility(state, nullptr);
}
const char* observedEligibility(const Eligibility& state, td::Recorder* diagnostic) noexcept {
    BOOL focused = FALSE;
    if (!state.manager) return "thread-focus-unavailable";
    const HRESULT threadResult = state.manager->IsThreadFocus(&focused);
    observe(diagnostic, {td::Stage::ThreadFocus, threadResult, true, 0, 0, 0, 0, focused});
    if (threadResult != S_OK) return "thread-focus-unavailable";
    if (!focused) return "thread-focus-missing";
    TF_INPUTPROCESSORPROFILE active{};
    if (!state.profiles) return "profile-unavailable";
    const HRESULT result = state.profiles->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &active);
    observe(diagnostic, {td::Stage::ActiveProfile, result, true, 0, 0, 0, active.dwProfileType,
        IsEqualGUID(active.clsid, state.clsid), IsEqualGUID(active.guidProfile, state.profile)});
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
    mutable td::Recorder diagnostic;
    ForegroundIdentity (*foreground)() noexcept = foregroundIdentity;
    const char* rejection(td::Recorder* trace = nullptr) const noexcept {
        const auto current = foreground();
        // Only observations from the existing checks; no extra COM/focus reads.
        observe(trace, {td::Stage::Foreground, S_OK, false, thread, current.thread, current.process,
            (current.window == window ? 1ULL : 0ULL) | (current.focus == focus && focus ? 2ULL : 0ULL) |
            (current.root == window ? 4ULL : 0ULL), active, GetCurrentThreadId() == thread});
        if (!active) return "lease-inactive";
        if (GetCurrentThreadId() != thread) return "callback-thread-mismatch";
        if (!eligibility) return "profile-unavailable";
        if (const auto why = eligibility->rejection(trace)) return why;
        if (current.window != window) return "foreground-changed";
        if (!focus || current.focus != focus || current.root != window) return "focus-changed";
        if (current.thread != thread || current.process != GetCurrentProcessId()) return "focus-owner-mismatch";
        ComPtr<ITfDocumentMgr> doc; ComPtr<ITfContext> top;
        if (!manager) return "no-focused-document";
        HRESULT queryResult = manager->GetFocus(&doc);
        observe(trace, {td::Stage::Document, queryResult, true, 0, 0, 0, 0, doc != nullptr, doc.Get() == document.Get()});
        if (FAILED(queryResult) || !doc) return "no-focused-document";
        if (doc.Get() != document.Get()) return "document-changed";
        queryResult = doc->GetTop(&top);
        observe(trace, {td::Stage::Context, queryResult, true, 0, 0, 0, 0, top != nullptr, top.Get() == context.Get()});
        if (FAILED(queryResult) || !top) return "no-top-context";
        if (top.Get() != context.Get()) return "context-changed";
        TF_STATUS status{};
        queryResult = context->GetStatus(&status);
        observe(trace, {td::Stage::Status, queryResult, true, 0, 0, status.dwStaticFlags, status.dwDynamicFlags});
        if (queryResult != S_OK) return "context-status-unavailable";
        if (status.dwDynamicFlags & TS_SD_READONLY) return "context-read-only";
        if (status.dwDynamicFlags & TS_SD_LOADING) return "context-loading";
        // A host COM call above may reenter a TSF revocation notification.
        if (!active || !eligibility->alive) return "lease-inactive";
        return nullptr;
    }
    bool valid(td::Recorder* trace = nullptr) const noexcept {
        const char* why = rejection(trace);
        observe(trace, {td::Stage::Lease, S_OK, false, 0, 0, 0, 0, why == nullptr, diagnosticRejection(why)});
        return why == nullptr;
    }
};
// Pure observation: querying status cannot bind, revive, advance a generation,
// perform an edit, or erase an uncertain outcome in the frontend.
const char* sessionRejection(const SessionIdentity& identity, const std::shared_ptr<Lease>& lease,
    const json& request, td::Recorder* diagnostic = nullptr) {
    if (const auto why = identity.rejection(request)) {
        observe(diagnostic, {td::Stage::Lease, S_OK, false, 0, 0, 0, 0, 0, diagnosticRejection(why)});
        return why;
    }
    const char* why = lease ? lease->rejection(diagnostic) : "lease-inactive";
    observe(diagnostic, {td::Stage::Lease, S_OK, false, 0, 0, 0, 0, why == nullptr, diagnosticRejection(why)});
    return why;
}

// Navigation/deletion use Unicode scalar boundaries, not half a surrogate pair.
HRESULT step(ITfRange* range, TfEditCookie cookie, int direction, td::Recorder* diagnostic = nullptr) {
    ComPtr<ITfRange> probe; HRESULT hr = range->Clone(&probe);
    observe(diagnostic, {td::Stage::Clone, hr, true}); if (FAILED(hr)) return hr;
    LONG moved = 0;
    if (direction < 0) hr = probe->ShiftStart(cookie, -2, &moved, nullptr);
    else hr = probe->ShiftEnd(cookie, 2, &moved, nullptr);
    observe(diagnostic, {td::Stage::ProbeShift, hr, true, direction < 0 ? -2 : 2, moved});
    if (FAILED(hr)) return hr;
    WCHAR text[2]{}; ULONG count = 0;
    hr = probe->GetText(cookie, 0, text, 2, &count);
    observe(diagnostic, {td::Stage::ProbeText, hr, true, 2, 0, count}); if (FAILED(hr)) return hr;
    int width = count == 2 && text[0] >= 0xd800 && text[0] <= 0xdbff && text[1] >= 0xdc00 && text[1] <= 0xdfff ? 2 : 1;
    // Keep the existing width/movement semantics, including boundary no-ops.
    if (direction < 0) hr = range->ShiftStart(cookie, -width, &moved, nullptr);
    else hr = range->ShiftEnd(cookie, width, &moved, nullptr);
    observe(diagnostic, {td::Stage::StepShift, hr, true, direction < 0 ? -width : width, moved, count, 0, width == 2});
    if (SUCCEEDED(hr)) {
        hr = range->Collapse(cookie, direction < 0 ? TF_ANCHOR_START : TF_ANCHOR_END);
        observe(diagnostic, {td::Stage::Collapse, hr, true, 0, 0, 0, 0, direction < 0 ? TF_ANCHOR_START : TF_ANCHOR_END});
    }
    return hr;
}

class Edit final : public ITfEditSession {
public:
    Edit(std::shared_ptr<Lease> lease, std::wstring text, std::string key, bool extend)
        : lease_(std::move(lease)), text_(std::move(text)), key_(std::move(key)), extend_(extend) {
        lease_->diagnostic.action = diagnosticAction(key_, !text_.empty() && key_.empty());
        lease_->diagnostic.extend = extend_;
        YimeModuleAddRef();
    }
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
        auto* diagnostic = &lease_->diagnostic;
        observe(diagnostic, {td::Stage::Callback});
        // This check is deliberately inside the actual edit callback.
        if (lease_->valid(diagnostic)) { lease_->attempted = true; hr = apply(cookie); }
        lease_->outcome = hr; lease_->completed = true;
        observe(diagnostic, {td::Stage::Complete, hr, true, 0, 0, 0, 0, lease_->attempted, lease_->completed});
        return hr;
    }
private:
    HRESULT apply(TfEditCookie cookie) noexcept {
        auto* context = lease_->context.Get();
        auto* diagnostic = &lease_->diagnostic;
        TF_SELECTION selection{}; ULONG fetched = 0;
        HRESULT hr = context->GetSelection(cookie, TF_DEFAULT_SELECTION, 1, &selection, &fetched);
        observe(diagnostic, {td::Stage::GetSelection, hr, true, 1, selection.range != nullptr, fetched,
            static_cast<uint64_t>(selection.style.ase), selection.style.fInterimChar});
        if (FAILED(hr) || fetched != 1 || !selection.range) return FAILED(hr) ? hr : E_FAIL;
        ComPtr<ITfRange> range; range.Attach(selection.range);
        auto select = [&](ITfRange* r, TfActiveSelEnd end) {
            if (!lease_->valid(diagnostic)) return E_ABORT;
            TF_SELECTION value{}; value.range = r; value.style.ase = end; value.style.fInterimChar = FALSE;
            const HRESULT result = context->SetSelection(cookie, 1, &value);
            observe(diagnostic, {td::Stage::SetSelection, result, true, 1, 0, 0, static_cast<uint64_t>(end)});
            return result;
        };
        auto collapse = [&](ITfRange* r, TfAnchor anchor) {
            const HRESULT result = r->Collapse(cookie, anchor);
            observe(diagnostic, {td::Stage::Collapse, result, true, 0, 0, 0, 0, anchor});
            return result;
        };
        auto clone = [&](ITfRange* r, ITfRange** copy) {
            const HRESULT result = r->Clone(copy);
            observe(diagnostic, {td::Stage::Clone, result, true});
            return result;
        };
        if (!text_.empty()) {
            if (!lease_->valid(diagnostic)) return E_ABORT;
            hr = range->SetText(cookie, 0, text_.data(), static_cast<LONG>(text_.size()));
            // Do not log the insertion length or any part of the text payload.
            observe(diagnostic, {td::Stage::SetText, hr, true, 0, 0, 0, 0, 0});
            if (SUCCEEDED(hr)) hr = collapse(range.Get(), TF_ANCHOR_END);
            return SUCCEEDED(hr) ? select(range.Get(), TF_AE_END) : hr;
        }
        BOOL empty = FALSE; hr = range->IsEmpty(cookie, &empty);
        observe(diagnostic, {td::Stage::IsEmpty, hr, true, 0, 0, 0, 0, empty}); if (FAILED(hr)) return hr;
        if (key_ == "SelectAll") {
            ComPtr<ITfRange> start, end;
            hr = context->GetStart(cookie, &start); if (FAILED(hr)) return hr;
            hr = context->GetEnd(cookie, &end); if (FAILED(hr)) return hr;
            hr = start->ShiftEndToRange(cookie, end.Get(), TF_ANCHOR_END);
            observe(diagnostic, {td::Stage::ExtendRange, hr, true});
            return SUCCEEDED(hr) ? select(start.Get(), TF_AE_END) : hr;
        }
        if (key_ == "Backspace" || key_ == "Delete") {
            if (empty) {
                ComPtr<ITfRange> edge; hr = clone(range.Get(), &edge); if (FAILED(hr)) return hr;
                hr = step(edge.Get(), cookie, key_ == "Backspace" ? -1 : 1, diagnostic); if (FAILED(hr)) return hr;
                hr = key_ == "Backspace" ? range->ShiftStartToRange(cookie, edge.Get(), TF_ANCHOR_START)
                    : range->ShiftEndToRange(cookie, edge.Get(), TF_ANCHOR_END);
                observe(diagnostic, {td::Stage::ExtendRange, hr, true});
                if (FAILED(hr)) return hr;
            }
            if (!lease_->valid(diagnostic)) return E_ABORT;
            hr = range->SetText(cookie, 0, L"", 0);
            observe(diagnostic, {td::Stage::SetText, hr, true, 0, 0, 0, 0, 1}); if (FAILED(hr)) return hr;
            hr = collapse(range.Get(), TF_ANCHOR_START);
            return SUCCEEDED(hr) ? select(range.Get(), TF_AE_END) : hr;
        }
        const bool back = key_ == "ArrowLeft" || key_ == "Home";
        ComPtr<ITfRange> caret; hr = clone(range.Get(), &caret); if (FAILED(hr)) return hr;
        TfAnchor active = selection.style.ase == TF_AE_START ? TF_ANCHOR_START : TF_ANCHOR_END;
        hr = collapse(caret.Get(), extend_ ? active : back ? TF_ANCHOR_START : TF_ANCHOR_END);
        if (FAILED(hr)) return hr;
        if (key_ == "Home" || key_ == "End") {
            // Defined as document boundaries for this TSF route, independent of visual wrapping.
            caret.Reset(); hr = back ? context->GetStart(cookie, &caret) : context->GetEnd(cookie, &caret);
        } else if (empty || extend_) hr = step(caret.Get(), cookie, back ? -1 : 1, diagnostic);
        if (FAILED(hr)) return hr;
        if (!extend_) return select(caret.Get(), TF_AE_END);
        ComPtr<ITfRange> anchor; hr = clone(range.Get(), &anchor); if (FAILED(hr)) return hr;
        hr = collapse(anchor.Get(), active == TF_ANCHOR_START ? TF_ANCHOR_END : TF_ANCHOR_START);
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
    // An opt-in observer shared by this endpoint's leases, never a protocol field.
    std::shared_ptr<td::Budget> diagnosticBudget;
    uint64_t diagnosticInstance = 0;
    bool diagnosticEnabled = false, diagnosticEdit = false, diagnosticRequested = false;
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
        if (td::Recorder::EnabledFromEnvironment()) {
            // Diagnostics cannot make activation fail when their budget cannot be allocated.
            try {
                static std::atomic<uint64_t> instances{0};
                diagnosticBudget = std::make_shared<td::Budget>();
                diagnosticInstance = ++instances;
                diagnosticEnabled = diagnosticInstance != 0;
            } catch (...) {}
        }
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
        if (diagnosticEdit && lease) lease->diagnostic.emit({td::Stage::Disconnect,
            diagnosticRequested ? lease->outcome : E_PENDING, diagnosticRequested && lease->completed,
            0, 0, 0, 0, diagnosticRequested && lease->attempted, diagnosticRequested && lease->completed});
        invalidate(); lease.reset();
        if (pipe != INVALID_HANDLE_VALUE) {
            if (pending) { CancelIoEx(pipe, &io); DWORD count = 0; GetOverlappedResult(pipe, &io, &count, TRUE); }
            CloseHandle(pipe); pipe = INVALID_HANDLE_VALUE;
        }
        if (peer) { CloseHandle(peer); peer = nullptr; }
        pending = false; input.clear(); output.clear(); sequence = 0; closeAfterWrite = false;
        diagnosticEdit = diagnosticRequested = false;
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
        if (diagnosticEdit && lease) lease->diagnostic.emit({td::Stage::Reply,
            diagnosticRequested ? lease->outcome : E_PENDING, diagnosticRequested && lease->completed, 0, 0,
            std::string_view(outcome) == "applied" ? 1 : std::string_view(outcome) == "unknown" ? 2 : 3,
            identity.generation, ok, false});
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
        diagnosticEdit = op == "edit";
        diagnosticRequested = false;
        if (op == "bind") {
            require(sequence == 1 && q.size() == 5 && q.at("window").is_number_unsigned() && q.at("focus").is_number_unsigned());
            require(identity.advance());
            lease = std::make_shared<Lease>(); lease->manager = manager; lease->eligibility = eligibility;
            lease->diagnostic = td::Recorder(diagnosticBudget, diagnosticInstance);
            lease->diagnostic.enabled = diagnosticEnabled;
            lease->diagnostic.generation = identity.generation;
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
        auto* diagnostic = diagnosticEdit && lease ? &lease->diagnostic : nullptr;
        if (diagnostic && diagnostic->enabled) {
            diagnostic->sequence = sequence;
            diagnostic->action = td::Action::None;
            diagnostic->extend = false;
            // Classify only fixed editing verbs; never pass request strings to the sink.
            auto keyField = q.find("key"), textField = q.find("text"), extendField = q.find("extend");
            if (keyField != q.end() && keyField->is_string())
                diagnostic->action = diagnosticAction(keyField->get_ref<const std::string&>(),
                    textField != q.end() && textField->is_string() && !textField->get_ref<const std::string&>().empty());
            if (extendField != q.end() && extendField->is_boolean()) diagnostic->extend = extendField->get<bool>();
            observe(diagnostic, {td::Stage::Begin, S_OK, false, 0, 0, 0, identity.generation});
        }
        if (const auto why = sessionRejection(identity, lease, q, diagnostic)) {
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
        diagnosticRequested = true;
        // Host callbacks may reenter listen()/closePipe() and clear or replace
        // the endpoint lease. Observe and complete only this original request.
        const auto requestLease = lease;
        requestLease->completed = requestLease->attempted = false; requestLease->outcome = E_PENDING;
        auto* edit = new Edit(requestLease, std::move(content), key, extend);
        phase = Phase::Editing;
        HRESULT result = E_FAIL;
        const HRESULT request = requestLease->context->RequestEditSession(client, edit, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, &result);
        observe(&requestLease->diagnostic, {td::Stage::RequestEditSession, request, true,
            request == S_OK ? static_cast<uint32_t>(result) : 0, request == S_OK, 0,
            TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, requestLease->attempted, requestLease->completed});
        edit->Release();
        if (FAILED(request) || (result != TF_S_ASYNC && !requestLease->completed)) {
            requestLease->completed = true;
            requestLease->outcome = FAILED(request) ? request : FAILED(result) ? result : E_UNEXPECTED;
        }
    }
    void tick() noexcept {
        try {
            if (pipe == INVALID_HANDLE_VALUE
#ifdef YIME_TOUCH_FRONTEND_MEMORY_TEST
                && !memoryOnly
#endif
                ) return;
            if (lease && lease->active) {
                if (const char* why = lease->rejection()) {
                    // Observe this existing poll only on rejection; successful idle
                    // polls must not consume the finite edit-diagnostic budget.
                    if (phase == Phase::Editing) lease->diagnostic.emit({td::Stage::Lease,
                        S_OK, false, 0, 0, 0, identity.generation, 0, diagnosticRejection(why)});
                    invalidate();
                }
            }
            if (peer && WaitForSingleObject(peer, 0) != WAIT_TIMEOUT) { listen(); return; }
            if (deadline && GetTickCount64() > deadline) {
                if (diagnosticEdit && lease) lease->diagnostic.emit({td::Stage::Timeout,
                    diagnosticRequested ? lease->outcome : E_PENDING, diagnosticRequested && lease->completed,
                    0, 0, 0, 0, diagnosticRequested && lease->attempted, diagnosticRequested && lease->completed});
                listen(); return;
            }
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
