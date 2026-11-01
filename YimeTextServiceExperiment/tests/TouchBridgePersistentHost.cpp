// S3a isolated CI fixture: one parent-owned anonymous pipe, one persistent own
// TSF text context. No registration, external HWND, SendInput, or listening IPC.
// Synchronous edits only here; S2b independently verifies real asynchronous edits.
// ActivateEx suppresses activation at this call, not forever: never run on a user PC.
#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include <nlohmann/json.hpp>
#include <atomic>
#include <cstdint>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string>
#include "CompositionEditSession.h"
using Microsoft::WRL::ComPtr;
using nlohmann::json;
using namespace yime::experiment;
namespace {
void require(HRESULT hr,const char* what){if(FAILED(hr))throw std::runtime_error(what);}
std::wstring widen(const std::string& value){
    const int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0);
    if(n<=0)throw std::runtime_error("invalid UTF-8");
    std::wstring result(static_cast<size_t>(n),L'\0');
    if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),result.data(),n)!=n)
        throw std::runtime_error("UTF-8 conversion failed");
    return result;
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
        if(SUCCEEDED(hr))hr=begin->GetText(cookie,0,buffer,1025,&n);
        if(SUCCEEDED(hr) && n>1024)return E_BOUNDS;
        if(SUCCEEDED(hr))text.assign(buffer,n);
        return hr;
    }
};
std::wstring read(ITfContext* context,TfClientId client){
    ComPtr<Reader> reader;reader.Attach(new Reader(context));HRESULT edit=E_FAIL;
    require(context->RequestEditSession(client,reader.Get(),TF_ES_SYNC|TF_ES_READ,&edit),"request read");
    require(edit,"read edit");if(!reader->completed)throw std::runtime_error("read not completed");
    return reader->text;
}

struct Apartment {
    Apartment(){require(CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED),"initialize COM");}
    ~Apartment(){CoUninitialize();}
};
struct Host final : IBrokerEditExecutionGuard {
    std::atomic<ULONG> refs{1};
    ComPtr<ITfThreadMgr> manager;
    ComPtr<ITfDocumentMgr> document,other;
    ComPtr<ITfContext> context,otherContext;
    ComPtr<Sink> sink;
    TfClientId client=TF_CLIENTID_NULL;
    bool active=false,bound=true,completed=false;
    uint64_t epoch=1,requestEpoch=0;
    HRESULT completionResult=E_FAIL;
    unsigned checks=0,callbacks=0,edits=0;
    std::wstring expected;
    std::set<std::string> ids;
    void initialize(){
        require(CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,
            __uuidof(ITfThreadMgr),reinterpret_cast<void**>(manager.GetAddressOf())),"create thread manager");
        ComPtr<ITfThreadMgrEx> extended;require(manager.As(&extended),"extended manager");
        require(extended->ActivateEx(&client,TF_TMAE_NOACTIVATETIP|TF_TMAE_NOACTIVATEKEYBOARDLAYOUT),"activate own manager");active=true;
        create(document,context);create(other,otherContext);
        require(manager->SetFocus(document.Get()),"focus own document");sink.Attach(new Sink);
    }
    void create(ComPtr<ITfDocumentMgr>& doc,ComPtr<ITfContext>& ctx){
        TfEditCookie cookie=0;require(manager->CreateDocumentMgr(&doc),"create own document");
        require(doc->CreateContext(client,0,nullptr,&ctx,&cookie),"create own context");
        require(doc->Push(ctx.Get()),"push own context");
    }
    ~Host(){if(active)manager->Deactivate();}
    STDMETHODIMP QueryInterface(REFIID iid,void** out) override{
        if(!out)return E_POINTER;*out=nullptr;
        if(iid!=IID_IUnknown)return E_NOINTERFACE;
        *out=static_cast<IBrokerEditExecutionGuard*>(this);AddRef();return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override{return ++refs;}
    STDMETHODIMP_(ULONG) Release() override{ULONG n=--refs;if(!n)delete this;return n;}
    HRESULT ValidateExecution(ITfContext* actual) noexcept override{
        ++checks;ComPtr<ITfDocumentMgr> focus;
        if(!bound || requestEpoch!=epoch || actual!=context.Get() ||
           FAILED(manager->GetFocus(&focus)) || focus.Get()!=document.Get())return E_ABORT;
        return S_OK;
    }
    static void completion(void* opaque,ITfContext* actual,const BrokerUpdate&,HRESULT result) noexcept{
        auto* h=static_cast<Host*>(opaque);++h->callbacks;h->completed=true;
        h->completionResult=actual==h->context.Get()?result:E_UNEXPECTED;
    }
    void verify(){
        if(read(context.Get(),client)!=expected || !read(otherContext.Get(),client).empty())
            throw std::runtime_error("independent readback mismatch; stop without replay");
    }
    void commit(const std::string& id,const std::string& text){
        if(!bound || id.empty() || id.size()>256 || text.empty() || text.size()>1024 || edits>=16 || !ids.insert(id).second)
            throw std::runtime_error("invalid or duplicate commit");
        const auto wide=widen(text);
        if(expected.size()+wide.size()>1024)throw std::runtime_error("own text limit");
        requestEpoch=epoch;completed=false;completionResult=E_FAIL;checks=callbacks=0;
        BrokerUpdate update;update.commit=text;
        ITfComposition* composition=nullptr;bool ending=false;
        ++edits;
        const HRESULT hr=ApplyBrokerUpdateToContext(context.Get(),client,sink.Get(),&composition,&ending,
            update,nullptr,nullptr,false,completion,this,this);
        if(composition)composition->Release();
        if(hr!=S_OK || !completed || completionResult!=S_OK || callbacks!=1 || checks!=1)
            throw std::runtime_error("commit outcome unknown; stop without replay");
        expected+=wide;verify();
    }
    void close(){
        verify();require(document->Pop(TF_POPF_ALL),"pop own context");
        require(other->Pop(TF_POPF_ALL),"pop other context");
        require(manager->Deactivate(),"deactivate manager");active=false;
    }
};
std::string frame(){
    std::string line;char ch=0;
    while(std::cin.get(ch)){
        if(ch=='\n')return line;
        if(line.size()>=16384)throw std::runtime_error("request frame limit");
        line+=ch;
    }
    throw std::runtime_error("pipe disconnected without close; no replay");
}
void nativeGate(){
    using Query=BOOL(WINAPI*)(HANDLE,USHORT*,USHORT*);
    auto query=reinterpret_cast<Query>(GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"IsWow64Process2"));
    USHORT process=0,native=0;
    if(!query || !query(GetCurrentProcess(),&process,&native) || process!=IMAGE_FILE_MACHINE_UNKNOWN || native!=IMAGE_FILE_MACHINE_AMD64)
        throw std::runtime_error("native Windows x64 required");
    // PIPE type rejects consoles/files, but does not authenticate the parent or
    // prove anonymity. Trust here comes from the CI parent creating both pipes
    // and launching this exact fixture; this is not a public IPC security gate.
    if(GetFileType(GetStdHandle(STD_INPUT_HANDLE))!=FILE_TYPE_PIPE || GetFileType(GetStdHandle(STD_OUTPUT_HANDLE))!=FILE_TYPE_PIPE)
        throw std::runtime_error("pipe handles required");
}
}
int main(){
    try{
        nativeGate();Apartment apartment;ComPtr<Host> host;
        for(uint64_t sequence=1;sequence<=64;++sequence){
            const auto request=json::parse(frame());
            if(!request.is_object() || !request.contains("seq") || !request.at("seq").is_number_unsigned() ||
               request.at("seq").get<uint64_t>()!=sequence || !request.contains("epoch") || !request.at("epoch").is_number_unsigned() ||
               !request.contains("op") || !request.at("op").is_string())throw std::runtime_error("invalid request envelope");
            const auto op=request.at("op").get<std::string>();
            const auto epoch=request.at("epoch").get<uint64_t>();
            if(request.size()!=(op=="commit"?5u:3u))throw std::runtime_error("unexpected request fields");
            bool callback=false;std::string outcome;
            if(!host){
                if(op!="init" || epoch!=0 || sequence!=1)throw std::runtime_error("init required");
                host.Attach(new Host);host->initialize();host->verify();
            }else{
                if(epoch!=host->epoch)throw std::runtime_error("stale epoch");
                if(op=="commit"){
                    host->commit(request.at("id").get<std::string>(),request.at("text").get<std::string>());
                    callback=host->completed;outcome="applied";
                }else if(op=="invalidate"){
                    if(!host->bound)throw std::runtime_error("already invalidated");
                    host->bound=false;require(host->manager->SetFocus(host->other.Get()),"invalidate own focus");host->verify();
                }else if(op=="rebind"){
                    if(host->bound)throw std::runtime_error("invalidate before rebind");
                    require(host->manager->SetFocus(host->document.Get()),"restore own focus");
                    ++host->epoch;host->bound=true;host->verify();
                }else if(op=="read")host->verify();
                else if(op=="close")host->close();
                else throw std::runtime_error("unsupported operation");
            }
            std::cout<<json{{"seq",sequence},{"op",op},{"epoch",host->epoch},{"context","own-test-host"},
                {"ok",true},{"outcome",outcome},{"readbackMatch",true},{"totalUTF16Units",host->expected.size()},
                {"callbackSeen",callback}}.dump()<<std::endl;
            if(!std::cout)throw std::runtime_error("response pipe failed; no replay");
            if(op=="close")return 0;
        }
        throw std::runtime_error("request count limit");
    }catch(const json::exception&){
        // Parser diagnostics may contain a fragment of input text; never log it.
        std::cerr<<"persistent own TSF test failed: invalid JSON protocol\n";return 1;
    }catch(const std::exception& e){std::cerr<<"persistent own TSF test failed: "<<e.what()<<'\n';return 1;}
}
