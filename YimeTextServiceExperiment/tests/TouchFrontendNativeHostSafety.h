#pragma once
#include <cstdint>
#include <exception>
#include <utility>

namespace yime::nativehost {
// Shared by the real host and offline tests. Time is supplied by the caller;
// cancellation is one-way and must run before another grant or dispatch.
class RunBoundary {
public:
    enum class Reason { None, Close, Deadline };
    void Start(uint64_t now, uint64_t duration) noexcept {
        started_ = now; duration_ = duration; started = true;
    }
    void RequestClose() noexcept { if (reason_ == Reason::None) reason_ = Reason::Close; }
    template<class Cancel> bool Allow(uint64_t now, Cancel&& cancel) {
        if (reason_ == Reason::None && started && now - started_ >= duration_) reason_ = Reason::Deadline;
        if (reason_ == Reason::None) return true;
        if (!cancelled_) { cancelled_ = true; std::forward<Cancel>(cancel)(reason_); }
        return false;
    }
    bool Closing() const noexcept { return reason_ != Reason::None; }
private:
    uint64_t started_ = 0, duration_ = 0;
    bool started = false, cancelled_ = false;
    Reason reason_ = Reason::None;
};

struct CleanupState {
    bool verified = false;
    const char* stage = nullptr;
    uint32_t result = 0;
};

// Keep the owner alive across serialization/write failures. Report callbacks
// must not throw; preservation may never return in the real host. The tests use
// a returning preservation callback solely to observe ordering without a TSF run.
template<class Publish, class Report, class Preserve>
bool PublishEvidenceSafely(CleanupState cleanup, Publish&& publish, Report&& report, Preserve&& preserve) noexcept {
    bool written = false;
    try { std::forward<Publish>(publish)(); written = true; }
    catch (const std::exception& error) { report(cleanup, true, &error); }
    catch (...) { report(cleanup, true, nullptr); }
    if (!cleanup.verified) {
        if (written) report(cleanup, false, nullptr);
        std::forward<Preserve>(preserve)();
    }
    return written;
}
} // namespace yime::nativehost
