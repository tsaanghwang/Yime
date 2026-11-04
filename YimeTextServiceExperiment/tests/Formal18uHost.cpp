// S3c.1 isolated CI gate: loads the actual independent TextService DLL.
// A separately named, default-OFF target uses an already registered profile.
// Neither target registers/enables profiles or changes the default input method.
// No registration, external target, arbitrary text commit, or SendInput.
// Never run on a user PC; ActivateEx flags do not sandbox asynchronous TIPs.
#include <windows.h>
#include <msctf.h>
#include <oleauto.h>
#include <wrl/client.h>
#include <nlohmann/json.hpp>
#include <atomic>
#include <functional>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include "DedicatedTouchService.h"
#include "ActionFailureObservation.h"
#include "FormalInputSequence.h"
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
yimeactionfailure::Field actionFailureField(const json& response,const char* key){
 using namespace yimeactionfailure;
 const auto found=response.find(key);if(found==response.end())return {};
 if(found->is_null())return {Type::Null,false,{}};
 if(found->is_boolean())return {Type::Boolean,found->get<bool>(),{}};
 if(found->is_string())return {Type::String,false,found->get_ref<const json::string_t&>()};
 if(found->is_number())return {Type::Number,false,{}};
 if(found->is_array())return {Type::Array,false,{}};
 return {Type::Object,false,{}};
}
void actionFailureObservation(HRESULT hr,yimeactionfailure::Action action,bool quit,
                              const json* state,yimeactionfailure::Response responseKind) noexcept {
 try {
  yimeactionfailure::Evidence evidence; evidence.hresult=static_cast<uint32_t>(hr);
  evidence.action=action;evidence.wmQuit=quit;evidence.response=responseKind;
  if(state&&state->is_object()){
   evidence.ok=actionFailureField(*state,"ok");evidence.outcome=actionFailureField(*state,"outcome");
   evidence.localEditOutcome=actionFailureField(*state,"localEditOutcome");evidence.retryAllowed=actionFailureField(*state,"retryAllowed");
  }
  yimeactionfailure::Emit(evidence,[](const std::string& text){std::cerr<<text;});
 }catch(...){/* Observation/formatting cannot hide the original action HRESULT. */}
}
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
// Compare the file Windows actually loaded, without loading the expected path.
// The expected-file handle also prevents replacement during activation/checking.
struct ExpectedModule {
 HANDLE file=INVALID_HANDLE_VALUE;
 explicit ExpectedModule(const std::wstring& path){
  file=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
  if(file==INVALID_HANDLE_VALUE)winFail("open expected DLL identity");
 }
 ~ExpectedModule(){if(file!=INVALID_HANDLE_VALUE)CloseHandle(file);}
 ExpectedModule(const ExpectedModule&)=delete;
 ExpectedModule& operator=(const ExpectedModule&)=delete;
 bool matches(HMODULE actual)const{
  wchar_t path[32768]{};const DWORD n=GetModuleFileNameW(actual,path,static_cast<DWORD>(std::size(path)));
  if(!n||n>=std::size(path))winFail("loaded DLL path");
  HANDLE loaded=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
  if(loaded==INVALID_HANDLE_VALUE)winFail("open loaded DLL identity");
  BY_HANDLE_FILE_INFORMATION expected{},observed{};
  const BOOL first=GetFileInformationByHandle(file,&expected);const DWORD firstError=first?ERROR_SUCCESS:GetLastError();
  const BOOL second=GetFileInformationByHandle(loaded,&observed);const DWORD secondError=second?ERROR_SUCCESS:GetLastError();
  CloseHandle(loaded);
  if(!first||!second)throw GateFailure{"loaded DLL file identity","win32",!first?firstError:secondError};
  return expected.dwVolumeSerialNumber==observed.dwVolumeSerialNumber&&expected.nFileIndexHigh==observed.nFileIndexHigh&&expected.nFileIndexLow==observed.nFileIndexLow;
 }
};
void requireColdModule(const std::wstring& path){
 if(GetModuleHandleW(path.c_str()))fail("registered DLL already loaded before activation");
}
// Inert Win32 regression: no TIP, profile, window, or installed product is used.
void moduleIdentityContract(){
 HMODULE system=GetModuleHandleW(L"ntdll.dll"),different=GetModuleHandleW(L"kernel32.dll");
 if(!system||!different||system==different)fail("module contract system modules");
 wchar_t path[32768]{};const DWORD n=GetModuleFileNameW(system,path,static_cast<DWORD>(std::size(path)));
 if(!n||n>=std::size(path))winFail("module contract system path");
 ExpectedModule expected(path);
 if(!expected.matches(system)||expected.matches(different))fail("module contract identity mismatch");
 bool rejected=false;try{requireColdModule(path);}catch(const GateFailure&failure){rejected=std::string(failure.stage)=="registered DLL already loaded before activation";}
 if(!rejected)fail("module contract accepted warm module");
 HMODULE pinned=nullptr;
 if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,reinterpret_cast<LPCWSTR>(system),&pinned))winFail("module contract pin");
 const bool matches=expected.matches(pinned);FreeLibrary(pinned);
 if(!matches)fail("module contract pinned identity");
 std::cout<<json{{"stage","module-identity-contract"},{"ok",true},{"sameFileAccepted",true},{"differentFileRejected",true},{"warmModuleRejected",true},{"ownedPinReleased",true},{"productActivated",false}}.dump()<<std::endl;
}
struct Host {
 bool lastAwaitWmQuit=false; // Diagnostic only; never gates input or focus.
 ComPtr<ITfThreadMgr> manager;ComPtr<ITfDocumentMgr> document,other;ComPtr<ITfContext> context,otherContext;
 ComPtr<ITfTextInputProcessorEx> tip;ComPtr<IDedicatedTouchService> route;TfClientId client=TF_CLIENTID_NULL;
 HMODULE module=nullptr;HWND window=nullptr;bool managerActive=false,tipActive=false;
#ifdef YIME_TOUCH_REGISTERED_FORMAL_HOST
 ComPtr<ITfInputProcessorProfileMgr> profiles;
 static constexpr bool registered=true;
#else
 static constexpr bool registered=false;
#endif
  void initialize(const std::wstring& dll,bool traceCold=false){
  if(GetEnvironmentVariableW(L"YIME_TEXTSERVICE_EXPERIMENT_DIRECT_TEST",nullptr,0))fail("direct test bypass forbidden");
#ifdef YIME_TOUCH_REGISTERED_FORMAL_HOST
  ExpectedModule expected(dll);requireColdModule(dll);
  if(traceCold)std::cout<<json{{"stage","registered-cold-initial"},{"expectedDLLLoaded",false},{"preloadedByHost",false}}.dump()<<std::endl;
#else
  (void)traceCold;
  module=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);if(!module)winFail("load dedicated DLL");
  auto entry=reinterpret_cast<HRESULT(STDAPICALLTYPE*)(REFCLSID,REFIID,LPVOID*)>(GetProcAddress(module,"DllGetClassObject"));if(!entry)winFail("class factory export");
  ComPtr<IClassFactory> factory;require(entry(CLSID_YimeTextServiceExperiment,IID_IClassFactory,reinterpret_cast<void**>(factory.GetAddressOf())),"dedicated class factory");
  require(factory->CreateInstance(nullptr,__uuidof(ITfTextInputProcessorEx),reinterpret_cast<void**>(tip.GetAddressOf())),"actual TIP instance");
#endif
  require(CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,__uuidof(ITfThreadMgr),reinterpret_cast<void**>(manager.GetAddressOf())),"thread manager");
  ComPtr<ITfThreadMgrEx> extended;require(manager.As(&extended),"extended manager");require(extended->ActivateEx(&client,TF_TMAE_NOACTIVATETIP|TF_TMAE_NOACTIVATEKEYBOARDLAYOUT),"own manager activate");managerActive=true;
  // Direct-load component adapter only: use the actually activated host client.
  // GetClientId(new CLSID) is not a Windows-activated text-service identity.
  // Keep real AdviseKeyEventSink active; do not set DIRECT_TEST or register a TIP.
  create(document,context);create(other,otherContext);
  window=CreateWindowExW(0,L"STATIC",L"Isolated 18u formal host gate",WS_OVERLAPPEDWINDOW,40,40,400,120,nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
  if(!window)winFail("own foreground window");
  ComPtr<ITfDocumentMgr> previous;require(manager->AssociateFocus(window,document.Get(),&previous),"associate own window");
  ShowWindow(window,SW_SHOWNORMAL);SetForegroundWindow(window);::SetFocus(window);
  if(GetForegroundWindow()!=window)fail("own foreground not granted; no bypass");
  require(manager->SetFocus(document.Get()),"own focus");
#ifdef YIME_TOUCH_REGISTERED_FORMAL_HOST
  require(CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles)),"registered profile manager");
  ComPtr<ITfInputProcessorProfiles> languages;require(profiles.As(&languages),"registered language manager");
  LANGID language=0;require(languages->GetCurrentLanguage(&language),"registered current language");
  if(language!=0x0804 || LOWORD(reinterpret_cast<ULONG_PTR>(GetKeyboardLayout(0)))!=0x0804)fail("registered language precondition");
  BOOL enabled=FALSE;require(languages->IsEnabledLanguageProfile(CLSID_YimeTextServiceExperiment,0x0804,GUID_YimeTextServiceExperimentProfile,&enabled),"registered profile query");
  if(!enabled)fail("registered profile disabled");
  // NOACTIVATETIP suppresses activation only during ActivateEx; Windows may
  // activate the current TIP asynchronously when this thread gains focus.
  // That is a legitimate cold load after our initial guard, not host preload.
  const bool loadedDuringWindowsSetup=GetModuleHandleW(dll.c_str())!=nullptr;
  if(traceCold)std::cout<<json{{"stage","registered-cold-before-activation"},{"expectedDLLLoaded",loadedDuringWindowsSetup},{"preloadedByHost",false},{"registeredProfileEnabled",true}}.dump()<<std::endl;
  // Exactly one process-scoped activation. This does not register or enable it.
  const HRESULT activated=profiles->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,0x0804,CLSID_YimeTextServiceExperiment,GUID_YimeTextServiceExperimentProfile,nullptr,TF_IPPMF_FORPROCESS);
  if(traceCold)std::cout<<json{{"stage","registered-cold-activation"},{"hresult",static_cast<unsigned long>(activated)}}.dump()<<std::endl;
  require(activated,"registered profile activation");if(activated!=S_OK)fail("registered profile activation incomplete");tipActive=true;
  ComPtr<ITfFunctionProvider> provider;
  const ULONGLONG deadline=GetTickCount64()+1000;
  do {
   MSG message{};while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)){TranslateMessage(&message);DispatchMessageW(&message);}
   if(manager->GetFunctionProvider(CLSID_YimeTextServiceExperiment,&provider)==S_OK && provider)break;
   provider.Reset();Sleep(10);
  }while(GetTickCount64()<deadline);
  if(!provider)fail("registered provider unavailable");
  TF_INPUTPROCESSORPROFILE active{};require(profiles->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD,&active),"registered active profile");
  if(active.dwProfileType!=TF_PROFILETYPE_INPUTPROCESSOR || active.langid!=0x0804 || !IsEqualGUID(active.clsid,CLSID_YimeTextServiceExperiment) || !IsEqualGUID(active.guidProfile,GUID_YimeTextServiceExperimentProfile))fail("registered profile mismatch");
  GUID providerType{};require(provider->GetType(&providerType),"registered provider type");
  if(!IsEqualGUID(providerType,CLSID_YimeTextServiceExperiment))fail("registered provider mismatch");
  ComPtr<IUnknown> function;require(provider->GetFunction(GUID_NULL,__uuidof(IDedicatedTouchService),&function),"registered route lookup");
  require(function.As(&route),"dedicated private interface");require(route.As(&tip),"registered TIP interface");
  // Pin the Windows-activated module only now. Host owns this additional reference
  // until every TSF/COM reference has been released; no LoadLibrary in this path.
  const auto address=(*reinterpret_cast<void***>(route.Get()))[0];
  if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,reinterpret_cast<LPCWSTR>(address),&module))winFail("pin registered DLL");
  if(!expected.matches(module))fail("registered DLL mismatch");
  if(traceCold)std::cout<<json{{"stage","registered-cold-module-verified"},{"profileMatches",true},{"providerMatches",true},{"actualDLLFileMatches",true},{"preloadedByHost",false}}.dump()<<std::endl;
#else
  require(tip->ActivateEx(manager.Get(),client,0),"actual TIP activation");tipActive=true;require(tip.As(&route),"dedicated private interface");
#endif
 }
 HRESULT deactivate(){
  if(!tipActive)return S_OK;
#ifdef YIME_TOUCH_REGISTERED_FORMAL_HOST
  const HRESULT hr=profiles->DeactivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,0x0804,CLSID_YimeTextServiceExperiment,GUID_YimeTextServiceExperimentProfile,nullptr,TF_IPPMF_FORPROCESS);
#else
  const HRESULT hr=tip->Deactivate();
#endif
  if(hr==S_OK){tipActive=false;return S_OK;}
  return FAILED(hr)?hr:E_FAIL;
 }
 void create(ComPtr<ITfDocumentMgr>& doc,ComPtr<ITfContext>& ctx){TfEditCookie cookie=0;require(manager->CreateDocumentMgr(&doc),"document");require(doc->CreateContext(client,0,nullptr,&ctx,&cookie),"context");require(doc->Push(ctx.Get()),"push");}
  ~Host(){if(route)route->DisconnectDedicated();route.Reset();if(tipActive)deactivate();tip.Reset();if(window){ComPtr<ITfDocumentMgr> previous;manager->AssociateFocus(window,nullptr,&previous);DestroyWindow(window);}context.Reset();otherContext.Reset();document.Reset();other.Reset();if(managerActive)manager->Deactivate();manager.Reset();
#ifdef YIME_TOUCH_REGISTERED_FORMAL_HOST
   profiles.Reset();
#endif
   if(module)FreeLibrary(module);}
 HRESULT awaitResult(HRESULT hr,BSTR* value,DWORD timeout=15000,const std::function<void()>& beforePoll={}){
  lastAwaitWmQuit=false;
  const auto deadline=GetTickCount64()+timeout;
  while(hr==E_PENDING){
   MSG message;while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)){
    if(message.message==WM_QUIT){lastAwaitWmQuit=true;route->DisconnectDedicated();return E_ABORT;}
    TranslateMessage(&message);DispatchMessageW(&message);
   }
   if(GetTickCount64()>=deadline){route->DisconnectDedicated();return HRESULT_FROM_WIN32(ERROR_TIMEOUT);}
   if(beforePoll)beforePoll();
   hr=route->PollDedicated(value);
   if(hr==E_PENDING)MsgWaitForMultipleObjectsEx(0,nullptr,5,QS_ALLINPUT,MWMO_INPUTAVAILABLE);
  }
  // S_FALSE is not a completed operation. Never replay a lost operation.
  return hr==S_FALSE?E_UNEXPECTED:hr;
 }
 json action(const json& request,HRESULT& hr,yimeactionfailure::Action kind){
  BSTR value=nullptr;const auto body=request.dump();hr=awaitResult(route->ActionDedicated(body.c_str(),&value),&value);
  if(FAILED(hr)){
   if(!value){actionFailureObservation(hr,kind,lastAwaitWmQuit,nullptr,yimeactionfailure::Response::Missing);return json::object();}
   json state;
   try{state=response(value);}catch(...){
    actionFailureObservation(hr,kind,lastAwaitWmQuit,nullptr,yimeactionfailure::Response::Malformed);
    require(hr,kind==yimeactionfailure::Action::Input?"engine input":"actual edit and completion"); // Preserve the original HRESULT, not a parser exception.
   }
   actionFailureObservation(hr,kind,lastAwaitWmQuit,&state,state.is_object()?yimeactionfailure::Response::Object:yimeactionfailure::Response::NonObject);
   return state;
  }
  if(!value)return json::object();return response(value);
 }
};
}
#ifndef YIME_TOUCH_FRONTEND_HOST
int main(int argc,char**argv){try{
 if(argc==2&&std::string(argv[1])=="--module-identity-contract"){moduleIdentityContract();return 0;}
 if(argc!=1)fail("arguments");
 auto config=input();const std::string scenario=config.at("scenario");
#ifdef YIME_TOUCH_REGISTERED_FORMAL_HOST
 if(scenario=="activation-only"){
  const auto dll=widen(config.at("dll").get<std::string>());
  {
   Apartment apartment;Host host;host.initialize(dll,true);
   if(!read(host.context.Get(),host.client).empty()||!read(host.otherContext.Get(),host.client).empty())fail("activation-only document not empty");
   const HRESULT deactivated=host.deactivate();
   std::cout<<json{{"stage","registered-cold-deactivation"},{"hresult",static_cast<unsigned long>(deactivated)}}.dump()<<std::endl;
   require(deactivated,"activation-only deactivation");
  }
  std::cout<<json{{"stage","result"},{"scenario","activation-only"},{"ok",true},{"registered",true},{"coldLoadVerified",true},{"preloadedByHost",false},{"hostReferencesReleased",true},{"ownDocumentsEmpty",true},{"textActions",0},{"newBrokerOrFrontend",false},{"registrationMutation",false},{"sendInput",false}}.dump()<<std::endl;return 0;
 }
#endif
 if(scenario!="commit"&&scenario!="duplicate"&&scenario!="wrong-server-pid"&&scenario!="wrong-server-image"&&scenario!="deactivated"&&scenario!="focus-lost"&&scenario!="disconnect-before-action"&&scenario!="pending-focus-away-back"&&scenario!="pending-deactivated"&&scenario!="disconnect-after-edit")fail("scenario");
 Apartment apartment;
 Host host;host.initialize(widen(config.at("dll").get<std::string>()));
 DWORD pid=config.at("brokerPID");if(scenario=="wrong-server-pid")pid=GetCurrentProcessId();
 BSTR initial=nullptr;HRESULT hr=host.route->ConnectDedicated(widen(config.at("pipe").get<std::string>()).c_str(),pid,widen(config.at(scenario=="wrong-server-image"?"dll":"brokerImage").get<std::string>()).c_str(),&initial);
 hr=host.awaitResult(hr,&initial,95000);
 json state=initial?response(initial):json::object();bool connected=hr==S_OK;
 std::cout<<json{{"stage","connected"},{"accepted",connected}}.dump()<<std::endl;
 if(!input().value("proceed",false))fail("control");
 bool rejected=false,duplicateRejected=false,readMatches=false;std::string outcome="not-applied";
 bool pendingObserved=false,postWriteDisconnect=false,replayRejected=false;
 if(scenario=="wrong-server-pid"||scenario=="wrong-server-image"){
  if(connected)fail("wrong server accepted");rejected=true;
 }else{
  require(hr,"connect actual Broker");if(!state.value("ok",false))fail("open rejected");
  const auto code=config.at("code").get<std::string>();
  if(code.empty() || code.size()>16)fail("canonical input bound");
  json request={{"kind","input"},{"code",code.substr(0,1)},{"revision",state.at("snapshot").at("revision")}};
  if(scenario=="deactivated")require(host.deactivate(),"deactivate actual TIP");
  if(scenario=="disconnect-before-action"||scenario=="deactivated"){
   state=host.action(request,hr,yimeactionfailure::Action::Input);rejected=FAILED(hr)||!state.value("ok",false);if(!rejected)fail("disconnected action accepted");
  }else{
   state=FormalInputSequence(code,std::move(state),[&](const json& key){
    auto next=host.action(key,hr,yimeactionfailure::Action::Input);
    require(hr,"engine input");return next;
   });
   json selected;for(const auto& c:state.at("snapshot").at("state").at("candidates")){if(c.at("text").get<std::string>()=="你"){selected=c;break;}}
   if(selected.is_null())fail("canonical ni candidate missing");
   request={{"kind","select"},{"candidateId",selected.at("id")},{"revision",state.at("snapshot").at("revision")}};
   if(scenario=="focus-lost")require(host.manager->SetFocus(host.other.Get()),"change own focus");
   if(scenario=="pending-focus-away-back" || scenario=="pending-deactivated" || scenario=="disconnect-after-edit"){
    BSTR value=nullptr;const auto body=request.dump();
    hr=host.route->ActionDedicated(body.c_str(),&value);
    pendingObserved=hr==E_PENDING && value==nullptr;
    if(!pendingObserved){if(value)SysFreeString(value);fail("action did not become pending");}
    if(scenario=="pending-focus-away-back"){
     require(host.manager->SetFocus(host.other.Get()),"change own focus");
     require(host.manager->SetFocus(host.document.Get()),"restore own focus");
    }
    if(scenario=="pending-deactivated")require(host.deactivate(),"deactivate actual TIP");
    const auto beforePoll=[&]{
     if(scenario!="disconnect-after-edit" || postWriteDisconnect)return;
     const auto text=read(host.context.Get(),host.client);
     if(text.empty())return;
     if(text!=L"你")fail("independent readback mismatch");
     // Test controller barrier only. The real edit has completed; Poll has
     // not yet sent completion to the broker. Never invent an Applied receipt.
     std::cout<<json{{"stage","edit-written"},{"readbackMatches",true},{"operationPending",true}}.dump()<<std::endl;
     if(!input().value("brokerStopped",false))fail("post-write disconnect control");
     postWriteDisconnect=true;
    };
    hr=host.awaitResult(hr,&value,15000,beforePoll);
    state=value?response(value):json::object();
   }else state=host.action(request,hr,yimeactionfailure::Action::Select);
   if(scenario=="focus-lost" || scenario=="pending-focus-away-back" || scenario=="pending-deactivated"){
    rejected=FAILED(hr)||!state.value("ok",false);if(!rejected)fail("stale focus accepted");
   }else if(scenario=="disconnect-after-edit"){
    if(!postWriteDisconnect || !FAILED(hr) || state.value("ok",true) ||
       state.value("outcome","")!="unknown" || state.value("localEditOutcome","")!="applied" ||
       state.value("retryAllowed",true))fail("lost completion not unknown");
    outcome="unknown";
    readMatches=read(host.context.Get(),host.client)==L"你";
    if(!readMatches)fail("independent readback mismatch");
    auto again=host.action(request,hr,yimeactionfailure::Action::Select);
    replayRejected=FAILED(hr) && !again.value("ok",false);
    if(!replayRejected || read(host.context.Get(),host.client)!=L"你")fail("unknown outcome replayed");
   }else{
    require(hr,"actual edit and completion");if(!state.value("ok",false)||!state.contains("receipt"))fail("missing actual receipt");
    outcome=state.at("receipt").at("outcome").get<std::string>();if(outcome!="applied")fail("not actually applied");
    readMatches=read(host.context.Get(),host.client)==L"你";if(!readMatches)fail("independent readback mismatch");
    if(scenario=="duplicate"){
     auto again=host.action(request,hr,yimeactionfailure::Action::Select);duplicateRejected=FAILED(hr)||!again.value("ok",false);if(!duplicateRejected||read(host.context.Get(),host.client)!=L"你")fail("duplicate rewrote");
    }
   }
  }
 }
 bool empty=read(host.context.Get(),host.client).empty(),otherEmpty=read(host.otherContext.Get(),host.client).empty();
 if(rejected&&(!empty||!otherEmpty))fail("rejected operation wrote");
 require(host.deactivate(),"deactivate actual TIP");
 std::cout<<json{{"stage","result"},{"scenario",scenario},{"actualDLLLoaded",true},{"activationIdentity",Host::registered?"windows-activated-profile":"owned-host-activation-client"},{"registered",Host::registered},{"sendInput",false},{"outcome",outcome},{"rejected",rejected},{"duplicateRejected",duplicateRejected},{"readbackMatches",readMatches},{"readbackEmpty",empty},{"otherContextEmpty",otherEmpty},{"unknownAfterPendingEditCovered",postWriteDisconnect},{"operationPendingObserved",pendingObserved},{"postWriteDisconnectObserved",postWriteDisconnect},{"replayRejected",replayRejected}}.dump()<<std::endl;return 0;
 }catch(const GateFailure& failure){diagnostic(failure);return 1;}catch(...){diagnostic({"unexpected","exception",0});return 1;}}
#endif
