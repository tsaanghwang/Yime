// Production edit callback against memory-only TSF substitutes. No registration,
// real thread manager activation, foreground change, or user-document access.
#define YIME_TOUCH_FRONTEND_MEMORY_TEST 1
#include "../TouchFrontendEndpoint.cpp"
#include <iostream>
#include <functional>

static long moduleRefs = 0;
void YimeModuleAddRef() noexcept { ++moduleRefs; }
void YimeModuleRelease() noexcept { --moduleRefs; }
long YimeModuleRefCount() noexcept { return moduleRefs; }

namespace {
void check(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
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
struct Memory { std::wstring text; LONG first=0, last=0; TfActiveSelEnd active=TF_AE_END; HRESULT write=S_OK; unsigned writes=0,selections=0; std::function<void()> afterWrite; };
class Range final : public FakeCom<ITfRange> {
public:
    Memory& m; LONG first, last;
    Range(Memory& value, LONG a, LONG b):m(value),first(a),last(b){}
    STDMETHODIMP_(ULONG) Release() override { ULONG n=--refs; if(!n)delete this; return n; }
    STDMETHODIMP SetText(TfEditCookie cookie,DWORD,const WCHAR* value,LONG n) override {
        check(cookie==73,"write cookie"); if(FAILED(m.write))return m.write;
        m.text.replace(first,last-first,value,n);last=first+n;++m.writes;if(m.afterWrite)m.afterWrite();return S_OK;
    }
    STDMETHODIMP GetText(TfEditCookie,DWORD,WCHAR* out,ULONG max,ULONG* count) override {
        *count=std::min(max,static_cast<ULONG>(last-first));std::copy_n(m.text.data()+first,*count,out);return S_OK;
    }
    STDMETHODIMP Collapse(TfEditCookie,TfAnchor anchor) override { if(anchor==TF_ANCHOR_START)last=first;else first=last;return S_OK; }
    STDMETHODIMP Clone(ITfRange** out) override { *out=new Range(m,first,last);return S_OK; }
    STDMETHODIMP ShiftStart(TfEditCookie,LONG n,LONG* moved,const TF_HALTCOND*) override {
        LONG next=std::clamp(first+n,0L,static_cast<LONG>(m.text.size()));*moved=next-first;first=next;last=std::max(first,last);return S_OK;
    }
    STDMETHODIMP ShiftEnd(TfEditCookie,LONG n,LONG* moved,const TF_HALTCOND*) override {
        LONG next=std::clamp(last+n,0L,static_cast<LONG>(m.text.size()));*moved=next-last;last=next;first=std::min(first,last);return S_OK;
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
    DWORD status = 0; HRESULT statusResult = S_OK; std::function<void()> afterSelection, afterStatus;
    STDMETHODIMP RequestEditSession(TfClientId,ITfEditSession* edit,DWORD,HRESULT* result) override {pending=edit;*result=TF_S_ASYNC;return S_OK;}
    HRESULT drain(){auto edit=pending;pending.Reset();return edit->DoEditSession(73);}
    STDMETHODIMP GetSelection(TfEditCookie,ULONG,ULONG,TF_SELECTION* out,ULONG* count) override {
        out->range=new Range(m,m.first,m.last);out->style={m.active,FALSE};*count=1;if(afterSelection)afterSelection();return S_OK;
    }
    STDMETHODIMP SetSelection(TfEditCookie,ULONG,const TF_SELECTION* value) override {
        auto* r=static_cast<Range*>(value->range);m.first=r->first;m.last=r->last;m.active=value->style.ase;++m.selections;return S_OK;
    }
    STDMETHODIMP GetStart(TfEditCookie,ITfRange** out) override {*out=new Range(m,0,0);return S_OK;}
    STDMETHODIMP GetEnd(TfEditCookie,ITfRange** out) override {LONG n=static_cast<LONG>(m.text.size());*out=new Range(m,n,n);return S_OK;}
    STDMETHODIMP InWriteSession(TfClientId,BOOL*) override{return E_NOTIMPL;}
    STDMETHODIMP GetActiveView(ITfContextView**) override{return E_NOTIMPL;}
    STDMETHODIMP EnumViews(IEnumTfContextViews**) override{return E_NOTIMPL;}
    STDMETHODIMP GetStatus(TF_STATUS* out) override{*out={};out->dwDynamicFlags=status;if(afterStatus)afterStatus();return statusResult;}
    STDMETHODIMP GetProperty(REFGUID,ITfProperty**) override{return E_NOTIMPL;}
    STDMETHODIMP GetAppProperty(REFGUID,ITfReadOnlyProperty**) override{return E_NOTIMPL;}
    STDMETHODIMP TrackProperties(const GUID**,ULONG,const GUID**,ULONG,ITfReadOnlyProperty**) override{return E_NOTIMPL;}
    STDMETHODIMP EnumProperties(IEnumTfProperties**) override{return E_NOTIMPL;}
    STDMETHODIMP GetDocumentMgr(ITfDocumentMgr**) override{return E_NOTIMPL;}
    STDMETHODIMP CreateRangeBackup(TfEditCookie,ITfRange*,ITfRangeBackup**) override{return E_NOTIMPL;}
};
class Document final : public FakeCom<ITfDocumentMgr> {
public:
    Context context; bool replaced=false;
    STDMETHODIMP GetTop(ITfContext** out) override {*out=replaced?nullptr:&context;if(*out)(*out)->AddRef();return S_OK;}
    STDMETHODIMP CreateContext(TfClientId,DWORD,IUnknown*,ITfContext**,TfEditCookie*) override{return E_NOTIMPL;}
    STDMETHODIMP Push(ITfContext*) override{return E_NOTIMPL;}
    STDMETHODIMP Pop(DWORD) override{return E_NOTIMPL;}
    STDMETHODIMP GetBase(ITfContext**) override{return E_NOTIMPL;}
    STDMETHODIMP EnumContexts(IEnumTfContexts**) override{return E_NOTIMPL;}
};
class Manager final : public FakeCom<ITfThreadMgr> {
public:
    Document document;
    HRESULT threadFocusResult=S_OK;BOOL threadFocused=TRUE;unsigned threadFocusQueries=0;
    STDMETHODIMP GetFocus(ITfDocumentMgr** out) override {*out=&document;document.AddRef();return S_OK;}
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
};
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
int main(){try{actualEligibilityQueries();edits();focusedChildLease();failures();reentrantRevocation();readonlyStatusAndEpochs();eligibilityRevokesDelayedEdits();newBindingDoesNotReviveOldCallback();selectionReadReentrancy();actualDispatcherV2Contract();dispatcherStaleIdentityAndNoRevival();dispatcherUnknownAndEligibility();check(moduleRefs==0,"module lifetime leak");std::cout<<"PASS frontend edits: memory TSF, actual profile/thread eligibility queries, actual v2 dispatcher/status/epochs, A-B-A revocation, Unicode, selection, delayed/reentrant revocation, write failure; no native-host acceptance\n";return 0;}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
