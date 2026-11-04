// Production edit callback against memory-only TSF substitutes. No registration,
// real thread manager activation, foreground change, or user-document access.
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
    STDMETHODIMP RequestEditSession(TfClientId,ITfEditSession* edit,DWORD,HRESULT* result) override {pending=edit;*result=TF_S_ASYNC;return S_OK;}
    HRESULT drain(){auto edit=pending;pending.Reset();return edit->DoEditSession(73);}
    STDMETHODIMP GetSelection(TfEditCookie,ULONG,ULONG,TF_SELECTION* out,ULONG* count) override {
        out->range=new Range(m,m.first,m.last);out->style={m.active,FALSE};*count=1;return S_OK;
    }
    STDMETHODIMP SetSelection(TfEditCookie,ULONG,const TF_SELECTION* value) override {
        auto* r=static_cast<Range*>(value->range);m.first=r->first;m.last=r->last;m.active=value->style.ase;++m.selections;return S_OK;
    }
    STDMETHODIMP GetStart(TfEditCookie,ITfRange** out) override {*out=new Range(m,0,0);return S_OK;}
    STDMETHODIMP GetEnd(TfEditCookie,ITfRange** out) override {LONG n=static_cast<LONG>(m.text.size());*out=new Range(m,n,n);return S_OK;}
    STDMETHODIMP InWriteSession(TfClientId,BOOL*) override{return E_NOTIMPL;}
    STDMETHODIMP GetActiveView(ITfContextView**) override{return E_NOTIMPL;}
    STDMETHODIMP EnumViews(IEnumTfContextViews**) override{return E_NOTIMPL;}
    STDMETHODIMP GetStatus(TF_STATUS*) override{return E_NOTIMPL;}
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
    STDMETHODIMP GetFocus(ITfDocumentMgr** out) override {*out=&document;document.AddRef();return S_OK;}
    STDMETHODIMP Activate(TfClientId*) override{return E_NOTIMPL;}
    STDMETHODIMP Deactivate() override{return E_NOTIMPL;}
    STDMETHODIMP CreateDocumentMgr(ITfDocumentMgr**) override{return E_NOTIMPL;}
    STDMETHODIMP EnumDocumentMgrs(IEnumTfDocumentMgrs**) override{return E_NOTIMPL;}
    STDMETHODIMP SetFocus(ITfDocumentMgr*) override{return E_NOTIMPL;}
    STDMETHODIMP AssociateFocus(HWND,ITfDocumentMgr*,ITfDocumentMgr**) override{return E_NOTIMPL;}
    STDMETHODIMP IsThreadFocus(BOOL*) override{return E_NOTIMPL;}
    STDMETHODIMP GetFunctionProvider(REFCLSID,ITfFunctionProvider**) override{return E_NOTIMPL;}
    STDMETHODIMP EnumFunctionProviders(IEnumTfFunctionProviders**) override{return E_NOTIMPL;}
    STDMETHODIMP GetGlobalCompartment(ITfCompartmentMgr**) override{return E_NOTIMPL;}
};
ForegroundIdentity fakeForeground() noexcept{return {reinterpret_cast<HWND>(1),GetCurrentThreadId(),GetCurrentProcessId(),reinterpret_cast<HWND>(2),reinterpret_cast<HWND>(1)};}
struct Fixture {
    Manager manager;
    std::shared_ptr<Lease> lease=std::make_shared<Lease>();
    Context& context=manager.document.context; Memory& m=context.m;
    Fixture(){lease->manager=&manager;lease->document=&manager.document;lease->context=&context;lease->window=reinterpret_cast<HWND>(1);lease->focus=reinterpret_cast<HWND>(2);lease->active=true;lease->foreground=fakeForeground;}
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
}
int main(){try{edits();focusedChildLease();failures();reentrantRevocation();check(moduleRefs==0,"module lifetime leak");std::cout<<"PASS frontend edits: memory TSF, focused-child identity, Unicode, selection, delayed/reentrant revocation, write failure; no native-host acceptance\n";return 0;}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
