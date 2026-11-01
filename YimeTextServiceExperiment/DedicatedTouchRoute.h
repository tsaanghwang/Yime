#pragma once
#include "CompositionEditSession.h"
#include <wrl/client.h>
#include <nlohmann/json.hpp>
#include <atomic>
class DedicatedTouchRoute final : public yime::experiment::IBrokerEditExecutionGuard {
public:
    DedicatedTouchRoute(ITfThreadMgr* manager,TfClientId client);
    HRESULT Connect(LPCWSTR pipe,DWORD expectedPID,LPCWSTR expectedImage,BSTR* response);
    HRESULT Action(LPCSTR action,ITfCompositionSink* sink,BSTR* response);
    void Disconnect() noexcept;
    void FocusChanged(ITfDocumentMgr* document) noexcept;
    void ContextChanged(ITfContext* context) noexcept;
    STDMETHODIMP QueryInterface(REFIID iid,void** result) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;
    HRESULT ValidateExecution(ITfContext* context) noexcept override;
private:
    ~DedicatedTouchRoute();
    using json=nlohmann::json;
    json Exchange(const char* operation,const json& extra=json::object(),DWORD timeout=5000);
    bool SameTarget() noexcept;
    void Export(const json& response,BSTR* output);
    static void Completed(void*,ITfContext*,const yime::experiment::BrokerUpdate&,HRESULT) noexcept;
    std::atomic<ULONG> refs_{1};
    Microsoft::WRL::ComPtr<ITfThreadMgr> manager_;
    Microsoft::WRL::ComPtr<ITfDocumentMgr> document_;
    Microsoft::WRL::ComPtr<ITfContext> context_;
    TfClientId client_;DWORD thread_;HWND foreground_=nullptr;HANDLE pipe_=INVALID_HANDLE_VALUE,server_=nullptr;
    uint64_t sequence_=0,epoch_=0;
    json identity_,focus_;std::string session_;
    bool active_=false,busy_=false,completed_=false,guardDenied_=false;HRESULT editResult_=E_FAIL;unsigned callbacks_=0,checks_=0;
};
