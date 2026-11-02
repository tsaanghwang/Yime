#include "DedicatedBrokerTransport.h"
#include "BrokerClient.h"
#include <stdexcept>
#include <vector>
namespace {
void check(bool value){if(!value)throw std::runtime_error("dedicated transport rejected");}
struct Handle{HANDLE value=nullptr;~Handle(){if(value)CloseHandle(value);}};
std::vector<BYTE> tokenUser(HANDLE token){
    DWORD size=0;GetTokenInformation(token,TokenUser,nullptr,0,&size);check(size>0 && size<65536);
    std::vector<BYTE> bytes(size);check(GetTokenInformation(token,TokenUser,bytes.data(),size,&size)!=FALSE);return bytes;
}
void sameOwner(HANDLE server,DWORD pid){
    DWORD a=0,b=0;check(ProcessIdToSessionId(pid,&a) && ProcessIdToSessionId(GetCurrentProcessId(),&b) && a==b);
    Handle left,right;check(OpenProcessToken(server,TOKEN_QUERY,&left.value) && OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&right.value));
    auto lu=tokenUser(left.value),ru=tokenUser(right.value);
    check(EqualSid(reinterpret_cast<TOKEN_USER*>(lu.data())->User.Sid,reinterpret_cast<TOKEN_USER*>(ru.data())->User.Sid)!=FALSE);
    TOKEN_STATISTICS ls{},rs{};DWORD size=0;
    check(GetTokenInformation(left.value,TokenStatistics,&ls,sizeof(ls),&size) && size==sizeof(ls));
    check(GetTokenInformation(right.value,TokenStatistics,&rs,sizeof(rs),&size) && size==sizeof(rs));
    check(ls.AuthenticationId.LowPart==rs.AuthenticationId.LowPart && ls.AuthenticationId.HighPart==rs.AuthenticationId.HighPart);
}
}
DedicatedBrokerTransport::DedicatedBrokerTransport(std::wstring pipe,DWORD pid,std::wstring image)
    :name_(std::move(pipe)),image_(std::move(image)),pid_(pid){
    cancel_=CreateEventW(nullptr,TRUE,FALSE,nullptr);check(cancel_!=nullptr);
}
DedicatedBrokerTransport::~DedicatedBrokerTransport(){
    if(pipe_!=INVALID_HANDLE_VALUE)CloseHandle(pipe_);
    if(server_)CloseHandle(server_);
    if(cancel_)CloseHandle(cancel_);
}
void DedicatedBrokerTransport::Cancel() noexcept{SetEvent(cancel_);}
void DedicatedBrokerTransport::Open(){
    check(WaitForSingleObject(cancel_,0)==WAIT_TIMEOUT);
    check(pid_ && pid_!=GetCurrentProcessId());
    server_=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION|SYNCHRONIZE,FALSE,pid_);check(server_!=nullptr);
    check(WaitForSingleObject(server_,0)==WAIT_TIMEOUT);
    wchar_t actual[32768];DWORD size=32768;check(QueryFullProcessImageNameW(server_,0,actual,&size)!=FALSE);
    check(_wcsicmp(image_.c_str(),std::wstring(actual,size).c_str())==0);sameOwner(server_,pid_);
    const ULONGLONG deadline=GetTickCount64()+30000;
    do{
        check(WaitForSingleObject(cancel_,0)==WAIT_TIMEOUT);
        pipe_=CreateFileW(name_.c_str(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,yime::experiment::BrokerPipeClientOpenFlags(),nullptr);
        if(pipe_!=INVALID_HANDLE_VALUE)break;
        const DWORD error=GetLastError();check(error==ERROR_PIPE_BUSY || error==ERROR_FILE_NOT_FOUND);
        check(WaitForSingleObject(cancel_,10)==WAIT_TIMEOUT);
    }while(GetTickCount64()<deadline);
    check(pipe_!=INVALID_HANDLE_VALUE);ULONG actualPID=0;
    check(GetNamedPipeServerProcessId(pipe_,&actualPID) && actualPID==pid_);
}
struct DedicatedBrokerTransport::Work {
    std::shared_ptr<DedicatedBrokerTransport> owner;
    std::shared_ptr<DedicatedExchangeResult> result;
    std::string request;
    DWORD timeout;
    bool connect;
    HMODULE module=nullptr;
};
DWORD WINAPI DedicatedBrokerTransport::Run(void* parameter) noexcept {
    HMODULE module=nullptr;
    {
        std::unique_ptr<Work> work(static_cast<Work*>(parameter));module=work->module;
        const auto& owner=work->owner;const auto& result=work->result;
        try{
            if(work->connect)owner->Open();
            check(owner->pipe_!=INVALID_HANDLE_VALUE && owner->server_ && WaitForSingleObject(owner->server_,0)==WAIT_TIMEOUT);
            std::string error;
            result->ok=yime::experiment::ExchangeBrokerPipeFrame(owner->pipe_,work->timeout,work->request,&result->response,&error,owner->cancel_);
        }catch(...){result->ok=false;}
        owner->running_.store(false);
        result->done.store(true,std::memory_order_release);
    }
    // No COM pointer crosses threads. The independent module pin also prevents
    // DLL unload while a cancelled worker is draining its outstanding I/O.
    FreeLibraryAndExitThread(module,0);
}
std::shared_ptr<DedicatedExchangeResult> DedicatedBrokerTransport::Start(std::string request,DWORD timeout,bool connect){
    check(!running_.exchange(true));
    HMODULE module=nullptr;
    try{
        auto result=std::make_shared<DedicatedExchangeResult>();auto owner=shared_from_this();
        auto work=std::make_unique<Work>(Work{owner,result,std::move(request),timeout,connect});
        check(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,reinterpret_cast<LPCWSTR>(&Run),&module)!=FALSE);
        work->module=module;
        // Release before CreateThread: a successful worker may finish before
        // CreateThread returns. On failure no worker owns or touched the packet.
        Work* packet=work.release();
        HANDLE thread=CreateThread(nullptr,0,Run,packet,0,nullptr);
        if(!thread){work.reset(packet);throw std::runtime_error("worker creation failed");}
        CloseHandle(thread);
        return result;
    }catch(...){if(module)FreeLibrary(module);running_.store(false);throw;}
}
