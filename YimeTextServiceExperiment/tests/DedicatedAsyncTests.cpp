// Actual OS pipe I/O and route/edit-session code with substitute TSF only.
// Never registers or activates a TIP, opens a window, or edits user text.
#include "DedicatedTouchRoute.h"
#include "TouchProductIdentity.h"
#include <iostream>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
using json=nlohmann::json;
namespace {
void check(bool value,const char* message){if(!value)throw std::runtime_error(message);}
template<class T> class StackCom : public T {
public:
    ULONG refs=1;
    STDMETHODIMP QueryInterface(REFIID iid,void** out) override {
        if(!out)return E_POINTER;*out=nullptr;
        if(iid!=IID_IUnknown && iid!=__uuidof(T))return E_NOINTERFACE;
        *out=static_cast<T*>(this);AddRef();return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override {return ++refs;}
    STDMETHODIMP_(ULONG) Release() override {return --refs;}
};
class Sink final : public StackCom<ITfCompositionSink> {
    STDMETHODIMP OnCompositionTerminated(TfEditCookie,ITfComposition*) override {return S_OK;}
};
class Context final : public StackCom<ITfContext>,public ITfInsertAtSelection {
public:
    ComPtr<ITfEditSession> pending;
    std::wstring text;
    unsigned writes=0,requests=0;
    HRESULT writeResult=S_OK,requestResult=S_OK;
    DWORD owner=GetCurrentThreadId();
    STDMETHODIMP QueryInterface(REFIID iid,void** out) override {
        if(!out)return E_POINTER;
        if(iid==__uuidof(ITfInsertAtSelection)){*out=static_cast<ITfInsertAtSelection*>(this);AddRef();return S_OK;}
        return StackCom::QueryInterface(iid,out);
    }
    STDMETHODIMP_(ULONG) AddRef() override {return StackCom::AddRef();}
    STDMETHODIMP_(ULONG) Release() override {return StackCom::Release();}
    STDMETHODIMP RequestEditSession(TfClientId,ITfEditSession* session,DWORD flags,HRESULT* result) override {
        check(GetCurrentThreadId()==owner,"TSF request left owning STA");
        check(flags==(TF_ES_ASYNC|TF_ES_READWRITE) && !pending,"must queue exactly one asynchronous edit");
        ++requests;if(FAILED(requestResult))return requestResult;
        pending=session;*result=TF_S_ASYNC;return S_OK;
    }
    HRESULT drain(){
        check(pending!=nullptr,"no edit to drain");auto session=pending;pending.Reset();return session->DoEditSession(73);
    }
    STDMETHODIMP InsertTextAtSelection(TfEditCookie cookie,DWORD flags,const WCHAR* value,LONG length,ITfRange** range) override {
        check(GetCurrentThreadId()==owner && cookie==73 && flags==0,"invalid STA write");
        *range=nullptr;if(FAILED(writeResult))return writeResult;
        ++writes;text.append(value,length);return S_OK;
    }
    STDMETHODIMP InsertEmbeddedAtSelection(TfEditCookie,DWORD,IDataObject*,ITfRange**) override {return E_NOTIMPL;}
    STDMETHODIMP InWriteSession(TfClientId,BOOL*) override {return E_NOTIMPL;}
    STDMETHODIMP GetSelection(TfEditCookie,ULONG,ULONG,TF_SELECTION*,ULONG*) override {return E_NOTIMPL;}
    STDMETHODIMP SetSelection(TfEditCookie,ULONG,const TF_SELECTION*) override {return E_NOTIMPL;}
    STDMETHODIMP GetStart(TfEditCookie,ITfRange**) override {return E_NOTIMPL;}
    STDMETHODIMP GetEnd(TfEditCookie,ITfRange**) override {return E_NOTIMPL;}
    STDMETHODIMP GetActiveView(ITfContextView**) override {return E_NOTIMPL;}
    STDMETHODIMP EnumViews(IEnumTfContextViews**) override {return E_NOTIMPL;}
    STDMETHODIMP GetStatus(TF_STATUS*) override {return E_NOTIMPL;}
    STDMETHODIMP GetProperty(REFGUID,ITfProperty**) override {return E_NOTIMPL;}
    STDMETHODIMP GetAppProperty(REFGUID,ITfReadOnlyProperty**) override {return E_NOTIMPL;}
    STDMETHODIMP TrackProperties(const GUID**,ULONG,const GUID**,ULONG,ITfReadOnlyProperty**) override {return E_NOTIMPL;}
    STDMETHODIMP EnumProperties(IEnumTfProperties**) override {return E_NOTIMPL;}
    STDMETHODIMP GetDocumentMgr(ITfDocumentMgr**) override {return E_NOTIMPL;}
    STDMETHODIMP CreateRangeBackup(TfEditCookie,ITfRange*,ITfRangeBackup**) override {return E_NOTIMPL;}
};
class Document final : public StackCom<ITfDocumentMgr> {
public:
    Context context;
    STDMETHODIMP GetTop(ITfContext** out) override {*out=&context;context.AddRef();return S_OK;}
    STDMETHODIMP CreateContext(TfClientId,DWORD,IUnknown*,ITfContext**,TfEditCookie*) override {return E_NOTIMPL;}
    STDMETHODIMP Push(ITfContext*) override {return E_NOTIMPL;}
    STDMETHODIMP Pop(DWORD) override {return E_NOTIMPL;}
    STDMETHODIMP GetBase(ITfContext**) override {return E_NOTIMPL;}
    STDMETHODIMP EnumContexts(IEnumTfContexts**) override {return E_NOTIMPL;}
};
class Manager final : public StackCom<ITfThreadMgr> {
public:
    Document document;
    STDMETHODIMP GetFocus(ITfDocumentMgr** out) override {*out=&document;document.AddRef();return S_OK;}
    STDMETHODIMP Activate(TfClientId*) override {return E_NOTIMPL;}
    STDMETHODIMP Deactivate() override {return E_NOTIMPL;}
    STDMETHODIMP CreateDocumentMgr(ITfDocumentMgr**) override {return E_NOTIMPL;}
    STDMETHODIMP EnumDocumentMgrs(IEnumTfDocumentMgrs**) override {return E_NOTIMPL;}
    STDMETHODIMP SetFocus(ITfDocumentMgr*) override {return E_NOTIMPL;}
    STDMETHODIMP AssociateFocus(HWND,ITfDocumentMgr*,ITfDocumentMgr**) override {return E_NOTIMPL;}
    STDMETHODIMP IsThreadFocus(BOOL*) override {return E_NOTIMPL;}
    STDMETHODIMP GetFunctionProvider(REFCLSID,ITfFunctionProvider**) override {return E_NOTIMPL;}
    STDMETHODIMP EnumFunctionProviders(IEnumTfFunctionProviders**) override {return E_NOTIMPL;}
    STDMETHODIMP GetGlobalCompartment(ITfCompartmentMgr**) override {return E_NOTIMPL;}
};
struct Handle {
    HANDLE value=nullptr;
    explicit Handle(HANDLE v=nullptr):value(v){}
    ~Handle(){if(value && value!=INVALID_HANDLE_VALUE)CloseHandle(value);}
    Handle(const Handle&)=delete;Handle& operator=(const Handle&)=delete;
};
std::wstring image(){
    wchar_t value[32768];const auto n=GetModuleFileNameW(nullptr,value,32768);
    check(n>0 && n<32768,"image path");return {value,n};
}
json take(BSTR value){
    if(!value)return json::object();
    struct Free {BSTR value;~Free(){SysFreeString(value);}} free{value};
    const int size=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,SysStringLen(value),nullptr,0,nullptr,nullptr);
    check(size>0,"response UTF8");std::string text(size,'\0');
    check(WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,SysStringLen(value),text.data(),size,nullptr,nullptr)==size,"response conversion");
    return json::parse(text);
}
std::wstring eventName(const std::wstring& id,const wchar_t* suffix){return L"Local\\Yime18uAsyncTest-"+id+suffix;}
int broker(const std::wstring& id,const std::wstring& scenario){
    Handle reached(OpenEventW(EVENT_MODIFY_STATE,FALSE,eventName(id,L"-reached").c_str()));
    Handle release(OpenEventW(SYNCHRONIZE,FALSE,eventName(id,L"-release").c_str()));
    Handle completed(OpenEventW(EVENT_MODIFY_STATE,FALSE,eventName(id,L"-completed").c_str()));
    check(reached.value && release.value && completed.value,"fixture events");
    const auto name=L"\\\\.\\pipe\\YimeBroker.18uTouch.v1."+id;
    Handle pipe(CreateNamedPipeW(name.c_str(),PIPE_ACCESS_DUPLEX|FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_BYTE|PIPE_READMODE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,1,65536,16384,0,nullptr));
    check(pipe.value!=INVALID_HANDLE_VALUE,"fixture pipe");
    check(ConnectNamedPipe(pipe.value,nullptr) || GetLastError()==ERROR_PIPE_CONNECTED,"fixture accept");
    unsigned actions=0,completions=0;
    for(;;){
        std::string frame;char ch=0;DWORD n=0;
        while(ReadFile(pipe.value,&ch,1,&n,nullptr) && n==1 && ch!='\n'){
            frame.push_back(ch);check(frame.size()<=16384,"fixture request bound");
        }
        if(ch!='\n' || !n)return 0; // client closed or cancelled
        const auto request=json::parse(frame);const auto op=request.at("operation").get<std::string>();
        if((scenario==L"open" && op=="open") || (scenario==L"action" && op=="action")){
            SetEvent(reached.value);
            check(WaitForSingleObject(release.value,10000)==WAIT_OBJECT_0,"fixture gate timed out");
        }
        json response={{"version",2},{"sequence",request.at("sequence")},{"ok",true},
            {"identity",{{"layoutSHA256",YIME_TOUCH_LAYOUT_SHA},{"dictionarySHA256",YIME_TOUCH_DICTIONARY_SHA},
             {"mode","variable"},{"sessionPolicy","concept-keyboard-modes-v2+ellipsis-choice-v1"}}},
            {"focus",request.at("focus")},{"sessionId","isolated-test-session"},{"snapshot",{{"revision",1}}}};
        if(op=="action"){
            check(++actions==1,"unexpected action replay");
            response["commit"]={{"id","isolated-commit"},{"text","one-write"},{"focus",request.at("focus")}};
        }
        if(op=="complete"){
            check(++completions==1 && actions==1,"completion count");
            check(request.at("commitId")=="isolated-commit","complete commit id");
            check(request.at("outcome")==((scenario==L"write-failed" || scenario==L"queue-failed")?"unknown":"applied"),"actual completion outcome");
            SetEvent(completed.value);
            if(scenario==L"ack-lost"){DisconnectNamedPipe(pipe.value);return 0;}
            response["receipt"]={{"id",request.at("commitId")},{"outcome",request.at("outcome")}};
        }
        const auto output=response.dump()+"\n";DWORD written=0;
        if(!WriteFile(pipe.value,output.data(),static_cast<DWORD>(output.size()),&written,nullptr))return 0;
        check(written==output.size(),"fixture partial response");
    }
}
struct Peer {
    static unsigned serial;
    std::wstring id=L"test-"+std::to_wstring(GetCurrentProcessId())+L"-"+std::to_wstring(++serial);
    std::wstring pipe=L"\\\\.\\pipe\\YimeBroker.18uTouch.v1."+id;
    Handle reached{CreateEventW(nullptr,TRUE,FALSE,eventName(id,L"-reached").c_str())};
    Handle release{CreateEventW(nullptr,TRUE,FALSE,eventName(id,L"-release").c_str())};
    Handle completed{CreateEventW(nullptr,TRUE,FALSE,eventName(id,L"-completed").c_str())};
    Handle process;DWORD pid=0;
    explicit Peer(const wchar_t* scenario){
        check(reached.value && release.value && completed.value,"create fixture events");
        auto command=L"\""+image()+L"\" --broker "+id+L" "+scenario;
        STARTUPINFOW startup{};startup.cb=sizeof(startup);PROCESS_INFORMATION info{};
        check(CreateProcessW(image().c_str(),command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&startup,&info),"fixture child");
        process.value=info.hProcess;pid=info.dwProcessId;CloseHandle(info.hThread);
    }
    ~Peer(){
        SetEvent(release.value);
        if(process.value && WaitForSingleObject(process.value,5000)!=WAIT_OBJECT_0){
            // Only the child just created by this fixture; never a product.
            TerminateProcess(process.value,9);WaitForSingleObject(process.value,5000);
        }
    }
    void gate(){check(WaitForSingleObject(reached.value,5000)==WAIT_OBJECT_0,"broker did not reach response gate");}
    void finish(){
        SetEvent(release.value);check(WaitForSingleObject(process.value,5000)==WAIT_OBJECT_0,"broker did not stop after client disconnect");
        DWORD exit=1;check(GetExitCodeProcess(process.value,&exit) && exit==0,"broker fixture failed");
    }
};
unsigned Peer::serial=0;
DedicatedForeground fakeForeground() noexcept{return {reinterpret_cast<HWND>(1),GetCurrentThreadId(),GetCurrentProcessId()};}
struct Route {
    Manager manager;Sink sink;
    DedicatedTouchRoute* value=new DedicatedTouchRoute(&manager,37,fakeForeground);
    Context& context=manager.document.context;
    ~Route(){close();}
    void close(){
        if(value){value->Disconnect();value->Release();value=nullptr;}
        // Pending callback owns the route after release and must remain safe.
        if(context.pending)check(context.drain()==E_ABORT,"revoked edit after owner release");
        check(manager.refs==1 && manager.document.refs==1 && context.refs==1 && sink.refs==1,"COM lifetime leak");
    }
    HRESULT poll(json* response=nullptr){
        BSTR out=nullptr;auto hr=value->Poll(&sink,&out);auto data=take(out);if(response)*response=data;return hr;
    }
    HRESULT wait(json* response=nullptr){
        const auto deadline=GetTickCount64()+7000;HRESULT hr;
        do{hr=poll(response);if(hr!=E_PENDING)return hr;Sleep(1);}while(GetTickCount64()<deadline);
        throw std::runtime_error("route deadline");
    }
    HRESULT start(Peer& peer){BSTR out=nullptr;auto hr=value->Connect(peer.pipe.c_str(),peer.pid,image().c_str(),&out);take(out);return hr;}
    void connect(Peer& peer){check(start(peer)==E_PENDING && wait()==S_OK,"async open");}
    HRESULT action(){BSTR out=nullptr;auto hr=value->Action(R"({"kind":"select","candidateId":"candidate","revision":1})",&out);take(out);return hr;}
    void queued(){
        const auto deadline=GetTickCount64()+5000;
        while(!context.pending){check(poll()==E_PENDING,"action did not queue");check(GetTickCount64()<deadline,"edit queue deadline");Sleep(1);}
        check(context.writes==0 && context.text.empty(),"queued is not applied");
        check(poll()==E_PENDING,"TF_S_ASYNC reported applied before DoEditSession");
    }
    void awayBack(){
        value->FocusChanged(nullptr);value->FocusChanged(&manager.document);
    }
};
void heartbeat(Route& route){
    MSG message{};PeekMessageW(&message,nullptr,0,0,PM_NOREMOVE);
    check(PostThreadMessageW(GetCurrentThreadId(),WM_APP+42,0,0),"post STA heartbeat");
    check(PeekMessageW(&message,nullptr,WM_APP+42,WM_APP+42,PM_REMOVE),"STA heartbeat starved");
    check(route.poll()==E_PENDING,"response gate did not keep operation pending");
    check(route.action()==HRESULT_FROM_WIN32(ERROR_BUSY),"second action must be rejected, not queued");
}
void delayed(const wchar_t* phase,bool contextChange=false){
    Peer peer(phase);Route route;
    if(!wcscmp(phase,L"open"))check(route.start(peer)==E_PENDING,"open must return before reply");
    else{route.connect(peer);check(route.action()==E_PENDING,"action must return before reply");}
    peer.gate();heartbeat(route);
    if(contextChange){route.value->ContextChanged(nullptr);route.value->ContextChanged(&route.context);}
    else route.awayBack();
    SetEvent(peer.release.value);json result;
    check(route.wait(&result)==E_ABORT && result.at("outcome")=="failed" && !result.at("retryAllowed").get<bool>(),"away-back must revoke pending response");
    check(route.context.requests==0 && route.context.writes==0,"revoked response queued a write");
    route.close();peer.finish();
}
void commit(const wchar_t* scenario){
    Peer peer(scenario);Route route;route.connect(peer);
    if(!wcscmp(scenario,L"write-failed"))route.context.writeResult=E_ACCESSDENIED;
    if(!wcscmp(scenario,L"queue-failed"))route.context.requestResult=E_ACCESSDENIED;
    check(route.action()==E_PENDING,"select start");
    const bool failed=!wcscmp(scenario,L"write-failed") || !wcscmp(scenario,L"queue-failed");
    if(wcscmp(scenario,L"queue-failed")){
        route.queued();check(WaitForSingleObject(peer.completed.value,0)==WAIT_TIMEOUT,"completion sent before write");
        check(route.context.drain()==(failed?E_ACCESSDENIED:S_OK),"DoEditSession result");
    }
    json result;const auto hr=route.wait(&result);
    check(WaitForSingleObject(peer.completed.value,0)==WAIT_OBJECT_0,"no complete request observed");
    if(!wcscmp(scenario,L"ack-lost")){
        check(hr==E_ABORT && result.at("outcome")=="unknown" && result.at("localEditOutcome")=="applied" && result.at("retryAllowed")==false,"lost ACK must stay unknown and forbid replay");
        check(route.action()==E_ABORT,"lost ACK permitted replay");
    }else if(failed){
        check(hr==E_ABORT && result.at("receipt").at("outcome")=="unknown","failed edit must never report applied");
    }else check(hr==S_OK && result.at("receipt").at("outcome")=="applied","completed actual edit not applied");
    check(route.context.writes==(failed?0u:1u) && route.context.text==(failed?L"":L"one-write"),"independent text/write count");
    check(route.poll()==S_FALSE && route.context.writes==(failed?0u:1u),"completion replayed");
    route.close();peer.finish();
}
void queuedRevoked(bool releaseOwner){
    Peer peer(L"normal");Route route;route.connect(peer);check(route.action()==E_PENDING,"select start");route.queued();
    route.awayBack();
    if(releaseOwner){route.close();}
    else{
        json response;check(route.poll(&response)==E_ABORT && response.at("outcome")=="unknown","queued revocation must be conservative");
        check(route.start(peer)==HRESULT_FROM_WIN32(ERROR_BUSY),"rebind while old edit still queued");
        check(route.context.drain()==E_ABORT && route.context.writes==0,"old edit survived away/back");
        // New generation can start only after old completion, against new peer.
        peer.finish();Peer next(L"normal");route.connect(next);
        check(route.action()==E_PENDING,"new generation action");route.queued();
        check(route.context.drain()==S_OK && route.wait()==S_OK && route.context.writes==1,"fresh generation blocked or corrupted");
        route.close();next.finish();
    }
    check(WaitForSingleObject(peer.completed.value,0)==WAIT_TIMEOUT,"revoked edit sent applied receipt");
    if(releaseOwner)peer.finish();
}
void destroyPending(){
    Peer peer(L"open");Route route;check(route.start(peer)==E_PENDING,"pending open start");peer.gate();
    route.close();peer.finish(); // transport outlives route and drains safely
}
void standardFrame(){
    // Exercise the shared framing API with its original, null-cancel argument.
    Peer peer(L"normal");Handle pipe(INVALID_HANDLE_VALUE);
    const auto deadline=GetTickCount64()+5000;
    do{
        pipe.value=CreateFileW(peer.pipe.c_str(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,
            yime::experiment::BrokerPipeClientOpenFlags(),nullptr);
        if(pipe.value!=INVALID_HANDLE_VALUE)break;
        Sleep(1);
    }while(GetTickCount64()<deadline);
    check(pipe.value!=INVALID_HANDLE_VALUE,"standard frame connection");
    const std::string request=R"({"operation":"open","sequence":1,"focus":{"context":"synthetic","epoch":1}})";
    std::string response,error;
    check(yime::experiment::ExchangeBrokerPipeFrame(pipe.value,5000,request,&response,&error),"default framing regression");
    check(json::parse(response).at("ok")==true,"default framing response");
    CloseHandle(pipe.value);pipe.value=INVALID_HANDLE_VALUE;peer.finish();
}
}
int wmain(int argc,wchar_t** argv){
    try{
        if(argc==4 && !wcscmp(argv[1],L"--broker"))return broker(argv[2],argv[3]);
        check(argc==1,"unexpected test arguments");
        delayed(L"open");std::cout<<"PASS pending open: STA heartbeat and away/back revocation\n";
        delayed(L"action");std::cout<<"PASS pending action: STA heartbeat and away/back revocation\n";
        delayed(L"action",true);std::cout<<"PASS pending action: context replacement revocation\n";
        commit(L"normal");std::cout<<"PASS queued edit: actual callback before applied receipt, one write\n";
        commit(L"ack-lost");std::cout<<"PASS write then lost ACK: unknown, applied locally, replay rejected\n";
        commit(L"write-failed");std::cout<<"PASS failed write: no applied receipt, no text mutation\n";
        commit(L"queue-failed");std::cout<<"PASS failed edit request: no fabricated callback or write\n";
        queuedRevoked(false);std::cout<<"PASS queued revocation: old guard denies, later generation succeeds\n";
        queuedRevoked(true);std::cout<<"PASS queued edit lifetime after owner release\n";
        destroyPending();std::cout<<"PASS transport lifetime after pending route destruction\n";
        standardFrame();std::cout<<"PASS shared framing with original null-cancel argument\n";
        std::cout<<"11 scenarios passed; real pipes, substitute TSF; no registration or native-host acceptance\n";return 0;
    }catch(const std::exception& error){std::cerr<<error.what()<<'\n';return 1;}
}
