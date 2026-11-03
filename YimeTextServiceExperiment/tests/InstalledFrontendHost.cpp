// Reuse the registered native host's activation and independent TSF reader.
// This entry never calls ConnectDedicated/ActionDedicated/PollDedicated.
#define YIME_TOUCH_FRONTEND_HOST 1
#include "Formal18uHost.cpp"
#include <filesystem>

namespace {
class Seed final:public ITfEditSession{
 std::atomic<ULONG>refs_{1};ComPtr<ITfContext>context_;std::wstring text_;
public:
 Seed(ITfContext*c,std::wstring text):context_(c),text_(std::move(text)){}
 STDMETHODIMP QueryInterface(REFIID id,void**out)override{if(!out)return E_POINTER;*out=nullptr;if(id!=IID_IUnknown&&id!=__uuidof(ITfEditSession))return E_NOINTERFACE;*out=static_cast<ITfEditSession*>(this);AddRef();return S_OK;}
 STDMETHODIMP_(ULONG) AddRef()override{return ++refs_;}STDMETHODIMP_(ULONG) Release()override{auto n=--refs_;if(!n)delete this;return n;}
 STDMETHODIMP DoEditSession(TfEditCookie cookie)override{ComPtr<ITfInsertAtSelection> insertion;HRESULT hr=context_.As(&insertion);ComPtr<ITfRange>range;if(SUCCEEDED(hr))hr=insertion->InsertTextAtSelection(cookie,0,text_.data(),static_cast<LONG>(text_.size()),&range);if(SUCCEEDED(hr)&&range){hr=range->Collapse(cookie,TF_ANCHOR_END);TF_SELECTION s{};s.range=range.Get();s.style.ase=TF_AE_NONE;if(SUCCEEDED(hr))hr=context_->SetSelection(cookie,1,&s);}return hr;}
};
void seed(ITfContext*c,TfClientId client,const wchar_t*text){ComPtr<Seed>s;s.Attach(new Seed(c,text));HRESULT result=E_FAIL;require(c->RequestEditSession(client,s.Get(),TF_ES_SYNC|TF_ES_READWRITE,&result),"seed request");require(result,"seed edit");}
void pump(){MSG m;while(PeekMessageW(&m,nullptr,0,0,PM_REMOVE)){if(m.message==WM_QUIT)fail("host quit");TranslateMessage(&m);DispatchMessageW(&m);}}
struct GUI{
 HANDLE process=nullptr,output=nullptr,input=nullptr;
 ~GUI(){if(process){if(WaitForSingleObject(process,0)!=WAIT_OBJECT_0){TerminateProcess(process,8);WaitForSingleObject(process,5000);}CloseHandle(process);}if(output)CloseHandle(output);if(input)CloseHandle(input);}
 void start(const json&config){
  SECURITY_ATTRIBUTES sa{sizeof(sa),nullptr,TRUE};HANDLE childIn=nullptr,childOut=nullptr;
  if(!CreatePipe(&childIn,&input,&sa,0)||!CreatePipe(&output,&childOut,&sa,0))winFail("frontend pipes");
  SetHandleInformation(input,HANDLE_FLAG_INHERIT,0);SetHandleInformation(output,HANDLE_FLAG_INHERIT,0);
  const auto root=widen(config.at("installRoot").get<std::string>()),exe=(std::filesystem::path(root)/L"bin"/L"YimeTouchKeyboard.exe").wstring();
  const auto hash=widen(config.at("manifestSHA256").get<std::string>());if(hash.size()!=64||hash.find_first_not_of(L"0123456789abcdef")!=std::wstring::npos)fail("manifest hash");
  std::wstring command=L"\""+exe+L"\" --installed-tsf --installed-smoke --install-root \""+root+L"\" --manifest-sha256 "+hash+L" --broker-pid "+std::to_wstring(config.at("brokerPID").get<DWORD>());
  STARTUPINFOW start{};start.cb=sizeof(start);start.dwFlags=STARTF_USESTDHANDLES;start.hStdInput=childIn;start.hStdOutput=childOut;start.hStdError=childOut;PROCESS_INFORMATION pi{};
  const BOOL ok=CreateProcessW(exe.c_str(),command.data(),nullptr,nullptr,TRUE,CREATE_NO_WINDOW,nullptr,root.c_str(),&start,&pi);
  CloseHandle(childIn);CloseHandle(childOut);if(!ok)winFail("start installed frontend");process=pi.hProcess;CloseHandle(pi.hThread);
 }
 json next(){std::string line;const auto deadline=GetTickCount64()+95000;while(GetTickCount64()<deadline){pump();DWORD bytes=0;if(!PeekNamedPipe(output,nullptr,0,nullptr,&bytes,nullptr))winFail("frontend output closed");if(bytes){char c=0;DWORD n=0;if(!ReadFile(output,&c,1,&n,nullptr)||n!=1)winFail("frontend read");if(c=='\n')return json::parse(line);line+=c;if(line.size()>65536)fail("frontend output bound");}else{if(WaitForSingleObject(process,0)==WAIT_OBJECT_0)fail("frontend exited before result");MsgWaitForMultipleObjectsEx(0,nullptr,5,QS_ALLINPUT,MWMO_INPUTAVAILABLE);}}fail("frontend deadline");}
 void proceed(){const char reply[]="{\"proceed\":true}\n";DWORD n=0;if(!WriteFile(input,reply,sizeof(reply)-1,&n,nullptr)||n!=sizeof(reply)-1)winFail("frontend checkpoint ack");}
};
}
int main(){try{
 Apartment apartment;const auto config=input();Host host;host.initialize(widen(config.at("dll").get<std::string>()));
 seed(host.context.Get(),host.client,L"KEEP|");seed(host.otherContext.Get(),host.client,L"OTHER|");
 GUI gui;gui.start(config);std::wstring expected=L"KEEP|";unsigned checkpoints=0;std::vector<std::string> names{"preedit","candidate","english-literal","host-edit","cancel","focus-cancel"};
 auto first=gui.next();if(first.value("name","")!="ready"||read(host.context.Get(),host.client)!=expected)fail("frontend ready");gui.proceed();
 for(const auto mode:{"full","variable","shorthand"})for(const auto&name:names){
  const auto step=gui.next();if(step.value("stage","")!="checkpoint"||step.value("name","")!=name||step.value("mode","")!=mode)fail("frontend ordered checkpoint");
  const auto code=widen(step.at("code").get<std::string>());if(code.empty()||code.size()>4)fail("canonical code bound");
  if(name=="candidate")expected+=L"你";else if(name=="english-literal")expected+=L"x7";else if(name=="host-edit"){if(expected.size()<2)fail("edit expectation");expected.resize(expected.size()-2);expected+=L"Z";}
  const auto actual=read(host.context.Get(),host.client);
  if(name=="preedit"){if(actual!=expected+code)fail("real preedit readback");}
  else if(name=="focus-cancel"){
   if(actual!=expected+code)fail("focus preedit readback");require(host.manager->SetFocus(host.other.Get()),"focus other context");const auto deadline=GetTickCount64()+5000;
   while(read(host.context.Get(),host.client)!=expected&&GetTickCount64()<deadline){pump();Sleep(5);}if(read(host.context.Get(),host.client)!=expected)fail("focus cancellation removed confirmed or preserved preedit");
   require(host.manager->SetFocus(host.document.Get()),"restore primary context");
  }else if(actual!=expected)fail("actual TSF checkpoint readback");
  if(read(host.otherContext.Get(),host.client)!=L"OTHER|")fail("foreign context changed");++checkpoints;gui.proceed();
 }
 const auto result=gui.next();if(!result.value("ok",false)||result.value("sendInput",true)||result.value("physicalAcceptance",true))fail("frontend final evidence");
 const auto deadline=GetTickCount64()+5000;while(WaitForSingleObject(gui.process,0)!=WAIT_OBJECT_0&&GetTickCount64()<deadline){pump();Sleep(5);}DWORD exit=1;if(!GetExitCodeProcess(gui.process,&exit)||exit!=0)fail("frontend exit");
 std::cout<<json{{"stage","result"},{"ok",true},{"registered",true},{"activationIdentity","windows-activated-profile"},{"actualDLLLoaded",true},{"frontendPipeChain",true},{"checkpoints",checkpoints},{"preeditReadback",true},{"threeModes",true},{"hostEditing",true},{"focusCancellation",true},{"nonCompositionProtected",true},{"sendInput",false},{"physicalAcceptance",false}}.dump()<<std::endl;return 0;
 }catch(const GateFailure&failure){diagnostic(failure);return 1;}catch(...){diagnostic({"frontend unexpected","exception",0});return 1;}}
