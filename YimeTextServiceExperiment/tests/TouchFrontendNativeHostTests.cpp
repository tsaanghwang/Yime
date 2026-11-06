// Offline contracts for the same ITextStoreACP implementation used by the
// controlled native host. The sink is fake; this executable never activates
// COM/TSF, loads a TIP, creates a host window, or changes registration.
#include "TouchFrontendNativeTextStore.h"
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using yime::nativehost::Scenario;
using yime::nativehost::TextStore;

void check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

class FakeSink final : public ITextStoreACPSink {
public:
    ULONG references = 1;
    unsigned grants = 0;
    std::vector<DWORD> grantedFlags;
    std::function<HRESULT(DWORD)> action;
    std::string callbackError;

    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (iid != IID_IUnknown && iid != IID_ITextStoreACPSink) return E_NOINTERFACE;
        *out = static_cast<ITextStoreACPSink*>(this);
        AddRef();
        return S_OK;
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
    STDMETHODIMP OnLockGranted(DWORD flags) override {
        ++grants;
        grantedFlags.push_back(flags);
        try {
            return action ? action(flags) : S_OK;
        } catch (const std::exception& error) {
            // Do not propagate a C++ exception through the COM-style callback.
            callbackError = error.what();
            return E_FAIL;
        }
    }
};

class Fixture {
public:
    TextStore* store;
    FakeSink sink;

    explicit Fixture(size_t capacity = 256) : store(new TextStore(nullptr, capacity)) {
        check(store->AdviseSink(IID_ITextStoreACPSink, &sink,
                               TS_AS_TEXT_CHANGE | TS_AS_SEL_CHANGE | TS_AS_LAYOUT_CHANGE) == S_OK,
              "advise the fake sink on the real text store");
    }
    ~Fixture() {
        store->Close();
        store->UnadviseSink(&sink);
        store->Release();
    }
    void checkCallback() const {
        if (!sink.callbackError.empty()) throw std::runtime_error(sink.callbackError);
    }
    HRESULT request(DWORD flags) {
        HRESULT session = E_UNEXPECTED;
        const HRESULT result = store->RequestLock(flags, &session);
        checkCallback();
        check(result == S_OK, "RequestLock must return its session result separately");
        return session;
    }
    HRESULT insert(const std::wstring& text, DWORD flags = 0) {
        LONG first = -1, last = -1;
        TS_TEXTCHANGE change{};
        return store->InsertTextAtSelection(flags, text.data(), static_cast<ULONG>(text.size()),
                                           &first, &last, &change);
    }
    void seed() {
        sink.action = [&](DWORD flags) {
            check((flags & TS_LF_READWRITE) == TS_LF_READWRITE, "seed requires a real write grant");
            check(insert(L"baseline") == S_OK, "seed the private document before arming");
            TS_SELECTION_ACP selection{2, 5, {TS_AE_END, FALSE}};
            check(store->SetSelection(1, &selection) == S_OK, "seed a noncollapsed selection");
            return S_OK;
        };
        check(request(TS_LF_SYNC | TS_LF_READWRITE) == S_OK, "seed grant completes");
        check(store->Text() == L"baseline" && store->Selection() == std::make_pair(2L, 5L),
              "seed text and selection are observable");
        sink.action = {};
    }
};

void queryInsertUsesExistingDocumentRange() {
    Fixture f;
    auto accepted = [&](LONG start, LONG end, ULONG count) {
        LONG resultStart = -1, resultEnd = -1;
        check(f.store->QueryInsert(start, end, count, &resultStart, &resultEnd) == S_OK,
              "QueryInsert accepts a valid current-document replacement range");
        check(resultStart == start && resultEnd == end && resultStart >= 0 &&
              static_cast<size_t>(resultEnd) <= f.store->Text().size(),
              "QueryInsert returns the existing range, never the future insertion end");
    };
    auto invalid = [&](LONG start, LONG end, ULONG count) {
        LONG resultStart = -7, resultEnd = -9;
        check(f.store->QueryInsert(start, end, count, &resultStart, &resultEnd) == TS_E_INVALIDPOS,
              "QueryInsert refuses invalid positions or an unsupported replacement length");
        check(resultStart == -7 && resultEnd == -9, "invalid query does not publish a usable range");
    };
    accepted(0, 0, 1); // Empty-document insertion must return [0, 0], not [0, 1].
    accepted(0, 0, 0);
    invalid(-1, 0, 1);
    invalid(0, 1, 1);
    invalid(1, 0, 1);
    invalid(0, 0, ULONG_MAX);
    LONG result = -7;
    check(f.store->QueryInsert(0, 0, 1, nullptr, &result) == E_POINTER && result == -7,
          "missing start output fails without changing the other output");
    check(f.store->QueryInsert(0, 0, 1, &result, nullptr) == E_POINTER && result == -7,
          "missing end output fails without changing the other output");
    check(f.store->Text().empty() && f.store->Selection() == std::make_pair(0L, 0L) &&
          f.store->WriteCallCount() == 0 && f.store->MutationCount() == 0 && f.sink.grants == 0,
          "empty-document queries neither request locks nor mutate text or selection");

    f.seed();
    const auto selection = f.store->Selection();
    const auto calls = f.store->WriteCallCount(), mutations = f.store->MutationCount();
    const auto grants = f.sink.grants;
    accepted(8, 8, 10); // Tail insertion remains a collapsed current-document range.
    accepted(2, 5, 1);
    accepted(2, 5, 10); // A longer replacement does not extend the returned range.
    accepted(0, 8, 0);
    accepted(0, 8, 1024);
    invalid(0, 8, 1025);
    invalid(9, 9, 1);
    invalid(5, 2, 1);
    check(f.store->Text() == L"baseline" && f.store->Selection() == selection &&
          f.store->WriteCallCount() == calls && f.store->MutationCount() == mutations &&
          f.sink.grants == grants && !f.store->HasPendingLock() && !f.store->Triggered(),
          "successful and rejected range queries preserve the seeded document and lock state");

    Fixture full;
    full.sink.action = [&](DWORD) {
        for (unsigned i = 0; i < 4; ++i)
            check(full.insert(std::wstring(1024, L'x')) == S_OK, "fill only the private offline document");
        return S_OK;
    };
    check(full.request(TS_LF_SYNC | TS_LF_READWRITE) == S_OK, "bounded document fixture is full");
    LONG first = -1, last = -1;
    check(full.store->QueryInsert(4096, 4096, 1, &first, &last) == TS_E_INVALIDPOS,
          "query rejects insertion beyond the same capacity enforced by actual writes");
    check(full.store->QueryInsert(4095, 4096, 1, &first, &last) == S_OK && first == 4095 && last == 4096,
          "same-size replacement at capacity remains valid");
    check(full.store->Text().size() == 4096 && full.store->MutationCount() == 4 &&
          full.store->WriteCallCount() == 4 && full.store->Selection() == std::make_pair(4096L, 4096L),
          "capacity queries leave the private document and selection unchanged");
}

void delayWriteDefersUntilOneGrant() {
    Fixture f;
    check(f.store->Arm(Scenario::DelayWrite, L"once"), "D1 arms once");
    check(f.request(TS_LF_SYNC | TS_LF_READ) == S_OK, "ordinary reads remain available while armed");
    check(!f.store->Triggered() && !f.store->HasPendingLock(), "read must not consume the write fault");
    const auto readGrants = f.sink.grants;
    f.sink.action = [&](DWORD flags) {
        check((flags & TS_LF_READWRITE) == TS_LF_READWRITE, "D1 grants write access");
        TS_TEXTCHANGE change{};
        return f.store->InsertTextAtSelection(TS_IAS_NOQUERY, L"once", 4, nullptr, nullptr, &change);
    };
    check(f.request(TS_LF_SYNC | TS_LF_READWRITE) == TS_E_SYNCHRONOUS,
          "D1 rejects synchronous write without pretending asynchronous coverage");
    check(!f.store->HasPendingLock() && f.sink.grants == readGrants,
          "synchronous refusal must not queue or grant a callback");
    check(f.request(TS_LF_READWRITE) == TS_S_ASYNC, "D1 queues the actual asynchronous request");
    check(f.store->HasPendingLock() && f.store->DelayPending(), "D1 holds the queued write");
    LONG queryStart = -1, queryEnd = -1;
    check(f.store->QueryInsert(0, 0, 4, &queryStart, &queryEnd) == S_OK && queryStart == 0 && queryEnd == 0,
          "D1 insertion query uses the existing empty-document range");
    check(f.store->HasPendingLock() && f.store->DelayPending() && !f.store->Triggered(),
          "QueryInsert cannot consume or grant a delayed write");
    check(f.store->Text().empty() && f.store->MutationCount() == 0 && f.sink.grants == readGrants,
          "before grant there is no callback or document mutation");
    check(f.store->GrantPending() == S_OK, "the queued callback completes once");
    f.checkCallback();
    check(f.store->Text() == L"once" && f.store->MutationCount() == 1 &&
          f.sink.grants == readGrants + 1 && !f.store->HasPendingLock(),
          "one pending callback causes exactly one insertion");
    check(f.store->GrantPending() == E_UNEXPECTED, "a consumed pending grant cannot be replayed");
    check(!f.store->Arm(Scenario::DelayWrite, L"twice"), "D1 cannot be armed a second time");
    check(f.store->Text() == L"once" && f.store->MutationCount() == 1,
          "rejected second arm/grant does not mutate text");
}

void failedWritePreservesTextAndSelection(bool useSetText) {
    Fixture f;
    f.seed();
    const auto baseline = f.store->Text();
    const auto selection = f.store->Selection();
    const auto writes = f.store->MutationCount();
    check(f.store->Arm(Scenario::FailWrite, L"new"), "D2 arms once");
    f.sink.action = [&](DWORD flags) {
        check((flags & TS_LF_READWRITE) == TS_LF_READWRITE, "D2 uses write lock");
        LONG queryStart = -1, queryEnd = -1;
        check(f.store->QueryInsert(selection.first, selection.second, 3, &queryStart, &queryEnd) == S_OK &&
              queryStart == selection.first && queryEnd == selection.second,
              "D2 replacement query retains the current selected range");
        check(f.store->InsertTextAtSelection(TS_IAS_QUERYONLY, L"new", 3,
                                             &queryStart, &queryEnd, nullptr) == S_OK,
              "query-only insertion allows a null change output");
        check(f.store->FailureCount() == 0 && !f.store->Triggered(),
              "query-only insertion must not consume the failure");
        check(f.store->Text() == baseline && f.store->Selection() == selection &&
              f.store->MutationCount() == writes, "query-only leaves all document state unchanged");
        TS_TEXTCHANGE change{};
        const HRESULT failed = useSetText
            ? f.store->SetText(0, selection.first, selection.second, L"new", 3, &change)
            : f.insert(L"new");
        check(failed == E_FAIL, "D2 fails at the selected real write method");
        check(f.store->FailureCount() == 1 && f.store->Triggered(), "failure is consumed exactly once");
        check(f.store->Text() == baseline && f.store->Selection() == selection &&
              f.store->MutationCount() == writes, "failed write preserves text and selection");
        return failed;
    };
    check(f.request(TS_LF_SYNC | TS_LF_READWRITE) == E_FAIL, "sink failure is the lock session result");
    check(!f.store->Arm(Scenario::FailWrite, L"new"), "D2 has no second arm");
    f.sink.action = [&](DWORD) {
        TS_SELECTION_ACP actual{};
        ULONG fetched = 0;
        check(f.store->GetSelection(TS_DEFAULT_SELECTION, 1, &actual, &fetched) == S_OK && fetched == 1,
              "read-only selection remains available after failure");
        check(actual.acpStart == selection.first && actual.acpEnd == selection.second,
              "read-only query sees the original selection");
        return S_OK;
    };
    check(f.request(TS_LF_SYNC | TS_LF_READ) == S_OK, "D2 preserves readback access");
    check(f.store->Text() == baseline && f.store->MutationCount() == writes,
          "readback does not recover or resend the failed write");
}

void readToWriteUpgradeIsDeferred() {
    Fixture f;
    unsigned readCallbacks = 0, writeCallbacks = 0;
    bool inReadCallback = false;
    f.sink.action = [&](DWORD flags) {
        if ((flags & TS_LF_READWRITE) == TS_LF_READWRITE) {
            check(!inReadCallback, "write upgrade never reenters the active read callback");
            ++writeCallbacks;
            return f.insert(L"upgrade");
        }
        ++readCallbacks;
        inReadCallback = true;
        HRESULT nested = E_UNEXPECTED;
        check(f.store->RequestLock(TS_LF_SYNC | TS_LF_READWRITE, &nested) == S_OK &&
              nested == TS_E_SYNCHRONOUS, "nested synchronous upgrade is refused");
        check(f.store->RequestLock(TS_LF_READWRITE, &nested) == S_OK && nested == TS_S_ASYNC,
              "nested asynchronous read-to-write upgrade is queued");
        check(f.store->RequestLock(TS_LF_READWRITE, &nested) == S_OK && nested == TS_S_ASYNC,
              "repeated nested upgrade merges into the same pending write");
        check(f.store->RequestLock(TS_LF_READ, &nested) == S_OK && nested == TS_S_ASYNC,
              "a later pending read must not downgrade the queued write upgrade");
        check(writeCallbacks == 0 && f.store->Text().empty(), "write callback cannot reenter read grant");
        inReadCallback = false;
        return S_OK;
    };
    check(f.request(TS_LF_SYNC | TS_LF_READ) == S_OK, "outer read grant completes");
    check(readCallbacks == 1 && writeCallbacks == 1 && !f.store->HasPendingLock() &&
          f.store->Text() == L"upgrade" && f.store->MutationCount() == 1,
          "outer request drains the merged upgrade only after the read callback returned");
    check(f.store->GrantPending() == E_UNEXPECTED && writeCallbacks == 1,
          "a deferred upgrade cannot grant twice");
}

void nestedAsyncLockSurvivesSynchronousGrant(DWORD outerMode, DWORD queuedMode, HRESULT outerResult) {
    Fixture f;
    bool inOuterCallback = false;
    f.sink.action = [&](DWORD flags) {
        if (f.sink.grants == 1) {
            check(flags == (TS_LF_SYNC | outerMode), "first grant has the requested synchronous mode");
            inOuterCallback = true;
            HRESULT nested = E_UNEXPECTED;
            check(f.store->RequestLock(queuedMode, &nested) == S_OK && nested == TS_S_ASYNC,
                  "nested asynchronous request is accepted separately from the active grant");
            check(f.store->HasPendingLock() && f.sink.grants == 1,
                  "accepted nested request stays pending during the outer callback");
            inOuterCallback = false;
            return outerResult;
        }
        check(!inOuterCallback && flags == queuedMode,
              "nested request receives its own grant only after the outer callback returns");
        return S_OK;
    };
    check(f.request(TS_LF_SYNC | outerMode) == outerResult, "outer session retains its own result");
    check(f.sink.grants == 2 && f.store->GrantCount() == 2 && !f.store->HasPendingLock(),
          "synchronous grant must not discard an accepted same-mode or weaker nested request");
    check(f.store->GrantPending() == E_UNEXPECTED && f.sink.grants == 2 &&
          f.store->Text().empty() && f.store->MutationCount() == 0,
          "nested request grants once without an unintended document mutation");
}

void repeatedWriteIsVisibleAndCannotReplay() {
    Fixture f;
    f.seed();
    const auto baseline = f.store->Text();
    const auto selection = f.store->Selection();
    const auto writes = f.store->MutationCount();
    const auto calls = f.store->WriteCallCount();
    check(f.store->Arm(Scenario::FailWrite, L"new"), "arm replay counterexample once");
    f.sink.action = [&](DWORD) {
        check(f.insert(L"new") == E_FAIL, "first write consumes the one-shot failure");
        check(FAILED(f.insert(L"new")), "a second mutation cannot replay the failed write");
        TS_SELECTION_ACP moved{0, 0, {TS_AE_END, FALSE}};
        check(FAILED(f.store->SetSelection(1, &moved)), "a failed case cannot later move selection");
        return E_FAIL;
    };
    check(f.request(TS_LF_SYNC | TS_LF_READWRITE) == E_FAIL, "counterexample returns failed callback");
    check(f.store->WriteCallCount() == calls + 2 && f.store->FailureCount() == 1,
          "rejected replay remains observable without consuming a second fault");
    check(f.store->Stopped() && f.store->Text() == baseline && f.store->Selection() == selection &&
          f.store->MutationCount() == writes, "replay attempt fails the case without mutating or rollback");
    check(!f.store->Arm(Scenario::FailWrite, L"new"), "a replay violation cannot rearm the case");
}

void closingCancelsPendingWithoutCallback() {
    Fixture f;
    check(f.store->Arm(Scenario::DelayWrite, L"never"), "arm close-pending case");
    f.sink.action = [&](DWORD) { return f.insert(L"never"); };
    check(f.request(TS_LF_READWRITE) == TS_S_ASYNC && f.store->HasPendingLock(), "write is pending");
    f.store->Close();
    check(f.store->Stopped() && !f.store->HasPendingLock(), "closing clears pending work");
    check(f.store->GrantPending() != S_OK && f.sink.grants == 0,
          "closing cannot invoke a retained sink callback");
    check(f.store->Text().empty() && f.store->MutationCount() == 0 &&
          !f.store->Arm(Scenario::DelayWrite, L"never"), "closed case never writes or rearms");
    f.store->Close();
    check(f.sink.grants == 0, "closing is idempotent");
}

void evidenceOverflowStopsTheCase() {
    Fixture f(2);
    // Bounded read-only activity fills the actual evidence buffer; it is not a
    // retry loop for a mutation or a native TSF execution.
    for (unsigned i = 0; i != 16 && !f.store->EvidenceOverflow(); ++i) {
        HRESULT session = E_UNEXPECTED;
        (void)f.store->RequestLock(TS_LF_SYNC | TS_LF_READ, &session);
    }
    check(f.store->EvidenceOverflow() && f.store->Stopped(), "lost evidence stops the case");
    check(f.store->Events().size() <= 2, "evidence buffer remains bounded");
    const auto grants = f.sink.grants;
    check(!f.store->Arm(Scenario::FailWrite, L"blocked"), "overflow cannot arm a new fault");
    check(f.store->GrantPending() != S_OK && f.sink.grants == grants &&
          f.store->Text().empty() && f.store->MutationCount() == 0,
          "overflow cannot authorize a write or pending grant");

    Fixture selectionCase(32);
    selectionCase.seed();
    const auto originalSelection = selectionCase.store->Selection();
    selectionCase.sink.action = [&](DWORD) {
        while (selectionCase.store->Events().size() < 32)
            check(selectionCase.store->Record("offline-capacity-fixture"), "fill bounded evidence buffer");
        TS_SELECTION_ACP moved{0, 0, {TS_AE_END, FALSE}};
        check(selectionCase.store->SetSelection(1, &moved) == E_ABORT,
              "selection update stops if its evidence cannot be recorded");
        check(selectionCase.store->Selection() == originalSelection,
              "evidence overflow must not change selection before returning failure");
        return E_ABORT;
    };
    check(selectionCase.request(TS_LF_SYNC | TS_LF_READWRITE) == E_ABORT &&
          selectionCase.store->EvidenceOverflow() && selectionCase.store->Stopped(),
          "selection overflow is an explicit stopped case");
}

void writesRequireWriteLock() {
    Fixture f;
    check(FAILED(f.insert(L"unlocked")), "write outside a granted lock is rejected");
    f.sink.action = [&](DWORD) {
        check(FAILED(f.insert(L"read-only")), "read grant does not allow mutation");
        return S_OK;
    };
    check(f.request(TS_LF_SYNC | TS_LF_READ) == S_OK, "read grant remains usable");
    check(f.store->Text().empty() && f.store->MutationCount() == 0,
          "invalid write attempts preserve the private document");
}

void runInfoOnlyReadAndSinkOwnership() {
    Fixture f;
    const auto references = f.sink.references;
    check(f.store->AdviseSink(IID_ITextStoreACPSink, &f.sink, TS_AS_SEL_CHANGE) == S_OK,
          "the same sink identity may update its advisory mask");
    check(f.sink.references == references, "mask update does not retain the sink twice");
    FakeSink stranger;
    check(FAILED(f.store->AdviseSink(IID_ITextStoreACPSink, &stranger, TS_AS_TEXT_CHANGE)),
          "a different sink cannot replace the live advisory connection");
    check(FAILED(f.store->UnadviseSink(&stranger)), "a different identity cannot unadvise the owner");
    check(stranger.references == 1 && f.sink.references == references,
          "rejected advisory operations preserve ownership");
    f.seed();
    ULONG plainCount = 0, runCount = 0;
    LONG next = -1;
    TS_RUNINFO run{};
    check(FAILED(f.store->GetText(0, -1, nullptr, 0, &plainCount, &run, 1, &runCount, &next)),
          "text reads require a granted read lock");
    f.sink.action = [&](DWORD) {
        plainCount = runCount = 0;
        next = -1;
        check(f.store->GetText(0, -1, nullptr, 0, &plainCount, &run, 1, &runCount, &next) == S_OK,
              "TSF can query run information without a plain-text buffer");
        check(plainCount == 0 && runCount == 1 && run.type == TS_RT_PLAIN &&
              run.uCount == 8 && next == 8, "run-only text query advances next through the described text");
        return S_OK;
    };
    check(f.request(TS_LF_SYNC | TS_LF_READ) == S_OK, "original sink still owns read grants");
}

nlohmann::json validPlan(const char* caseId = "D1") {
    using namespace yime::nativehost;
    return {
        {"schemaVersion", "yime-18u-native-host-plan-v1"}, {"runId", "offline-case-1"},
        {"caseId", caseId}, {"expectedMachine", "OFFLINE-FIXTURE"}, {"architecture", "native-x64"},
        {"packageVersion", "0.1.0-18u-test.12"}, {"sourceCommit", SourceCommit},
        {"outerZipSha256", OuterHash}, {"innerZipSha256", InnerHash}, {"descriptorSha256", DescriptorHash},
        {"installedRoot", "C:\\Program Files\\YimeCore 18u Touch"},
        {"frontendSha256", FrontendHash}, {"tipSha256", TipHash},
        {"hostSha256", std::string(64, 'a')}, {"expectedText", "synthetic-only"},
        {"expectedTextUtf16Sha256", std::string(64, 'b')}, {"maxDurationMs", 30000},
        {"delayMs", std::string(caseId) == "D1" ? 300 : 0}, {"allowManualRecovery", false}
    };
}

template<class F> void rejected(F&& operation, const char* message) {
    bool didReject = false;
    try { operation(); } catch (const std::exception&) { didReject = true; }
    check(didReject, message);
}

void planGateRejectsScopeAndIdentityDrift() {
    using namespace yime::nativehost;
    const auto d1 = validPlan();
    const auto accepted = parsePlan(d1.dump(), "D1");
    check(accepted.caseId == "D1" && accepted.scenario == Scenario::DelayWrite && accepted.delayMs == 300,
          "valid D1 plan parses without starting any host");
    check(parsePlan(validPlan("D2").dump(), "D2").scenario == Scenario::FailWrite,
          "valid D2 plan parses without starting any host");
    auto changed = [&](const char* field, const nlohmann::json& value) {
        auto j = d1; j[field] = value;
        rejected([&] { (void)parsePlan(j.dump(), "D1"); }, field);
    };
    changed("caseId", "D3");
    rejected([&] { (void)parsePlan(d1.dump(), "D2"); }, "requested case must match the plan");
    changed("architecture", "arm64");
    changed("sourceCommit", std::string(40, '0'));
    changed("tipSha256", std::string(64, '0'));
    changed("frontendSha256", std::string(64, '0'));
    changed("hostSha256", "not-a-hash");
    changed("allowManualRecovery", true);
    changed("unexpectedTargetPid", 123);
    changed("expectedText", nullptr);
    changed("expectedText", "line\nbreak");
    changed("expectedText", std::string(129, 'x'));
    changed("runId", "../escape");
    changed("installedRoot", "\\\\server\\share\\Yime");
    changed("installedRoot", "C:\\allowed\\..\\elsewhere");
    changed("installedRoot", "C:\\allowed:alternate");
    changed("maxDurationMs", true);
    changed("maxDurationMs", -1);
    changed("maxDurationMs", 120001);
    changed("delayMs", 249);
    changed("delayMs", 501);
    changed("delayMs", 300.0);
    auto missing = d1; missing.erase("allowManualRecovery");
    rejected([&] { (void)parsePlan(missing.dump()); }, "missing permission field fails closed");
    auto d2WrongDelay = validPlan("D2"); d2WrongDelay["delayMs"] = 300;
    rejected([&] { (void)parsePlan(d2WrongDelay.dump()); }, "D2 cannot smuggle in D1 delay");
    const auto duplicate = std::string("{\"runId\":\"duplicate\",") + d1.dump().substr(1);
    rejected([&] { (void)parsePlan(duplicate); }, "duplicate JSON keys are rejected before validation");
    rejected([&] { (void)parsePlan("[]"); }, "plan must be a single object");
    rejected([&] { (void)parsePlan(d1.dump() + "{}"); }, "trailing JSON is rejected");
    rejected([&] { (void)parsePlan(std::string(32769, ' ')); }, "oversized plan is rejected");
    auto invalidUtf8 = d1.dump();
    const auto marker = invalidUtf8.find("synthetic-only");
    check(marker != std::string::npos, "invalid UTF8 fixture locates only its own synthetic text");
    invalidUtf8.replace(marker, std::string("synthetic-only").size(), "\xc0\xaf");
    rejected([&] { (void)parsePlan(invalidUtf8); }, "malformed UTF8 cannot reach the text store");
}
} // namespace

int main() {
    try {
        queryInsertUsesExistingDocumentRange();
        delayWriteDefersUntilOneGrant();
        failedWritePreservesTextAndSelection(false);
        failedWritePreservesTextAndSelection(true);
        readToWriteUpgradeIsDeferred();
        nestedAsyncLockSurvivesSynchronousGrant(TS_LF_READ, TS_LF_READ, S_OK);
        nestedAsyncLockSurvivesSynchronousGrant(TS_LF_READWRITE, TS_LF_READWRITE, S_OK);
        nestedAsyncLockSurvivesSynchronousGrant(TS_LF_READWRITE, TS_LF_READ, S_OK);
        nestedAsyncLockSurvivesSynchronousGrant(TS_LF_READ, TS_LF_READ, E_FAIL);
        repeatedWriteIsVisibleAndCannotReplay();
        closingCancelsPendingWithoutCallback();
        evidenceOverflowStopsTheCase();
        writesRequireWriteLock();
        runInfoOnlyReadAndSinkOwnership();
        planGateRejectsScopeAndIdentityDrift();
        std::cout << "offline_textstore_contracts=passed\n"
                     "sink=fake\n"
                     "native_tsf_executed=false\n"
                     "tip_loaded=false\n"
                     "registration_changed=false\n"
                     "physical_acceptance=false\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "offline_textstore_contracts=failed: " << error.what() << '\n';
        return 1;
    }
}
