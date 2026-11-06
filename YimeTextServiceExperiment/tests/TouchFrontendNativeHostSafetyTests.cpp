// Offline only: fake registry/ACP sink and injected clock/output failures. No COM
// initialization, window, profile, installed package, or native TSF session.
#include "TouchFrontendNativeHostRegistry.h"
#include "TouchFrontendNativeHostSafety.h"
#include "TouchFrontendNativeTextStore.h"
#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using namespace yime::nativehost;
void check(bool value, const char* message) { if (!value) throw std::runtime_error(message); }

struct RegistryQueryFixture {
    const std::wstring path = L"C:\\Program Files\\YimeCore 18u Touch\\x64\\YimeTextService18u.dll";
    const std::wstring key = L"CLSID\\offline-fixture\\InprocServer32";
    DWORD capacityBytes = 128, returnedBytes = 126;
    LSTATUS sizeStatus = ERROR_SUCCESS, valueStatus = ERROR_SUCCESS;
    std::wstring payload = path + L'\0';
    wchar_t padding = L'\0';
    unsigned queries = 0;

    LSTATUS operator()(HKEY root, LPCWSTR subkey, LPCWSTR name, DWORD flags,
        LPDWORD type, void* data, LPDWORD bytes) {
        ++queries;
        check(root == HKEY_CLASSES_ROOT && subkey && subkey == key && !name && !type && bytes &&
            flags == (RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY),
            "registry fixture requires the real default REG_SZ/64-bit query contract");
        if (queries == 1) {
            check(!data && *bytes == 0, "first registry call only obtains capacity");
            *bytes = capacityBytes;
            return sizeStatus;
        }
        check(queries == 2 && data && *bytes == capacityBytes,
            "second registry call receives the original capacity without retry");
        auto* buffer = static_cast<wchar_t*>(data);
        const size_t capacity = capacityBytes / sizeof(wchar_t);
        std::fill_n(buffer, capacity, padding);
        std::copy_n(payload.data(), (std::min)(payload.size(), capacity), buffer);
        *bytes = returnedBytes;
        return valueStatus;
    }
};

void expectRegistryRejection(RegistryQueryFixture fixture, const char* diagnostic,
    unsigned queries, const char* scenario, bool optional = false) {
    bool rejected = false;
    try {
        ReadRegisteredDll(HKEY_CLASSES_ROOT, fixture.key, optional, fixture);
    } catch (const std::runtime_error& error) {
        rejected = true;
        check(std::string(error.what()) == diagnostic, scenario);
    }
    check(rejected && fixture.queries == queries, scenario);
}

void registryActualLengthIsUsed() {
    static_assert(sizeof(wchar_t) == 2, "the Windows fixture uses UTF-16 byte counts");
    RegistryQueryFixture exact;
    check(exact.path.size() == 62 && exact.payload.size() * sizeof(wchar_t) == 126,
        "the fixture reproduces the observed installed path and actual byte count");
    exact.capacityBytes = exact.returnedBytes;
    check(ReadRegisteredDll(HKEY_CLASSES_ROOT, exact.key, false, exact) == exact.path && exact.queries == 2,
        "exact capacity/actual length returns the registered path");
    std::cout << "PASS: registry exact capacity=126 returned=126\n";

    for (wchar_t padding : {L'\0', L'X'}) {
        RegistryQueryFixture shorter;
        shorter.padding = padding;
        try {
            check(ReadRegisteredDll(HKEY_CLASSES_ROOT, shorter.key, false, shorter) == shorter.path &&
                shorter.queries == 2, "128/126 registry read returns the unmodified path");
        } catch (const std::runtime_error& error) {
            throw std::runtime_error(std::string("capacity=128 returned=126 regression: ") + error.what());
        }
    }
    std::cout << "PASS: registry capacity=128 returned=126 ignores only unused zero/nonzero padding\n";
}

void registryMalformedValuesFailClosed() {
    for (DWORD capacity : {DWORD(0), DWORD(1), DWORD(127), DWORD(65535), DWORD(65536)}) {
        RegistryQueryFixture fixture;
        fixture.capacityBytes = capacity;
        expectRegistryRejection(fixture, "registered DLL query", 1, "invalid size query is rejected before allocation/read");
    }
    for (DWORD actual : {DWORD(0), DWORD(1), DWORD(125), DWORD(130)}) {
        RegistryQueryFixture fixture;
        fixture.returnedBytes = actual;
        expectRegistryRejection(fixture, "registered DLL value", 2, "invalid actual byte count is rejected before decoding");
    }
    RegistryQueryFixture unterminated;
    unterminated.payload.back() = L'X';
    expectRegistryRejection(unterminated, "registered DLL value", 2,
        "terminator must be inside returned bytes even if allocation padding is zero");
    RegistryQueryFixture empty;
    empty.payload = std::wstring(1, L'\0');
    empty.returnedBytes = sizeof(wchar_t);
    expectRegistryRejection(empty, "registered DLL path", 2, "an empty REG_SZ is not an absent optional overlay", true);
    RegistryQueryFixture embedded;
    embedded.payload[3] = L'\0';
    expectRegistryRejection(embedded, "registered DLL path", 2, "embedded NUL does not hide a path suffix");
    RegistryQueryFixture repeatedTerminator;
    repeatedTerminator.payload.push_back(L'\0');
    repeatedTerminator.returnedBytes = repeatedTerminator.capacityBytes;
    expectRegistryRejection(repeatedTerminator, "registered DLL path", 2,
        "extra NUL inside actual data is rejected rather than trimmed");
    std::cout << "PASS: registry invalid size/actual count, missing terminator, empty and embedded/repeated NUL fail closed\n";
}

void registryQueryFailuresDoNotRetry() {
    for (LSTATUS status : {LSTATUS(ERROR_FILE_NOT_FOUND), LSTATUS(ERROR_PATH_NOT_FOUND)}) {
        RegistryQueryFixture optional;
        optional.sizeStatus = status;
        check(ReadRegisteredDll(HKEY_CLASSES_ROOT, optional.key, true, optional).empty() && optional.queries == 1,
            "only an absent optional registration may return an empty path");
    }
    for (LSTATUS status : {LSTATUS(ERROR_FILE_NOT_FOUND), LSTATUS(ERROR_PATH_NOT_FOUND),
        LSTATUS(ERROR_ACCESS_DENIED), LSTATUS(ERROR_UNSUPPORTED_TYPE)}) {
        RegistryQueryFixture fixture;
        fixture.sizeStatus = status;
        expectRegistryRejection(fixture, "registered DLL query", 1,
            "required registration query failure blocks without retry");
    }
    RegistryQueryFixture deniedOptional;
    deniedOptional.sizeStatus = ERROR_ACCESS_DENIED;
    expectRegistryRejection(deniedOptional, "registered DLL query", 1,
        "optional does not suppress access failure", true);
    for (LSTATUS status : {LSTATUS(ERROR_FILE_NOT_FOUND), LSTATUS(ERROR_PATH_NOT_FOUND), LSTATUS(ERROR_MORE_DATA),
        LSTATUS(ERROR_ACCESS_DENIED), LSTATUS(ERROR_UNSUPPORTED_TYPE)}) {
        RegistryQueryFixture fixture;
        fixture.valueStatus = status;
        expectRegistryRejection(fixture, "registered DLL value", 2,
            "value changed, grew, disappeared or has non-REG_SZ type: block without retry", true);
    }
    std::cout << "PASS: registry missing optional versus failed required/value queries; no retry or type expansion\n";
}

class DirectTestEnvironmentFixture {
public:
    static constexpr const wchar_t* Name = L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST";
    DirectTestEnvironmentFixture() {
        SetLastError(ERROR_SUCCESS);
        const DWORD size = GetEnvironmentVariableW(Name, nullptr, 0);
        const DWORD error = GetLastError();
        check(size || error == ERROR_SUCCESS || error == ERROR_ENVVAR_NOT_FOUND, "read process environment fixture");
        present_ = size || error == ERROR_SUCCESS;
        if (size) {
            original_.resize(size);
            SetLastError(ERROR_SUCCESS);
            const DWORD copied = GetEnvironmentVariableW(Name, original_.data(), size);
            check(copied < size && (copied || GetLastError() == ERROR_SUCCESS), "capture original process-only flag");
            original_.resize(copied);
        }
    }
    ~DirectTestEnvironmentFixture() { if (!restored_) SetEnvironmentVariableW(Name, present_ ? original_.c_str() : nullptr); }
    void Set(const wchar_t* value) { check(SetEnvironmentVariableW(Name, value) != FALSE, "set process-only test flag"); }
    void Restore() {
        Set(present_ ? original_.c_str() : nullptr);
        restored_ = true;
    }
private:
    bool present_ = false, restored_ = false;
    std::wstring original_;
};

void environmentQueryErrorsBlockBeforeActivation() {
    for (DWORD error : {DWORD(ERROR_ACCESS_DENIED), DWORD(ERROR_INVALID_PARAMETER)}) {
        unsigned queries = 0;
        bool reachedNextStage = false, rejected = false;
        try {
            RequireNormalTsfActivationEnvironment([&](LPCWSTR name, LPWSTR buffer, DWORD capacity) -> DWORD {
                ++queries;
                check(std::wstring(name) == DirectTestEnvironmentFixture::Name && !buffer && capacity == 0,
                    "fault injection exercises the real preflight query contract");
                SetLastError(error);
                return 0;
            });
            reachedNextStage = true; // No COM, profile or TIP activation.
        } catch (const std::runtime_error& failure) {
            rejected = true;
            check(std::string(failure.what()) == "cannot verify normal TSF activation environment",
                "query failure retains its distinct diagnostic");
        }
        check(queries == 1 && rejected && !reachedNextStage,
            "query errors fail closed before activation without retry");
    }
    std::cout << "PASS: injected environment query errors block activation without retry\n";
}

void directTestFlagBlocksBeforeActivation() {
    DirectTestEnvironmentFixture environment;
    const wchar_t* values[] = {nullptr, L"", L"0", L"1", L"false"};
    for (const wchar_t* value : values) {
        environment.Set(value);
        bool reachedNextStage = false, rejected = false;
        try {
            RequireNormalTsfActivationEnvironment();
            reachedNextStage = true; // Fake next stage; never initialize COM or a TIP.
        } catch (const std::runtime_error& error) {
            rejected = true;
            check(std::string(error.what()) == "direct-test bypass forbidden", "flag rejection keeps its diagnostic");
        }
        check(rejected == (value != nullptr) && reachedNextStage == (value == nullptr),
            "only an absent flag reaches the next stage; empty/zero/false do not mean native activation");
        SetLastError(ERROR_SUCCESS);
        const DWORD size = GetEnvironmentVariableW(DirectTestEnvironmentFixture::Name, nullptr, 0);
        const bool stillPresent = size || GetLastError() != ERROR_ENVVAR_NOT_FOUND;
        check(stillPresent == (value != nullptr), "preflight refuses the flag without clearing it");
    }
    environment.Restore();
    std::cout << "PASS: activation environment absent/empty/0/1/false; process-local only\n";
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
        registryActualLengthIsUsed();
        registryMalformedValuesFailClosed();
        registryQueryFailuresDoNotRetry();
        directTestFlagBlocksBeforeActivation();
        environmentQueryErrorsBlockBeforeActivation();
        deadlineBeforeDelayedTimer(); closeThenTimerInOneBatch(); deadlineCrossedDuringEligibility();
        permittedWriteAndLaterStop(); combinedFailureReportedBeforePreserve();
        serializationFailureAlsoRetainsOwner(); outputFailureAfterCleanCleanupDoesNotPark();
        successfulEvidenceStillPreservesCleanupFailure();
        std::cout << "PASS: registry read, activation environment and 8 offline stop/evidence regressions; native TSF not executed\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << "FAIL: " << error.what() << '\n'; return 1; }
}
