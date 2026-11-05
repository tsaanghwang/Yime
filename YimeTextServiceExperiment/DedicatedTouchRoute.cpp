#include "DedicatedTouchRoute.h"
#include "TouchProductIdentity.h"
#include "InputAbortDiagnostic.h"
#include <cstring>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
using namespace yime::experiment;
namespace diag=yime::abortdiag;
namespace {
void check(bool value,diag::Reason reason){if(!value){diag::Emit(diag::Stage::RouteCheck,reason);throw std::runtime_error("dedicated route check rejected");}}
std::wstring fullPath(LPCWSTR path){
    check(path && wcslen(path)>=3 && path[1]==L':' && (path[2]==L'\\' || path[2]==L'/'),diag::Reason::AbsoluteLocalImageRequired);
    wchar_t buffer[32768];const DWORD n=GetFullPathNameW(path,32768,buffer,nullptr);check(n>0 && n<32768,diag::Reason::ImagePath);return {buffer,n};
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
void DedicatedTouchRoute::Diagnose(diag::Stage stage,diag::Reason reason,HRESULT result) const noexcept {
    diag::State state;state.epoch=epoch_;state.pendingEpoch=pendingEpoch_;state.editEpoch=editEpoch_;
    state.phase=static_cast<unsigned>(phase_);state.active=active_;state.bound=bound_;state.editOutstanding=editOutstanding_;
    diag::Emit(stage,reason,static_cast<uint32_t>(result),state);
}
void DedicatedTouchRoute::Disconnect() noexcept{
    active_=bound_=false;++epoch_;
    if(transport_)transport_->Cancel();transport_.reset();
    session_.clear();foreground_=nullptr;document_.Reset();context_.Reset();
    // Pending edit slots must live until DoEditSession releases its guard ref.
}
void DedicatedTouchRoute::FocusChanged(ITfDocumentMgr* document) noexcept{if(bound_ && document!=document_.Get()){Diagnose(diag::Stage::Lifecycle,diag::Reason::FocusRevoked);Disconnect();}}
void DedicatedTouchRoute::ContextChanged(ITfContext* context) noexcept{if(bound_ && context!=context_.Get()){Diagnose(diag::Stage::Lifecycle,diag::Reason::ContextRevoked);Disconnect();}}
bool DedicatedTouchRoute::SameTarget() noexcept{
    if(GetCurrentThreadId()!=thread_ || !bound_ || !context_ || !document_ || !foreground_){Diagnose(diag::Stage::Target,diag::Reason::TargetStateMissing);return false;}
    const auto now=foregroundQuery_();
    if(now.window!=foreground_ || now.thread!=thread_ || now.process!=GetCurrentProcessId()){Diagnose(diag::Stage::Target,diag::Reason::ForegroundChanged);return false;}
    ComPtr<ITfDocumentMgr> focus;ComPtr<ITfContext> top;
    const HRESULT focusResult=manager_->GetFocus(&focus);
    if(FAILED(focusResult)){Diagnose(diag::Stage::Target,diag::Reason::DocumentQueryFailed,focusResult);return false;}
    if(focus.Get()!=document_.Get()){Diagnose(diag::Stage::Target,diag::Reason::DocumentChanged);return false;}
    const HRESULT topResult=focus->GetTop(&top);
    if(FAILED(topResult)){Diagnose(diag::Stage::Target,diag::Reason::ContextQueryFailed,topResult);return false;}
    if(top.Get()!=context_.Get()){Diagnose(diag::Stage::Target,diag::Reason::ContextChanged);return false;}
    return true;
}
HRESULT DedicatedTouchRoute::ValidateExecution(ITfContext* context) noexcept{
    ++checks_;guardDenied_=editEpoch_!=epoch_ || !SameTarget() || context!=editContext_.Get();if(guardDenied_)Diagnose(diag::Stage::Target,diag::Reason::ExecutionGuardDenied,E_ABORT);return guardDenied_?E_ABORT:S_OK;
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
    const std::string value=response.dump();check(value.size()<=65536,diag::Reason::ResponseSize);
    const int count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0);
    check(count>0,diag::Reason::ResponseEncoding);*output=SysAllocStringLen(nullptr,count);check(*output!=nullptr,diag::Reason::ResponseAllocation);
    if(MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),*output,count)!=count){SysFreeString(*output);*output=nullptr;throw std::runtime_error("response conversion");}
}
HRESULT DedicatedTouchRoute::Failed(BSTR* output) noexcept{
    Diagnose(diag::Stage::RouteFailed,diag::Reason::Failed,E_ABORT);
    SummarizeEdit();
    const bool unknown=editOutstanding_ || !strcmp(localOutcome_,"applied") || !strcmp(localOutcome_,"unknown");
    try{Export({{"ok",false},{"outcome",unknown?"unknown":"failed"},{"localEditOutcome",localOutcome_},{"retryAllowed",false}},output);}catch(...){}
    Disconnect();phase_=Phase::None;work_.reset();return E_ABORT;
}
void DedicatedTouchRoute::StartExchange(Phase phase,const char* operation,const json& extra,DWORD timeout){
    check(transport_ && sequence_<UINT64_MAX,diag::Reason::TransportUnavailable);
    json request{{"version",2},{"sequence",++sequence_},{"operation",operation},{"product","YimeCore18uTouch"},{"focus",focus_}};
    if(phase!=Phase::Open){request["sessionId"]=session_;request["identity"]=identity_;}
    for(auto it=extra.begin();it!=extra.end();++it)request[it.key()]=it.value();
    const auto frame=request.dump();check(frame.size()<=16384,diag::Reason::RequestLimit);
    work_=transport_->Start(frame,timeout,phase==Phase::Open);phase_=phase;
}
DedicatedTouchRoute::json DedicatedTouchRoute::ReadReply(){
    check(work_ && work_->ok && work_->response.size()<=65536,diag::Reason::TransportFailedNoReplay);
    const auto reply=json::parse(work_->response);
    try {
        if(reply.is_object() && reply.contains("ok") && reply["ok"].is_boolean() && reply["ok"]==false)
            Diagnose(diag::Stage::RouteCheck,diag::Reason::BrokerOkFalse);
    } catch(...) {} // Diagnostic inspection must not alter response handling.
    check(reply.is_object() && reply.contains("version") && unsignedValue(reply["version"]) && reply["version"]==2 &&
          reply.contains("sequence") && unsignedValue(reply["sequence"]) && reply["sequence"]==sequence_ && reply.value("ok",false),diag::Reason::BrokerRejectedOrMalformedResponse);
    check(reply.at("identity")==identity_ && reply.at("focus")==focus_,diag::Reason::BrokerIdentityOrFocusMismatch);
    const auto session=reply.at("sessionId").get<std::string>();check(!session.empty() && session.size()<=256,diag::Reason::SessionMissing);
    if(session_.empty())session_=session;else check(session==session_,diag::Reason::ForeignSession);return reply;
}
HRESULT DedicatedTouchRoute::Connect(LPCWSTR pipe,DWORD pid,LPCWSTR image,BSTR* output){
    if(!output){diag::Emit(diag::Stage::RouteConnect,diag::Reason::MissingOutput,static_cast<uint32_t>(E_POINTER));return E_POINTER;}*output=nullptr;if(GetCurrentThreadId()!=thread_){diag::Emit(diag::Stage::RouteConnect,diag::Reason::WrongThread,static_cast<uint32_t>(RPC_E_WRONG_THREAD));return RPC_E_WRONG_THREAD;}
    if(phase_!=Phase::None || editOutstanding_ || polling_){Diagnose(diag::Stage::RouteConnect,diag::Reason::Busy,HRESULT_FROM_WIN32(ERROR_BUSY));return HRESULT_FROM_WIN32(ERROR_BUSY);}
    Disconnect();completed_=false;localOutcome_="not-attempted";
    try{
        const std::wstring prefix=L"\\\\.\\pipe\\YimeBroker.18uTouch.v1.";
        check(pipe && std::wstring(pipe).rfind(prefix,0)==0,diag::Reason::DedicatedLocalPipeRequired);
        const auto suffix=std::wstring(pipe).substr(prefix.size());
        check(!suffix.empty() && suffix.size()<=96 && suffix.find_first_not_of(L"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")==std::wstring::npos,diag::Reason::InvalidDedicatedPipeSuffix);
        const auto expected=fullPath(image);check(pid && pid!=GetCurrentProcessId(),diag::Reason::ExpectedBrokerPidRequired);
        check(SUCCEEDED(manager_->GetFocus(&document_)) && document_ && SUCCEEDED(document_->GetTop(&context_)) && context_,diag::Reason::TipHasNoOwnFocusedContext);
        const auto now=foregroundQuery_();foreground_=now.window;
        check(foreground_ && now.thread==thread_ && now.process==GetCurrentProcessId(),diag::Reason::TipHostMustOwnActualForegroundThreadWindow);
        GUID lease{};check(SUCCEEDED(CoCreateGuid(&lease)),diag::Reason::ContextLease);wchar_t leaseText[40];check(StringFromGUID2(lease,leaseText,40)>0,diag::Reason::LeaseEncoding);
        std::string token;for(const wchar_t* c=leaseText;*c;++c)token.push_back(static_cast<char>(*c));
        focus_={{"context",token},{"epoch",epoch_}};identity_={{"layoutSHA256",YIME_TOUCH_LAYOUT_SHA},{"dictionarySHA256",YIME_TOUCH_DICTIONARY_SHA},{"mode","variable"},{"sessionPolicy","concept-keyboard-modes-v2+ellipsis-choice-v1"}};
        sequence_=0;pendingEpoch_=epoch_;bound_=true;
        transport_=std::make_shared<DedicatedBrokerTransport>(pipe,pid,expected);
        StartExchange(Phase::Open,"open",json::object(),60000);return E_PENDING;
    }catch(const json::exception&){Diagnose(diag::Stage::RouteConnect,diag::Reason::JsonException);return Failed(output);}catch(const std::exception&){Diagnose(diag::Stage::RouteConnect,diag::Reason::StandardException);return Failed(output);}catch(...){Diagnose(diag::Stage::RouteConnect,diag::Reason::UnknownException);return Failed(output);}
}
HRESULT DedicatedTouchRoute::Action(LPCSTR action,BSTR* output){
    if(!output){diag::Emit(diag::Stage::RouteAction,diag::Reason::MissingOutput,static_cast<uint32_t>(E_POINTER));return E_POINTER;}*output=nullptr;if(GetCurrentThreadId()!=thread_){diag::Emit(diag::Stage::RouteAction,diag::Reason::WrongThread,static_cast<uint32_t>(RPC_E_WRONG_THREAD));return RPC_E_WRONG_THREAD;}
    if(phase_!=Phase::None || editOutstanding_ || polling_){Diagnose(diag::Stage::RouteAction,diag::Reason::Busy,HRESULT_FROM_WIN32(ERROR_BUSY));return HRESULT_FROM_WIN32(ERROR_BUSY);}
    completed_=false;localOutcome_="not-attempted";
    try{
        check(active_ && SameTarget(),diag::Reason::StaleTarget);
        check(action && strnlen(action,16385)<=16384,diag::Reason::ActionLimit);const auto value=json::parse(action);
        check(value.is_object() && value.contains("kind") && value["kind"].is_string() && value.contains("revision") && value["revision"].is_number_unsigned(),diag::Reason::ActionEnvelope);
        for(auto it=value.begin();it!=value.end();++it)check(it.key()=="kind" || it.key()=="code" || it.key()=="candidateId" || it.key()=="revision" || it.key()=="delta",diag::Reason::ForbiddenActionField);
        const auto kind=value["kind"].get<std::string>();check(kind=="input" || kind=="backspace" || kind=="clear" || kind=="page" || kind=="select",diag::Reason::UnsupportedAction);
        pendingEpoch_=epoch_;StartExchange(Phase::Action,"action",{{"action",value}});return E_PENDING;
    }catch(const json::exception&){Diagnose(diag::Stage::RouteAction,diag::Reason::JsonException);return Failed(output);}catch(const std::exception&){Diagnose(diag::Stage::RouteAction,diag::Reason::StandardException);return Failed(output);}catch(...){Diagnose(diag::Stage::RouteAction,diag::Reason::UnknownException);return Failed(output);}
}
HRESULT DedicatedTouchRoute::Poll(ITfCompositionSink* sink,BSTR* output){
    if(!output){diag::Emit(diag::Stage::RoutePoll,diag::Reason::MissingOutput,static_cast<uint32_t>(E_POINTER));return E_POINTER;}*output=nullptr;if(GetCurrentThreadId()!=thread_){diag::Emit(diag::Stage::RoutePoll,diag::Reason::WrongThread,static_cast<uint32_t>(RPC_E_WRONG_THREAD));return RPC_E_WRONG_THREAD;}
    if(polling_){Diagnose(diag::Stage::RoutePoll,diag::Reason::Busy,HRESULT_FROM_WIN32(ERROR_BUSY));return HRESULT_FROM_WIN32(ERROR_BUSY);}if(phase_==Phase::None)return S_FALSE;
    polling_=true;struct Reset {bool& flag;~Reset(){flag=false;}} reset{polling_};
    try{
        check(pendingEpoch_==epoch_ && SameTarget(),diag::Reason::RevokedTarget);
        if(phase_==Phase::Edit){
            if(!completed_)return E_PENDING;
            SummarizeEdit();StartExchange(Phase::Complete,"complete",{{"commitId",commitId_},{"outcome",localOutcome_}});return E_PENDING;
        }
        if(!work_->done.load(std::memory_order_acquire))return E_PENDING;
        auto response=ReadReply();
        if(phase_==Phase::Action && response.contains("commit")){
            const auto& commit=response["commit"];check(commit.at("focus")==focus_,diag::Reason::ForeignCommitFocus);
            commitId_=commit.at("id").get<std::string>();const auto text=commit.at("text").get<std::string>();
            check(!commitId_.empty() && commitId_.size()<=256 && !text.empty() && text.size()<=4096 && sink,diag::Reason::CommitBounds);
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
            check(response.at("receipt").at("id")==commitId_ && response.at("receipt").at("outcome")==localOutcome_,diag::Reason::ReceiptMismatch);
            success=!strcmp(localOutcome_,"applied");
        }
        if(phase_==Phase::Open)active_=true;
        Export(response,output);phase_=Phase::None;work_.reset();if(!success)Disconnect();return success?S_OK:E_ABORT;
    }catch(const json::exception&){Diagnose(diag::Stage::RoutePoll,diag::Reason::JsonException);return Failed(output);}catch(const std::exception&){Diagnose(diag::Stage::RoutePoll,diag::Reason::StandardException);return Failed(output);}catch(...){Diagnose(diag::Stage::RoutePoll,diag::Reason::UnknownException);return Failed(output);}
}
