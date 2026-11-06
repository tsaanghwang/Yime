// Offline only: fake ACP sink and injected clock/output failures. No COM
// initialization, window, profile, installed package, or native TSF session.
#include "TouchFrontendNativeHostSafety.h"
#include "TouchFrontendNativeTextStore.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using namespace yime::nativehost;
void check(bool value, const char* message) { if (!value) throw std::runtime_error(message); }

void directTestActivationOverrideIsRejected() {
    constexpr auto name = L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST";
    struct RestoreEnvironment {
        const wchar_t* name;
        std::wstring value;
        bool present;
        ~RestoreEnvironment() { SetEnvironmentVariableW(name, present ? value.c_str() : nullptr); }
    } saved{name, {}, false};
    SetLastError(ERROR_SUCCESS);
    const DWORD size = GetEnvironmentVariableW(name, nullptr, 0);
    saved.present = size != 0 || GetLastError() == ERROR_SUCCESS;
    if (size) {
        saved.value.resize(size);
        const DWORD copied = GetEnvironmentVariableW(name, saved.value.data(), size);
        check(copied < size, "save inherited process-local activation override");
        saved.value.resize(copied);
    }
    check(SetEnvironmentVariableW(name, nullptr) != FALSE, "remove override only in offline test process");
    check(!HasDirectTestActivationOverride(), "unset override permits normal activation preflight");
    for (const auto* value : {L"1", L"0", L"false", L" "}) {
        check(SetEnvironmentVariableW(name, value) != FALSE, "set process-local override fixture");
        check(HasDirectTestActivationOverride(), "every nonempty override rejects native activation preflight");
    }
}

class WriteSink final : public ITextStoreACPSink {
public:
    TextStore* store = nullptr;
    ULONG references = 1;
    unsigned grants = 0;
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid != IID_IUnknown && iid != IID_ITextStoreACPSink) return E_NOINTERFACE;
        *out = static_cast<ITextStoreACPSink*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references; }
    STDMETHODIMP_(ULONG) Release() override { return --references; }
    STDMETHODIMP OnTextChange(DWORD, const TS_TEXTCHANGE*) override { return S_OK; }
    STDMETHODIMP OnSelectionChange() override { return S_OK; }
    STDMETHODIMP OnLayoutChange(TsLayoutCode, TsViewCookie) override { return S_OK; }
    STDMETHODIMP OnStatusChange(DWORD) override { return S_OK; }
    STDMETHODIMP OnAttrsChange(LONG, LONG, ULONG, const TS_ATTRID*) override { return S_OK; }
    STDMETHODIMP OnStartEditTransaction() override { return S_OK; }
    STDMETHODIMP OnEndEditTransaction() override { return S_OK; }
    STDMETHODIMP OnLockGranted(DWORD) override {
        ++grants; TS_TEXTCHANGE change{};
        return store->SetText(0, 0, 0, L"test", 4, &change);
    }
};
class DelayedWrite {
public:
    WriteSink sink;
    TextStore* store = new TextStore;
    RunBoundary boundary;
    unsigned cancellations = 0;
    DelayedWrite() {
        sink.store = store;
        check(store->AdviseSink(IID_ITextStoreACPSink, &sink, TS_AS_TEXT_CHANGE) == S_OK, "advise fake sink");
        check(store->Arm(Scenario::DelayWrite, L"test"), "arm one delayed write");
        HRESULT session = E_FAIL;
        check(store->RequestLock(TS_LF_READWRITE, &session) == S_OK && session == TS_S_ASYNC,
            "real store holds asynchronous write");
        check(store->DelayPending(), "delayed write must be pending before boundary test");
        boundary.Start(100, 1000);
    }
    ~DelayedWrite() { store->Close(); store->UnadviseSink(&sink); store->Release(); }
    bool allow(uint64_t now) {
        return boundary.Allow(now, [&](RunBoundary::Reason) { ++cancellations; store->Close(); });
    }
    void timer(uint64_t now) { if (allow(now)) check(store->GrantPending() == S_OK, "allowed grant succeeds"); }
    void unchanged() {
        check(store->Text().empty() && store->MutationCount() == 0 && store->WriteCallCount() == 0 &&
            sink.grants == 0 && !store->HasPendingLock() && store->Stopped(),
            "stop cancels pending without granting, writing, or replaying");
    }
};

void deadlineBeforeDelayedTimer() {
    DelayedWrite f;
    f.timer(1100); // First timer arrives exactly at the deadline.
    f.timer(1200);
    f.unchanged(); check(f.cancellations == 1, "deadline cancels only once");
}
void closeThenTimerInOneBatch() {
    DelayedWrite f;
    f.boundary.RequestClose();
    check(!f.allow(500), "WM_CLOSE immediately disarms");
    f.unchanged();
    f.timer(500); // Same batch and clock; a later timer must not grant.
    f.unchanged(); check(f.cancellations == 1, "close is irreversible");
}
void deadlineCrossedDuringEligibility() {
    DelayedWrite f;
    check(f.allow(1099), "pre-dispatch guard can still permit");
    f.timer(1101); // A query/pumped callback consumed the remaining budget.
    f.unchanged();
}
void permittedWriteAndLaterStop() {
    DelayedWrite f;
    f.timer(1099);
    check(f.store->Text() == L"test" && f.store->MutationCount() == 1 && f.sink.grants == 1,
        "the boundary still permits the single timely write");
    check(!f.allow(1100) && f.store->Text() == L"test" && f.store->MutationCount() == 1,
        "later stop preserves committed synthetic text");
}

struct WriteFailure : std::runtime_error {
    uint32_t result;
    WriteFailure() : std::runtime_error("flush evidence"), result(0x80070070u) {}
};
void combinedFailureReportedBeforePreserve() {
    std::vector<int> order;
    bool ownerAlive = true, observed = false;
    struct Owner { bool& alive; ~Owner() { alive = false; } };
    {
        Owner owner{ownerAlive};
        const bool published = PublishEvidenceSafely({false, "cleanup-unadvise", 0x80004005u},
            [&] { order.push_back(1); throw WriteFailure{}; },
            [&](CleanupState cleanup, bool failed, const std::exception* error) noexcept {
                const auto* write = dynamic_cast<const WriteFailure*>(error);
                observed = ownerAlive && !cleanup.verified && std::string(cleanup.stage) == "cleanup-unadvise" &&
                    cleanup.result == 0x80004005u && failed && write && write->result == 0x80070070u &&
                    std::string(error->what()) == "flush evidence";
                order.push_back(2);
            },
            [&]() noexcept { observed = observed && ownerAlive; order.push_back(3); });
        check(!published && observed && order == std::vector<int>({1, 2, 3}),
            "both original failures are reported with live owner before preservation");
    }
    check(!ownerAlive, "test owner leaves scope only after reporting/preservation callback");
}
void serializationFailureAlsoRetainsOwner() {
    bool reported = false, preserved = false;
    const bool published = PublishEvidenceSafely({false, "cleanup-manager", 0x80004005u},
        [] { throw std::runtime_error("summary serialization"); },
        [&](CleanupState cleanup, bool failed, const std::exception* error) noexcept {
            reported = !cleanup.verified && failed && error && std::string(error->what()) == "summary serialization";
        }, [&]() noexcept { preserved = reported; });
    check(!published && reported && preserved, "serialization failure is caught before owner unwinding");
}
void outputFailureAfterCleanCleanupDoesNotPark() {
    bool reported = false, preserved = false;
    const bool published = PublishEvidenceSafely({true, nullptr, 0}, [] { throw WriteFailure{}; },
        [&](CleanupState cleanup, bool failed, const std::exception* error) noexcept {
            reported = cleanup.verified && failed && dynamic_cast<const WriteFailure*>(error);
        }, [&]() noexcept { preserved = true; });
    check(!published && reported && !preserved, "clean owner reports output failure and can return failure");
}
void successfulEvidenceStillPreservesCleanupFailure() {
    bool publishedOnce = false, reported = false, preserved = false;
    const bool published = PublishEvidenceSafely({false, "cleanup-profile", 0x80004005u},
        [&] { publishedOnce = true; },
        [&](CleanupState cleanup, bool failed, const std::exception* error) noexcept {
            reported = publishedOnce && !cleanup.verified && !failed && !error;
        }, [&]() noexcept { preserved = reported; });
    check(published && reported && preserved, "cleanup failure remains unverified even with intact evidence");
}
} // namespace
int main() {
    try {
        directTestActivationOverrideIsRejected();
        deadlineBeforeDelayedTimer(); closeThenTimerInOneBatch(); deadlineCrossedDuringEligibility();
        permittedWriteAndLaterStop(); combinedFailureReportedBeforePreserve();
        serializationFailureAlsoRetainsOwner(); outputFailureAfterCleanCleanupDoesNotPark();
        successfulEvidenceStillPreservesCleanupFailure();
        std::cout << "PASS: 9 offline activation/stop/evidence regressions; native TSF not executed\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << "FAIL: " << error.what() << '\n'; return 1; }
}
