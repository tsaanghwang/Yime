#pragma once
#include "TouchFrontendNativeHostContract.h"
#include <windows.h>
#include <msctf.h>
#include <textstor.h>
#include <olectl.h>
#include <wrl/client.h>
#include <algorithm>
#include <atomic>
#include <climits>
#include <utility>

namespace yime::nativehost {
struct Event {
    const char* name = "";
    unsigned long flags = 0;
    long result = 0;
    uint64_t sequence = 0;
    int64_t ticks = 0;
};

// The actual host store, also exercised with a fake ACPSink by offline tests.
// Construction does not create a window, initialize COM, or activate a TIP.
class TextStore final : public ITextStoreACP {
public:
    explicit TextStore(HWND window = nullptr, size_t evidenceCapacity = 256)
        : window_(window), thread_(GetCurrentThreadId()), capacity_(evidenceCapacity) {
        events_.reserve(capacity_);
    }
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid != IID_IUnknown && iid != __uuidof(ITextStoreACP)) return E_NOINTERFACE;
        *out = static_cast<ITextStoreACP*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
    STDMETHODIMP_(ULONG) Release() override { const auto n = --refs_; if (!n) delete this; return n; }
    bool Arm(Scenario scenario, std::wstring expectedText) {
        if (!OnThread() || everArmed_ || closed_ || overflow_ || invalid_ || lock_ || pending_ || expectedText.empty()) return false;
        everArmed_ = true; armed_ = true; scenario_ = scenario; expected_ = std::move(expectedText);
        armMutationBaseline_ = mutations_;
        return Record("armed");
    }
    HRESULT GrantPending() {
        if (!OnThread()) return RPC_E_WRONG_THREAD;
        if (closed_ || overflow_ || lock_ || !pending_ || !sink_) return E_UNEXPECTED;
        const DWORD flags = pending_; pending_ = 0;
        const bool injected = delayHeld_; delayHeld_ = false;
        if (injected) { armed_ = false; triggered_ = true; }
        return Grant(flags, true);
    }
    void Close() {
        if (!OnThread()) return;
        armed_ = false; pending_ = 0; delayHeld_ = false; closed_ = true;
        Record("closed");
    }
    const std::wstring& Text() const noexcept { return text_; }
    std::pair<LONG, LONG> Selection() const noexcept { return {start_, end_}; }
    bool HasPendingLock() const noexcept { return pending_ != 0; }
    bool DelayPending() const noexcept { return delayHeld_; }
    bool Stopped() const noexcept { return closed_ || overflow_ || invalid_; }
    bool Triggered() const noexcept { return triggered_; }
    bool EvidenceOverflow() const noexcept { return overflow_; }
    unsigned FailureCount() const noexcept { return failures_; }
    unsigned MutationCount() const noexcept { return mutations_; }
    unsigned GrantCount() const noexcept { return grants_; }
    unsigned WriteCallCount() const noexcept { return writes_; }
    const std::vector<Event>& Events() const noexcept { return events_; }
    bool Record(const char* name, DWORD flags = 0, HRESULT result = S_OK) noexcept {
        if (events_.size() >= capacity_) { overflow_ = true; armed_ = false; return false; }
        try {
            LARGE_INTEGER ticks{}; QueryPerformanceCounter(&ticks);
            events_.push_back({name, flags, result, ++eventSequence_, ticks.QuadPart});
            return true;
        } catch (...) { overflow_ = true; armed_ = false; return false; }
    }
    STDMETHODIMP AdviseSink(REFIID iid, IUnknown* unknown, DWORD mask) override {
        if (!OnThread()) return RPC_E_WRONG_THREAD;
        if (closed_ || !unknown || iid != __uuidof(ITextStoreACPSink)) return E_INVALIDARG;
        Microsoft::WRL::ComPtr<ITextStoreACPSink> proposed;
        HRESULT hr = unknown->QueryInterface(IID_PPV_ARGS(&proposed)); if (FAILED(hr)) return hr;
        if (sink_) {
            Microsoft::WRL::ComPtr<IUnknown> a, b;
            sink_.As(&a); proposed.As(&b);
            if (a.Get() != b.Get()) return CONNECT_E_ADVISELIMIT;
        }
        sink_ = proposed; sinkMask_ = mask; return S_OK;
    }
    STDMETHODIMP UnadviseSink(IUnknown* unknown) override {
        if (!OnThread()) return RPC_E_WRONG_THREAD;
        if (!sink_ || !unknown) return CONNECT_E_NOCONNECTION;
        Microsoft::WRL::ComPtr<IUnknown> a, b;
        sink_.As(&a); HRESULT hr = unknown->QueryInterface(IID_PPV_ARGS(&b));
        if (FAILED(hr) || a.Get() != b.Get()) return CONNECT_E_NOCONNECTION;
        sink_.Reset(); pending_ = 0; delayHeld_ = false; return S_OK;
    }
    STDMETHODIMP RequestLock(DWORD flags, HRESULT* sessionResult) override {
        if (!sessionResult) return E_POINTER; *sessionResult = E_FAIL;
        if (!OnThread()) return RPC_E_WRONG_THREAD;
        if (closed_ || overflow_ || invalid_) { *sessionResult = E_ABORT; return S_OK; }
        if (!sink_) return E_UNEXPECTED;
        if ((flags & ~(TS_LF_SYNC | TS_LF_READWRITE)) || !(flags & TS_LF_READ)) return E_INVALIDARG;
        const bool sync = (flags & TS_LF_SYNC) != 0, write = IsWrite(flags);
        if (!Record("request-lock", flags)) { *sessionResult = E_ABORT; return S_OK; }
        // ASYNCDONTCARE may first ask synchronously. Never allow that attempt to
        // mutate before the D1 barrier; leave TSF to request an asynchronous lock.
        if (sync && write && armed_ && scenario_ == Scenario::DelayWrite) {
            *sessionResult = TS_E_SYNCHRONOUS; Record("sync-write-refused", flags, *sessionResult); return S_OK;
        }
        if (lock_) {
            if (sync) { *sessionResult = TS_E_SYNCHRONOUS; Record("nested-sync-refused", flags, *sessionResult); return S_OK; }
            Queue(flags); *sessionResult = TS_S_ASYNC; Record("nested-async-queued", flags, *sessionResult); return S_OK;
        }
        if (!sync && write && armed_ && scenario_ == Scenario::DelayWrite) {
            Queue(flags); delayHeld_ = true;
            *sessionResult = TS_S_ASYNC; Record("delay-held", flags, *sessionResult); return S_OK;
        }
        const auto pendingGenerationBeforeGrant = pendingGeneration_;
        *sessionResult = Grant(flags, false);
        // A successful synchronous grant may satisfy an older pending request.
        // Never consume a request accepted during that callback, even if its
        // mode matches. A failed grant cannot satisfy an older request, and a
        // read grant cannot satisfy RW.
        if (sync && SUCCEEDED(*sessionResult) && pending_ &&
            pendingGeneration_ == pendingGenerationBeforeGrant &&
            (IsWrite(flags) || !IsWrite(pending_))) { pending_ = 0; delayHeld_ = false; }
        Drain();
        return S_OK;
    }
    STDMETHODIMP GetStatus(TS_STATUS* status) override {
        if (!status) return E_POINTER;
        status->dwDynamicFlags = 0; status->dwStaticFlags = TS_SS_NOHIDDENTEXT; return S_OK;
    }
    STDMETHODIMP QueryInsert(LONG start, LONG end, ULONG count, LONG* resultStart, LONG* resultEnd) override {
        if (!resultStart || !resultEnd) return E_POINTER;
        // QueryInsert describes the replaceable range in the current document,
        // not the post-insertion end returned by InsertTextAtSelection. Validate
        // the replacement length against the same bounded store as actual writes.
        if (!Range(start, end) || count > 1024 || text_.size() - (end - start) + count > 4096)
            return TS_E_INVALIDPOS;
        *resultStart = start; *resultEnd = end; return S_OK;
    }
    STDMETHODIMP GetSelection(ULONG index, ULONG count, TS_SELECTION_ACP* selection, ULONG* fetched) override {
        if (!ReadLocked()) return TS_E_NOLOCK;
        if (!selection || !fetched) return E_POINTER;
        *fetched = 0;
        if (!count || (index != TS_DEFAULT_SELECTION && index != 0)) return E_INVALIDARG;
        selection[0] = {start_, end_, {activeEnd_, FALSE}}; *fetched = 1; return S_OK;
    }
    STDMETHODIMP SetSelection(ULONG count, const TS_SELECTION_ACP* selection) override {
        if (!WriteLocked()) return TS_E_NOLOCK;
        if (failures_ || closed_ || overflow_ || invalid_) {
            if (failures_) { invalid_ = true; Record("selection-after-failure", 0, E_ABORT); }
            return E_ABORT;
        }
        if (!selection || count != 1 || !Range(selection[0].acpStart, selection[0].acpEnd) ||
            selection[0].style.fInterimChar || (selection[0].style.ase != TS_AE_START &&
            selection[0].style.ase != TS_AE_END && selection[0].style.ase != TS_AE_NONE)) return E_INVALIDARG;
        if (!Record("set-selection")) return E_ABORT;
        start_ = selection[0].acpStart; end_ = selection[0].acpEnd; activeEnd_ = selection[0].style.ase;
        return S_OK;
    }
    STDMETHODIMP GetText(LONG start, LONG end, WCHAR* plain, ULONG plainCapacity, ULONG* plainCount,
        TS_RUNINFO* runs, ULONG runCapacity, ULONG* runCount, LONG* next) override {
        if (!ReadLocked()) return TS_E_NOLOCK;
        if (!plainCount || !runCount || !next || (plainCapacity && !plain) || (runCapacity && !runs)) return E_POINTER;
        *plainCount = *runCount = 0; *next = start;
        if (end == -1) end = static_cast<LONG>(text_.size());
        if (!Range(start, end)) return TS_E_INVALIDPOS;
        const ULONG available = static_cast<ULONG>(end - start);
        const ULONG count = plainCapacity ? std::min(plainCapacity, available) : runCapacity ? available : 0;
        if (plainCapacity && count) { std::copy_n(text_.data() + start, count, plain); *plainCount = count; }
        if (runCapacity && count) { runs[0] = {count, TS_RT_PLAIN}; *runCount = 1; }
        *next = start + static_cast<LONG>(count); return S_OK;
    }
    STDMETHODIMP SetText(DWORD flags, LONG start, LONG end, const WCHAR* text, ULONG count, TS_TEXTCHANGE* change) override {
        if (!WriteLocked()) return TS_E_NOLOCK;
        if (!change || (count && !text)) return E_POINTER;
        if (!Range(start, end) || count > 1024 || text_.size() - (end - start) + count > 4096) return TS_E_INVALIDPOS;
        return Write("set-text", flags, start, end, text, count, change);
    }
    STDMETHODIMP GetFormattedText(LONG, LONG, IDataObject** object) override { if (object) *object = nullptr; return E_NOTIMPL; }
    STDMETHODIMP GetEmbedded(LONG, REFGUID, REFIID, IUnknown** object) override { if (object) *object = nullptr; return E_NOTIMPL; }
    STDMETHODIMP QueryInsertEmbedded(const GUID*, const FORMATETC*, BOOL* insertable) override {
        if (!insertable) return E_POINTER; *insertable = FALSE; return S_OK;
    }
    STDMETHODIMP InsertEmbedded(DWORD, LONG, LONG, IDataObject*, TS_TEXTCHANGE*) override { return E_NOTIMPL; }
    STDMETHODIMP InsertTextAtSelection(DWORD flags, const WCHAR* text, ULONG count, LONG* start, LONG* end,
        TS_TEXTCHANGE* change) override {
        if (!WriteLocked()) return TS_E_NOLOCK;
        if ((flags & ~(TS_IAS_QUERYONLY | TS_IAS_NOQUERY)) ||
            (flags & TS_IAS_QUERYONLY && flags & TS_IAS_NOQUERY)) return E_INVALIDARG;
        if ((count && !text) || (!(flags & TS_IAS_NOQUERY) && (!start || !end))) return E_POINTER;
        if (count > 1024 || text_.size() - (end_ - start_) + count > 4096) return TS_E_INVALIDPOS;
        if (flags & TS_IAS_QUERYONLY) {
            *start = start_; *end = start_ + static_cast<LONG>(count);
            Record("query-insert", flags); return overflow_ ? E_ABORT : S_OK;
        }
        if (!change) return E_POINTER;
        const LONG before = start_;
        const HRESULT hr = Write("insert-at-selection", flags, start_, end_, text, count, change);
        if (SUCCEEDED(hr) && !(flags & TS_IAS_NOQUERY)) { *start = before; *end = before + static_cast<LONG>(count); }
        return hr;
    }
    STDMETHODIMP InsertEmbeddedAtSelection(DWORD, IDataObject*, LONG*, LONG*, TS_TEXTCHANGE*) override { return E_NOTIMPL; }
    STDMETHODIMP RequestSupportedAttrs(DWORD, ULONG, const TS_ATTRID*) override { return S_OK; }
    STDMETHODIMP RequestAttrsAtPosition(LONG, ULONG, const TS_ATTRID*, DWORD) override { return S_OK; }
    STDMETHODIMP RequestAttrsTransitioningAtPosition(LONG, ULONG, const TS_ATTRID*, DWORD) override { return S_OK; }
    STDMETHODIMP FindNextAttrTransition(LONG, LONG halt, ULONG, const TS_ATTRID*, DWORD, LONG* next, BOOL* found, LONG* offset) override {
        if (!next || !found || !offset) return E_POINTER; *next = halt; *found = FALSE; *offset = 0; return S_OK;
    }
    STDMETHODIMP RetrieveRequestedAttrs(ULONG, TS_ATTRVAL*, ULONG* fetched) override { if (!fetched) return E_POINTER; *fetched = 0; return S_OK; }
    STDMETHODIMP GetEndACP(LONG* end) override {
        if (!ReadLocked()) return TS_E_NOLOCK; if (!end) return E_POINTER; *end = static_cast<LONG>(text_.size()); return S_OK;
    }
    STDMETHODIMP GetActiveView(TsViewCookie* view) override { if (!view) return E_POINTER; *view = 1; return S_OK; }
    STDMETHODIMP GetACPFromPoint(TsViewCookie, const POINT*, DWORD, LONG*) override { return E_NOTIMPL; }
    STDMETHODIMP GetTextExt(TsViewCookie view, LONG start, LONG end, RECT* rect, BOOL* clipped) override {
        if (!ReadLocked()) return TS_E_NOLOCK;
        if (view != 1 || !rect || !clipped || !Range(start, end)) return E_INVALIDARG;
        if (!window_ || !IsWindow(window_)) return TS_E_NOLAYOUT;
        RECT bounds{}; if (!GetClientRect(window_, &bounds)) return TS_E_NOLAYOUT;
        POINT origin{24, 70}; if (!ClientToScreen(window_, &origin)) return TS_E_NOLAYOUT;
        *rect = {origin.x, origin.y, origin.x + std::max<LONG>(16, (end - start) * 12), origin.y + 26};
        *clipped = FALSE; return S_OK;
    }
    STDMETHODIMP GetScreenExt(TsViewCookie view, RECT* rect) override {
        if (view != 1 || !rect || !window_ || !GetWindowRect(window_, rect)) return TS_E_NOLAYOUT; return S_OK;
    }
    STDMETHODIMP GetWnd(TsViewCookie view, HWND* window) override {
        if (!window) return E_POINTER; if (view != 1) return E_INVALIDARG; *window = window_; return S_OK;
    }
private:
    ~TextStore() = default;
    bool OnThread() const noexcept { return GetCurrentThreadId() == thread_; }
    static bool IsWrite(DWORD flags) noexcept { return (flags & TS_LF_READWRITE) == TS_LF_READWRITE; }
    bool ReadLocked() const noexcept { return OnThread() && (lock_ & TS_LF_READ) != 0; }
    bool WriteLocked() const noexcept { return OnThread() && IsWrite(lock_); }
    bool Range(LONG start, LONG end) const noexcept { return start >= 0 && end >= start && static_cast<size_t>(end) <= text_.size(); }
    void Queue(DWORD flags) noexcept {
        ++pendingGeneration_;
        pending_ = IsWrite(flags) || IsWrite(pending_) ? TS_LF_READWRITE : TS_LF_READ;
    }
    HRESULT Grant(DWORD flags, bool drain) {
        if (!sink_ || lock_ || closed_ || overflow_ || invalid_) return E_ABORT;
        Microsoft::WRL::ComPtr<TextStore> self(this);
        auto sink = sink_; // Unadvise/Close may reenter OnLockGranted.
        lock_ = flags & TS_LF_READWRITE; ++grants_;
        if (!Record("grant-begin", flags)) { lock_ = 0; return E_ABORT; }
        HRESULT result = E_FAIL;
        try { result = sink->OnLockGranted(flags); }
        catch (...) { invalid_ = true; result = E_UNEXPECTED; }
        lock_ = 0;
        Record("grant-end", flags, result);
        if (drain) Drain();
        return result;
    }
    void Drain() {
        if (draining_) return;
        draining_ = true;
        unsigned budget = 8;
        while (pending_ && !delayHeld_ && !lock_ && !closed_ && !overflow_ && !invalid_) {
            if (!budget--) { invalid_ = true; Record("nested-lock-limit", 0, E_ABORT); break; }
            const DWORD flags = pending_; pending_ = 0;
            // An upgrade requested during a read grant still participates in D1.
            if (armed_ && scenario_ == Scenario::DelayWrite && IsWrite(flags)) {
                pending_ = flags; delayHeld_ = true; Record("delay-held", flags, TS_S_ASYNC); break;
            }
            Grant(flags, false);
        }
        draining_ = false;
    }
    HRESULT Write(const char* method, DWORD flags, LONG start, LONG end, const WCHAR* text, ULONG count, TS_TEXTCHANGE* change) {
        ++writes_; if (!Record(method, flags)) return E_ABORT;
        if (closed_ || overflow_ || invalid_ || failures_) {
            invalid_ = true; Record("additional-write-rejected", flags, E_ABORT); return E_ABORT;
        }
        if (everArmed_ && mutations_ > armMutationBaseline_) {
            invalid_ = true; Record("additional-write-rejected", flags, E_ABORT); return E_ABORT;
        }
        if (everArmed_ && (expected_.size() != count || (count && !std::equal(expected_.begin(), expected_.end(), text)))) {
            invalid_ = true; armed_ = false; Record("unexpected-text", flags, E_ABORT); return E_ABORT;
        }
        if (armed_ && scenario_ == Scenario::FailWrite) {
            armed_ = false; triggered_ = true; ++failures_;
            Record("injected-write-failure", flags, E_FAIL); return E_FAIL;
        }
        // D1 must not write until the held asynchronous lock was explicitly granted.
        if (armed_ && scenario_ == Scenario::DelayWrite) {
            invalid_ = true; Record("write-before-grant", flags, E_ABORT); return E_ABORT;
        }
        try {
            std::wstring replacement = text_;
            replacement.replace(static_cast<size_t>(start), static_cast<size_t>(end - start), text ? text : L"", count);
            TS_TEXTCHANGE value{start, end, start + static_cast<LONG>(count)};
            if (!Record("text-mutation", flags)) return E_ABORT;
            text_.swap(replacement); start_ = end_ = value.acpNewEnd; activeEnd_ = TS_AE_END;
            *change = value; ++mutations_; return S_OK;
        } catch (...) { invalid_ = true; return E_OUTOFMEMORY; }
    }
    std::atomic<ULONG> refs_{1};
    HWND window_ = nullptr;
    DWORD thread_ = 0, sinkMask_ = 0, lock_ = 0, pending_ = 0;
    Microsoft::WRL::ComPtr<ITextStoreACPSink> sink_;
    bool everArmed_ = false, armed_ = false, delayHeld_ = false, triggered_ = false;
    bool closed_ = false, overflow_ = false, invalid_ = false, draining_ = false;
    Scenario scenario_ = Scenario::DelayWrite;
    std::wstring text_, expected_;
    LONG start_ = 0, end_ = 0;
    TsActiveSelEnd activeEnd_ = TS_AE_END;
    unsigned failures_ = 0, mutations_ = 0, grants_ = 0, writes_ = 0, armMutationBaseline_ = 0;
    size_t capacity_;
    uint64_t eventSequence_ = 0, pendingGeneration_ = 0;
    std::vector<Event> events_;
};
} // namespace yime::nativehost
