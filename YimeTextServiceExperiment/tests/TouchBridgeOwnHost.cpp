// Test-only process: owns every TSF document it touches; no TIP registration,
// explicit product activation, SendInput or external window access. Run only in
// an isolated Windows CI environment: ActivateEx flags suppress activation at
// this call, not every possible later TSF asynchronous activation. S2b pumps
// a bounded STA queue; this fixture is restricted to clean Windows CI, no user PC.
#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include <nlohmann/json.hpp>
#include <atomic>
#include <iostream>
#include <stdexcept>
#include <string>
#include <functional>
#include "CompositionEditSession.h"

using Microsoft::WRL::ComPtr;
using nlohmann::json;
using namespace yime::experiment;
namespace {
void require(HRESULT hr, const char* what) { if (FAILED(hr)) throw std::runtime_error(what); }
std::string utf8(const std::wstring& value) {
    if (value.empty()) return {};
    const int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (n <= 0) throw std::runtime_error("invalid readback UTF-16");
    std::string out(static_cast<size_t>(n), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), out.data(), n, nullptr, nullptr) != n)
        throw std::runtime_error("readback conversion failed");
    return out;
}
class Sink final : public ITfCompositionSink {
    std::atomic<ULONG> refs_{1};
public:
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid != IID_IUnknown && iid != __uuidof(ITfCompositionSink)) return E_NOINTERFACE;
        *out = static_cast<ITfCompositionSink*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
    STDMETHODIMP_(ULONG) Release() override { const ULONG n=--refs_; if (!n) delete this; return n; }
    STDMETHODIMP OnCompositionTerminated(TfEditCookie, ITfComposition*) override { return S_OK; }
};
class Reader final : public ITfEditSession {
    std::atomic<ULONG> refs_{1};
    ComPtr<ITfContext> context_;
public:
    std::wstring text;
    bool completed=false;
    explicit Reader(ITfContext* context):context_(context){}
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out=nullptr;
        if (iid!=IID_IUnknown && iid!=__uuidof(ITfEditSession)) return E_NOINTERFACE;
        *out=static_cast<ITfEditSession*>(this);AddRef();return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override{return ++refs_;}
    STDMETHODIMP_(ULONG) Release() override{const ULONG n=--refs_;if(!n)delete this;return n;}
    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        completed=true;
        ComPtr<ITfRange> begin,end;
        HRESULT hr=context_->GetStart(cookie,&begin);
        if(SUCCEEDED(hr))hr=context_->GetEnd(cookie,&end);
        if(SUCCEEDED(hr))hr=begin->ShiftEndToRange(cookie,end.Get(),TF_ANCHOR_END);
        wchar_t buffer[1025]{};ULONG n=0;
        if(SUCCEEDED(hr))hr=begin->GetText(cookie,0,buffer,1024,&n);
        if(SUCCEEDED(hr))text.assign(buffer,n);
        return hr;
    }
};
std::string read(ITfContext* context,TfClientId client){
    ComPtr<Reader> reader;reader.Attach(new Reader(context));HRESULT edit=E_FAIL;
    require(context->RequestEditSession(client,reader.Get(),TF_ES_SYNC|TF_ES_READ,&edit),"request read");
    require(edit,"read edit");if(!reader->completed)throw std::runtime_error("read not completed");
    return utf8(reader->text);
}
struct Completion { bool seen=false; HRESULT result=E_FAIL; ITfContext* expected=nullptr; };
void completed(void* opaque,ITfContext* context,const BrokerUpdate&,HRESULT result) noexcept {
    auto* c=static_cast<Completion*>(opaque);c->seen=true;c->result=context==c->expected?result:E_UNEXPECTED;
}
// Async request state is also the execution guard. The edit session AddRefs it,
// keeping every raw composition/completion slot alive until the queued edit dies.
class AsyncState final : public IBrokerEditExecutionGuard {
    std::atomic<ULONG> refs_{1};
public:
    ComPtr<ITfThreadMgr> manager;
    ComPtr<ITfDocumentMgr> document,other;
    ComPtr<ITfContext> context,otherContext;
    ComPtr<Sink> sink;
    TfClientId client=TF_CLIENTID_NULL;
    ITfComposition* composition=nullptr;
    bool ending=false,cancelled=false,seen=false,queued=false,controlled=false;
    unsigned requestEpoch=1,activeEpoch=1,checks=0,denied=0,callbacks=0;
    HRESULT result=E_PENDING,requestResult=E_PENDING;
    BrokerUpdate update;
    ~AsyncState(){if(composition)composition->Release();}
    STDMETHODIMP QueryInterface(REFIID iid,void** out) override {
        if(!out)return E_POINTER;*out=nullptr;
        if(iid!=IID_IUnknown)return E_NOINTERFACE;
        *out=static_cast<IBrokerEditExecutionGuard*>(this);AddRef();return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override{return ++refs_;}
    STDMETHODIMP_(ULONG) Release() override{const ULONG n=--refs_;if(!n)delete this;return n;}
    HRESULT ValidateExecution(ITfContext* actual) noexcept override {
        ++checks;
        ComPtr<ITfDocumentMgr> focused;
        const HRESULT focusResult=manager->GetFocus(&focused);
        if(actual!=context.Get() || cancelled || requestEpoch!=activeEpoch ||
           focusResult!=S_OK || focused.Get()!=document.Get()) {++denied;return E_ABORT;}
        return S_OK;
    }
    static void Completed(void* opaque,ITfContext* actual,const BrokerUpdate&,HRESULT hr) noexcept {
        auto* state=static_cast<AsyncState*>(opaque);
        ++state->callbacks;state->seen=true;
        state->result=actual==state->context.Get()?hr:E_UNEXPECTED;
        // Store the old request's result only; never mutate activation/epoch.
    }
    HRESULT Queue() {
        requestResult=ApplyBrokerUpdateToContext(context.Get(),client,sink.Get(),&composition,
            &ending,update,nullptr,nullptr,true,Completed,this,this);
        queued=requestResult==TF_S_ASYNC && !seen;
        return requestResult;
    }
};
// Holding a real TSF read edit lock induces a deterministic deferred write. It
// is test scheduling, not a claim about normal OS queue latency or frequency.
class ReadLockQueue final : public ITfEditSession {
    std::atomic<ULONG> refs_{1};
    ComPtr<AsyncState> state_;
    std::string scenario_;
public:
    bool executed=false;
    ReadLockQueue(AsyncState* state,std::string scenario):state_(state),scenario_(std::move(scenario)){}
    STDMETHODIMP QueryInterface(REFIID iid,void** out) override {
        if(!out)return E_POINTER;*out=nullptr;
        if(iid!=IID_IUnknown && iid!=__uuidof(ITfEditSession))return E_NOINTERFACE;
        *out=static_cast<ITfEditSession*>(this);AddRef();return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override{return ++refs_;}
    STDMETHODIMP_(ULONG) Release() override{const ULONG n=--refs_;if(!n)delete this;return n;}
    STDMETHODIMP DoEditSession(TfEditCookie) override {
        executed=true;state_->controlled=true;
        const HRESULT hr=state_->Queue();
        // Do not count a negative as deferred if Windows ran the write inline.
        if(hr!=TF_S_ASYNC || state_->seen)return E_UNEXPECTED;
        if(scenario_=="async-focus-lost")return state_->manager->SetFocus(state_->other.Get());
        if(scenario_=="async-cancel")state_->cancelled=true;
        if(scenario_=="async-old-epoch")state_->activeEpoch=2;
        return S_OK;
    }
};
void awaitCompletion(AsyncState* state){
    const ULONGLONG deadline=GetTickCount64()+5000;
    while(!state->seen && GetTickCount64()<deadline){
        MSG msg{};
        while(GetTickCount64()<deadline && PeekMessageW(&msg,nullptr,0,0,PM_REMOVE)){
            if(msg.message==WM_QUIT)break;
            TranslateMessage(&msg);DispatchMessageW(&msg);
        }
        if(!state->seen)MsgWaitForMultipleObjects(0,nullptr,FALSE,10,QS_ALLINPUT);
    }
    if(!state->seen){
        // Never unwind slots potentially still referenced by an async edit.
        // Parent sees a failed child and must preserve Unknown, not replay.
        std::cerr<<"async completion deadline; outcome unknown\n";
        ExitProcess(2);
    }
}
struct Apartment {
    Apartment(){require(CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED),"initialize COM");}
    ~Apartment(){CoUninitialize();}
};
struct Manager {
    ComPtr<ITfThreadMgr> manager;TfClientId client=TF_CLIENTID_NULL;bool active=false;
    Manager(){require(CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,
        __uuidof(ITfThreadMgr),reinterpret_cast<void**>(manager.GetAddressOf())),"create thread manager");
        ComPtr<ITfThreadMgrEx> extended;
        require(manager.As(&extended),"query extended thread manager");
        require(extended->ActivateEx(&client,TF_TMAE_NOACTIVATETIP | TF_TMAE_NOACTIVATEKEYBOARDLAYOUT),
            "activate isolated test manager without TIP/keyboard-layout activation");active=true;}
    ~Manager(){if(active)manager->Deactivate();}
};
}
int main(){
    try{
        using MachineQuery = BOOL(WINAPI*)(HANDLE, USHORT*, USHORT*);
        const auto machineQuery=reinterpret_cast<MachineQuery>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"IsWow64Process2"));
        USHORT processMachine=0,nativeMachine=0;
        if(!machineQuery || !machineQuery(GetCurrentProcess(),&processMachine,&nativeMachine) ||
           processMachine!=IMAGE_FILE_MACHINE_UNKNOWN || nativeMachine!=IMAGE_FILE_MACHINE_AMD64)
            throw std::runtime_error("S2a requires native Windows x64, not emulation");
        // Read a single bounded request; this is not a public/runtime IPC API.
        std::string line;char ch=0;
        while(std::cin.get(ch) && ch!='\n'){if(line.size()>=16384)throw std::runtime_error("request too large");line+=ch;}
        const auto request=json::parse(line);
        const auto id=request.at("id").get<std::string>();
        const auto text=request.at("text").get<std::string>();
        const auto scenario=request.at("scenario").get<std::string>();
        if(!request.is_object() || request.size()!=5 || !request.contains("id") || !request.contains("text") ||
           !request.contains("scenario") || !request.contains("context") || !request.contains("epoch") ||
           id.empty()||id.size()>256||text.empty()||text.size()>1024 ||
           request.at("context").get<std::string>()!="own-test-host" ||
           !request.at("epoch").is_number_unsigned() || request.at("epoch")!=json(1u) ||
           (scenario!="commit" && scenario!="duplicate" && scenario!="focus-lost" &&
            scenario!="async-commit" && scenario!="async-focus-lost" &&
            scenario!="async-cancel" && scenario!="async-old-epoch"))
            throw std::runtime_error("invalid isolated test request");
        Apartment apartment;Manager owner;
        ComPtr<ITfDocumentMgr> document,other;
        ComPtr<ITfContext> context,otherContext;TfEditCookie cookie=0;
        require(owner.manager->CreateDocumentMgr(&document),"create own document");
        require(document->CreateContext(owner.client,0,nullptr,&context,&cookie),"create own context");
        require(document->Push(context.Get()),"push own context");
        require(owner.manager->SetFocus(document.Get()),"focus own document");
        if(scenario=="focus-lost"){
            require(owner.manager->CreateDocumentMgr(&other),"create second own document");
            TfEditCookie otherCookie=0;
            require(other->CreateContext(owner.client,0,nullptr,&otherContext,&otherCookie),"create second own context");
            require(other->Push(otherContext.Get()),"push second own context");
            require(owner.manager->SetFocus(other.Get()),"invalidate focus");
        }
        ComPtr<Sink> sink;sink.Attach(new Sink);
        std::string consumed;
        unsigned actualEdits=0;
        bool callback=false;std::string outcome="failed";bool duplicateRejected=false;
        auto applyOnce=[&](const std::string& commitID)->bool {
            if(!consumed.empty())return false;
            ComPtr<ITfDocumentMgr> focused;
            require(owner.manager->GetFocus(&focused),"read TSF focus");
            if(focused.Get()!=document.Get())return false;
            // Synchronous-only own-context test: no queued edit or message pump.
            // This is not a proof of an async focus gate in production TSF.
            consumed=commitID;
            ITfComposition* composition=nullptr;bool ending=false;
            BrokerUpdate update;update.commit=text;
            Completion receipt;receipt.expected=context.Get();
            ++actualEdits;
            const HRESULT result=ApplyBrokerUpdateToContext(context.Get(),owner.client,sink.Get(),
                &composition,&ending,update,nullptr,nullptr,false,completed,&receipt);
            if(composition)composition->Release();
            callback=receipt.seen;
            outcome=receipt.seen && result==S_OK && receipt.result==S_OK ? "applied" : "unknown";
            return true;
        };
        const bool asynchronous=scenario.rfind("async-",0)==0;
        ComPtr<AsyncState> asyncState;
        if(asynchronous){
            asyncState.Attach(new AsyncState);
            asyncState->manager=owner.manager;asyncState->document=document;
            asyncState->context=context;asyncState->sink=sink;asyncState->client=owner.client;
            asyncState->update.commit=text;
            ++actualEdits;
            if(scenario=="async-commit"){
                const HRESULT queued=asyncState->Queue();
                if(queued!=TF_S_ASYNC)throw std::runtime_error("async write was not queued");
            }else{
                require(owner.manager->CreateDocumentMgr(&asyncState->other),"create delayed-test own document");
                TfEditCookie otherCookie=0;
                require(asyncState->other->CreateContext(owner.client,0,nullptr,&asyncState->otherContext,&otherCookie),"create delayed-test own context");
                require(asyncState->other->Push(asyncState->otherContext.Get()),"push delayed-test own context");
                ComPtr<ReadLockQueue> outer;outer.Attach(new ReadLockQueue(asyncState.Get(),scenario));
                HRESULT locked=E_FAIL;
                require(context->RequestEditSession(owner.client,outer.Get(),TF_ES_SYNC|TF_ES_READ,&locked),"read-lock test request");
                require(locked,"read-lock induced deferred write");
                if(!outer->executed || !asyncState->queued)throw std::runtime_error("controlled deferred request not observed");
            }
            awaitCompletion(asyncState.Get());
            callback=asyncState->seen;
            if(asyncState->callbacks!=1 || asyncState->checks!=1)throw std::runtime_error("async completion/guard count mismatch");
            outcome=asyncState->result==S_OK?"applied":asyncState->result==E_ABORT?"failed":"unknown";
        }else{
            const bool accepted=applyOnce(id);
            if(scenario=="duplicate")duplicateRejected=!applyOnce(id);
            if(scenario=="focus-lost" && accepted)throw std::runtime_error("lost focus accepted");
        }
        const std::string observed=read(context.Get(),owner.client);
        if(outcome=="applied" && observed!=text)outcome="unknown";
        const bool blocked=scenario=="focus-lost" || (asynchronous && scenario!="async-commit");
        if(blocked && !observed.empty())throw std::runtime_error("invalidated request wrote text");
        ITfContext* newContext=asyncState?asyncState->otherContext.Get():otherContext.Get();
        const bool newContextChecked=newContext!=nullptr;
        const bool newContextEmpty=newContextChecked && read(newContext,owner.client).empty();
        if(newContextChecked && !newContextEmpty)throw std::runtime_error("new context was contaminated");
        if(asyncState && asyncState->otherContext)require(asyncState->other->Pop(TF_POPF_ALL),"pop delayed-test context");
        if(otherContext)require(other->Pop(TF_POPF_ALL),"pop second own context");
        require(document->Pop(TF_POPF_ALL),"pop own context");
        std::cout<<json{{"id",id},{"outcome",outcome},{"readbackMatches",observed==text},{"readbackEmpty",observed.empty()},
            {"newContextChecked",newContextChecked},{"newContextEmpty",newContextEmpty},
            {"actualEditRequests",actualEdits},{"asyncRequested",asynchronous},
            {"queuedBeforeCompletion",asyncState?asyncState->queued:false},
            {"controlledDelay",asyncState?asyncState->controlled:false},
            {"guardChecks",asyncState?asyncState->checks:0},
            {"guardDenied",asyncState?asyncState->denied:0},
            {"completionEpoch",asyncState?asyncState->requestEpoch:0},
            {"activeEpoch",asyncState?asyncState->activeEpoch:0},
            {"editCompleted",callback},{"duplicateRejected",duplicateRejected},
            {"registered",false},{"sendInput",false}}.dump()<<'\n';
        return 0;
    }catch(const std::exception& e){std::cerr<<"own TSF test failed: "<<e.what()<<'\n';return 1;}
}
