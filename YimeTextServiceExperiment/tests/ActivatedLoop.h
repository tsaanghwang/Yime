#pragma once
#include <windows.h>
#include <string>
#include <memory>
// One registered-host commit, using the Windows-created function provider.
// This entry never registers a profile; its caller owns the transaction.
struct ActivatedProviderProbe {
 virtual HRESULT CheckDisconnected(bool& outputNull)=0;
 virtual ~ActivatedProviderProbe()=default;
};
struct ActivatedLoopResult {
 bool completed=false;
 const char* stage="registered-host-not-run";
 const char* kind="assertion";
 unsigned long code=0;
 std::string hostResult;
 std::shared_ptr<ActivatedProviderProbe> retainedProvider;
};
ActivatedLoopResult RunActivatedRegisteredHost(const std::string& config,const std::wstring& pinnedDll);
