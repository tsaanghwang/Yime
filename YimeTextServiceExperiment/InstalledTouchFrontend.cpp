#include "InstalledTouchFrontend.h"
#include "DedicatedTouchRoute.h"
#include <nlohmann/json.hpp>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <wrl/client.h>
using json=nlohmann::json;
namespace {
constexpr wchar_t kClass[]=L"Yime18uInstalledSTA.v2";
std::string utf8(BSTR value){if(!value)return {};const int n=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,SysStringLen(value),nullptr,0,nullptr,nullptr);if(n<=0)return {};std::string s(n,'\0');WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,SysStringLen(value),s.data(),n,nullptr,nullptr);return s;}
}
InstalledTouchFrontend::InstalledTouchFrontend(ITfThreadMgr*m,TfClientId client,ITfCompositionSink*owner):manager_(m),client_(client),owner_(owner),thread_(GetCurrentThreadId()){}
InstalledTouchFrontend* InstalledTouchFrontend::Create(ITfThreadMgr*m,TfClientId client,ITfCompositionSink*owner)noexcept{
    try{auto item=std::unique_ptr<InstalledTouchFrontend>(new InstalledTouchFrontend(m,client,owner));if(!item->Start())return nullptr;return item.release();}catch(...){return nullptr;}
}
bool InstalledTouchFrontend::Start(){
    HMODULE module=nullptr;if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(&WindowProc),&module))return false;
    wchar_t path[32768];const DWORD n=GetModuleFileNameW(module,path,32768);if(!n||n>=32768)return false;
    const auto root=std::filesystem::path(path).parent_path().parent_path();
    // Historical controlled-host and loose test DLLs never start this adapter.
    std::ifstream file(root/L"installed-18u-product.json");if(!file)return false;json manifest;file>>manifest;
    if(manifest.value("schema","")!="installed-18u-product-v2"||manifest.value("product","")!="yimecore-18u")return false;
    broker_=(root/L"bin"/L"YimeBroker18u.exe").wstring();
    DWORD session=0;if(!ProcessIdToSessionId(GetCurrentProcessId(),&session))return false;
    base_=L"\\\\.\\pipe\\YimeBroker.18uTouch.v1.desktop-"+std::to_wstring(session);
    WNDCLASSW wc{};wc.hInstance=module;wc.lpszClassName=kClass;wc.lpfnWndProc=WindowProc;
    if(!RegisterClassW(&wc)&&GetLastError()!=ERROR_CLASS_ALREADY_EXISTS)return false;
    window_=CreateWindowExW(0,kClass,L"",0,0,0,0,0,HWND_MESSAGE,nullptr,module,this);if(!window_)return false;
    route_=new DedicatedTouchRoute(manager_,client_);
    return SetTimer(window_,1,20,nullptr)!=0;
}
InstalledTouchFrontend::~InstalledTouchFrontend(){
    Revoke();if(window_){SetWindowLongPtrW(window_,GWLP_USERDATA,0);KillTimer(window_,1);DestroyWindow(window_);window_=nullptr;}
    if(route_)route_->Release();
}
void InstalledTouchFrontend::Focus(bool value)noexcept{if(!value)Revoke();focused_=value;}
HRESULT InstalledTouchFrontend::CompositionTerminated(TfEditCookie cookie,ITfComposition* composition)noexcept{return route_?route_->CompositionTerminated(cookie,composition):S_FALSE;}
void InstalledTouchFrontend::Revoke()noexcept{
    ++generation_;editing_=false;closing_=false;pendingBindMode_.clear();ticket_.clear();if(route_){route_->Disconnect();BSTR response=nullptr;route_->Poll(owner_,&response);if(response)SysFreeString(response);}if(relay_)relay_->Cancel();relay_.reset();work_.reset();retryAt_=GetTickCount64()+250;
}
LRESULT CALLBACK InstalledTouchFrontend::WindowProc(HWND h,UINT message,WPARAM w,LPARAM l){
    if(message==WM_NCCREATE){auto*create=reinterpret_cast<CREATESTRUCTW*>(l);SetWindowLongPtrW(h,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(create->lpCreateParams));}
    auto*self=reinterpret_cast<InstalledTouchFrontend*>(GetWindowLongPtrW(h,GWLP_USERDATA));
    if(message==WM_TIMER&&w==1&&self){self->Tick();return 0;}
    if(message==WM_NCDESTROY)SetWindowLongPtrW(h,GWLP_USERDATA,0);
    return DefWindowProcW(h,message,w,l);
}
void InstalledTouchFrontend::Next(){
    const HWND foreground=GetForegroundWindow();DWORD pid=0;const DWORD thread=GetWindowThreadProcessId(foreground,&pid);
    if(!focused_||pid!=GetCurrentProcessId()||thread!=thread_){Revoke();return;}
    Microsoft::WRL::ComPtr<ITfDocumentMgr> document;Microsoft::WRL::ComPtr<ITfContext> context;
    if(FAILED(manager_->GetFocus(&document))||!document||FAILED(document->GetTop(&context))||!context){Revoke();return;}
    const bool connect=!relay_;
    if(connect&&!WaitNamedPipeW((base_+L"-tip").c_str(),0)){retryAt_=GetTickCount64()+1000;return;}
    if(connect)relay_=std::make_shared<DedicatedBrokerTransport>(base_+L"-tip",0,broker_,true);
    work_=relay_->Start(json{{"operation","next"},{"window",reinterpret_cast<uint64_t>(foreground)},{"thread",thread_},{"generation",generation_}}.dump(),2000,connect);
}
void InstalledTouchFrontend::Complete(HRESULT hr,BSTR response){
    std::string raw=utf8(response);if(response)SysFreeString(response);
    json result;try{result=json::parse(raw);}catch(...){result={{"ok",false},{"error","TIP operation failed or completion unknown"},{"retryAllowed",false}};}
    if(FAILED(hr))result["ok"]=false;
    if(!relay_||ticket_.empty()){Revoke();return;}
    work_=relay_->Start(json{{"operation","complete"},{"ticket",ticket_},{"result",result}}.dump(),2000,false);
    ticket_.clear();editing_=false;
}
void InstalledTouchFrontend::Tick()noexcept{
    if(ticking_||GetCurrentThreadId()!=thread_)return;ticking_=true;struct Reset{bool&value;~Reset(){value=false;}}reset{ticking_};
    try{
        if(!focused_){if(relay_)Revoke();return;}
        DWORD pid=0;const DWORD t=GetWindowThreadProcessId(GetForegroundWindow(),&pid);
        if(pid!=GetCurrentProcessId()||t!=thread_){if(relay_)Revoke();return;}
        if(closing_){
            if(GetTickCount64()>=closeDeadline_){closing_=false;pendingBindMode_.clear();Complete(HRESULT_FROM_WIN32(ERROR_TIMEOUT),SysAllocString(L"{\"ok\":false,\"error\":\"previous composition cancellation still pending; no new session or input replay\",\"retryAllowed\":false}"));return;}
            const HRESULT cancelled=route_->DesktopCancellationResult();
            if(cancelled!=E_PENDING&&FAILED(cancelled)){closing_=false;pendingBindMode_.clear();Complete(cancelled,SysAllocString(L"{\"ok\":false,\"error\":\"previous composition cancellation failed; explicit rebind may retry only that original range\",\"retryAllowed\":false}"));return;}
            if(!route_->DesktopSettled())return;
            closing_=false;BSTR response=nullptr;HRESULT hr=S_OK;
            if(!pendingBindMode_.empty()){const auto mode=pendingBindMode_;pendingBindMode_.clear();hr=route_->ConnectDesktop((base_+L"-engine").c_str(),relay_->ServerPID(),broker_.c_str(),mode,&response);}
            else response=SysAllocString(L"{\"ok\":true}");
            if(hr==E_PENDING){editing_=true;return;}Complete(hr,response);return;
        }
        if(editing_){BSTR response=nullptr;const HRESULT hr=route_->Poll(owner_,&response);if(hr==E_PENDING)return;Complete(hr,response);return;}
        if(work_){
            if(!work_->done.load(std::memory_order_acquire))return;
            if(!work_->ok)throw std::runtime_error("relay closed");
            auto reply=json::parse(work_->response);work_.reset();if(!reply.value("ok",false))throw std::runtime_error("relay rejected");
            if(reply.contains("ticket")){
                ticket_=reply.at("ticket").get<std::string>();const auto operation=reply.at("operation").get<std::string>();BSTR response=nullptr;HRESULT hr=E_INVALIDARG;
                if(operation=="bind"){
                    route_->Disconnect();pendingBindMode_=reply.at("mode").get<std::string>();closing_=true;closeDeadline_=GetTickCount64()+10000;return;
                }else if(operation=="action"){const auto action=reply.at("action").dump();hr=route_->Action(action.c_str(),&response);}
                else if(operation=="close"){route_->Disconnect();closing_=true;closeDeadline_=GetTickCount64()+10000;return;}
                if(hr==E_PENDING){editing_=true;return;}Complete(hr,response);return;
            }
        }
        if(GetTickCount64()>=retryAt_)Next();
    }catch(...){Revoke();retryAt_=GetTickCount64()+1000;}
}
