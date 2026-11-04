#include <windows.h>
static HANDLE ready=nullptr,release=nullptr;
extern "C" __declspec(dllexport) void ConfigureExitBlocker(HANDLE r,HANDLE x){ready=r;release=x;}
BOOL WINAPI DllMain(HINSTANCE image,DWORD reason,LPVOID){
    if(reason==DLL_PROCESS_ATTACH)DisableThreadLibraryCalls(image);
    // Intentional private fixture barrier, never linked into a product.
    if(reason==DLL_PROCESS_DETACH && ready && release){SetEvent(ready);WaitForSingleObject(release,10000);}
    return TRUE;
}
