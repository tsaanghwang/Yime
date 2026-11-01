// S3c.1 isolated CI gate: loads the actual independent TextService DLL.
// No registration, external target, arbitrary text commit, or SendInput.
// Never run on a user PC; ActivateEx flags do not sandbox asynchronous TIPs.
#include <windows.h>
#include <msctf.h>
#include <oleauto.h>
#include <wrl/client.h>
#include <nlohmann/json.hpp>
#include <atomic>
#include <iostream>
#include <stdexcept>
#include <string>
#include "DedicatedTouchService.h"
#include "YimeTextServiceIds.h"
using Microsoft::WRL::ComPtr;
using nlohmann::json;
namespace {
// Only source-defined labels and numeric status codes cross the diagnostic boundary.
struct GateFailure { const char* stage; const char* kind; unsigned long code; };
[[noreturn]] void fail(const char* stage){throw GateFailure{stage,"assertion",0};}
[[noreturn]] void winFail(const char* stage){const DWORD error=GetLastError();throw GateFailure{stage,"win32",error};}
void require(HRESULT hr,const char* operation){if(FAILED(hr))throw GateFailure{operation,"hresult",static_cast<unsigned long>(hr)};}
void diagnostic(const GateFailure& failure){std::cerr<<json{{"stage",failure.stage},{"kind",failure.kind},{"code",failure.code}}.dump()<<std::endl;}
std::wstring widen(const std::string& value){
 int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0);
 if(n<=0)fail("invalid UTF8");std::wstring out(n,L'\0');
 if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),out.data(),n)!=n)fail("UTF8 conversion");return out;
}
std::string narrow(BSTR value){
 if(!value)return "";int n=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,SysStringLen(value),nullptr,0,nullptr,nullptr);
 if(n<=0)fail("invalid response");std::string out(n,'\0');
 WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,SysStringLen(value),out.data(),n,nullptr,nullptr);return out;
}
json input(){std::string line;char ch;while(std::cin.get(ch)&&ch!='\n'){if(line.size()>=65536)fail("input bound");line+=ch;}if(line.empty())fail("missing input");return json::parse(line);}
json response(BSTR value){try{auto r=json::parse(narrow(value));SysFreeString(value);return r;}catch(...){SysFreeString(value);throw;}}
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
    require(edit,"read edit");if(!reader->completed)fail("read not completed");
    return reader->text;
}

struct Apartment {
    Apartment(){require(CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED),"initialize COM");}
    ~Apartment(){CoUninitialize();}
};
struct Host {
 ComPtr<ITfThreadMgr> manager;ComPtr<ITfDocumentMgr> document,other;ComPtr<ITfContext> context,otherContext;
 ComPtr<ITfTextInputProcessorEx> tip;ComPtr<IDedicatedTouchService> route;TfClientId client=TF_CLIENTID_NULL;
 HMODULE module=nullptr;HWND window=nullptr;bool managerActive=false,tipActive=false;
 void initialize(const std::wstring& dll){
  module=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);if(!module)winFail("load dedicated DLL");
  auto entry=reinterpret_cast<HRESULT(STDAPICALLTYPE*)(REFCLSID,REFIID,LPVOID*)>(GetProcAddress(module,"DllGetClassObject"));if(!entry)winFail("class factory export");
  ComPtr<IClassFactory> factory;require(entry(CLSID_YimeTextServiceExperiment,IID_IClassFactory,reinterpret_cast<void**>(factory.GetAddressOf())),"dedicated class factory");
  require(factory->CreateInstance(nullptr,__uuidof(ITfTextInputProcessorEx),reinterpret_cast<void**>(tip.GetAddressOf())),"actual TIP instance");
  require(CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,__uuidof(ITfThreadMgr),reinterpret_cast<void**>(manager.GetAddressOf())),"thread manager");
  ComPtr<ITfThreadMgrEx> extended;require(manager.As(&extended),"extended manager");require(extended->ActivateEx(&client,TF_TMAE_NOACTIVATETIP|TF_TMAE_NOACTIVATEKEYBOARDLAYOUT),"own manager activate");managerActive=true;
  // The host owns the documents; the actual TIP uses its distinct CLSID client ID.
  ComPtr<ITfClientId> clientIds;require(manager.As(&clientIds),"query service client IDs");
  TfClientId serviceClientId=TF_CLIENTID_NULL;require(clientIds->GetClientId(CLSID_YimeTextServiceExperiment,&serviceClientId),"allocate dedicated service client ID");
  create(document,context);create(other,otherContext);
  window=CreateWindowExW(0,L"STATIC",L"Isolated 18u formal host gate",WS_OVERLAPPEDWINDOW,40,40,400,120,nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
  if(!window)winFail("own foreground window");
  ComPtr<ITfDocumentMgr> previous;require(manager->AssociateFocus(window,document.Get(),&previous),"associate own window");
  ShowWindow(window,SW_SHOWNORMAL);SetForegroundWindow(window);::SetFocus(window);
  if(GetForegroundWindow()!=window)fail("own foreground not granted; no bypass");
  require(manager->SetFocus(document.Get()),"own focus");
  require(tip->ActivateEx(manager.Get(),serviceClientId,0),"actual TIP activation");tipActive=true;require(tip.As(&route),"dedicated private interface");
 }
 void create(ComPtr<ITfDocumentMgr>& doc,ComPtr<ITfContext>& ctx){TfEditCookie cookie=0;require(manager->CreateDocumentMgr(&doc),"document");require(doc->CreateContext(client,0,nullptr,&ctx,&cookie),"context");require(doc->Push(ctx.Get()),"push");}
 ~Host(){if(route)route->DisconnectDedicated();route.Reset();if(tipActive)tip->Deactivate();tip.Reset();if(window){ComPtr<ITfDocumentMgr> previous;manager->AssociateFocus(window,nullptr,&previous);DestroyWindow(window);}context.Reset();otherContext.Reset();document.Reset();other.Reset();if(managerActive)manager->Deactivate();manager.Reset();if(module)FreeLibrary(module);}
 json action(const json& request,HRESULT& hr){BSTR value=nullptr;const auto body=request.dump();hr=route->ActionDedicated(body.c_str(),&value);if(!value)return json::object();return response(value);}
};
}
int main(){try{
 Apartment apartment;auto config=input();const std::string scenario=config.at("scenario");
 if(scenario!="commit"&&scenario!="duplicate"&&scenario!="wrong-server-pid"&&scenario!="wrong-server-image"&&scenario!="deactivated"&&scenario!="focus-lost"&&scenario!="disconnect-before-action")fail("scenario");
 Host host;host.initialize(widen(config.at("dll").get<std::string>()));
 DWORD pid=config.at("brokerPID");if(scenario=="wrong-server-pid")pid=GetCurrentProcessId();
 BSTR initial=nullptr;HRESULT hr=host.route->ConnectDedicated(widen(config.at("pipe").get<std::string>()).c_str(),pid,widen(config.at(scenario=="wrong-server-image"?"dll":"brokerImage").get<std::string>()).c_str(),&initial);
 json state=initial?response(initial):json::object();bool connected=SUCCEEDED(hr);
 std::cout<<json{{"stage","connected"},{"accepted",connected}}.dump()<<std::endl;
 if(!input().value("proceed",false))fail("control");
 bool rejected=false,duplicateRejected=false,readMatches=false;std::string outcome="not-applied";
 if(scenario=="wrong-server-pid"||scenario=="wrong-server-image"){
  if(connected)fail("wrong server accepted");rejected=true;
 }else{
  require(hr,"connect actual Broker");if(!state.value("ok",false))fail("open rejected");
  auto revision=state.at("snapshot").at("revision");
  json request={{"kind","input"},{"code",config.at("code")},{"revision",revision}};
  if(scenario=="deactivated"){require(host.tip->Deactivate(),"deactivate actual TIP");host.tipActive=false;}
  if(scenario=="disconnect-before-action"||scenario=="deactivated"){
   state=host.action(request,hr);rejected=FAILED(hr)||!state.value("ok",false);if(!rejected)fail("disconnected action accepted");
  }else{
   state=host.action(request,hr);require(hr,"engine input");if(!state.value("ok",false))fail("engine rejected input");
   json selected;for(const auto& c:state.at("snapshot").at("state").at("candidates")){if(c.at("text").get<std::string>()=="你"){selected=c;break;}}
   if(selected.is_null())fail("canonical ni candidate missing");
   request={{"kind","select"},{"candidateId",selected.at("id")},{"revision",state.at("snapshot").at("revision")}};
   if(scenario=="focus-lost")require(host.manager->SetFocus(host.other.Get()),"change own focus");
   state=host.action(request,hr);
   if(scenario=="focus-lost"){
    rejected=FAILED(hr)||!state.value("ok",false);if(!rejected)fail("stale focus accepted");
   }else{
    require(hr,"actual edit and completion");if(!state.value("ok",false)||!state.contains("receipt"))fail("missing actual receipt");
    outcome=state.at("receipt").at("outcome").get<std::string>();if(outcome!="applied")fail("not actually applied");
    readMatches=read(host.context.Get(),host.client)==L"你";if(!readMatches)fail("independent readback mismatch");
    if(scenario=="duplicate"){
     auto again=host.action(request,hr);duplicateRejected=FAILED(hr)||!again.value("ok",false);if(!duplicateRejected||read(host.context.Get(),host.client)!=L"你")fail("duplicate rewrote");
    }
   }
  }
 }
 bool empty=read(host.context.Get(),host.client).empty(),otherEmpty=read(host.otherContext.Get(),host.client).empty();
 if(rejected&&(!empty||!otherEmpty))fail("rejected operation wrote");
 std::cout<<json{{"stage","result"},{"scenario",scenario},{"actualDLLLoaded",true},{"registered",false},{"sendInput",false},{"outcome",outcome},{"rejected",rejected},{"duplicateRejected",duplicateRejected},{"readbackMatches",readMatches},{"readbackEmpty",empty},{"otherContextEmpty",otherEmpty},{"unknownAfterPendingEditCovered",false}}.dump()<<std::endl;return 0;
 }catch(const GateFailure& failure){diagnostic(failure);return 1;}catch(...){diagnostic({"unexpected","exception",0});return 1;}}
