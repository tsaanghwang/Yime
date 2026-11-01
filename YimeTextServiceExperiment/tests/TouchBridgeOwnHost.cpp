// Test-only process: owns every TSF document it touches; no TIP registration,
// explicit product activation, SendInput or external window access. Run only in
// an isolated Windows CI environment: ActivateEx flags suppress activation at
// this call, not every possible later TSF asynchronous activation. No pump/UI.
#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include <nlohmann/json.hpp>
#include <atomic>
#include <iostream>
#include <stdexcept>
#include <string>
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
           (scenario!="commit" && scenario!="duplicate" && scenario!="focus-lost"))
            throw std::runtime_error("invalid isolated test request");
        Apartment apartment;Manager owner;
        ComPtr<ITfDocumentMgr> document,other;
        ComPtr<ITfContext> context;TfEditCookie cookie=0;
        require(owner.manager->CreateDocumentMgr(&document),"create own document");
        require(document->CreateContext(owner.client,0,nullptr,&context,&cookie),"create own context");
        require(document->Push(context.Get()),"push own context");
        require(owner.manager->SetFocus(document.Get()),"focus own document");
        if(scenario=="focus-lost"){
            require(owner.manager->CreateDocumentMgr(&other),"create second own document");
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
        const bool accepted=applyOnce(id);
        if(scenario=="duplicate")duplicateRejected=!applyOnce(id);
        if(scenario=="focus-lost" && accepted)throw std::runtime_error("lost focus accepted");
        const std::string observed=read(context.Get(),owner.client);
        if(outcome=="applied" && observed!=text)outcome="unknown";
        if(scenario=="focus-lost" && !observed.empty())throw std::runtime_error("foreign focus wrote text");
        require(document->Pop(TF_POPF_ALL),"pop own context");
        std::cout<<json{{"id",id},{"outcome",outcome},{"readbackMatches",observed==text},{"readbackEmpty",observed.empty()},
            {"actualEditRequests",actualEdits},
            {"editCompleted",callback},{"duplicateRejected",duplicateRejected},
            {"registered",false},{"sendInput",false}}.dump()<<'\n';
        return 0;
    }catch(const std::exception& e){std::cerr<<"own TSF test failed: "<<e.what()<<'\n';return 1;}
}
