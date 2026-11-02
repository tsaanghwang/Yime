#include "DedicatedTouchRoute.h"
#include "TouchProductIdentity.h"
#include <cstring>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
using namespace yime::experiment;
namespace {
void check(bool value,const char* reason){if(!value)throw std::runtime_error(reason);}
std::wstring fullPath(LPCWSTR path){
    check(path && wcslen(path)>=3 && path[1]==L':' && (path[2]==L'\\' || path[2]==L'/'),"absolute local image required");
    wchar_t buffer[32768];const DWORD n=GetFullPathNameW(path,32768,buffer,nullptr);check(n>0 && n<32768,"image path");return {buffer,n};
}
DedicatedForeground actualForeground() noexcept {
    DedicatedForeground result;result.window=GetForegroundWindow();
    result.thread=GetWindowThreadProcessId(result.window,&result.process);return result;
}
bool unsignedValue(const nlohmann::json& value){return value.is_number_unsigned();}
}
DedicatedTouchRoute::DedicatedTouchRoute(ITfThreadMgr* manager,TfClientId client,DedicatedForegroundQuery query)
    :manager_(manager),foregroundQuery_(query?query:actualForeground),client_(client),thread_(GetCurrentThreadId()){}
DedicatedTouchRoute::~DedicatedTouchRoute(){Disconnect();if(editComposition_)editComposition_->Release();}
STDMETHODIMP DedicatedTouchRoute::QueryInterface(REFIID iid,void** out){if(!out)return E_POINTER;*out=nullptr;if(iid!=IID_IUnknown)return E_NOINTERFACE;*out=static_cast<IBrokerEditExecutionGuard*>(this);AddRef();return S_OK;}
STDMETHODIMP_(ULONG) DedicatedTouchRoute::AddRef(){return ++refs_;}
STDMETHODIMP_(ULONG) DedicatedTouchRoute::Release(){auto n=--refs_;if(!n)delete this;return n;}
void DedicatedTouchRoute::Disconnect() noexcept{
    active_=bound_=false;++epoch_;
    if(transport_)transport_->Cancel();transport_.reset();
    session_.clear();foreground_=nullptr;document_.Reset();context_.Reset();
    // Pending edit slots must live until DoEditSession releases its guard ref.
}
void DedicatedTouchRoute::FocusChanged(ITfDocumentMgr* document) noexcept{if(bound_ && document!=document_.Get())Disconnect();}
void DedicatedTouchRoute::ContextChanged(ITfContext* context) noexcept{if(bound_ && context!=context_.Get())Disconnect();}
bool DedicatedTouchRoute::SameTarget() noexcept{
    if(GetCurrentThreadId()!=thread_ || !bound_ || !context_ || !document_ || !foreground_)return false;
    const auto now=foregroundQuery_();
    if(now.window!=foreground_ || now.thread!=thread_ || now.process!=GetCurrentProcessId())return false;
    ComPtr<ITfDocumentMgr> focus;ComPtr<ITfContext> top;
    return SUCCEEDED(manager_->GetFocus(&focus)) && focus.Get()==document_.Get() &&
        SUCCEEDED(focus->GetTop(&top)) && top.Get()==context_.Get();
}
HRESULT DedicatedTouchRoute::ValidateExecution(ITfContext* context) noexcept{
    ++checks_;guardDenied_=editEpoch_!=epoch_ || !SameTarget() || context!=editContext_.Get();return guardDenied_?E_ABORT:S_OK;
}
void DedicatedTouchRoute::Completed(void* value,ITfContext* context,const BrokerUpdate&,HRESULT result) noexcept{
    auto* self=static_cast<DedicatedTouchRoute*>(value);++self->callbacks_;self->completed_=true;self->editOutstanding_=false;
    self->editResult_=context==self->editContext_.Get()?result:E_UNEXPECTED;
}
void DedicatedTouchRoute::SummarizeEdit() noexcept{
    if(!completed_)return;
    const bool applied=editResult_==S_OK && callbacks_==1 && checks_==1;
    const bool rejected=guardDenied_ && editResult_==E_ABORT && callbacks_==1 && checks_==1;
    localOutcome_=applied?"applied":rejected?"failed":"unknown";
}
void DedicatedTouchRoute::Export(const json& response,BSTR* output){
    const std::string value=response.dump();check(value.size()<=65536,"response size");
    const int count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0);
    check(count>0,"response encoding");*output=SysAllocStringLen(nullptr,count);check(*output!=nullptr,"response allocation");
    if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),*output,count)!=count){SysFreeString(*output);*output=nullptr;throw std::runtime_error("response conversion");}
}
HRESULT DedicatedTouchRoute::Failed(BSTR* output) noexcept{
    SummarizeEdit();
    const bool unknown=editOutstanding_ || !strcmp(localOutcome_,"applied") || !strcmp(localOutcome_,"unknown");
    try{Export({{"ok",false},{"outcome",unknown?"unknown":"failed"},{"localEditOutcome",localOutcome_},{"retryAllowed",false}},output);}catch(...){}
    Disconnect();phase_=Phase::None;work_.reset();return E_ABORT;
}
void DedicatedTouchRoute::StartExchange(Phase phase,const char* operation,const json& extra,DWORD timeout){
    check(transport_ && sequence_<UINT64_MAX,"transport unavailable");
    json request{{"version",2},{"sequence",++sequence_},{"operation",operation},{"product","YimeCore18uTouch"},{"focus",focus_}};
    if(phase!=Phase::Open){request["sessionId"]=session_;request["identity"]=identity_;}
    for(auto it=extra.begin();it!=extra.end();++it)request[it.key()]=it.value();
    const auto frame=request.dump();check(frame.size()<=16384,"request limit");
    work_=transport_->Start(frame,timeout,phase==Phase::Open);phase_=phase;
}
DedicatedTouchRoute::json DedicatedTouchRoute::ReadReply(){
    check(work_ && work_->ok && work_->response.size()<=65536,"transport failed; no replay");
    const auto reply=json::parse(work_->response);
    check(reply.is_object() && reply.contains("version") && unsignedValue(reply["version"]) && reply["version"]==2 &&
          reply.contains("sequence") && unsignedValue(reply["sequence"]) && reply["sequence"]==sequence_ && reply.value("ok",false),"broker rejected or malformed response");
    check(reply.at("identity")==identity_ && reply.at("focus")==focus_,"broker identity or focus mismatch");
    const auto session=reply.at("sessionId").get<std::string>();check(!session.empty() && session.size()<=256,"session missing");
    if(session_.empty())session_=session;else check(session==session_,"foreign session");return reply;
}
HRESULT DedicatedTouchRoute::Connect(LPCWSTR pipe,DWORD pid,LPCWSTR image,BSTR* output){
    if(!output)return E_POINTER;*output=nullptr;if(GetCurrentThreadId()!=thread_)return RPC_E_WRONG_THREAD;
    if(phase_!=Phase::None || editOutstanding_ || polling_)return HRESULT_FROM_WIN32(ERROR_BUSY);
    Disconnect();completed_=false;localOutcome_="not-attempted";
    try{
        const std::wstring prefix=L"\\\\.\\pipe\\YimeBroker.18uTouch.v1.";
        check(pipe && std::wstring(pipe).rfind(prefix,0)==0,"dedicated local pipe required");
        const auto suffix=std::wstring(pipe).substr(prefix.size());
        check(!suffix.empty() && suffix.size()<=96 && suffix.find_first_not_of(L"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")==std::wstring::npos,"invalid dedicated pipe suffix");
        const auto expected=fullPath(image);check(pid && pid!=GetCurrentProcessId(),"expected broker PID required");
        check(SUCCEEDED(manager_->GetFocus(&document_)) && document_ && SUCCEEDED(document_->GetTop(&context_)) && context_,"TIP has no own focused context");
        const auto now=foregroundQuery_();foreground_=now.window;
        check(foreground_ && now.thread==thread_ && now.process==GetCurrentProcessId(),"TIP host must own actual foreground thread window");
        GUID lease{};check(SUCCEEDED(CoCreateGuid(&lease)),"context lease");wchar_t leaseText[40];check(StringFromGUID2(lease,leaseText,40)>0,"lease encoding");
        std::string token;for(const wchar_t* c=leaseText;*c;++c)token.push_back(static_cast<char>(*c));
        focus_={{"context",token},{"epoch",epoch_}};identity_={{"layoutSHA256",YIME_TOUCH_LAYOUT_SHA},{"dictionarySHA256",YIME_TOUCH_DICTIONARY_SHA},{"mode","variable"},{"sessionPolicy","concept-keyboard-modes-v2+ellipsis-choice-v1"}};
        sequence_=0;pendingEpoch_=epoch_;bound_=true;
        transport_=std::make_shared<DedicatedBrokerTransport>(pipe,pid,expected);
        StartExchange(Phase::Open,"open",json::object(),60000);return E_PENDING;
    }catch(...){return Failed(output);}
}
HRESULT DedicatedTouchRoute::Action(LPCSTR action,BSTR* output){
    if(!output)return E_POINTER;*output=nullptr;if(GetCurrentThreadId()!=thread_)return RPC_E_WRONG_THREAD;
    if(phase_!=Phase::None || editOutstanding_ || polling_)return HRESULT_FROM_WIN32(ERROR_BUSY);
    completed_=false;localOutcome_="not-attempted";
    try{
        check(active_ && SameTarget(),"stale target");
        check(action && strnlen(action,16385)<=16384,"action limit");const auto value=json::parse(action);
        check(value.is_object() && value.contains("kind") && value["kind"].is_string() && value.contains("revision") && value["revision"].is_number_unsigned(),"action envelope");
        for(auto it=value.begin();it!=value.end();++it)check(it.key()=="kind" || it.key()=="code" || it.key()=="candidateId" || it.key()=="revision" || it.key()=="delta","forbidden action field");
        const auto kind=value["kind"].get<std::string>();check(kind=="input" || kind=="backspace" || kind=="clear" || kind=="page" || kind=="select","unsupported action");
        pendingEpoch_=epoch_;StartExchange(Phase::Action,"action",{{"action",value}});return E_PENDING;
    }catch(...){return Failed(output);}
}
HRESULT DedicatedTouchRoute::Poll(ITfCompositionSink* sink,BSTR* output){
    if(!output)return E_POINTER;*output=nullptr;if(GetCurrentThreadId()!=thread_)return RPC_E_WRONG_THREAD;
    if(polling_)return HRESULT_FROM_WIN32(ERROR_BUSY);if(phase_==Phase::None)return S_FALSE;
    polling_=true;struct Reset {bool& flag;~Reset(){flag=false;}} reset{polling_};
    try{
        check(pendingEpoch_==epoch_ && SameTarget(),"revoked target");
        if(phase_==Phase::Edit){
            if(!completed_)return E_PENDING;
            SummarizeEdit();StartExchange(Phase::Complete,"complete",{{"commitId",commitId_},{"outcome",localOutcome_}});return E_PENDING;
        }
        if(!work_->done.load(std::memory_order_acquire))return E_PENDING;
        auto response=ReadReply();
        if(phase_==Phase::Action && response.contains("commit")){
            const auto& commit=response["commit"];check(commit.at("focus")==focus_,"foreign commit focus");
            commitId_=commit.at("id").get<std::string>();const auto text=commit.at("text").get<std::string>();
            check(!commitId_.empty() && commitId_.size()<=256 && !text.empty() && text.size()<=4096 && sink,"commit bounds");
            completed_=guardDenied_=false;callbacks_=checks_=0;editResult_=E_FAIL;
            editContext_=context_;editEpoch_=epoch_;editOutstanding_=true;localOutcome_="pending";
            if(editComposition_){editComposition_->Release();editComposition_=nullptr;}editEnding_=false;
            phase_=Phase::Edit;work_.reset();BrokerUpdate update;update.commit=text;
            const HRESULT result=ApplyBrokerUpdateToContext(editContext_.Get(),client_,sink,&editComposition_,&editEnding_,update,nullptr,nullptr,true,Completed,this,this);
            if(result!=TF_S_ASYNC && !completed_){editOutstanding_=false;completed_=true;editResult_=result;}
            return E_PENDING;
        }
        bool success=true;
        if(phase_==Phase::Complete){
            check(response.at("receipt").at("id")==commitId_ && response.at("receipt").at("outcome")==localOutcome_,"receipt mismatch");
            success=!strcmp(localOutcome_,"applied");
        }
        if(phase_==Phase::Open)active_=true;
        Export(response,output);phase_=Phase::None;work_.reset();if(!success)Disconnect();return success?S_OK:E_ABORT;
    }catch(...){return Failed(output);}
}
