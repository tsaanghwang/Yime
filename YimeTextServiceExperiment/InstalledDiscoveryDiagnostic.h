#pragma once
#include <atomic>
#include <cstdint>
#include <deque>
#include <memory>
#include <string>
#include <utility>
#include <nlohmann/json.hpp>

namespace yime::installeddiag {
enum class DiscoveryReason : unsigned {
    Ready, NotFocused, NoForeground, ForegroundUnavailable, OtherProcess,
    OtherThread, GetFocusFailed, NoDocument, GetTopFailed, NoContext, NoEndpoint
};
struct DiscoveryRejection {
    DiscoveryReason reason = DiscoveryReason::Ready;
    uint32_t code = 0;
    bool hresult = false;
    bool win32 = false;
};
inline DiscoveryRejection ForegroundRejection(bool focused, bool window, uint32_t process,
    uint32_t owner, uint32_t thread, uint32_t ownThread) {
    if (!focused) return {DiscoveryReason::NotFocused};
    if (!window) return {DiscoveryReason::NoForeground};
    // A missing thread is useful evidence without borrowing an unrelated
    // LastError value from the STA. Only the relation is reported here.
    if (!thread) return {DiscoveryReason::ForegroundUnavailable};
    if (process != owner) return {DiscoveryReason::OtherProcess};
    if (thread != ownThread) return {DiscoveryReason::OtherThread};
    return {};
}
struct ContextObservation { uint32_t result; bool present; };
// The real STA supplies these two calls. Never call GetTop without a document,
// and retain the HRESULT at its original failing call rather than a later E_ABORT.
template<class GetFocus, class GetTop>
DiscoveryRejection ContextRejection(GetFocus getFocus, GetTop getTop) {
    const auto focus = getFocus();
    if (focus.result & 0x80000000u) return {DiscoveryReason::GetFocusFailed, focus.result, true};
    if (!focus.present) return {DiscoveryReason::NoDocument};
    const auto top = getTop();
    if (top.result & 0x80000000u) return {DiscoveryReason::GetTopFailed, top.result, true};
    if (!top.present) return {DiscoveryReason::NoContext};
    return {};
}
inline const char* DiscoveryReasonName(DiscoveryReason reason) {
    switch (reason) {
    case DiscoveryReason::NotFocused: return "tip-not-focused";
    case DiscoveryReason::NoForeground: return "foreground-missing";
    case DiscoveryReason::ForegroundUnavailable: return "foreground-query-failed";
    case DiscoveryReason::OtherProcess: return "foreground-other-process";
    case DiscoveryReason::OtherThread: return "foreground-thread-mismatch";
    case DiscoveryReason::GetFocusFailed: return "get-focus-failed";
    case DiscoveryReason::NoDocument: return "tsf-document-missing";
    case DiscoveryReason::GetTopFailed: return "get-top-failed";
    case DiscoveryReason::NoContext: return "tsf-context-missing";
    case DiscoveryReason::NoEndpoint: return "tip-endpoint-unavailable";
    default: return nullptr;
    }
}
// At most one attempt per reason per adapter lifetime. Taking a frame consumes
// it before any I/O: connection failure, lost response or cancellation never
// requeues it. No text, host identity, lease or input action is accepted here.
class DiscoveryDiagnostics {
public:
    void Observe(DiscoveryRejection value) {
        const auto ordinal = static_cast<unsigned>(value.reason);
        if (ordinal == 0 || ordinal > 10) return;
        const auto name = DiscoveryReasonName(value.reason);
        if (!name) return;
        const uint32_t bit = 1u << ordinal;
        if (seen_ & bit) return;
        seen_ |= bit;
        nlohmann::json diagnostic = {{"stage", "tip-discovery"}, {"reason", name}};
        if (value.hresult) diagnostic["hresult"] = value.code;
        else if (value.win32) diagnostic["win32"] = value.code;
        frames_.push_back(nlohmann::json{{"operation", "diagnostic"}, {"version", 1}, {"diagnostic", diagnostic}}.dump());
    }
    bool Take(std::string& frame) {
        if (frames_.empty()) return false;
        frame = std::move(frames_.front()); frames_.pop_front(); return true;
    }
private:
    uint32_t seen_ = 0;
    std::deque<std::string> frames_;
};

// This slot is independent of the input relay and owns no TSF/window pointers.
// The production transport starts pipe I/O on its worker; fake transports use
// the same draining/lifetime logic in the offline contract tests.
template<class Transport, class Work>
class DiscoveryDiagnosticChannel {
public:
    DiscoveryDiagnosticChannel() = default;
    DiscoveryDiagnosticChannel(const DiscoveryDiagnosticChannel&) = delete;
    DiscoveryDiagnosticChannel& operator=(const DiscoveryDiagnosticChannel&) = delete;
    ~DiscoveryDiagnosticChannel() { Stop(); }

    void Observe(DiscoveryRejection value) {
        if (!stopped_) diagnostics_.Observe(value);
    }
    template<class MakeTransport>
    void Drain(MakeTransport makeTransport) noexcept {
        if (stopped_) return;
        try {
            if (work_) {
                if (!work_->done.load(std::memory_order_acquire)) return;
                // The server intentionally closes a diagnostic connection.
                // Either I/O outcome retires this attempt, without replay.
                work_.reset();
                transport_.reset();
            }
            std::string frame;
            if (!diagnostics_.Take(frame)) return;
            transport_ = makeTransport();
            if (!transport_) return;
            work_ = transport_->Start(std::move(frame), 1000, true);
            if (!work_) CancelAndRelease();
        } catch (...) {
            // Taking the frame already consumed its one permitted attempt.
            CancelAndRelease();
        }
    }
    void Stop() noexcept {
        if (stopped_) return;
        stopped_ = true;
        CancelAndRelease();
    }
private:
    void CancelAndRelease() noexcept {
        if (transport_) transport_->Cancel();
        work_.reset();
        transport_.reset();
    }
    bool stopped_ = false;
    DiscoveryDiagnostics diagnostics_;
    std::shared_ptr<Transport> transport_;
    std::shared_ptr<Work> work_;
};
}
