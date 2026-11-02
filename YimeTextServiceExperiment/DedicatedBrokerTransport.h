#pragma once
#include <windows.h>
#include <atomic>
#include <memory>
#include <string>

// No COM/context/window pointers cross this boundary. The worker owns all pipe
// I/O; cancellation merely signals it and never closes a handle under pending I/O.
struct DedicatedExchangeResult {
    std::atomic<bool> done{false};
    bool ok=false;
    std::string response;
};
class DedicatedBrokerTransport final : public std::enable_shared_from_this<DedicatedBrokerTransport> {
public:
    DedicatedBrokerTransport(std::wstring pipe,DWORD pid,std::wstring image);
    ~DedicatedBrokerTransport();
    std::shared_ptr<DedicatedExchangeResult> Start(std::string request,DWORD timeout,bool connect);
    void Cancel() noexcept;
private:
    struct Work;
    static DWORD WINAPI Run(void* parameter) noexcept;
    void Open();
    std::wstring name_,image_;
    DWORD pid_;
    HANDLE cancel_=nullptr,pipe_=INVALID_HANDLE_VALUE,server_=nullptr;
    std::atomic<bool> running_{false};
};
