#pragma once
#include <windows.h>
#include <unknwn.h>
// Controlled native integration adapter, not a public frontend RPC endpoint.
// Caller never supplies a text commit, receipt, HWND, context, session or epoch.
// v2: Connect/Action return E_PENDING only after accepting a new operation.
// Pump the owning STA normally and call Poll; never retry Connect/Action.
// ERROR_BUSY rejects a second operation. S_FALSE from Poll means no operation.
// Poll's terminal result is consumed once. Missing/lost completion is never
// permission to replay. The old synchronous IID is deliberately unsupported.
MIDL_INTERFACE("E4647B73-53B6-4F62-AAB9-55D28740C465") IDedicatedTouchService : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE ConnectDedicated(LPCWSTR pipeName,DWORD expectedServerPID,
        LPCWSTR expectedServerImage,BSTR* responseJSON)=0;
    virtual HRESULT STDMETHODCALLTYPE ActionDedicated(LPCSTR actionJSON,BSTR* responseJSON)=0;
    virtual HRESULT STDMETHODCALLTYPE DisconnectDedicated()=0;
    virtual HRESULT STDMETHODCALLTYPE PollDedicated(BSTR* responseJSON)=0;
};
