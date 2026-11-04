#include <windows.h>
#include <cstdio>
#include <string>
#include <vector>
int wmain(int argc,wchar_t** argv){
    if(argc==5 && std::wstring(argv[1])==L"--child"){
        HANDLE ready=OpenEventW(EVENT_MODIFY_STATE,FALSE,argv[3]);
        HANDLE release=OpenEventW(SYNCHRONIZE,FALSE,argv[4]);
        if(!ready || !release)return 80;
        HMODULE module=LoadLibraryExW(argv[2],nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
        if(!module)return 81;
        auto configure=reinterpret_cast<void(*)(HANDLE,HANDLE)>(GetProcAddress(module,"ConfigureExitBlocker"));
        if(!configure)return 82;
        configure(ready,release);
        ExitProcess(37);
    }
    if(argc!=1)return 83;
    wchar_t own[32768]{};DWORD length=GetModuleFileNameW(nullptr,own,32768);
    if(!length || length>=32768)return 84;
    std::wstring exe(own,length),dll=exe.substr(0,exe.find_last_of(L"\\")+1)+L"ExitBlocker.dll";
    std::wstring prefix=L"Local\\YimePrivateExitFixture-"+std::to_wstring(GetCurrentProcessId())+L"-"+std::to_wstring(GetTickCount64());
    std::wstring readyName=prefix+L"-ready",releaseName=prefix+L"-release";
    HANDLE ready=CreateEventW(nullptr,TRUE,FALSE,readyName.c_str()),release=CreateEventW(nullptr,TRUE,FALSE,releaseName.c_str());
    HANDLE job=CreateJobObjectW(nullptr,nullptr);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};limits.BasicLimitInformation.LimitFlags=JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    PROCESS_INFORMATION process{};STARTUPINFOW startup{};startup.cb=sizeof(startup);
    DWORD error=0,beforeCode=0,afterCode=0,beforeWait=WAIT_FAILED,afterWait=WAIT_FAILED;
    bool assigned=false,barrier=false,queriedBefore=false,queriedAfter=false;
    if(!ready || !release || !job || !SetInformationJobObject(job,JobObjectExtendedLimitInformation,&limits,sizeof(limits))){error=GetLastError();}
    else{
        std::wstring command=L"\""+exe+L"\" --child \""+dll+L"\" \""+readyName+L"\" \""+releaseName+L"\"";
        std::vector<wchar_t> mutableCommand(command.begin(),command.end());mutableCommand.push_back(0);
        if(!CreateProcessW(exe.c_str(),mutableCommand.data(),nullptr,nullptr,FALSE,CREATE_SUSPENDED|CREATE_NO_WINDOW,nullptr,nullptr,&startup,&process)){error=GetLastError();}
        else if(!(assigned=AssignProcessToJobObject(job,process.hProcess)!=FALSE)){error=GetLastError();TerminateProcess(process.hProcess,85);}
        else if(ResumeThread(process.hThread)==DWORD(-1)){error=GetLastError();}
        else if(WaitForSingleObject(ready,10000)!=WAIT_OBJECT_0){error=WAIT_TIMEOUT;}
        else{
            barrier=true;queriedBefore=GetExitCodeProcess(process.hProcess,&beforeCode)!=FALSE;
            beforeWait=WaitForSingleObject(process.hProcess,0);
            SetEvent(release);
            afterWait=WaitForSingleObject(process.hProcess,10000);
            queriedAfter=GetExitCodeProcess(process.hProcess,&afterCode)!=FALSE;
            if(!queriedBefore || !queriedAfter || afterWait!=WAIT_OBJECT_0)error=GetLastError()?GetLastError():86;
        }
    }
    if(release)SetEvent(release);
    if(error && job)TerminateJobObject(job,87);
    if(process.hProcess)WaitForSingleObject(process.hProcess,10000);
    std::printf("{\"schema\":\"private-native-exit-signal-v1\",\"parentPID\":%lu,\"childPID\":%lu,\"jobAssigned\":%s,\"detachBarrierReached\":%s,\"beforeExitCode\":%lu,\"beforeWait\":%lu,\"afterExitCode\":%lu,\"afterWait\":%lu,\"error\":%lu,\"productTouched\":false}\n",GetCurrentProcessId(),process.dwProcessId,assigned?"true":"false",barrier?"true":"false",beforeCode,beforeWait,afterCode,afterWait,error);
    if(process.hThread)CloseHandle(process.hThread);
    if(process.hProcess)CloseHandle(process.hProcess);
    if(job)CloseHandle(job);
    if(release)CloseHandle(release);
    if(ready)CloseHandle(ready);
    return error?1:0;
}
