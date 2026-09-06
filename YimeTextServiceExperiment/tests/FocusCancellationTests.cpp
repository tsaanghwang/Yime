#include <windows.h>
#include <msctf.h>

#include <deque>
#include <iostream>
#include <string>
#include <vector>

#include "CompositionEditSession.h"

// These mocks never activate TSF, open a user document, connect to the Broker,
// or touch installed registrations. Every document below is synthetic memory.
namespace {

int failures = 0;
int checks = 0;
constexpr TfEditCookie kWriteCookie = 73;

void expect(bool value, const char* message) {
    ++checks;
    if (!value) {
        ++failures;
        std::cerr << message << '\n';
    }
}

template<class Interface>
class StackCom : public Interface {
public:
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (!IsEqualIID(iid, IID_IUnknown) && !IsEqualIID(iid, __uuidof(Interface))) return E_NOINTERFACE;
        *object = static_cast<Interface*>(this);
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references; }
    STDMETHODIMP_(ULONG) Release() override { return --references; }
    // The fixture retains the initial reference and owns stack lifetime.
    ULONG references = 1;
};

class FakeRange final : public StackCom<ITfRange> {
public:
    FakeRange(std::wstring& value, size_t first, size_t last)
        : document(value), start(first), end(last) {}
    STDMETHODIMP SetText(TfEditCookie cookie, DWORD, const WCHAR* text, LONG length) override {
        ++writes;
        if (cookie != kWriteCookie) return TF_E_NOLOCK;
        if (FAILED(writeResult)) return writeResult;
        if (length < 0 || (!text && length != 0)) return E_INVALIDARG;
        document.replace(start, end - start, text ? text : L"", static_cast<size_t>(length));
        end = start + static_cast<size_t>(length);
        return S_OK;
    }
    STDMETHODIMP Collapse(TfEditCookie cookie, TfAnchor anchor) override {
        if (cookie != kWriteCookie) return TF_E_NOLOCK;
        if (anchor == TF_ANCHOR_END) start = end;
        else end = start;
        return S_OK;
    }
    STDMETHODIMP GetText(TfEditCookie, DWORD, WCHAR*, ULONG, ULONG*) override { return E_NOTIMPL; }
    STDMETHODIMP GetFormattedText(TfEditCookie, IDataObject**) override { return E_NOTIMPL; }
    STDMETHODIMP GetEmbedded(TfEditCookie, REFGUID, REFIID, IUnknown**) override { return E_NOTIMPL; }
    STDMETHODIMP InsertEmbedded(TfEditCookie, DWORD, IDataObject*) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftStart(TfEditCookie, LONG, LONG*, const TF_HALTCOND*) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftEnd(TfEditCookie, LONG, LONG*, const TF_HALTCOND*) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftStartToRange(TfEditCookie, ITfRange*, TfAnchor) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftEndToRange(TfEditCookie, ITfRange*, TfAnchor) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftStartRegion(TfEditCookie, TfShiftDir, BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftEndRegion(TfEditCookie, TfShiftDir, BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP IsEmpty(TfEditCookie, BOOL* empty) override {
        if (!empty) return E_POINTER;
        *empty = start == end;
        return S_OK;
    }
    STDMETHODIMP IsEqualStart(TfEditCookie, ITfRange*, TfAnchor, BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP IsEqualEnd(TfEditCookie, ITfRange*, TfAnchor, BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP CompareStart(TfEditCookie, ITfRange*, TfAnchor, LONG*) override { return E_NOTIMPL; }
    STDMETHODIMP CompareEnd(TfEditCookie, ITfRange*, TfAnchor, LONG*) override { return E_NOTIMPL; }
    STDMETHODIMP AdjustForInsert(TfEditCookie, ULONG, BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP GetGravity(TfGravity*, TfGravity*) override { return E_NOTIMPL; }
    STDMETHODIMP SetGravity(TfEditCookie, TfGravity, TfGravity) override { return E_NOTIMPL; }
    STDMETHODIMP Clone(ITfRange**) override { return E_NOTIMPL; }
    STDMETHODIMP GetContext(ITfContext**) override { return E_NOTIMPL; }

    std::wstring& document;
    size_t start;
    size_t end;
    HRESULT writeResult = S_OK;
    int writes = 0;
};

class FakeSink final : public StackCom<ITfCompositionSink> {
public:
    STDMETHODIMP OnCompositionTerminated(TfEditCookie, ITfComposition*) override {
        ++terminations;
        plannedAtTermination = planned && *planned;
        return S_OK;
    }
    bool* planned = nullptr;
    bool plannedAtTermination = false;
    int terminations = 0;
};

class FakeComposition final : public StackCom<ITfComposition> {
public:
    FakeComposition(FakeRange& value, FakeSink& callback) : range(value), sink(callback) {}
    STDMETHODIMP GetRange(ITfRange** value) override {
        if (!value) return E_POINTER;
        *value = nullptr;
        if (FAILED(rangeResult)) return rangeResult;
        if (!nullRange) {
            *value = &range;
            range.AddRef();
        }
        return S_OK;
    }
    STDMETHODIMP ShiftStart(TfEditCookie, ITfRange*) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftEnd(TfEditCookie, ITfRange*) override { return E_NOTIMPL; }
    STDMETHODIMP EndComposition(TfEditCookie cookie) override {
        ++ends;
        return sink.OnCompositionTerminated(cookie, this);
    }
    FakeRange& range;
    FakeSink& sink;
    HRESULT rangeResult = S_OK;
    bool nullRange = false;
    int ends = 0;
};

class FakeContext final : public StackCom<ITfContext> {
public:
    ~FakeContext() { for (auto* session : pending) session->Release(); }
    STDMETHODIMP RequestEditSession(TfClientId, ITfEditSession* session, DWORD flags,
                                   HRESULT* result) override {
        if (!session || !result) return E_POINTER;
        lastFlags = flags;
        if (FAILED(requestResult)) return requestResult;
        if (defer && !(flags & TF_ES_SYNC)) {
            session->AddRef();
            pending.push_back(session);
            *result = TF_S_ASYNC;
        } else {
            *result = session->DoEditSession(kWriteCookie);
        }
        return S_OK;
    }
    HRESULT drainOne() {
        if (pending.empty()) return E_UNEXPECTED;
        auto* session = pending.front();
        pending.pop_front();
        const HRESULT result = session->DoEditSession(kWriteCookie);
        session->Release();
        return result;
    }
    STDMETHODIMP SetSelection(TfEditCookie cookie, ULONG, const TF_SELECTION*) override {
        if (cookie != kWriteCookie) return TF_E_NOLOCK;
        ++selections;
        return S_OK;
    }
    STDMETHODIMP InWriteSession(TfClientId, BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP GetSelection(TfEditCookie, ULONG, ULONG, TF_SELECTION*, ULONG*) override { return E_NOTIMPL; }
    STDMETHODIMP GetStart(TfEditCookie, ITfRange**) override { return E_NOTIMPL; }
    STDMETHODIMP GetEnd(TfEditCookie, ITfRange**) override { return E_NOTIMPL; }
    STDMETHODIMP GetActiveView(ITfContextView**) override { return E_NOTIMPL; }
    STDMETHODIMP EnumViews(IEnumTfContextViews**) override { return E_NOTIMPL; }
    STDMETHODIMP GetStatus(TF_STATUS*) override { return E_NOTIMPL; }
    STDMETHODIMP GetProperty(REFGUID, ITfProperty**) override { return E_NOTIMPL; }
    STDMETHODIMP GetAppProperty(REFGUID, ITfReadOnlyProperty**) override { return E_NOTIMPL; }
    STDMETHODIMP TrackProperties(const GUID**, ULONG, const GUID**, ULONG, ITfReadOnlyProperty**) override { return E_NOTIMPL; }
    STDMETHODIMP EnumProperties(IEnumTfProperties**) override { return E_NOTIMPL; }
    STDMETHODIMP GetDocumentMgr(ITfDocumentMgr**) override { return E_NOTIMPL; }
    STDMETHODIMP CreateRangeBackup(TfEditCookie, ITfRange*, ITfRangeBackup**) override { return E_NOTIMPL; }

    bool defer = true;
    HRESULT requestResult = S_OK;
    DWORD lastFlags = 0;
    int selections = 0;
    std::deque<ITfEditSession*> pending;
};

struct Completion {
    static void record(void* value, ITfComposition* captured, HRESULT result) noexcept {
        auto& self = *static_cast<Completion*>(value);
        self.identities.push_back(captured);
        self.results.push_back(result);
    }
    std::vector<ITfComposition*> identities;
    std::vector<HRESULT> results;
};

struct Fixture {
    const std::wstring prefix = L"confirmed-prefix:";
    const std::wstring raw = L"ascii42";
    const std::wstring suffix = L":confirmed-suffix";
    std::wstring document = prefix + raw + suffix;
    bool planned = false;
    FakeRange range{document, prefix.size(), prefix.size() + raw.size()};
    FakeSink sink;
    FakeComposition composition{range, sink};
    ITfComposition* active = &composition;
    Completion completion;
    FakeContext context;

    Fixture() {
        sink.planned = &planned;
        composition.AddRef();  // The active-composition slot owns one reference.
    }
    ~Fixture() {
        while (!context.pending.empty()) context.drainOne();
        if (active) active->Release();
    }
    HRESULT cancel() {
        return yime::experiment::CancelCompositionInContext(&context, 1, &sink,
            &active, &planned, &Completion::record, &completion);
    }
    bool completed(HRESULT expected, size_t count = 1) const {
        return completion.results.size() == count &&
               completion.results.back() == expected &&
               completion.identities.back() == &composition;
    }
};

void testDeferredCancellation() {
    Fixture f;
    expect(f.cancel() == TF_S_ASYNC, "deferred cancellation did not return TF_S_ASYNC");
    expect(f.document == f.prefix + f.raw + f.suffix && f.range.writes == 0 &&
               f.composition.ends == 0 && f.completion.results.empty() && f.active == &f.composition,
           "queued request edited text or reported premature completion");
    expect((f.context.lastFlags & TF_ES_READWRITE) != 0 &&
               (f.context.lastFlags & TF_ES_SYNC) == 0 && f.composition.references == 3,
           "deferred request did not capture and retain its composition identity");
    expect(f.context.drainOne() == S_OK && f.completed(S_OK), "drained cancellation completion failed");
    expect(f.document == f.prefix + f.suffix && !f.active && f.range.writes == 1 &&
               f.composition.ends == 1 && f.context.selections == 1,
           "cancellation did not remove exactly the unconfirmed range");
    expect(!f.planned && f.sink.plannedAtTermination && f.composition.references == 1 &&
               f.context.references == 1 && f.sink.references == 1 && f.range.references == 1,
           "cancellation did not balance lifetime and planned-termination guards");
}

void testImmediateCancellation() {
    Fixture f;
    f.context.defer = false;
    expect(f.cancel() == S_OK && f.completed(S_OK) && f.context.pending.empty(),
           "immediate lock grant did not complete synchronously");
    expect(f.document == f.prefix + f.suffix && !f.active,
           "immediate cancellation retained raw input or removed confirmed text");
}

void testDuplicateCancellation() {
    Fixture f;
    expect(f.cancel() == TF_S_ASYNC && f.cancel() == TF_S_ASYNC,
           "duplicate cancellation setup failed");
    expect(f.context.drainOne() == S_OK && f.context.drainOne() == S_FALSE && f.completed(S_FALSE, 2),
           "duplicate stale request was not reported as S_FALSE");
    expect(f.document == f.prefix + f.suffix && f.range.writes == 1 && f.composition.ends == 1,
           "duplicate cancellation mutated an already-finished composition");
}

void testReplacementIdentity() {
    Fixture f;
    std::wstring newDocument = L"new-prefix:newraw:new-suffix";
    FakeRange newRange(newDocument, 11, 17);
    FakeComposition newer(newRange, f.sink);
    expect(f.cancel() == TF_S_ASYNC, "replacement identity setup failed");
    f.active->Release();
    f.active = &newer;
    newer.AddRef();
    expect(f.context.drainOne() == S_FALSE && f.completed(S_FALSE),
           "old request was allowed to cancel a newer composition identity");
    expect(f.document == f.prefix + f.raw + f.suffix &&
               newDocument == L"new-prefix:newraw:new-suffix" && f.active == &newer &&
               f.range.writes == 0 && newRange.writes == 0 && f.context.selections == 0,
           "stale cancellation changed old or new text/selection");
    f.active->Release();
    f.active = nullptr;
    expect(newer.references == 1 && f.composition.references == 1,
           "stale identity cancellation leaked composition references");
}

void testFailedWrite() {
    Fixture f;
    f.range.writeResult = E_ACCESSDENIED;
    expect(f.cancel() == TF_S_ASYNC && f.completion.results.empty(), "failed-write setup failed");
    expect(f.context.drainOne() == E_ACCESSDENIED && f.completed(E_ACCESSDENIED),
           "write failure did not reach the completion callback");
    expect(f.document == f.prefix + f.raw + f.suffix && f.active == &f.composition &&
               f.context.selections == 0 && f.composition.ends == 0 && !f.planned,
           "failed write mutated text, selection, or composition ownership");
    f.range.writeResult = S_OK;
    expect(f.cancel() == TF_S_ASYNC && f.context.drainOne() == S_OK && f.completed(S_OK, 2),
           "a later cancellation could not recover after a failed write");
}

void testExternalTerminationClear() {
    Fixture f;
    expect(f.cancel() == TF_S_ASYNC, "external termination setup failed");
    expect(yime::experiment::ClearCompositionText(kWriteCookie, &f.composition) == S_OK,
           "external termination failed to clear its exact composition range");
    expect(f.document == f.prefix + f.suffix && f.composition.ends == 0 &&
               f.sink.terminations == 0 && f.context.selections == 0,
           "external clear ended composition recursively or touched selection/confirmed text");
    f.active->Release();
    f.active = nullptr;
    expect(f.context.drainOne() == S_FALSE && f.completed(S_FALSE) && f.range.writes == 1,
           "delayed focus cancellation rewrote an externally terminated composition");
}

void testConfirmedCommitWins() {
    Fixture f;
    expect(f.cancel() == TF_S_ASYNC, "explicit commit setup failed");
    yime::experiment::BrokerUpdate confirmed;
    confirmed.commit = "confirmed-choice";
    expect(yime::experiment::ApplyBrokerUpdateToContext(&f.context, 1, &f.sink, &f.active,
               &f.planned, confirmed) == S_OK && !f.active,
           "explicit confirmed commit did not end the old composition");
    expect(f.context.drainOne() == S_FALSE && f.completed(S_FALSE) &&
               f.document == f.prefix + L"confirmed-choice" + f.suffix && f.range.writes == 1,
           "delayed cancellation deleted an explicit confirmed commit");
}

void testRangeAndRequestFailures() {
    Fixture f;
    f.context.requestResult = E_ACCESSDENIED;
    expect(f.cancel() == E_ACCESSDENIED && f.context.pending.empty() &&
               f.completion.results.empty() && f.composition.references == 2,
           "rejected request queued work, completed, or leaked the captured identity");
    f.context.requestResult = S_OK;
    f.composition.nullRange = true;
    expect(f.cancel() == TF_S_ASYNC && f.context.drainOne() == E_UNEXPECTED && f.completed(E_UNEXPECTED),
           "successful GetRange with null output was not rejected");
    expect(yime::experiment::ClearCompositionText(kWriteCookie, &f.composition) == E_UNEXPECTED,
           "external clear accepted a null successful range");
    f.composition.nullRange = false;
    f.composition.rangeResult = E_FAIL;
    expect(yime::experiment::ClearCompositionText(kWriteCookie, &f.composition) == E_FAIL,
           "external clear masked a failed GetRange");
    f.composition.rangeResult = S_OK;
    f.range.writeResult = E_ACCESSDENIED;
    expect(yime::experiment::ClearCompositionText(kWriteCookie, &f.composition) == E_ACCESSDENIED &&
               f.document == f.prefix + f.raw + f.suffix && f.composition.ends == 0,
           "external clear masked a failed write or ended the composition");
    expect(yime::experiment::ClearCompositionText(kWriteCookie, nullptr) == E_INVALIDARG,
           "external clear accepted a null composition");
}

}  // namespace

int main() {
    testDeferredCancellation();
    testImmediateCancellation();
    testDuplicateCancellation();
    testReplacementIdentity();
    testFailedWrite();
    testExternalTerminationClear();
    testConfirmedCommitWins();
    testRangeAndRequestFailures();
    std::cout << "focus cancellation isolated mock checks=" << checks << " failures=" << failures << '\n';
    return failures ? 1 : 0;
}
