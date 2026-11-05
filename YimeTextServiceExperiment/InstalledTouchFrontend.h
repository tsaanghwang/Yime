#pragma once
#include <msctf.h>
#include <memory>
#include <string>
#include "DedicatedBrokerTransport.h"
class DedicatedTouchRoute;

// Lives exclusively on the activated TIP's STA. Workers exchange JSON only;
// all TSF calls and completion polling remain on the owning thread.
class InstalledTouchFrontend final {
public:
    static InstalledTouchFrontend* Create(ITfThreadMgr*,TfClientId,ITfCompositionSink*) noexcept;
    ~InstalledTouchFrontend();
    void Focus(bool) noexcept;
    void Revoke() noexcept;
    HRESULT CompositionTerminated(TfEditCookie,ITfComposition*) noexcept;
private:
    InstalledTouchFrontend(ITfThreadMgr*,TfClientId,ITfCompositionSink*);
    bool Start();
    void Tick() noexcept;
    void Next();
    void Complete(HRESULT,BSTR);
    static LRESULT CALLBACK WindowProc(HWND,UINT,WPARAM,LPARAM);
    ITfThreadMgr* manager_;TfClientId client_;ITfCompositionSink* owner_;
    DedicatedTouchRoute* route_=nullptr;
    HWND window_=nullptr,observedForeground_=nullptr,observedFocus_=nullptr;DWORD thread_=0;bool focused_=true,editing_=false,ticking_=false;
    uint64_t generation_=1;ULONGLONG retryAt_=0;
    std::wstring base_,broker_;
    std::string ticket_;
    std::string pendingBindMode_;
    bool closing_=false;
    ULONGLONG closeDeadline_=0;
    std::shared_ptr<DedicatedBrokerTransport> relay_;
    std::shared_ptr<DedicatedExchangeResult> work_;
};
