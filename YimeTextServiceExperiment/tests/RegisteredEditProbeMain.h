#pragma once
#include "DedicatedTouchService.h"
#include "RegisteredEditEvidence.h"
#include <atomic>
// Included only in the separately named, default-OFF disposable registration
// gate. It uses Transaction's manager/context and never constructs a TIP.
namespace {
std::wstring editWide(const std::string& text){
 const int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),nullptr,0);
 require(n>0,"edit-utf8");std::wstring out(n,L'\0');
 require(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),out.data(),n)==n,"edit-utf8");return out;
}
json editInput(){
 std::string line;char c=0;
 while(std::cin.get(c)&&c!='\n'){require(line.size()<16384,"edit-input-bound");line+=c;}
 require(!line.empty(),"edit-input-missing");return json::parse(line);
}
json editReply(BSTR value){
 struct Free{BSTR value;~Free(){SysFreeString(value);}} free{value};
 require(value!=nullptr,"edit-reply-missing");
 const int n=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,SysStringLen(value),nullptr,0,nullptr,nullptr);
 require(n>0 && n<=65536,"edit-reply-bound");std::string text(n,'\0');
 require(WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,SysStringLen(value),text.data(),n,nullptr,nullptr)==n,"edit-reply-utf8");
 return json::parse(text);
}
HRESULT editAwait(IDedicatedTouchService* route,HRESULT hr,BSTR* reply,DWORD timeout){
 const auto deadline=GetTickCount64()+timeout;
 while(hr==E_PENDING){
  MSG message{};
  while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)){
   if(message.message==WM_QUIT){route->DisconnectDedicated();return E_ABORT;}
   TranslateMessage(&message);DispatchMessageW(&message);
  }
  if(GetTickCount64()>=deadline){route->DisconnectDedicated();return HRESULT_FROM_WIN32(ERROR_TIMEOUT);}
  hr=route->PollDedicated(reply);
  if(hr==E_PENDING)MsgWaitForMultipleObjectsEx(0,nullptr,5,QS_ALLINPUT,MWMO_INPUTAVAILABLE);
 }
 return hr==S_FALSE?E_UNEXPECTED:hr;
}
class EditReader final : public ITfEditSession {
 std::atomic<ULONG> refs_{1};ComPtr<ITfContext> context_;
public:
 std::wstring text;bool completed=false;
 explicit EditReader(ITfContext* context):context_(context){}
 STDMETHODIMP QueryInterface(REFIID iid,void** out) override {
  if(!out)return E_POINTER;*out=nullptr;if(iid!=IID_IUnknown && iid!=__uuidof(ITfEditSession))return E_NOINTERFACE;
  *out=static_cast<ITfEditSession*>(this);AddRef();return S_OK;
 }
 STDMETHODIMP_(ULONG) AddRef() override{return ++refs_;}
 STDMETHODIMP_(ULONG) Release() override{auto n=--refs_;if(!n)delete this;return n;}
 STDMETHODIMP DoEditSession(TfEditCookie cookie) override{
  completed=true;ComPtr<ITfRange> begin,end;
  HRESULT hr=context_->GetStart(cookie,&begin);if(SUCCEEDED(hr))hr=context_->GetEnd(cookie,&end);
  if(SUCCEEDED(hr))hr=begin->ShiftEndToRange(cookie,end.Get(),TF_ANCHOR_END);
  wchar_t value[3]{};ULONG count=0;
  if(SUCCEEDED(hr))hr=begin->GetText(cookie,0,value,3,&count);
  if(SUCCEEDED(hr))text.assign(value,count);return hr;
 }
};
std::wstring editRead(Transaction& transaction){
 ComPtr<EditReader> reader;reader.Attach(new EditReader(transaction.context.Get()));HRESULT result=E_FAIL;
 check(transaction.context->RequestEditSession(transaction.editClient,reader.Get(),TF_ES_SYNC|TF_ES_READ,&result),"edit-read-request");
 check(result,"edit-read-result");require(reader->completed,"edit-read-not-completed");return reader->text;
}
json editAction(IDedicatedTouchService* route,const json& request,bool* pending=nullptr){
 BSTR value=nullptr;const auto body=request.dump();HRESULT hr=route->ActionDedicated(body.c_str(),&value);
 if(pending)*pending=hr==E_PENDING && value==nullptr;
 hr=editAwait(route,hr,&value,15000);
 if(hr!=S_OK){if(value)SysFreeString(value);check(hr,"edit-action-result");}
 return editReply(value);
}
}
int wmain(int argc,wchar_t** argv){
 // A new explicit gate; the previous registration commands do not opt into it.
 if(argc!=6 || wcscmp(argv[1],L"--dll") || wcscmp(argv[3],L"--ledger") ||
    wcscmp(argv[5],L"--confirm-once-registered-edit"))return 3;
 const HRESULT initialized=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
 if(FAILED(initialized))return 3;
 int exit=1;
 {
  struct Module{HMODULE value=nullptr;~Module(){if(value)FreeLibrary(value);}} module;
  Transaction transaction;Ledger ledger;transaction.ledger=&ledger;
  ComPtr<ITfFunctionProvider> provider;ComPtr<IDedicatedTouchService> route;
  yime::registered_edit::Evidence proof;
  bool attached=false,readback=false,pending=false,applied=false,revoked=false,absent=false;
  const char* stage="completed";HRESULT code=S_OK;
  const DWORD owner=GetCurrentProcessId();DWORD brokerTarget=0;
  try{
   const auto config=editInput();
   require(config.is_object() && config.size()==6 && config.at("scenario")=="commit" &&
       editWide(config.at("dll").get<std::string>())==argv[2],"edit-configuration");
   const auto pipe=editWide(config.at("pipe").get<std::string>());
   const auto brokerImage=editWide(config.at("brokerImage").get<std::string>());
   require(config.at("brokerPID").is_number_unsigned() && config.at("brokerPID").get<uint64_t>()>0 &&
       config.at("brokerPID").get<uint64_t>()<=MAXDWORD,"edit-broker-pid");
   const DWORD brokerPID=config.at("brokerPID").get<DWORD>();
   require(brokerPID!=owner && std::filesystem::path(brokerImage).is_absolute(),"edit-broker-target");
   const auto inputCode=config.at("code").get<std::string>();
   require(!inputCode.empty() && inputCode.size()<=32,"edit-code-bound");
   module.value=LoadLibraryExW(argv[2],nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
   require(module.value!=nullptr,"edit-load-expected-dll");
   ledger.create(argv[4],argv[2]);
   transaction.run(argv[2]); // Registration and Windows activation stay alive.
   brokerTarget=owner;require(proof.registered(owner,brokerTarget),"edit-registration-order");
   check(transaction.manager->GetFunctionProvider(CLSID_YimeTextServiceExperiment,&provider),"edit-activated-provider");
   GUID type{};check(provider->GetType(&type),"edit-provider-type");
   require(IsEqualGUID(type,CLSID_YimeTextServiceExperiment),"edit-provider-identity");
   ComPtr<IUnknown> function;
   check(provider->GetFunction(GUID_NULL,__uuidof(IDedicatedTouchService),&function),"edit-activated-route");
   check(function.As(&route),"edit-route-interface");
   ComPtr<IUnknown> providerIdentity,routeIdentity;
   check(provider.As(&providerIdentity),"edit-provider-iunknown");check(route.As(&routeIdentity),"edit-route-iunknown");
   require(providerIdentity.Get()==routeIdentity.Get(),"edit-same-activated-instance");
   HMODULE actual=nullptr;const auto address=(*reinterpret_cast<void***>(route.Get()))[0];
   require(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(address),&actual) && actual==module.value,"edit-activated-dll-mismatch");
   attached=true;require(proof.attached(attached),"edit-attach-order");
   require(editRead(transaction).empty(),"edit-initial-document-not-empty");
   BSTR initial=nullptr;
   HRESULT hr=route->ConnectDedicated(pipe.c_str(),brokerPID,brokerImage.c_str(),&initial);
   hr=editAwait(route.Get(),hr,&initial,95000);
   if(hr!=S_OK){if(initial)SysFreeString(initial);check(hr,"edit-broker-connect");}
   auto state=editReply(initial);require(state.value("ok",false),"edit-broker-open-rejected");
   require(proof.connected(),"edit-connect-order");
   std::cout<<json{{"stage","connected"},{"accepted",true}}.dump()<<std::endl;
   require(editInput().value("proceed",false),"edit-control");
   state=editAction(route.Get(),{{"kind","input"},{"code",inputCode},{"revision",state.at("snapshot").at("revision")}});
   require(state.value("ok",false),"edit-input-rejected");
   json candidate;
   for(const auto& c:state.at("snapshot").at("state").at("candidates"))if(c.at("text")=="你"){candidate=c;break;}
   require(!candidate.is_null(),"edit-canonical-candidate-missing");
   require(proof.issue(),"edit-single-selection");
   state=editAction(route.Get(),{{"kind","select"},{"candidateId",candidate.at("id")},{"revision",state.at("snapshot").at("revision")}},&pending);
   applied=state.value("ok",false) && state.contains("receipt") && state.at("receipt").at("outcome")=="applied";
   require(pending && proof.completed(applied),"edit-actual-completion");
   readback=editRead(transaction)==L"你";require(proof.readback(readback),"edit-independent-readback");
  }catch(const Failure& failure){proof.fail();stage=failure.stage;code=failure.code;}catch(...){proof.fail();stage="edit-exception";code=E_FAIL;}
  // No new activation, selection, host, or replay is attempted on failure.
  if(route)route->DisconnectDedicated();
  try{transaction.cleanup();}catch(const Failure& failure){transaction.cleanupCheck(failure.code,failure.stage);}catch(...){transaction.cleanupCheck(E_FAIL,"edit-cleanup-exception");}
  if(provider){
   ComPtr<IUnknown> stale;
   revoked=provider->GetFunction(GUID_NULL,__uuidof(IDedicatedTouchService),&stale)==TF_E_DISCONNECTED && !stale;
  }
  proof.revoked(revoked);
  if(transaction.cleanupOK){
   try{
    transaction.initialize();registryAbsent();apiAbsent(transaction.languages.Get(),transaction.profiles.Get(),transaction.categories.Get());
    absent=true;
    if(!ledger.data.empty())ledger.mark("cleanupVerified");
   }catch(const Failure& failure){transaction.cleanupCheck(failure.code,failure.stage);}catch(...){transaction.cleanupCheck(E_FAIL,"edit-absence-check");}
  }
  proof.absent(absent && transaction.cleanupOK);
  const bool passed=proof.passed();
  if(!passed && code==S_OK){stage="edit-lifecycle-incomplete";code=E_FAIL;}
  auto report=json{{"schema","18u-same-process-registered-edit-v1"},{"stage","result"},{"scenario","commit"},{"status",passed?"pass":"failed"},
   {"activationIdentity","windows-activated-profile"},{"windowsActivatedInstance",attached},{"sendInput",false},
   {"operationPendingObserved",pending},{"editAttempts",proof.attempts()},{"appliedReceipt",applied},{"readbackMatches",readback},
   {"registrationOwnerPID",owner},{"brokerTargetPID",brokerTarget},{"registrationLifecycleOwned",transaction.writes&&transaction.comOwned},
   {"cleanupVerified",absent&&transaction.cleanupOK},{"routeRevoked",revoked}};
  if(!passed)std::cerr<<json{{"stage",stage},{"code",static_cast<unsigned long>(code)},
    {"cleanupStage",transaction.cleanupStage},{"cleanupCode",static_cast<unsigned long>(transaction.cleanupCode)}}.dump()<<std::endl;
  std::cout<<report.dump()<<std::endl;exit=passed?0:1;
  route.Reset();provider.Reset();
 }
 CoUninitialize();return exit;
}
