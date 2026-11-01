#include "DedicatedTouchRoute.h"
#include "TouchProductIdentity.h"
#include <algorithm>
#include <stdexcept>
#include <vector>
using Microsoft::WRL::ComPtr;
using namespace yime::experiment;
namespace {
struct Handle {HANDLE value=nullptr;~Handle(){if(value && value!=INVALID_HANDLE_VALUE)CloseHandle(value);}};
void check(bool value,const char* reason){if(!value)throw std::runtime_error(reason);}
std::vector<BYTE> tokenInfo(HANDLE token,TOKEN_INFORMATION_CLASS kind){
    DWORD size=0;GetTokenInformation(token,kind,nullptr,0,&size);check(size>0 && size<65536,"token size");
    std::vector<BYTE> bytes(size);check(GetTokenInformation(token,kind,bytes.data(),size,&size)!=FALSE,"token query");return bytes;
}
void sameOwner(HANDLE server,DWORD pid){
    DWORD a=0,b=0;check(ProcessIdToSessionId(pid,&a) && ProcessIdToSessionId(GetCurrentProcessId(),&b) && a==b,"different Windows session");
    Handle left,right;check(OpenProcessToken(server,TOKEN_QUERY,&left.value) && OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&right.value),"peer tokens");
    auto lu=tokenInfo(left.value,TokenUser),ru=tokenInfo(right.value,TokenUser);
    check(EqualSid(reinterpret_cast<TOKEN_USER*>(lu.data())->User.Sid,reinterpret_cast<TOKEN_USER*>(ru.data())->User.Sid)!=FALSE,"different SID");
    auto ls=tokenInfo(left.value,TokenStatistics),rs=tokenInfo(right.value,TokenStatistics);
    const auto l=reinterpret_cast<TOKEN_STATISTICS*>(ls.data())->AuthenticationId,r=reinterpret_cast<TOKEN_STATISTICS*>(rs.data())->AuthenticationId;
    check(l.LowPart==r.LowPart && l.HighPart==r.HighPart,"different logon identity");
}
std::wstring fullPath(LPCWSTR path){
    check(path && wcslen(path)>=3 && path[1]==L':' && (path[2]==L'\\' || path[2]==L'/'),"absolute local image required");
    wchar_t buffer[32768];const DWORD n=GetFullPathNameW(path,32768,buffer,nullptr);check(n>0 && n<32768,"image path");return {buffer,n};
}
bool unsignedValue(const nlohmann::json& value){return value.is_number_unsigned();}
}
DedicatedTouchRoute::DedicatedTouchRoute(ITfThreadMgr* manager,TfClientId client):manager_(manager),client_(client),thread_(GetCurrentThreadId()){}
DedicatedTouchRoute::~DedicatedTouchRoute(){Disconnect();}
STDMETHODIMP DedicatedTouchRoute::QueryInterface(REFIID iid,void** out){if(!out)return E_POINTER;*out=nullptr;if(iid!=IID_IUnknown)return E_NOINTERFACE;*out=static_cast<IBrokerEditExecutionGuard*>(this);AddRef();return S_OK;}
STDMETHODIMP_(ULONG) DedicatedTouchRoute::AddRef(){return ++refs_;}
STDMETHODIMP_(ULONG) DedicatedTouchRoute::Release(){auto n=--refs_;if(!n)delete this;return n;}
void DedicatedTouchRoute::Disconnect() noexcept{
    active_=false;++epoch_;
    if(pipe_!=INVALID_HANDLE_VALUE){CloseHandle(pipe_);pipe_=INVALID_HANDLE_VALUE;}
    if(server_){CloseHandle(server_);server_=nullptr;}
    session_.clear();foreground_=nullptr;document_.Reset();context_.Reset();
}
void DedicatedTouchRoute::FocusChanged(ITfDocumentMgr* document) noexcept{if(active_ && document!=document_.Get())Disconnect();}
void DedicatedTouchRoute::ContextChanged(ITfContext* context) noexcept{if(active_ && context!=context_.Get())Disconnect();}
bool DedicatedTouchRoute::SameTarget() noexcept{
    if(GetCurrentThreadId()!=thread_ || !active_ || !context_ || !document_ || !foreground_ || GetForegroundWindow()!=foreground_)return false;
    DWORD pid=0;const DWORD tid=GetWindowThreadProcessId(foreground_,&pid);
    if(tid!=thread_ || pid!=GetCurrentProcessId())return false;
    ComPtr<ITfDocumentMgr> focus;ComPtr<ITfContext> top;
    return SUCCEEDED(manager_->GetFocus(&focus)) && focus.Get()==document_.Get() &&
        SUCCEEDED(focus->GetTop(&top)) && top.Get()==context_.Get();
}
HRESULT DedicatedTouchRoute::ValidateExecution(ITfContext* context) noexcept{
    ++checks_;guardDenied_=!SameTarget() || context!=context_.Get();return guardDenied_?E_ABORT:S_OK;
}
void DedicatedTouchRoute::Completed(void* value,ITfContext* context,const BrokerUpdate&,HRESULT result) noexcept{
    auto* self=static_cast<DedicatedTouchRoute*>(value);++self->callbacks_;self->completed_=true;
    self->editResult_=context==self->context_.Get()?result:E_UNEXPECTED;
}
void DedicatedTouchRoute::Export(const json& response,BSTR* output){
    const std::string value=response.dump();check(value.size()<=65536,"response size");
    const int count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0);
    check(count>0,"response encoding");*output=SysAllocStringLen(nullptr,count);check(*output!=nullptr,"response allocation");
    if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),*output,count)!=count){SysFreeString(*output);*output=nullptr;throw std::runtime_error("response conversion");}
}
DedicatedTouchRoute::json DedicatedTouchRoute::Exchange(const char* operation,const json& extra,DWORD timeout){
    check(pipe_!=INVALID_HANDLE_VALUE && server_ && WaitForSingleObject(server_,0)==WAIT_TIMEOUT,"broker unavailable");
    check(sequence_<UINT64_MAX,"sequence exhausted");
    json request{{"version",2},{"sequence",++sequence_},{"operation",operation},{"product","YimeCore18uTouch"},{"focus",focus_}};
    if(std::string(operation)!="open"){request["sessionId"]=session_;request["identity"]=identity_;}
    for(auto it=extra.begin();it!=extra.end();++it)request[it.key()]=it.value();
    const auto frame=request.dump();check(frame.size()<=16384,"request limit");
    std::string text,error;check(ExchangeBrokerPipeFrame(pipe_,timeout,frame,&text,&error),"dedicated transport failed; no replay");
    check(text.size()<=65536,"response limit");const auto reply=json::parse(text);
    check(reply.is_object() && reply.contains("version") && unsignedValue(reply["version"]) && reply["version"]==2 &&
          reply.contains("sequence") && unsignedValue(reply["sequence"]) && reply["sequence"]==sequence_ && reply.value("ok",false),"broker rejected or malformed response");
    check(reply.at("identity")==identity_ && reply.at("focus")==focus_,"broker identity or focus mismatch");
    const auto session=reply.at("sessionId").get<std::string>();check(!session.empty() && session.size()<=256,"session missing");
    if(session_.empty())session_=session;else check(session==session_,"foreign session");
    return reply;
}
HRESULT DedicatedTouchRoute::Connect(LPCWSTR pipe,DWORD pid,LPCWSTR image,BSTR* output){
    if(!output)return E_POINTER;*output=nullptr;if(GetCurrentThreadId()!=thread_)return RPC_E_WRONG_THREAD;
    if(busy_)return E_PENDING;
    Disconnect();busy_=true;
    try{
        const std::wstring prefix=L"\\\\.\\pipe\\YimeBroker.18uTouch.v1.";
        check(pipe && std::wstring(pipe).rfind(prefix,0)==0,"dedicated local pipe required");
        const auto suffix=std::wstring(pipe).substr(prefix.size());
        check(!suffix.empty() && suffix.size()<=96 && suffix.find_first_not_of(L"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")==std::wstring::npos,"invalid dedicated pipe suffix");
        const auto expected=fullPath(image);check(pid && pid!=GetCurrentProcessId(),"expected broker PID required");
        server_=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,pid);check(server_!=nullptr,"broker process handle");
        check(WaitForSingleObject(server_,0)==WAIT_TIMEOUT,"broker process exited");
        wchar_t actual[32768];DWORD size=32768;check(QueryFullProcessImageNameW(server_,0,actual,&size)!=FALSE,"broker image query");
        check(_wcsicmp(expected.c_str(),std::wstring(actual,size).c_str())==0,"unexpected broker image");sameOwner(server_,pid);
        const ULONGLONG until=GetTickCount64()+30000;
        do{pipe_=CreateFileW(pipe,GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,BrokerPipeClientOpenFlags(),nullptr);
            if(pipe_!=INVALID_HANDLE_VALUE)break;
            const DWORD error=GetLastError();check(error==ERROR_PIPE_BUSY || error==ERROR_FILE_NOT_FOUND,"broker pipe open");Sleep(10);
        }while(GetTickCount64()<until);
        check(pipe_!=INVALID_HANDLE_VALUE,"broker pipe timeout");ULONG actualPID=0;
        check(GetNamedPipeServerProcessId(pipe_,&actualPID) && actualPID==pid,"wrong broker server PID");
        check(SUCCEEDED(manager_->GetFocus(&document_)) && document_ && SUCCEEDED(document_->GetTop(&context_)) && context_,"TIP has no own focused context");
        foreground_=GetForegroundWindow();DWORD windowPID=0;const DWORD windowThread=GetWindowThreadProcessId(foreground_,&windowPID);
        check(foreground_ && windowThread==thread_ && windowPID==GetCurrentProcessId(),"TIP host must own actual foreground thread window");
        GUID lease{};check(SUCCEEDED(CoCreateGuid(&lease)),"context lease");wchar_t leaseText[40];check(StringFromGUID2(lease,leaseText,40)>0,"lease encoding");
        std::string token;for(const wchar_t* c=leaseText;*c;++c)token.push_back(static_cast<char>(*c));
        focus_={{"context",token},{"epoch",epoch_}};identity_={{"layoutSHA256",YIME_TOUCH_LAYOUT_SHA},{"dictionarySHA256",YIME_TOUCH_DICTIONARY_SHA},{"mode","variable"},{"sessionPolicy","concept-keyboard-modes-v2+ellipsis-choice-v1"}};
        sequence_=0;active_=true;const auto response=Exchange("open",json::object(),60000);check(SameTarget(),"focus changed while opening");Export(response,output);busy_=false;return S_OK;
    }catch(...){Disconnect();busy_=false;return E_FAIL;}
}
HRESULT DedicatedTouchRoute::Action(LPCSTR action,ITfCompositionSink* sink,BSTR* output){
    if(!output)return E_POINTER;*output=nullptr;if(GetCurrentThreadId()!=thread_)return RPC_E_WRONG_THREAD;
    if(busy_)return E_PENDING;
    if(!SameTarget()){Disconnect();return E_ABORT;}
    busy_=true;
    try{
        check(action && strnlen(action,16385)<=16384,"action limit");const auto value=json::parse(action);
        check(value.is_object() && value.contains("kind") && value["kind"].is_string() && value.contains("revision") && value["revision"].is_number_unsigned(),"action envelope");
        for(auto it=value.begin();it!=value.end();++it)check(it.key()=="kind" || it.key()=="code" || it.key()=="candidateId" || it.key()=="revision" || it.key()=="delta","forbidden action field");
        const auto kind=value["kind"].get<std::string>();check(kind=="input" || kind=="backspace" || kind=="clear" || kind=="page" || kind=="select","unsupported action");
        auto response=Exchange("action",{{"action",value}});
        if(response.contains("commit")){
            const auto commit=response["commit"];check(commit.at("focus")==focus_,"foreign commit focus");
            const auto id=commit.at("id").get<std::string>(),text=commit.at("text").get<std::string>();
            check(!id.empty() && id.size()<=256 && !text.empty() && text.size()<=4096,"commit bounds");
            check(SameTarget(),"focus changed before edit");completed_=false;guardDenied_=false;callbacks_=checks_=0;editResult_=E_FAIL;
            BrokerUpdate update;update.commit=text;ITfComposition* composition=nullptr;bool ending=false;
            const HRESULT result=ApplyBrokerUpdateToContext(context_.Get(),client_,sink,&composition,&ending,update,nullptr,nullptr,false,Completed,this,this);
            if(composition)composition->Release();
            const bool applied=result==S_OK && completed_ && editResult_==S_OK && callbacks_==1 && checks_==1;
            const bool rejected=guardDenied_ && result==E_ABORT && completed_ && editResult_==E_ABORT && callbacks_==1 && checks_==1;
            const char* outcome=applied?"applied":rejected?"failed":"unknown";
            response=Exchange("complete",{{"commitId",id},{"outcome",outcome}});
            check(response.at("receipt").at("id")==id && response.at("receipt").at("outcome")==outcome,"receipt mismatch");
            if(!applied){Export(response,output);Disconnect();busy_=false;return E_ABORT;}
        }
        Export(response,output);busy_=false;return S_OK;
    }catch(...){Disconnect();busy_=false;return E_FAIL;}
}
