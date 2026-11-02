#pragma once
#include <windows.h>
#include <string>
// One registered-host commit, using the Windows-created function provider.
// This entry never registers a profile; its caller owns the transaction.
struct ActivatedLoopResult {
 bool completed=false;
 const char* stage="registered-host-not-run";
 const char* kind="assertion";
 unsigned long code=0;
 std::string hostResult;
};
ActivatedLoopResult RunActivatedRegisteredHost(const std::string& config,const std::wstring& pinnedDll);
