// Production edit callback against memory-only TSF substitutes. No registration,
// real thread manager activation, foreground change, or user-document access.
#define YIME_TOUCH_FRONTEND_MEMORY_TEST 1
#include "../TouchFrontendEndpoint.cpp"
#include <iostream>
#include <functional>
#include <limits>
#include <vector>

static long moduleRefs = 0;
void YimeModuleAddRef() noexcept { ++moduleRefs; }
void YimeModuleRelease() noexcept { --moduleRefs; }
long YimeModuleRefCount() noexcept { return moduleRefs; }

namespace {
void check(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
std::vector<json> diagnosticEvents;
unsigned diagnosticSinkCalls=0;
void captureDiagnostic(const char* bytes,size_t size) {
    ++diagnosticSinkCalls;
    check(size<yime::touchdiag::kMaxRecordBytes,"bounded diagnostic record");
    diagnosticEvents.push_back(json::parse(bytes,bytes+size));
}
void throwingDiagnostic(const char*,size_t) {
    ++diagnosticSinkCalls;SetLastError(ERROR_ACCESS_DENIED);
    throw std::runtime_error("test diagnostic sink failure");
}
void resetDiagnostics() { diagnosticEvents.clear();diagnosticSinkCalls=0; }
const json& diagnosticAt(const char* stage) {
    for(const auto& row:diagnosticEvents)if(row.at("stage")==stage)return row;
    throw std::runtime_error(std::string("missing diagnostic stage: ")+stage);
}
template<class T> class FakeCom : public T {
public:
    ULONG refs = 1;
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid != __uuidof(IUnknown) && iid != __uuidof(T)) return E_NOINTERFACE;
        *out = static_cast<T*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs; }
    STDMETHODIMP_(ULONG) Release() override { return --refs; }
};
struct ShiftObservation { LONG requested, moved; };
struct Memory {
    std::wstring text; LONG first=0, last=0; TfActiveSelEnd active=TF_AE_END;
    HRESULT write=S_OK, read=S_OK, shiftStart=S_OK, shiftEnd=S_OK, collapse=S_OK;
    LONG maxStartShift=std::numeric_limits<LONG>::max(), maxEndShift=std::numeric_limits<LONG>::max();
    ULONG maxRead=std::numeric_limits<ULONG>::max();
    unsigned writes=0,selections=0,writeCalls=0,readCalls=0,collapseCalls=0,failCollapseCall=0;
    std::vector<ShiftObservation> startShifts,endShifts;
    std::function<void()> afterWrite;
};
class Range final : public FakeCom<ITfRange> {
public:
    Memory& m; LONG first, last;
    Range(Memory& value, LONG a, LONG b):m(value),first(a),last(b){}
    STDMETHODIMP_(ULONG) Release() override { ULONG n=--refs; if(!n)delete this; return n; }
    STDMETHODIMP SetText(TfEditCookie cookie,DWORD,const WCHAR* value,LONG n) override {
        check(cookie==73,"write cookie"); ++m.writeCalls;if(FAILED(m.write))return m.write;
        m.text.replace(first,last-first,value,n);last=first+n;++m.writes;if(m.afterWrite)m.afterWrite();return S_OK;
    }
    STDMETHODIMP GetText(TfEditCookie,DWORD,WCHAR* out,ULONG max,ULONG* count) override {
        ++m.readCalls;*count=0;if(FAILED(m.read))return m.read;
        *count=std::min({max,m.maxRead,static_cast<ULONG>(last-first)});std::copy_n(m.text.data()+first,*count,out);return S_OK;
    }
    STDMETHODIMP Collapse(TfEditCookie,TfAnchor anchor) override {
        ++m.collapseCalls;if(m.failCollapseCall==m.collapseCalls)return m.collapse;
        if(anchor==TF_ANCHOR_START)last=first;else first=last;return S_OK;
    }
    STDMETHODIMP Clone(ITfRange** out) override { *out=new Range(m,first,last);return S_OK; }
    STDMETHODIMP ShiftStart(TfEditCookie,LONG n,LONG* moved,const TF_HALTCOND*) override {
        *moved=0;
        if(FAILED(m.shiftStart)){m.startShifts.push_back({n,0});return m.shiftStart;}
        const LONG limited=std::clamp(n,-m.maxStartShift,m.maxStartShift);
        LONG next=std::clamp(first+limited,0L,static_cast<LONG>(m.text.size()));*moved=next-first;
        m.startShifts.push_back({n,*moved});first=next;last=std::max(first,last);return S_OK;
    }
    STDMETHODIMP ShiftEnd(TfEditCookie,LONG n,LONG* moved,const TF_HALTCOND*) override {
        *moved=0;
        if(FAILED(m.shiftEnd)){m.endShifts.push_back({n,0});return m.shiftEnd;}
        const LONG limited=std::clamp(n,-m.maxEndShift,m.maxEndShift);
        LONG next=std::clamp(last+limited,0L,static_cast<LONG>(m.text.size()));*moved=next-last;
        m.endShifts.push_back({n,*moved});last=next;first=std::min(first,last);return S_OK;
    }
    LONG edge(ITfRange* other,TfAnchor a) { auto* r=static_cast<Range*>(other);return a==TF_ANCHOR_START?r->first:r->last; }
    STDMETHODIMP ShiftStartToRange(TfEditCookie,ITfRange* other,TfAnchor a) override {first=edge(other,a);last=std::max(first,last);return S_OK;}
    STDMETHODIMP ShiftEndToRange(TfEditCookie,ITfRange* other,TfAnchor a) override {last=edge(other,a);first=std::min(first,last);return S_OK;}
    STDMETHODIMP CompareStart(TfEditCookie,ITfRange* other,TfAnchor a,LONG* order) override {*order=first-edge(other,a);return S_OK;}
    STDMETHODIMP IsEmpty(TfEditCookie,BOOL* out) override {*out=first==last;return S_OK;}
    STDMETHODIMP GetFormattedText(TfEditCookie,IDataObject**) override{return E_NOTIMPL;}
    STDMETHODIMP GetEmbedded(TfEditCookie,REFGUID,REFIID,IUnknown**) override{return E_NOTIMPL;}
    STDMETHODIMP InsertEmbedded(TfEditCookie,DWORD,IDataObject*) override{return E_NOTIMPL;}
    STDMETHODIMP ShiftStartRegion(TfEditCookie,TfShiftDir,BOOL*) override{return E_NOTIMPL;}
    STDMETHODIMP ShiftEndRegion(TfEditCookie,TfShiftDir,BOOL*) override{return E_NOTIMPL;}
    STDMETHODIMP IsEqualStart(TfEditCookie,ITfRange*,TfAnchor,BOOL*) override{return E_NOTIMPL;}
    STDMETHODIMP IsEqualEnd(TfEditCookie,ITfRange*,TfAnchor,BOOL*) override{return E_NOTIMPL;}
    STDMETHODIMP CompareEnd(TfEditCookie,ITfRange*,TfAnchor,LONG*) override{return E_NOTIMPL;}
    STDMETHODIMP AdjustForInsert(TfEditCookie,ULONG,BOOL*) override{return E_NOTIMPL;}
    STDMETHODIMP GetGravity(TfGravity*,TfGravity*) override{return E_NOTIMPL;}
    STDMETHODIMP SetGravity(TfEditCookie,TfGravity,TfGravity) override{return E_NOTIMPL;}
    STDMETHODIMP GetContext(ITfContext**) override{return E_NOTIMPL;}
};
class Context final : public FakeCom<ITfContext> {
public:
    Memory m; ComPtr<ITfEditSession> pending;
    DWORD status = 0; HRESULT statusResult = S_OK;
    HRESULT selectionResult=S_OK,setSelectionResult=S_OK,requestResult=S_OK,sessionResult=TF_S_ASYNC;
    ULONG selectionCount=1;bool nullSelection=false,synchronousEdit=false,writesSessionResult=true;
    unsigned selectionCalls=0,setSelectionCalls=0,requestCalls=0,statusCalls=0;
    std::function<void()> afterSelection, afterStatus, beforeRequestReturn;
    STDMETHODIMP RequestEditSession(TfClientId,ITfEditSession* edit,DWORD flags,HRESULT* result) override {
        check(flags==(TF_ES_ASYNCDONTCARE|TF_ES_READWRITE),"explicit read/write edit request");
        ++requestCalls;if(writesSessionResult)*result=sessionResult;
        if(SUCCEEDED(requestResult)) {
            if(synchronousEdit)*result=edit->DoEditSession(73);
            else if(sessionResult==TF_S_ASYNC)pending=edit;
        }
        if(beforeRequestReturn)beforeRequestReturn();
        return requestResult;
    }
    HRESULT drain(){auto edit=pending;pending.Reset();return edit->DoEditSession(73);}
    STDMETHODIMP GetSelection(TfEditCookie,ULONG,ULONG,TF_SELECTION* out,ULONG* count) override {
        ++selectionCalls;*out={};*count=0;
        if(FAILED(selectionResult))return selectionResult;
        *count=selectionCount;
        if(selectionCount==1 && !nullSelection)out->range=new Range(m,m.first,m.last);
        out->style={m.active,FALSE};if(afterSelection)afterSelection();return selectionResult;
    }
    STDMETHODIMP SetSelection(TfEditCookie,ULONG,const TF_SELECTION* value) override {
        ++setSelectionCalls;if(FAILED(setSelectionResult))return setSelectionResult;
        auto* r=static_cast<Range*>(value->range);m.first=r->first;m.last=r->last;m.active=value->style.ase;++m.selections;return S_OK;
    }
    STDMETHODIMP GetStart(TfEditCookie,ITfRange** out) override {*out=new Range(m,0,0);return S_OK;}
    STDMETHODIMP GetEnd(TfEditCookie,ITfRange** out) override {LONG n=static_cast<LONG>(m.text.size());*out=new Range(m,n,n);return S_OK;}
    STDMETHODIMP InWriteSession(TfClientId,BOOL*) override{return E_NOTIMPL;}
    STDMETHODIMP GetActiveView(ITfContextView**) override{return E_NOTIMPL;}
    STDMETHODIMP EnumViews(IEnumTfContextViews**) override{return E_NOTIMPL;}
    STDMETHODIMP GetStatus(TF_STATUS* out) override{++statusCalls;*out={};out->dwDynamicFlags=status;if(afterStatus)afterStatus();return statusResult;}
    STDMETHODIMP GetProperty(REFGUID,ITfProperty**) override{return E_NOTIMPL;}
    STDMETHODIMP GetAppProperty(REFGUID,ITfReadOnlyProperty**) override{return E_NOTIMPL;}
    STDMETHODIMP TrackProperties(const GUID**,ULONG,const GUID**,ULONG,ITfReadOnlyProperty**) override{return E_NOTIMPL;}
    STDMETHODIMP EnumProperties(IEnumTfProperties**) override{return E_NOTIMPL;}
    STDMETHODIMP GetDocumentMgr(ITfDocumentMgr**) override{return E_NOTIMPL;}
    STDMETHODIMP CreateRangeBackup(TfEditCookie,ITfRange*,ITfRangeBackup**) override{return E_NOTIMPL;}
};
class Document final : public FakeCom<ITfDocumentMgr> {
public:
    Context context; bool replaced=false;unsigned topQueries=0;
    HRESULT topResult=S_OK;std::function<void()> beforeTopReturn;
    STDMETHODIMP GetTop(ITfContext** out) override {
        ++topQueries;if(beforeTopReturn)beforeTopReturn();
        *out=FAILED(topResult)||replaced?nullptr:&context;if(*out)(*out)->AddRef();return topResult;
    }
    STDMETHODIMP CreateContext(TfClientId,DWORD,IUnknown*,ITfContext**,TfEditCookie*) override{return E_NOTIMPL;}
    STDMETHODIMP Push(ITfContext*) override{return E_NOTIMPL;}
    STDMETHODIMP Pop(DWORD) override{return E_NOTIMPL;}
    STDMETHODIMP GetBase(ITfContext**) override{return E_NOTIMPL;}
    STDMETHODIMP EnumContexts(IEnumTfContexts**) override{return E_NOTIMPL;}
};
class Manager final : public FakeCom<ITfThreadMgr> {
public:
    Document document;
    HRESULT threadFocusResult=S_OK;BOOL threadFocused=TRUE;unsigned threadFocusQueries=0,focusQueries=0;
    HRESULT focusResult=S_OK;std::function<void()> beforeFocusReturn;
    STDMETHODIMP GetFocus(ITfDocumentMgr** out) override {
        ++focusQueries;if(beforeFocusReturn)beforeFocusReturn();
        *out=FAILED(focusResult)?nullptr:&document;if(*out)(*out)->AddRef();return focusResult;
    }
    STDMETHODIMP Activate(TfClientId*) override{return E_NOTIMPL;}
    STDMETHODIMP Deactivate() override{return E_NOTIMPL;}
    STDMETHODIMP CreateDocumentMgr(ITfDocumentMgr**) override{return E_NOTIMPL;}
    STDMETHODIMP EnumDocumentMgrs(IEnumTfDocumentMgrs**) override{return E_NOTIMPL;}
    STDMETHODIMP SetFocus(ITfDocumentMgr*) override{return E_NOTIMPL;}
    STDMETHODIMP AssociateFocus(HWND,ITfDocumentMgr*,ITfDocumentMgr**) override{return E_NOTIMPL;}
    STDMETHODIMP IsThreadFocus(BOOL* out) override{++threadFocusQueries;*out=threadFocused;return threadFocusResult;}
    STDMETHODIMP GetFunctionProvider(REFCLSID,ITfFunctionProvider**) override{return E_NOTIMPL;}
    STDMETHODIMP EnumFunctionProviders(IEnumTfFunctionProviders**) override{return E_NOTIMPL;}
    STDMETHODIMP GetGlobalCompartment(ITfCompartmentMgr**) override{return E_NOTIMPL;}
};
class Profiles final : public FakeCom<ITfInputProcessorProfileMgr> {
public:
    TF_INPUTPROCESSORPROFILE active{};HRESULT result=S_OK;
    GUID queriedCategory{};unsigned activeQueries=0, unexpectedCalls=0;
    STDMETHODIMP GetActiveProfile(REFGUID category,TF_INPUTPROCESSORPROFILE* out) override {
        ++activeQueries;queriedCategory=category;*out=active;return result;
    }
    STDMETHODIMP ActivateProfile(DWORD,LANGID,REFCLSID,REFGUID,HKL,DWORD) override{++unexpectedCalls;return E_NOTIMPL;}
    STDMETHODIMP DeactivateProfile(DWORD,LANGID,REFCLSID,REFGUID,HKL,DWORD) override{++unexpectedCalls;return E_NOTIMPL;}
    STDMETHODIMP GetProfile(DWORD,LANGID,REFCLSID,REFGUID,HKL,TF_INPUTPROCESSORPROFILE*) override{++unexpectedCalls;return E_NOTIMPL;}
    STDMETHODIMP EnumProfiles(LANGID,IEnumTfInputProcessorProfiles**) override{++unexpectedCalls;return E_NOTIMPL;}
    STDMETHODIMP ReleaseInputProcessor(REFCLSID,DWORD) override{++unexpectedCalls;return E_NOTIMPL;}
    STDMETHODIMP RegisterProfile(REFCLSID,LANGID,REFGUID,const WCHAR*,ULONG,const WCHAR*,ULONG,ULONG,HKL,DWORD,BOOL,DWORD) override{++unexpectedCalls;return E_NOTIMPL;}
    STDMETHODIMP UnregisterProfile(REFCLSID,LANGID,REFGUID,DWORD) override{++unexpectedCalls;return E_NOTIMPL;}
};
void actualEligibilityQueries() {
    Manager manager;Profiles profiles;Eligibility state;
    state.manager=&manager;state.profiles=&profiles;
    state.clsid={0x12345678,0x1234,0x5678,{1,2,3,4,5,6,7,8}};
    state.profile={0x87654321,0x4321,0x8765,{8,7,6,5,4,3,2,1}};
    profiles.active.dwProfileType=TF_PROFILETYPE_INPUTPROCESSOR;
    profiles.active.clsid=state.clsid;profiles.active.guidProfile=state.profile;
    const auto matching=profiles.active;
    auto expect=[&](const char* reason,unsigned managerReads=1,unsigned profileReads=1){
        const auto beforeManager=manager.threadFocusQueries,beforeProfiles=profiles.activeQueries;
        check(state.query==actualEligibility,"real eligibility query remains installed");
        const auto actual=actualEligibility(state);
        if(!(reason?actual && std::string(actual)==reason:actual==nullptr))
            throw std::runtime_error(std::string("actual eligibility expected ")+(reason?reason:"ready")+", received "+(actual?actual:"ready"));
        check(manager.threadFocusQueries==beforeManager+managerReads && profiles.activeQueries==beforeProfiles+profileReads,
            "eligibility uses only required read queries");
        check(profiles.unexpectedCalls==0,"eligibility must not activate or change profiles");
        if(profileReads)check(IsEqualGUID(profiles.queriedCategory,GUID_TFCAT_TIP_KEYBOARD),"query keyboard profile category");
    };
    expect(nullptr);
    profiles.active.clsid.Data1^=1;expect("profile-inactive");profiles.active=matching;
    profiles.active.guidProfile.Data1^=1;expect("profile-inactive");profiles.active=matching;
    profiles.active.dwProfileType=TF_PROFILETYPE_KEYBOARDLAYOUT;expect("profile-inactive");profiles.active=matching;
    manager.threadFocused=FALSE;expect("thread-focus-missing",1,0);manager.threadFocused=TRUE;
    // Even a TRUE out-parameter must not turn a non-S_OK query into permission.
    manager.threadFocusResult=S_FALSE;expect("thread-focus-unavailable",1,0);
    manager.threadFocusResult=static_cast<HRESULT>(2);expect("thread-focus-unavailable",1,0);
    manager.threadFocusResult=E_FAIL;expect("thread-focus-unavailable",1,0);
    manager.threadFocusResult=E_ACCESSDENIED;expect("thread-focus-unavailable",1,0);
    manager.threadFocusResult=S_OK;
    state.manager.Reset();expect("thread-focus-unavailable",0,0);state.manager=&manager;
    profiles.result=S_FALSE;expect("profile-inactive");
    profiles.result=E_FAIL;expect("profile-unavailable");
    profiles.result=E_ACCESSDENIED;expect("profile-unavailable");profiles.result=S_OK;
    state.profiles.Reset();expect("profile-unavailable",1,0);state.profiles=&profiles;
    expect(nullptr);
}
ForegroundIdentity fakeForeground() noexcept{return {reinterpret_cast<HWND>(1),GetCurrentThreadId(),GetCurrentProcessId(),reinterpret_cast<HWND>(2),reinterpret_cast<HWND>(1)};}
const char* eligible(const Eligibility&) noexcept { return nullptr; }
const char* inactiveProfile(const Eligibility&) noexcept { return "profile-inactive"; }
const char* missingThreadFocus(const Eligibility&) noexcept { return "thread-focus-missing"; }
struct Fixture {
    Manager manager;
    std::shared_ptr<Lease> lease=std::make_shared<Lease>();
    std::shared_ptr<Eligibility> eligibility=std::make_shared<Eligibility>();
    Context& context=manager.document.context; Memory& m=context.m;
    Fixture(){eligibility->query=eligible;lease->eligibility=eligibility;lease->manager=&manager;lease->document=&manager.document;lease->context=&context;lease->window=reinterpret_cast<HWND>(1);lease->focus=reinterpret_cast<HWND>(2);lease->active=true;lease->foreground=fakeForeground;}
    void queue(std::wstring text={},std::string key={},bool extend=false){
        lease->completed=lease->attempted=false;lease->outcome=E_PENDING;
        ComPtr<ITfEditSession> edit;edit.Attach(new Edit(lease,std::move(text),key,extend));HRESULT result;
        check(context.RequestEditSession(1,edit.Get(),TF_ES_ASYNCDONTCARE|TF_ES_READWRITE,&result)==S_OK && result==TF_S_ASYNC,"async request");
        check(!lease->completed,"queue is not completion");
    }
    void apply(std::wstring text={},std::string key={},bool extend=false){queue(text,key,extend);check(context.drain()==S_OK && lease->completed && lease->outcome==S_OK,"edit completion");}
};
void edits(){
    Fixture f; f.m.text=L"left OLD right";f.m.first=5;f.m.last=8;
    f.apply(L"\x4f60\x597d");check(f.m.text==L"left \x4f60\x597d right" && f.m.first==7 && f.m.last==7,"selected Chinese replacement");
    f.apply({},"SelectAll");check(f.m.first==0 && f.m.last==13,"select all");
    f.apply(L"A\xd83d\xde00" L"B");check(f.m.first==4,"UTF16 caret");
    f.apply({},"ArrowLeft");check(f.m.first==3,"left B");
    f.apply({},"ArrowLeft");check(f.m.first==1,"left surrogate pair");
    f.apply({},"ArrowRight",true);check(f.m.first==1 && f.m.last==3 && f.m.active==TF_AE_END,"select pair");
    f.apply({},"ArrowLeft",true);check(f.m.first==1 && f.m.last==1,"shrink selection");
    f.apply({},"ArrowLeft",true);check(f.m.first==0 && f.m.last==1 && f.m.active==TF_AE_START,"cross anchor");
    f.apply({},"End");f.apply({},"Backspace");f.apply({},"Backspace");check(f.m.text==L"A","backspace surrogate pair");
    f.apply(L"\xd83d\xde00" L"B");f.apply({},"Home");f.apply({},"ArrowRight");f.apply({},"Delete");check(f.m.text==L"AB","delete surrogate pair");
    f.apply({},"Home");f.apply({},"Backspace");check(f.m.text==L"AB","document start boundary");
    f.apply({},"End");f.apply({},"Delete");check(f.m.text==L"AB","document end boundary");
}
void selectionFailuresAndSelectedBackspace() {
    for(unsigned mode=0;mode<3;++mode) {
        Fixture f;f.m.text=L"keep";f.m.first=f.m.last=4;
        if(mode==0)f.context.selectionResult=TF_E_NOLOCK;
        if(mode==1)f.context.selectionCount=0;
        if(mode==2)f.context.nullSelection=true;
        f.queue({},"Backspace");
        const HRESULT expected=mode==0?TF_E_NOLOCK:E_FAIL;
        check(f.context.drain()==expected && f.lease->completed && f.lease->attempted &&
            f.lease->outcome==expected,"invalid selection completes with its failure");
        check(f.context.selectionCalls==1 && f.m.text==L"keep" && f.m.writeCalls==0 &&
            f.context.setSelectionCalls==0 && f.m.startShifts.empty(),"selection failure never moves or writes");
    }
    for(const auto active:{TF_AE_START,TF_AE_END}) {
        Fixture f;f.m.text=L"A\x4e2d" L"B";f.m.first=1;f.m.last=2;f.m.active=active;
        f.apply({},"Backspace");
        check(f.m.text==L"AB" && f.m.first==1 && f.m.last==1 && f.m.active==TF_AE_END,
            "backspace deletes exactly the selected Chinese text");
        check(f.m.writes==1 && f.m.selections==1 && f.m.startShifts.empty() &&
            f.m.endShifts.empty() && f.m.readCalls==0,"selected deletion does not probe or expand the range");
    }
}
void limitedRangeCharacterization() {
    // Characterize the existing BMP behavior without treating host limitations as
    // successful deletion or changing the production range/Unicode policy.
    for(const bool back:{true,false}) {
        Fixture zero;zero.m.text=L"AB";zero.m.first=zero.m.last=back?2:0;
        zero.m.maxStartShift=zero.m.maxEndShift=0;
        zero.apply({},back?"Backspace":"Delete");
        const auto& shifts=back?zero.m.startShifts:zero.m.endShifts;
        check(shifts.size()==2 && shifts[0].requested==(back?-2:2) && shifts[0].moved==0 &&
            shifts[1].requested==(back?-1:1) && shifts[1].moved==0,"zero movement is visible at both range steps");
        check(zero.m.text==L"AB" && zero.m.writeCalls==1 && zero.m.writes==1 && zero.m.selections==1,
            "current zero-movement path acknowledges an empty write, not actual deletion");

        Fixture shortMove;shortMove.m.text=L"ABC";shortMove.m.first=shortMove.m.last=back?3:0;
        shortMove.m.maxStartShift=shortMove.m.maxEndShift=1;
        shortMove.apply({},back?"Backspace":"Delete");
        const auto& shortShifts=back?shortMove.m.startShifts:shortMove.m.endShifts;
        check(shortShifts.size()==2 && shortShifts[0].requested==(back?-2:2) &&
            shortShifts[0].moved==(back?-1:1),"probe may return fewer units than requested");
        check(shortMove.m.text==(back?L"AB":L"BC") && shortMove.m.writes==1,
            "short BMP probe retains existing single-unit deletion");

        for(const ULONG readLimit:{0UL,1UL}) {
            Fixture shortRead;shortRead.m.text=L"ABC";shortRead.m.first=shortRead.m.last=back?3:0;
            shortRead.m.maxRead=readLimit;shortRead.apply({},back?"Backspace":"Delete");
            const auto& readShifts=back?shortRead.m.startShifts:shortRead.m.endShifts;
            check(shortRead.m.readCalls==1 && readShifts.size()==2 && readShifts[1].requested==(back?-1:1),
                "short or empty probe text currently chooses one UTF16 unit");
            check(shortRead.m.text==(back?L"AB":L"BC"),"BMP short-read characterization is not a surrogate-pair guarantee");
        }
    }
    for(const bool readFailure:{false,true}) {
        Fixture f;f.m.text=L"keep";f.m.first=f.m.last=4;
        if(readFailure)f.m.read=TF_E_NOLOCK;else f.m.shiftStart=TF_E_DISCONNECTED;
        f.queue({},"Backspace");
        const HRESULT expected=readFailure?TF_E_NOLOCK:TF_E_DISCONNECTED;
        check(f.context.drain()==expected && f.lease->completed && f.m.text==L"keep" &&
            f.m.writeCalls==0 && f.context.setSelectionCalls==0,"range/read error cannot reach a write");
    }
}
void diagnosticsAreOptionalAndContentFree() {
    const std::wstring secret=L"PRIVATE_DOCUMENT_SENTINEL_7f91";
    resetDiagnostics();Fixture disabled;
    disabled.lease->diagnostic.sink=captureDiagnostic;
    check(!disabled.lease->diagnostic.enabled,"edit diagnostics default to disabled");
    disabled.apply(secret);
    check(diagnosticSinkCalls==0 && diagnosticEvents.empty() && disabled.m.text==secret,
        "disabled diagnostics emit nothing while normal edits succeed");

    resetDiagnostics();Fixture enabled;
    enabled.lease->diagnostic.enabled=true;enabled.lease->diagnostic.sink=captureDiagnostic;
    enabled.lease->diagnostic.instanceId=19;enabled.lease->diagnostic.sequence=23;
    enabled.lease->diagnostic.generation=29;
    enabled.apply(secret);
    check(!diagnosticEvents.empty() && enabled.m.text==secret && enabled.m.writes==disabled.m.writes &&
        enabled.m.selections==disabled.m.selections && enabled.context.selectionCalls==disabled.context.selectionCalls &&
        enabled.context.statusCalls==disabled.context.statusCalls && enabled.manager.focusQueries==disabled.manager.focusQueries &&
        enabled.manager.document.topQueries==disabled.manager.document.topQueries,
        "enabling observation must not add TSF queries or change the edit");
    for(const auto& row:diagnosticEvents) {
        check(row.size()==18 && row.at("schema")=="18u-touch-frontend-edit-diagnostic-v1" &&
            row.at("instanceId")==19 && row.at("sequence")==23 && row.at("generation")==29,
            "diagnostics retain their separate fixed numeric correlation schema");
        check(row.dump().find("PRIVATE_DOCUMENT_SENTINEL_7f91")==std::string::npos,
            "diagnostics never contain the input or document text");
        for(auto it=row.begin();it!=row.end();++it)
            if(it.value().is_string())check(it.key()=="schema" || it.key()=="stage" || it.key()=="action",
                "diagnostic strings are fixed schema/stage/action names only");
    }
    for(const auto stage:{"GetSelection","SetText","Collapse","SetSelection","Complete"}) {
        const auto& row=diagnosticAt(stage);
        check(row.at("hrKnown")==true && row.at("hr")==0,"S_OK must be an observed result, not a missing HRESULT");
    }

    resetDiagnostics();Fixture throwing;throwing.lease->diagnostic.enabled=true;
    throwing.lease->diagnostic.sink=throwingDiagnostic;SetLastError(ERROR_INVALID_HANDLE);
    throwing.apply(secret);
    check(diagnosticSinkCalls>0 && throwing.m.text==secret && throwing.m.writes==1 && throwing.m.selections==1 &&
        GetLastError()==ERROR_INVALID_HANDLE,"throwing diagnostic sink cannot alter the edit or thread last-error state");
}
void diagnosticsDescribeLimitedRanges() {
    for(const LONG limit:{0L,1L}) {
        resetDiagnostics();Fixture f;f.m.text=L"ABC";f.m.first=f.m.last=3;f.m.maxStartShift=limit;
        f.lease->diagnostic.enabled=true;f.lease->diagnostic.sink=captureDiagnostic;
        f.apply({},"Backspace");
        const auto& probe=diagnosticAt("ProbeShift");
        const auto& final=diagnosticAt("StepShift");
        check(probe.at("requested")==-2 && probe.at("actual")==-limit && probe.at("hrKnown")==true &&
            probe.at("hr")==0 && final.at("requested")==-1 && final.at("actual")==-limit,
            "zero and short range movements remain distinct from HRESULT success");
        check(diagnosticAt("ProbeText").at("count")==limit,
            "probe text length describes what the substitute actually returned");
    }
    resetDiagnostics();Fixture shortRead;shortRead.m.text=L"ABC";shortRead.m.first=shortRead.m.last=3;shortRead.m.maxRead=1;
    shortRead.lease->diagnostic.enabled=true;shortRead.lease->diagnostic.sink=captureDiagnostic;
    shortRead.apply({},"Backspace");
    check(diagnosticAt("ProbeShift").at("actual")==-2 && diagnosticAt("ProbeText").at("count")==1 &&
        diagnosticAt("StepShift").at("requested")==-1,"short read is separately observable from short movement");

    resetDiagnostics();Fixture failed;failed.m.text=L"keep";failed.context.selectionResult=TF_E_NOLOCK;
    failed.lease->diagnostic.enabled=true;failed.lease->diagnostic.sink=captureDiagnostic;
    failed.queue({},"Backspace");check(failed.context.drain()==TF_E_NOLOCK,"diagnosed selection failure");
    check(diagnosticAt("GetSelection").at("hrKnown")==true &&
        diagnosticAt("GetSelection").at("hr")==static_cast<uint32_t>(TF_E_NOLOCK) &&
        diagnosticAt("Complete").at("hr")==static_cast<uint32_t>(TF_E_NOLOCK) && failed.m.writeCalls==0,
        "failed API and final callback retain the original HRESULT without writing");
}
ForegroundIdentity changingIdentity{};
ForegroundIdentity changedForeground() noexcept { return changingIdentity; }
void focusedChildLease() {
    Fixture f;
    // The root HWND is only an identity/ancestry anchor. Endpoint ownership
    // follows the child focus thread, not the root's window thread.
    changingIdentity=fakeForeground(); f.lease->foreground=changedForeground;
    check(f.lease->valid(), "focused child lease");
    f.apply(L"child");
    changingIdentity.focus=reinterpret_cast<HWND>(3);
    check(std::string(f.lease->rejection())=="focus-changed", "same-thread focus replacement");
    f.queue(L"wrong"); check(f.context.drain()==E_ABORT && f.m.text==L"child", "no cross-control edit");
    changingIdentity=fakeForeground(); changingIdentity.thread++;
    check(std::string(f.lease->rejection())=="focus-owner-mismatch", "foreign focus thread");
    changingIdentity=fakeForeground(); changingIdentity.process++;
    check(!f.lease->valid(), "foreign focus process");
    changingIdentity=fakeForeground(); changingIdentity.root=reinterpret_cast<HWND>(9);
    check(!f.lease->valid(), "unrelated foreground ancestry");
    changingIdentity=fakeForeground(); changingIdentity.window=reinterpret_cast<HWND>(9);
    check(!f.lease->valid(), "foreground changed");
}
void failures(){
    Fixture f;f.m.text=L"keep";f.queue(L"new");check(f.m.text==L"keep" && f.m.writes==0,"queued must not write");
    f.lease->active=false;check(f.context.drain()==E_ABORT && !f.lease->attempted && f.m.text==L"keep","revoked callback");
    f.lease->active=true;f.manager.document.replaced=true;f.queue(L"new");check(f.context.drain()==E_ABORT && f.m.text==L"keep","replaced context");
    f.manager.document.replaced=false;f.m.write=E_ACCESSDENIED;f.queue(L"new");check(f.context.drain()==E_ACCESSDENIED && f.lease->completed && f.m.text==L"keep" && f.m.writes==0,"failed write");
    f.m.write=S_OK;f.queue(L"new");auto old=f.lease;old->active=false;f.lease.reset();check(f.context.drain()==E_ABORT && f.m.text==L"keep","callback after owner release");
}
void reentrantRevocation(){
    Fixture f;f.m.text=L"keep";f.m.afterWrite=[&]{f.lease->active=false;};f.queue(L"new");
    check(f.context.drain()==E_ABORT && f.lease->attempted && f.lease->completed,"reentrant invalidation outcome");
    check(f.m.writes==1 && f.m.selections==0 && f.m.text==L"newkeep","do not select or replay after reentrant revocation");
}
json identityRequest(const SessionIdentity& identity) {
    return {{"activationId",identity.activationId},{"generation",identity.generation}};
}
void readonlyStatusAndEpochs() {
    Fixture f; SessionIdentity identity;identity.activationId="activation-a";
    check(identity.advance(),"fresh binding generation");
    const auto request=identityRequest(identity);const auto generation=identity.generation;
    f.m.text=L"untouched";
    check(sessionRejection(identity,f.lease,request)==nullptr,"ready status");
    check(identity.generation==generation && f.lease->active && !f.lease->attempted && !f.lease->completed &&
        f.m.text==L"untouched" && f.m.writes==0 && f.m.selections==0 && !f.context.pending,"status does not mutate or queue");
    check(identity.advance(),"revocation generation");f.lease->active=false;
    check(std::string(sessionRejection(identity,f.lease,request))=="stale-generation","stale action/status identity");
    auto current=identityRequest(identity);
    check(std::string(sessionRejection(identity,f.lease,current))=="lease-inactive" && !f.lease->active,
        "status cannot reactivate old lease");
    current["activationId"]="older-activation";
    check(std::string(sessionRejection(identity,f.lease,current))=="stale-activation","activation ABA rejected");
    check(f.m.writes==0 && f.m.selections==0 && f.m.text==L"untouched","stale requests never edit");
    identity.generation=UINT64_MAX-1;check(identity.advance() && identity.generation==UINT64_MAX,"last generation");
    check(!identity.advance() && identity.generation==UINT64_MAX && identity.exhausted,"generation never wraps");
    check(std::string(identity.rejection(identityRequest(identity)))=="generation-exhausted","exhaustion fails closed");
}
void eligibilityRevokesDelayedEdits() {
    Fixture f;f.m.text=L"keep";
    auto deny=[&](const char* reason){
        f.queue(L"wrong");check(std::string(f.lease->rejection())==reason,"eligibility reason");
        check(f.context.drain()==E_ABORT && !f.lease->attempted && f.m.text==L"keep" && f.m.writes==0,
            "eligibility checked at actual callback");
    };
    f.eligibility->query=inactiveProfile;deny("profile-inactive");
    f.eligibility->query=missingThreadFocus;deny("thread-focus-missing");
    f.eligibility->query=eligible;f.eligibility->threadFocused=false;deny("thread-focus-missing");
    f.eligibility->threadFocused=true;f.eligibility->keyFocused=false;deny("key-focus-missing");
    f.eligibility->keyFocused=true;f.context.status=TS_SD_READONLY;deny("context-read-only");
    f.context.status=TS_SD_LOADING;deny("context-loading");
    f.context.status=0;f.context.statusResult=TF_E_DISCONNECTED;deny("context-status-unavailable");
    f.context.statusResult=S_FALSE;deny("context-status-unavailable");
    f.context.statusResult=S_OK;f.eligibility->alive=false;deny("activation-ended");
}
void newBindingDoesNotReviveOldCallback() {
    Fixture f;SessionIdentity identity;identity.activationId="same-activation";identity.advance();
    const auto oldRequest=identityRequest(identity);
    f.m.text=L"keep";f.queue(L"old");auto old=f.lease;
    old->active=false;identity.advance(); // A -> B -> A, even with identical final HWND/context.
    f.lease=std::make_shared<Lease>(*old);f.lease->active=true;identity.advance();
    check(std::string(sessionRejection(identity,f.lease,oldRequest))=="stale-generation","old candidate cannot target new binding");
    check(f.context.drain()==E_ABORT && !old->attempted && f.m.text==L"keep","old queued edit stays revoked after rebind");
    check(sessionRejection(identity,f.lease,identityRequest(identity))==nullptr,"new binding is independently ready");
    f.apply(L"fresh");check(f.m.text==L"freshkeep" && f.m.writes==1,"only fresh explicit input writes");
}
void selectionReadReentrancy() {
    Fixture f;f.m.text=L"keep";f.context.afterSelection=[&]{f.lease->active=false;};
    f.queue(L"wrong");check(f.context.drain()==E_ABORT && f.m.text==L"keep" && f.m.writes==0,
        "reentrant selection read cannot write after revocation");
    Fixture status;status.m.text=L"keep";status.context.afterStatus=[&]{status.lease->active=false;};
    status.queue(L"wrong");check(status.context.drain()==E_ABORT && !status.lease->attempted && status.m.writes==0,
        "reentrant status revocation cannot pass validation");
}
struct DispatcherFixture {
    Manager manager;
    std::shared_ptr<Eligibility> eligibility=std::make_shared<Eligibility>();
    std::shared_ptr<TouchFrontendEndpoint::Impl> endpoint;
    Context& context=manager.document.context;Memory& m=context.m;
    uint64_t sequence=0, boundGeneration=0;std::string activation;
    DispatcherFixture() {
        eligibility->query=eligible;
        endpoint=std::make_shared<TouchFrontendEndpoint::Impl>(&manager,1,eligibility,"memory-activation",fakeForeground);
    }
    void send(const char* operation,json fields=json::object()) {
        json request{{"version",2},{"sequence",++sequence},{"operation",operation}};
        if(std::string(operation)!="bind"){request["activationId"]=activation;request["generation"]=boundGeneration;}
        for(auto it=fields.begin();it!=fields.end();++it)request[it.key()]=it.value();
        endpoint->memoryResponse=nullptr;endpoint->input=request.dump()+"\n";endpoint->dispatch();
    }
    void bind() {
        send("bind",{{"window",uint64_t(1)},{"focus",uint64_t(2)}});
        expect("bound",true,1);activation=endpoint->memoryResponse.at("activationId").get<std::string>();
        boundGeneration=endpoint->memoryResponse.at("generation").get<uint64_t>();
    }
    void expect(const char* outcome,bool ok,uint64_t expectedSequence,const char* reason=nullptr) {
        const auto& r=endpoint->memoryResponse;
        check(r.is_object() && r.size()==(reason?8:7),"exact v2 response shape");
        check(r.at("version")==2 && r.at("sequence")==expectedSequence && r.at("ok")==ok &&
            r.at("outcome")==outcome && r.at("retryAllowed")==false,"v2 response contract");
        check(r.at("activationId")=="memory-activation" && r.at("generation").is_number_unsigned() &&
            r.at("generation").get<uint64_t>()>0,"response activation and generation");
        check(reason?r.at("reason")==reason:!r.contains("reason"),"response fixed reason");
    }
    void edit(){send("edit",{{"text","new"},{"key",""},{"extend",false}});}
    void backspace(){send("edit",{{"text",""},{"key","Backspace"},{"extend",false}});}
};
void dispatcherRequestCompletionPaths() {
    for(unsigned mode=0;mode<3;++mode) {
        DispatcherFixture f;f.m.text=L"keep";f.bind();
        if(mode==0)f.context.requestResult=E_ACCESSDENIED;
        if(mode==1)f.context.sessionResult=TF_E_NOLOCK;
        if(mode==2)f.context.sessionResult=S_OK; // No callback: success alone is not completion.
        f.backspace();
        const HRESULT expected=mode==0?E_ACCESSDENIED:mode==1?TF_E_NOLOCK:E_UNEXPECTED;
        check(f.context.requestCalls==1 && !f.context.pending && !f.endpoint->lease->attempted &&
            f.endpoint->lease->completed && f.endpoint->lease->outcome==expected,
            "request/session failure cannot masquerade as callback completion");
        f.endpoint->tick();f.expect("failed",false,2);
        check(f.endpoint->closeAfterWrite && f.m.writeCalls==0 && f.context.selectionCalls==0 &&
            f.m.text==L"keep","no callback means no document access or retry");
    }
    DispatcherFixture immediate;immediate.m.text=L"AB";immediate.m.first=immediate.m.last=2;immediate.bind();
    immediate.context.synchronousEdit=true;immediate.backspace();
    check(!immediate.context.pending && immediate.endpoint->lease->completed && immediate.m.text==L"A",
        "synchronous callback can apply one edit");
    immediate.endpoint->tick();immediate.expect("applied",true,2);
    check(immediate.m.writes==1,"synchronous acknowledgement does not execute twice");

    DispatcherFixture waiting;waiting.m.text=L"keep";waiting.bind();waiting.backspace();
    waiting.endpoint->tick();waiting.endpoint->tick();
    check(waiting.endpoint->memoryResponse.is_null() && waiting.context.pending &&
        !waiting.endpoint->lease->completed && !waiting.endpoint->lease->attempted && waiting.m.writeCalls==0,
        "TF_S_ASYNC remains pending until the actual callback");
    waiting.endpoint->invalidate();
    check(waiting.context.drain()==E_ABORT && !waiting.endpoint->lease->attempted,
        "focus revocation while queued prevents the delayed callback from editing");
    waiting.endpoint->tick();waiting.expect("failed",false,2);
    check(waiting.m.text==L"keep" && waiting.m.writeCalls==0 && waiting.endpoint->closeAfterWrite,
        "revoked pending edit stops without replay");
}
void requestReturnReentrancyKeepsOriginalLease() {
    enum class RequestKind { Queued, Synchronous, Failed };
    enum class Reentry { Close, Timeout, Rebind };
    for(const bool diagnostics:{false,true})
        for(const auto kind:{RequestKind::Queued,RequestKind::Synchronous,RequestKind::Failed})
            for(const auto reentry:{Reentry::Close,Reentry::Timeout,Reentry::Rebind}) {
                resetDiagnostics();DispatcherFixture f;f.m.text=L"keep";f.m.first=f.m.last=4;f.bind();
                f.endpoint->lease->diagnostic.enabled=diagnostics;
                f.endpoint->lease->diagnostic.sink=captureDiagnostic;
                // Do not keep an extra strong reference that could conceal a
                // use-after-free when RequestEditSession releases the old binding.
                std::weak_ptr<Lease> original=f.endpoint->lease;
                const auto generation=f.boundGeneration;
                f.context.synchronousEdit=kind==RequestKind::Synchronous;
                if(kind==RequestKind::Failed){f.context.requestResult=E_ACCESSDENIED;f.context.writesSessionResult=false;}
                unsigned reentries=0;json reboundReceipt;
                f.context.beforeRequestReturn=[&] {
                    ++reentries;
                    if(reentry==Reentry::Close)f.endpoint->closePipe();
                    else if(reentry==Reentry::Timeout){f.endpoint->deadline=1;f.endpoint->tick();}
                    else {f.endpoint->listen();f.sequence=0;f.bind();reboundReceipt=f.endpoint->memoryResponse;}
                    const auto old=original.lock();
                    check(old && !old->active,"original request lease survives reentrant teardown and stays revoked");
                };
                f.backspace();f.context.beforeRequestReturn={};
                const unsigned expectedWrites=kind==RequestKind::Synchronous?1U:0U;
                check(reentries==1 && f.context.requestCalls==1 && f.m.writes==expectedWrites &&
                    f.m.text==(expectedWrites?L"kee":L"keep"),
                    "request-return reentrancy preserves only edits already completed before revocation");
                if(diagnostics) {
                    const auto& row=diagnosticAt("RequestEditSession");
                    check(row.at("sequence")==2 && row.at("generation")==generation &&
                        row.at("hr")==static_cast<uint32_t>(kind==RequestKind::Failed?E_ACCESSDENIED:S_OK),
                        "request-return diagnostics still describe the original lease and request");
                    if(reentry==Reentry::Timeout)check(diagnosticAt("Timeout").at("sequence")==2,
                        "production tick timeout triggers the reentrant listen path");
                } else check(diagnosticSinkCalls==0,"disabled diagnostics stay silent during reentrant teardown");
                if(kind==RequestKind::Queued) {
                    const auto old=original.lock();
                    check(old && !old->attempted && f.context.pending && f.context.drain()==E_ABORT &&
                        old->completed && old->outcome==E_ABORT && !old->attempted,
                        "old queued callback cannot write after request-return revocation");
                } else check(!f.context.pending,"synchronous and failed requests leave no queued callback");
                f.endpoint->tick();f.endpoint->tick();
                check(f.m.writes==expectedWrites && f.context.requestCalls==1,"retired request is never replayed");
                if(reentry==Reentry::Rebind) {
                    check(f.endpoint->lease && f.endpoint->lease->active && !f.endpoint->lease->attempted &&
                        !f.endpoint->lease->completed && f.endpoint->lease->outcome==E_PENDING &&
                        f.boundGeneration>generation && f.endpoint->memoryResponse==reboundReceipt,
                        "old request return and callback cannot change the new lease or bind receipt");
                    f.context.requestResult=S_OK;f.context.writesSessionResult=true;f.context.synchronousEdit=false;
                    f.edit();check(f.context.drain()==S_OK,"fresh input on reentrant binding");
                    f.endpoint->tick();f.expect("applied",true,2);
                    check(f.m.writes==expectedWrites+1 && f.context.requestCalls==2,
                        "only a fresh explicit action may edit the new binding");
                } else check(!f.endpoint->lease && f.endpoint->memoryResponse.is_null(),
                    "teardown cannot publish an old edit receipt into a retired connection");
            }
}
void statusQueryReentrancyKeepsOriginalObservation() {
    enum class Operation { Edit, Status, Bind, Poll };
    struct Case { Operation operation;bool rebind;HRESULT result; };
    const Case cases[]={
        {Operation::Edit,false,E_ACCESSDENIED},{Operation::Edit,true,E_ACCESSDENIED},
        {Operation::Edit,false,S_OK},{Operation::Status,true,E_ACCESSDENIED},
        {Operation::Bind,true,E_ACCESSDENIED},{Operation::Poll,true,E_ACCESSDENIED}
    };
    for(const bool diagnostics:{false,true})for(const auto& sample:cases) {
        resetDiagnostics();DispatcherFixture f;f.m.text=L"keep";f.m.first=f.m.last=4;
        if(sample.operation!=Operation::Bind) {
            f.bind();f.endpoint->lease->diagnostic.enabled=diagnostics;
            f.endpoint->lease->diagnostic.sink=captureDiagnostic;
        }
        if(sample.operation==Operation::Poll) {
            // A completed synchronous edit has released its ITfEditSession, so
            // the polling lease must survive through the observer's own snapshot.
            f.context.synchronousEdit=true;f.backspace();f.context.synchronousEdit=false;
            check(!f.context.pending && f.endpoint->lease->completed,"poll follows completed synchronous edit");
            resetDiagnostics();
        }
        std::weak_ptr<Lease> original;uint64_t generation=0;
        bool reentered=false,retained=false;json reboundReceipt;
        f.context.afterStatus=[&] {
            if(reentered)return;reentered=true;original=f.endpoint->lease;
            generation=f.endpoint->identity.generation;
            f.endpoint->lease->diagnostic.enabled=diagnostics;
            f.endpoint->lease->diagnostic.sink=captureDiagnostic;
            if(sample.rebind){f.endpoint->listen();f.sequence=0;f.bind();reboundReceipt=f.endpoint->memoryResponse;}
            else f.endpoint->closePipe();
            {const auto old=original.lock();retained=old && !old->active;}
            // The inner bind must see the original S_OK status. The outer host
            // callback then returns this case's result from the same fake method.
            f.context.statusResult=sample.result;
        };
        if(sample.operation==Operation::Edit)f.backspace();
        else if(sample.operation==Operation::Status)f.send("status");
        else if(sample.operation==Operation::Bind)f.send("bind",{{"window",uint64_t(1)},{"focus",uint64_t(2)}});
        else f.endpoint->tick();
        f.context.afterStatus={};f.context.statusResult=S_OK;
        const unsigned priorWrites=sample.operation==Operation::Poll?1U:0U;
        check(reentered && retained && original.expired() && !f.context.pending &&
            f.context.requestCalls==priorWrites && f.m.writes==priorWrites && f.m.text==(priorWrites?L"kee":L"keep"),
            "host status teardown retains only the old observation and never starts or repeats an edit");
        if(diagnostics && sample.operation==Operation::Edit) {
            const auto& status=diagnosticAt("Status");const auto& rejection=diagnosticAt("Lease");
            check(status.at("sequence")==2 && status.at("generation")==generation && status.at("hrKnown")==true &&
                status.at("hr")==static_cast<uint32_t>(sample.result) && rejection.at("sequence")==2 &&
                rejection.at("generation")==generation && rejection.at("value")==0 &&
                rejection.at("value2")==(FAILED(sample.result)?16:7),
                "post-reentrancy status and rejection diagnostics belong to the old request");
        }
        for(const auto& row:diagnosticEvents) {
            check(row.at("stage")!="RequestEditSession" && row.at("stage")!="Reply",
                "replaced validation cannot request an edit or publish an old reply");
            if(sample.operation==Operation::Poll)check(row.at("stage")!="Lease" && row.at("stage")!="Status",
                "replaced poll stops silently instead of observing the new binding");
        }
        if(!diagnostics)check(diagnosticSinkCalls==0,"disabled diagnostics remain silent during status reentrancy");
        if(sample.rebind) {
            check(f.endpoint->lease && f.endpoint->lease->active && !f.endpoint->lease->attempted &&
                !f.endpoint->lease->completed && f.endpoint->lease->outcome==E_PENDING && !f.endpoint->closeAfterWrite &&
                f.boundGeneration>generation && f.endpoint->memoryResponse==reboundReceipt,
                "old bind/status/edit/poll result cannot reject, complete, or overwrite the new binding");
            f.endpoint->lease->diagnostic.sink=captureDiagnostic;
            f.backspace();check(f.context.drain()==S_OK,"explicit input after status-query rebind");
            f.endpoint->tick();f.expect("applied",true,2);
            check(f.m.writes==priorWrites+1 && f.context.requestCalls==priorWrites+1,
                "fresh explicit input is the sole new edit after status-query rebind");
        } else check(!f.endpoint->lease && f.endpoint->memoryResponse.is_null(),
            "cleared validation cannot emit an old reply even when GetStatus returned S_OK");
    }
}
void bindingQueryOutputsCannotTargetReentrantBinding() {
    for(const bool diagnostics:{false,true})for(const bool focusQuery:{true,false}) {
        resetDiagnostics();DispatcherFixture f;f.m.text=L"keep";f.m.first=f.m.last=4;
        std::weak_ptr<Lease> original;bool reentered=false,retained=false;json reboundReceipt;
        auto rebind=[&] {
            if(reentered)return;reentered=true;original=f.endpoint->lease;
            f.endpoint->lease->diagnostic.enabled=diagnostics;f.endpoint->lease->diagnostic.sink=captureDiagnostic;
            f.endpoint->listen();f.sequence=0;f.bind();reboundReceipt=f.endpoint->memoryResponse;
            {const auto old=original.lock();retained=old && !old->active;}
            if(focusQuery)f.manager.focusResult=E_ACCESSDENIED;else f.manager.document.topResult=E_ACCESSDENIED;
        };
        if(focusQuery)f.manager.beforeFocusReturn=rebind;else f.manager.document.beforeTopReturn=rebind;
        f.send("bind",{{"window",uint64_t(1)},{"focus",uint64_t(2)}});
        f.manager.beforeFocusReturn={};f.manager.document.beforeTopReturn={};
        f.manager.focusResult=f.manager.document.topResult=S_OK;
        check(reentered && retained && original.expired() && f.endpoint->lease && f.endpoint->lease->active &&
            f.endpoint->lease->document.Get()==&f.manager.document && f.endpoint->lease->context.Get()==&f.context &&
            f.endpoint->memoryResponse==reboundReceipt && !f.endpoint->closeAfterWrite &&
            f.context.requestCalls==0 && f.m.writeCalls==0,
            "failed original GetFocus/GetTop outputs cannot clear or reject the reentrant binding");
        f.backspace();check(f.context.drain()==S_OK,"fresh edit after reentrant binding query");
        f.endpoint->tick();f.expect("applied",true,2);
        check(f.context.requestCalls==1 && f.m.writes==1,"new binding remains independently editable");
    }
}
void dispatcherDeleteFailuresStayUnknown() {
    for(unsigned mode=0;mode<3;++mode) {
        DispatcherFixture f;f.m.text=L"A\x4e2d" L"B";f.m.first=1;f.m.last=2;f.bind();
        if(mode==0)f.m.write=E_ACCESSDENIED;
        if(mode==1){f.m.failCollapseCall=1;f.m.collapse=TF_E_NOLOCK;}
        if(mode==2)f.context.setSelectionResult=TF_E_DISCONNECTED;
        f.backspace();
        const HRESULT expected=mode==0?E_ACCESSDENIED:mode==1?TF_E_NOLOCK:TF_E_DISCONNECTED;
        check(f.context.drain()==expected && f.endpoint->lease->completed && f.endpoint->lease->attempted,
            "delete preserves the failing stage result");
        check(f.m.writeCalls==1 && f.m.writes==(mode==0?0U:1U) && f.m.selections==0 &&
            f.context.setSelectionCalls==(mode==2?1U:0U),"later edit stages cannot conceal write or selection failure");
        check(f.m.text==(mode==0?L"A\x4e2d" L"B":L"AB"),
            "failed SetText preserves text; post-write failure does not roll back committed deletion");
        f.endpoint->tick();f.expect("unknown",false,2);
        check(f.endpoint->closeAfterWrite,"an attempted failed edit remains unknown even when the fake rejected its write");
        const auto receipt=f.endpoint->memoryResponse;
        f.endpoint->tick();f.endpoint->tick();
        check(f.m.writeCalls==1 && f.endpoint->memoryResponse==receipt,"waiting after unknown cannot replay deletion");
        // Simulate the dispatcher's transport-close path, then try the old bound
        // identity. Only a fresh bind may authorize a new user action.
        f.endpoint->listen();f.sequence=0;f.backspace();f.expect("failed",false,1,"stale-generation");
        check(!f.context.pending && f.m.writeCalls==1,"old identity cannot replay an uncertain deletion after reconnect");
    }
}
void dispatcherDiagnosticsPreserveV2() {
    resetDiagnostics();DispatcherFixture f;f.m.text=L"AB";f.m.first=f.m.last=2;f.bind();
    f.endpoint->lease->diagnostic.enabled=true;f.endpoint->lease->diagnostic.sink=captureDiagnostic;
    f.backspace();
    check(f.endpoint->memoryResponse.is_null() && f.context.pending,"diagnostic enqueue remains unacknowledged");
    const auto& request=diagnosticAt("RequestEditSession");
    check(request.at("hrKnown")==true && request.at("hr")==0,
        "RequestEditSession outer success is recorded independently of callback success");
    check(f.context.drain()==S_OK,"diagnosed dispatcher callback");
    f.endpoint->tick();f.expect("applied",true,2);
    check(f.endpoint->memoryResponse.size()==7 && f.m.text==L"A" && f.m.writes==1 &&
        diagnosticAt("Reply").at("stage")=="Reply","diagnostic reply observation does not add any v2 fields");
}
void requestDiagnosticsDistinguishSessionResultAvailability() {
    struct Case { HRESULT request,session;bool writesSession; };
    const Case cases[]={
        {S_OK,TF_S_ASYNC,true},{S_OK,TF_E_NOLOCK,true},
        {E_ACCESSDENIED,S_OK,true},{E_ACCESSDENIED,TF_S_ASYNC,true},
        {E_ACCESSDENIED,TF_S_ASYNC,false},{S_FALSE,S_OK,true}
    };
    for(const auto& sample:cases) {
        resetDiagnostics();DispatcherFixture f;f.m.text=L"keep";f.bind();
        f.endpoint->lease->diagnostic.enabled=true;f.endpoint->lease->diagnostic.sink=captureDiagnostic;
        f.context.requestResult=sample.request;f.context.sessionResult=sample.session;
        f.context.writesSessionResult=sample.writesSession;f.backspace();
        const auto& row=diagnosticAt("RequestEditSession");
        const bool sessionKnown=sample.request==S_OK;
        check(row.at("hrKnown")==true && row.at("hr")==static_cast<uint32_t>(sample.request) &&
            row.at("actual")==static_cast<int>(sessionKnown) &&
            row.at("requested")==static_cast<uint32_t>(sessionKnown?sample.session:0),
            "session HRESULT bits are known only when RequestEditSession returns exactly S_OK");
        check(f.context.requestCalls==1 && f.m.writeCalls==0 && f.m.text==L"keep",
            "diagnosing request result availability cannot execute or repeat a pending edit");
        if(f.context.pending) {
            f.endpoint->invalidate();check(f.context.drain()==E_ABORT,"retire pending diagnostic fixture without writing");
        }
    }
}
void pendingDiagnosticPollsStayQuietUntilRejection() {
    resetDiagnostics();DispatcherFixture f;f.m.text=L"keep";f.bind();
    f.endpoint->lease->diagnostic.enabled=true;f.endpoint->lease->diagnostic.sink=captureDiagnostic;
    f.backspace();
    const auto eventsBefore=diagnosticEvents.size();const auto callsBefore=diagnosticSinkCalls;
    for(unsigned poll=0;poll<4;++poll)f.endpoint->tick();
    check(diagnosticEvents.size()==eventsBefore && diagnosticSinkCalls==callsBefore &&
        f.context.pending && !f.endpoint->lease->completed && f.endpoint->memoryResponse.is_null(),
        "successful pending polls do not consume edit diagnostic events or claim completion");
    f.context.status=TS_SD_READONLY;f.endpoint->tick();
    check(diagnosticEvents.size()==eventsBefore+1 && diagnosticSinkCalls==callsBefore+1,
        "existing poll emits only one rejection observation");
    const auto& rejection=diagnosticEvents.back();
    check(rejection.at("stage")=="Lease" && rejection.at("value")==0 && rejection.at("value2")==17 &&
        rejection.at("hrKnown")==false && rejection.at("sequence")==2,
        "read-only poll rejection uses the fixed reason without inventing an API HRESULT");
    check(f.context.requestCalls==1 && f.m.writeCalls==0 && f.context.pending && !f.endpoint->lease->active,
        "read-only polling revokes the existing edit without requesting or writing again");
    check(f.context.drain()==E_ABORT && !f.endpoint->lease->attempted && f.m.text==L"keep" && f.m.writeCalls==0,
        "delayed callback still refuses the lease revoked by read-only status");
    f.endpoint->tick();f.expect("failed",false,2);
    check(f.context.requestCalls==1 && f.m.writeCalls==0 && f.endpoint->closeAfterWrite,
        "read-only rejection and diagnostics never replay the pending edit");
}
void rejectedEditDoesNotInheritPreviousDiagnosticResult() {
    for(const bool staleGeneration:{true,false}) {
        resetDiagnostics();DispatcherFixture f;f.m.text=L"AB";f.m.first=f.m.last=2;f.bind();
        f.endpoint->lease->diagnostic.enabled=true;f.endpoint->lease->diagnostic.sink=captureDiagnostic;
        f.backspace();check(f.context.drain()==S_OK,"seed a completed successful edit");
        f.endpoint->tick();f.expect("applied",true,2);
        check(diagnosticAt("Reply").at("hrKnown")==true && diagnosticAt("Reply").at("hr")==0,
            "the first successful edit has a known HRESULT");

        resetDiagnostics();
        if(staleGeneration)++f.boundGeneration;
        else {
            changingIdentity=fakeForeground();changingIdentity.focus=reinterpret_cast<HWND>(3);
            f.endpoint->lease->foreground=changedForeground;
        }
        f.backspace();f.expect("failed",false,3,staleGeneration?"stale-generation":"focus-changed");
        check(f.context.requestCalls==1 && !f.context.pending && f.m.text==L"A" && f.m.writeCalls==1 &&
            f.endpoint->lease->completed && f.endpoint->lease->outcome==S_OK,
            "pre-request rejection preserves prior business state without issuing another edit");
        const auto& reply=diagnosticAt("Reply");
        check(reply.at("sequence")==3 && reply.at("hrKnown")==false &&
            reply.at("hr")==static_cast<uint32_t>(E_PENDING),
            "new rejected sequence cannot inherit the previous edit's successful HRESULT");
        for(const auto& row:diagnosticEvents)
            check(row.at("stage")!="RequestEditSession" && row.at("stage")!="Callback" && row.at("stage")!="Complete",
                "pre-request rejection must not invent a callback or completion record");
        f.endpoint->closePipe();
        check(diagnosticAt("Disconnect").at("sequence")==3 && diagnosticAt("Disconnect").at("hrKnown")==false,
            "disconnect of the rejected sequence also has no inherited completion result");
    }
}
class DiagnosticEnvironmentRestore {
public:
    DiagnosticEnvironmentRestore() {
        SetLastError(ERROR_SUCCESS);
        const DWORD needed=GetEnvironmentVariableW(yime::touchdiag::kEnvironment,nullptr,0);
        if(needed) {
            std::vector<wchar_t> buffer(needed);
            const DWORD copied=GetEnvironmentVariableW(yime::touchdiag::kEnvironment,buffer.data(),needed);
            check(copied<needed,"capture original process diagnostic environment");
            value_.assign(buffer.data(),copied);present_=true;
        } else {
            const DWORD result=GetLastError();
            check(result==ERROR_SUCCESS || result==ERROR_ENVVAR_NOT_FOUND,"read original process diagnostic environment");
            present_=result!=ERROR_ENVVAR_NOT_FOUND;
        }
    }
    ~DiagnosticEnvironmentRestore() noexcept { if(!restored_)restore(); }
    bool restore() noexcept {
        restored_=SetEnvironmentVariableW(yime::touchdiag::kEnvironment,present_?value_.c_str():nullptr)!=FALSE;
        return restored_;
    }
private:
    bool present_=false,restored_=false;
    std::wstring value_;
};
void diagnosticEnvironmentRequiresExactOptIn() {
    DiagnosticEnvironmentRestore restore;
    for(const wchar_t* value:{L"",L"0",L"true",L"11",L"1"}) {
        check(SetEnvironmentVariableW(yime::touchdiag::kEnvironment,value)!=FALSE,"set isolated process diagnostic option");
        SetLastError(ERROR_INVALID_HANDLE);
        check(yime::touchdiag::EnabledFromEnvironment()==(std::wstring(value)==L"1") &&
            GetLastError()==ERROR_INVALID_HANDLE,"only exact environment value 1 enables diagnostics and preserves last error");
    }
    // Even with the process opt-in present, the memory-only constructor must
    // remain offline/default-off. It does not activate the production endpoint.
    resetDiagnostics();DispatcherFixture f;f.bind();f.endpoint->lease->diagnostic.sink=captureDiagnostic;
    check(!f.endpoint->diagnosticEnabled && !f.endpoint->lease->diagnostic.enabled,
        "memory fixture does not inherit production environment opt-in");
    f.edit();check(f.context.drain()==S_OK,"memory edit under process opt-in");f.endpoint->tick();f.expect("applied",true,2);
    check(diagnosticSinkCalls==0,"environment alone cannot turn on the memory fixture sink");
    check(restore.restore(),"restore original process diagnostic environment");
}
void diagnosticBudgetIsSharedAndFailureSafe() {
    using namespace yime::touchdiag;
    resetDiagnostics();auto budget=std::make_shared<Budget>();Recorder first(budget,1);
    first.enabled=true;first.sink=captureDiagnostic;Recorder second=first;
    first.emit({Stage::Callback});
    const auto used=budget->usedBytes.load();
    check(used>0 && used<kMaxBytes && diagnosticSinkCalls==1,"diagnostic sink reserves a bounded record");
    budget->usedBytes=kMaxBytes;
    first.emit({Stage::Complete,S_OK,true});second.emit({Stage::Reply});
    check(diagnosticSinkCalls==1 && budget->usedBytes==kMaxBytes,
        "copied request recorders share the endpoint budget and stop at its limit");

    resetDiagnostics();auto failingBudget=std::make_shared<Budget>();Recorder throwing(failingBudget,2);
    throwing.enabled=true;throwing.sink=throwingDiagnostic;throwing.emit({Stage::Callback});
    check(diagnosticSinkCalls==1 && failingBudget->usedBytes>0,
        "sink failure consumes budget and is never retried");
}
void actualDispatcherV2Contract() {
    DispatcherFixture f;f.m.text=L"keep";f.bind();
    const auto generation=f.boundGeneration;
    f.send("status");f.expect("ready",true,2);
    check(f.endpoint->identity.generation==generation && f.endpoint->lease->active && !f.context.pending &&
        f.m.text==L"keep" && f.m.writes==0 && f.m.selections==0,"actual status has no mutation");
    f.edit();check(f.endpoint->memoryResponse.is_null() && f.context.pending && f.m.writes==0,
        "dispatcher cannot acknowledge asynchronous enqueue");
    check(f.context.drain()==S_OK,"memory async edit");f.endpoint->tick();f.expect("applied",true,3);
    check(f.m.writes==1 && f.endpoint->memoryResponse.at("generation")==generation,"applied identity");
    f.send("close");f.expect("closed",true,4);
    check(f.endpoint->memoryResponse.at("generation")==generation && !f.endpoint->lease->active &&
        f.endpoint->identity.generation>generation,"close receipt echoes old identity then revokes");
    f.send("status");f.expect("unavailable",true,5,"stale-generation");
    check(!f.endpoint->lease->active && f.m.writes==1,"status after close cannot revive session");
}
void dispatcherStaleIdentityAndNoRevival() {
    DispatcherFixture f;f.bind();f.endpoint->invalidate();
    f.send("status");f.expect("unavailable",true,2,"stale-generation");
    check(f.endpoint->memoryResponse.at("generation")==f.endpoint->identity.generation,"status reports current generation");
    f.edit();f.expect("failed",false,3,"stale-generation");
    check(!f.context.pending && f.m.writes==0,"stale edit never requests write lock");
    f.endpoint->listen();f.sequence=0;f.bind();
    f.activation="former-activation";f.edit();f.expect("failed",false,2,"stale-activation");
    check(!f.context.pending && f.m.writes==0,"wrong activation cannot write");

    DispatcherFixture delayed;delayed.m.text=L"keep";delayed.bind();delayed.edit();
    auto old=delayed.endpoint->lease;const auto oldGeneration=delayed.boundGeneration;
    delayed.endpoint->listen();delayed.sequence=0;delayed.bind();
    check(delayed.boundGeneration>oldGeneration && !old->active,"reconnect creates new lease");
    const auto boundReceipt=delayed.endpoint->memoryResponse;
    check(delayed.context.drain()==E_ABORT && delayed.m.writes==0 && delayed.m.text==L"keep",
        "old asynchronous callback cannot write after real dispatcher rebind");
    check(delayed.endpoint->memoryResponse==boundReceipt,"old callback cannot replace new bind receipt");
    delayed.edit();check(delayed.context.drain()==S_OK,"new edit allowed");delayed.endpoint->tick();
    delayed.expect("applied",true,2);check(delayed.m.writes==1,"only new input writes once");
}
void dispatcherUnknownAndEligibility() {
    DispatcherFixture f;f.bind();f.m.afterWrite=[&]{f.endpoint->invalidate();};f.edit();
    check(f.context.drain()==E_ABORT,"reentrant mutation outcome");f.endpoint->tick();f.expect("unknown",false,2);
    check(f.m.writes==1 && f.endpoint->memoryResponse.at("generation").get<uint64_t>()>f.boundGeneration &&
        f.endpoint->closeAfterWrite,"partial edit outcome stays unknown and stops session");
    DispatcherFixture disabled;disabled.eligibility->query=inactiveProfile;
    disabled.send("bind",{{"window",uint64_t(1)},{"focus",uint64_t(2)}});
    disabled.expect("bind-rejected",false,1,"profile-inactive");
    check(!disabled.context.pending && disabled.m.writes==0 && !disabled.endpoint->lease->active,
        "inactive dedicated profile cannot bind");
    DispatcherFixture statusUnknown;statusUnknown.context.statusResult=S_FALSE;
    statusUnknown.send("bind",{{"window",uint64_t(1)},{"focus",uint64_t(2)}});
    statusUnknown.expect("bind-rejected",false,1,"context-status-unavailable");
    check(!statusUnknown.context.pending && statusUnknown.m.writes==0,"unknown writable status fails closed");
}
}
int main() {
    try {
        actualEligibilityQueries();edits();selectionFailuresAndSelectedBackspace();limitedRangeCharacterization();
        diagnosticsAreOptionalAndContentFree();diagnosticsDescribeLimitedRanges();
        focusedChildLease();failures();reentrantRevocation();readonlyStatusAndEpochs();
        eligibilityRevokesDelayedEdits();newBindingDoesNotReviveOldCallback();selectionReadReentrancy();
        dispatcherRequestCompletionPaths();requestReturnReentrancyKeepsOriginalLease();
        statusQueryReentrancyKeepsOriginalObservation();bindingQueryOutputsCannotTargetReentrantBinding();
        dispatcherDeleteFailuresStayUnknown();
        dispatcherDiagnosticsPreserveV2();requestDiagnosticsDistinguishSessionResultAvailability();
        pendingDiagnosticPollsStayQuietUntilRejection();rejectedEditDoesNotInheritPreviousDiagnosticResult();
        diagnosticEnvironmentRequiresExactOptIn();diagnosticBudgetIsSharedAndFailureSafe();
        actualDispatcherV2Contract();dispatcherStaleIdentityAndNoRevival();dispatcherUnknownAndEligibility();
        check(moduleRefs==0,"module lifetime leak");
        std::cout<<"PASS frontend edits: memory TSF, actual profile/thread eligibility queries, actual v2 dispatcher/status/epochs, "
            "A-B-A revocation, Unicode, selection/limited-range characterization, request/callback completion, "
            "delayed/reentrant revocation, write/post-write failure, optional bounded content-free diagnostics; no native-host acceptance\n";
        return 0;
    } catch(const std::exception& e) { std::cerr<<e.what()<<'\n';return 1; }
}
