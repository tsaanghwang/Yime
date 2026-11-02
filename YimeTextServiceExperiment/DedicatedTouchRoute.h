#pragma once
#include "CompositionEditSession.h"
#include "DedicatedBrokerTransport.h"
#include <wrl/client.h>
#include <nlohmann/json.hpp>
#include <atomic>
// Internal constructor seam for substitute-TSF tests; never exposed over COM.
struct DedicatedForeground { HWND window=nullptr; DWORD thread=0,process=0; };
using DedicatedForegroundQuery=DedicatedForeground(*)() noexcept;
class DedicatedTouchRoute final : public yime::experiment::IBrokerEditExecutionGuard {
public:
    DedicatedTouchRoute(ITfThreadMgr* manager,TfClientId client,DedicatedForegroundQuery query=nullptr);
    HRESULT Connect(LPCWSTR pipe,DWORD expectedPID,LPCWSTR expectedImage,BSTR* response);
    HRESULT Action(LPCSTR action,BSTR* response);
    HRESULT Poll(ITfCompositionSink* sink,BSTR* response);
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
    enum class Phase { None,Open,Action,Edit,Complete };
    void StartExchange(Phase phase,const char* operation,const json& extra=json::object(),DWORD timeout=5000);
    json ReadReply();
    bool SameTarget() noexcept;
    void Export(const json& response,BSTR* output);
    HRESULT Failed(BSTR* output) noexcept;
    void SummarizeEdit() noexcept;
    static void Completed(void*,ITfContext*,const yime::experiment::BrokerUpdate&,HRESULT) noexcept;
    std::atomic<ULONG> refs_{1};
    Microsoft::WRL::ComPtr<ITfThreadMgr> manager_;
    Microsoft::WRL::ComPtr<ITfDocumentMgr> document_;
    Microsoft::WRL::ComPtr<ITfContext> context_,editContext_;
    DedicatedForegroundQuery foregroundQuery_;
    TfClientId client_;DWORD thread_;HWND foreground_=nullptr;
    std::shared_ptr<DedicatedBrokerTransport> transport_;
    std::shared_ptr<DedicatedExchangeResult> work_;
    uint64_t sequence_=0,epoch_=0,pendingEpoch_=0,editEpoch_=0;
    json identity_,focus_;std::string session_,commitId_;
    Phase phase_=Phase::None;
    bool active_=false,bound_=false,polling_=false,completed_=false,guardDenied_=false,editOutstanding_=false;
    ITfComposition* editComposition_=nullptr;bool editEnding_=false;
    const char* localOutcome_="not-attempted";
    HRESULT editResult_=E_FAIL;unsigned callbacks_=0,checks_=0;
};
