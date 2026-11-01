#pragma once
#include <windows.h>
#include <unknwn.h>
// Controlled native integration adapter, not a public frontend RPC endpoint.
// Caller never supplies a text commit, receipt, HWND, context, session or epoch.
MIDL_INTERFACE("A1FB7854-777D-4B34-9B23-04F5BBCA2B92") IDedicatedTouchService : public IUnknown {
    virtual HRESULT STDMETHODCALLTYPE ConnectDedicated(LPCWSTR pipeName,DWORD expectedServerPID,
        LPCWSTR expectedServerImage,BSTR* responseJSON)=0;
    virtual HRESULT STDMETHODCALLTYPE ActionDedicated(LPCSTR actionJSON,BSTR* responseJSON)=0;
    virtual HRESULT STDMETHODCALLTYPE DisconnectDedicated()=0;
};
